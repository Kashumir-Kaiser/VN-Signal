//go:build postgres_integration

package dq

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func insertSyntheticSourceLanding(t *testing.T, ctx context.Context, db *sql.DB, symbol, source, attributedSource, organisation, day string, close float64) int64 {
	t.Helper()
	frame := struct {
		Columns    []string          `json:"columns"`
		Count      int               `json:"count"`
		Rows       []map[string]any  `json:"rows"`
		Attributes map[string]string `json:"attributes"`
	}{
		Columns: []string{"time", "open", "high", "low", "close", "volume"},
		Count:   1,
		Rows: []map[string]any{{
			"time": day, "open": close, "high": close + 1, "low": close - 1, "close": close, "volume": 100,
		}},
		Attributes: map[string]string{
			"source": attributedSource, "route": "market.equity.ohlcv", "source_name": source,
			"organisation": organisation, "fixture": "synthetic CI-only evidence",
		},
	}
	raw, err := json.Marshal(frame)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(raw)
	var landingID int64
	err = db.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES(gen_random_uuid(),$1,'equity_ohlcv',now(),$2,$3::jsonb,$4,$5) RETURNING landing_id`,
		source, symbol, string(raw), hex.EncodeToString(digest[:]), raw).Scan(&landingID)
	if err != nil {
		t.Fatal(err)
	}
	return landingID
}

func TestPostgresGatePersistsLineageBlockAndInjectedFailures(t *testing.T) {
	// Synthetic DQ fixtures are allowed only in CI's disposable vnsignal_test DB.
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL is mandatory for postgres integration")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx := context.Background()
	if err = db.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	var databaseName string
	if err = db.QueryRowContext(ctx, `SELECT current_database()`).Scan(&databaseName); err != nil {
		t.Fatal(err)
	}
	if databaseName != "vnsignal_test" {
		t.Fatalf("refusing synthetic DQ fixtures outside disposable vnsignal_test database (connected database %q)", databaseName)
	}
	var day time.Time
	err = db.QueryRowContext(ctx, `SELECT date '2098-01-01'+n
		FROM generate_series(0,300) AS g(n)
		WHERE NOT EXISTS (SELECT 1 FROM core.calendar c WHERE c.trade_date IN (date '2098-01-01'+n-1,date '2098-01-01'+n,date '2098-01-01'+n+1))
		AND NOT EXISTS (SELECT 1 FROM core.calendar_overrides o WHERE o.trade_date IN (date '2098-01-01'+n-1,date '2098-01-01'+n,date '2098-01-01'+n+1))
		ORDER BY n LIMIT 1`).Scan(&day)
	if err != nil {
		t.Fatal(err)
	}
	prior := day.AddDate(0, 0, -1)
	missingDay := day.AddDate(0, 0, 1)
	fixtureID := fmt.Sprintf("%d", time.Now().UnixNano())
	fixtureSource := "dq_test_" + fixtureID
	fixtureReason := "synthetic DQ fixture " + fixtureID
	qualityJobID := int64(0)
	qualityLandingID := int64(0)
	qualityJobKey := "dq-quality-" + fixtureID
	primaryLandingIDs := make([]int64, RequiredCrossSourcePairs)
	secondaryLandingIDs := make([]int64, RequiredCrossSourcePairs)
	symbols := make([]string, RequiredCrossSourcePairs)
	for i := range symbols {
		symbols[i] = fmt.Sprintf("DQZ%02d_%s", i, fixtureID)
	}
	runKeyPrefix := "dq-gate-" + fixtureID + "-"
	// Register cleanup before the first fixture write. It uses unique markers
	// and symbol names so it can remove any partially-created setup safely.
	t.Cleanup(func() {
		cleanup := func(query string, args ...any) {
			if _, cleanupErr := db.ExecContext(context.Background(), query, args...); cleanupErr != nil {
				t.Errorf("fixture cleanup failed: %v", cleanupErr)
			}
		}
		cleanup(`DELETE FROM ops.dq_gate_results WHERE run_id IN (SELECT run_id FROM ops.pipeline_runs WHERE idempotency_key LIKE $1)`, runKeyPrefix+"%")
		cleanup(`DELETE FROM ops.pipeline_runs WHERE idempotency_key LIKE $1`, runKeyPrefix+"%")
		cleanup(`DELETE FROM ops.bar_quality_issues WHERE job_id=$1`, qualityJobID)
		cleanup(`DELETE FROM ops.ingest_jobs WHERE job_id=$1`, qualityJobID)
		cleanup(`DELETE FROM ops.dq_cross_source_samples WHERE trade_date=$1 AND symbol=ANY($2)`, day, symbols)
		cleanup(`DELETE FROM ops.dq_tier_a_symbols WHERE trade_date=$1 AND symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol=ANY($2))`, day, symbols)
		cleanup(`DELETE FROM core.bars_daily WHERE symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol=ANY($1))`, symbols)
		cleanup(`DELETE FROM core.calendar_overrides WHERE trade_date=$1 AND reason=$2`, day, fixtureReason)
		cleanup(`DELETE FROM core.calendar WHERE trade_date IN ($1,$2,$3) AND source=$4`, prior, day, missingDay, fixtureSource)
		cleanup(`DELETE FROM core.symbols WHERE symbol=ANY($1)`, symbols)
	})
	for _, d := range []time.Time{prior, day} {
		isSession := !d.Equal(day) // Expected-session override below supersedes this false base row.
		if _, err = db.ExecContext(ctx, `INSERT INTO core.calendar(trade_date,is_session,source) VALUES($1,$2,$3)`, d, isSession, fixtureSource); err != nil {
			t.Fatal(err)
		}
	}
	if _, err = db.ExecContext(ctx, `INSERT INTO core.calendar_overrides(trade_date,is_session,reason) VALUES($1,true,$2)`, day, fixtureReason); err != nil {
		t.Fatal(err)
	}
	ids := make([]int64, RequiredCrossSourcePairs)
	for i := range ids {
		symbol := symbols[i]
		if err = db.QueryRowContext(ctx, `INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at) VALUES($1,'HOSE',now(),now()) RETURNING symbol_id`, symbol).Scan(&ids[i]); err != nil {
			t.Fatal(err)
		}
		for _, d := range []time.Time{prior, day} {
			_, err = db.ExecContext(ctx, `INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at) VALUES($1,$2,100,101,99,100,100,'unknown',$3,'00000000-0000-0000-0000-000000000001',now())`, ids[i], d, fixtureSource)
			if err != nil {
				t.Fatal(err)
			}
		}
		_, err = db.ExecContext(ctx, `INSERT INTO ops.dq_tier_a_symbols(trade_date,symbol_id) VALUES($1,$2)`, day, ids[i])
		if err != nil {
			t.Fatal(err)
		}
		primaryLandingIDs[i] = insertSyntheticSourceLanding(t, ctx, db, symbol, "fixture_primary", "fixture_primary", "synthetic provider A", day.Format("2006-01-02"), 100)
		secondaryLandingIDs[i] = insertSyntheticSourceLanding(t, ctx, db, symbol, "fixture_secondary", "fixture_secondary", "synthetic provider B", day.Format("2006-01-02"), 100)
	}
	for i := 0; i < RequiredCrossSourcePairs; i++ {
		_, err = db.ExecContext(ctx, `INSERT INTO ops.dq_cross_source_samples(
			trade_date,symbol,primary_source,primary_close,secondary_source,secondary_close,selected_for_gate,
			primary_landing_id,primary_source_row,secondary_landing_id,secondary_source_row)
			VALUES($1,$2,'fixture_primary',100,'fixture_secondary',100,true,$3,0,$4,0)`, day, symbols[i], primaryLandingIDs[i], secondaryLandingIDs[i])
		if err != nil {
			t.Fatal(err)
		}
	}
	var tierCount, pairCount int
	if err = db.QueryRowContext(ctx, `SELECT tier_a_symbols,independent_source_pairs FROM ops.dq_gate_input_readiness WHERE trade_date=$1`, day).Scan(&tierCount, &pairCount); err != nil || tierCount != len(ids) || pairCount != RequiredCrossSourcePairs {
		t.Fatalf("fixture input readiness tier=%d pairs=%d err=%v", tierCount, pairCount, err)
	}
	newRun := func(label string) string {
		var id string
		key := runKeyPrefix + label
		err := db.QueryRowContext(ctx, `INSERT INTO ops.pipeline_runs(run_id,idempotency_key,status,step) VALUES(gen_random_uuid(),$1,'RUNNING','dq_test') RETURNING run_id`, key).Scan(&id)
		if err != nil {
			t.Fatal(err)
		}
		return id
	}
	passID := newRun("pass")
	report, err := RunPostgresGate(ctx, db, passID, day)
	if err != nil || len(report.Blocking) != 0 {
		t.Fatalf("healthy lineaged evidence did not pass: report=%+v err=%v", report, err)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET primary_source_row=NULL
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0]); err == nil {
		t.Fatal("partial source-row lineage was accepted")
	}
	var savedStatus, pipelineStatus string
	if err = db.QueryRowContext(ctx, `SELECT g.status,p.status FROM ops.dq_gate_results g JOIN ops.pipeline_runs p USING(run_id) WHERE g.run_id=$1`, passID).Scan(&savedStatus, &pipelineStatus); err != nil || savedStatus != "PASSED" || pipelineStatus != "PASSED" {
		t.Fatalf("saved=%s pipeline=%s err=%v", savedStatus, pipelineStatus, err)
	}
	// Missing lineage blocks even when stored values disagree; the gate must
	// not consume closes that cannot be replayed to exact source rows.
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET primary_close=120,
		primary_landing_id=NULL,primary_source_row=NULL,secondary_landing_id=NULL,secondary_source_row=NULL
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0]); err != nil {
		t.Fatal(err)
	}
	lineageID := newRun("missing-lineage")
	lineageReport, lineageErr := RunPostgresGate(ctx, db, lineageID, day)
	lineageBlockers := strings.Join(lineageReport.Blocking, " ")
	if !errors.Is(lineageErr, ErrBlocked) || !strings.Contains(lineageBlockers, "source-landing and source-row lineage") || strings.Contains(lineageBlockers, "cross-source close mismatch") {
		t.Fatalf("unlineaged values were consumed: report=%+v err=%v", lineageReport, lineageErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET primary_close=100,
		primary_landing_id=$3,primary_source_row=0,secondary_landing_id=$4,secondary_source_row=0
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], primaryLandingIDs[0], secondaryLandingIDs[0]); err != nil {
		t.Fatal(err)
	}
	// A payload that claims a different provider than the raw landing is
	// rejected without feeding its stored close into Gate.
	badAttributionID := insertSyntheticSourceLanding(t, ctx, db, symbols[0], "fixture_secondary", "fixture_primary", "synthetic provider B", day.Format("2006-01-02"), 120)
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=120,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], badAttributionID); err != nil {
		t.Fatal(err)
	}
	metadataID := newRun("source-metadata")
	metadataReport, metadataErr := RunPostgresGate(ctx, db, metadataID, day)
	metadataBlockers := strings.Join(metadataReport.Blocking, " ")
	if !errors.Is(metadataErr, ErrBlocked) || !strings.Contains(metadataBlockers, "provider source or organisation attribution unavailable") || strings.Contains(metadataBlockers, "cross-source close mismatch") {
		t.Fatalf("mismatched provider attribution was not rejected safely: report=%+v err=%v", metadataReport, metadataErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=100,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], secondaryLandingIDs[0]); err != nil {
		t.Fatal(err)
	}
	// Matching source IDs still do not prove independent providers when the
	// archived provider organisation is the same on both legs.
	sameOrgID := insertSyntheticSourceLanding(t, ctx, db, symbols[0], "fixture_secondary", "fixture_secondary", "synthetic provider A", day.Format("2006-01-02"), 120)
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=120,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], sameOrgID); err != nil {
		t.Fatal(err)
	}
	providerID := newRun("same-provider")
	providerReport, providerErr := RunPostgresGate(ctx, db, providerID, day)
	providerBlockers := strings.Join(providerReport.Blocking, " ")
	if !errors.Is(providerErr, ErrBlocked) || !strings.Contains(providerBlockers, "providers are not independently identified") || strings.Contains(providerBlockers, "cross-source close mismatch") {
		t.Fatalf("same-organisation sources were treated as independent: report=%+v err=%v", providerReport, providerErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=100,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], secondaryLandingIDs[0]); err != nil {
		t.Fatal(err)
	}
	// Tampering with the archived bytes without updating the digest blocks
	// the sample before its source close can enter Gate.
	badBytesID := insertCorruptSourceLanding(t, ctx, db, symbols[0], day.Format("2006-01-02"))
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=120,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], badBytesID); err != nil {
		t.Fatal(err)
	}
	checksumID := newRun("payload-checksum")
	checksumReport, checksumErr := RunPostgresGate(ctx, db, checksumID, day)
	checksumBlockers := strings.Join(checksumReport.Blocking, " ")
	if !errors.Is(checksumErr, ErrBlocked) || !strings.Contains(checksumBlockers, "source landing checksum or JSON invalid") || strings.Contains(checksumBlockers, "cross-source close mismatch") {
		t.Fatalf("tampered source bytes were not rejected before comparison: report=%+v err=%v", checksumReport, checksumErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=100,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], secondaryLandingIDs[0]); err != nil {
		t.Fatal(err)
	}
	// Valid independent source rows with a >0.5% difference reach Gate and
	// block with its cross-source mismatch reason.
	badCloseID := insertSyntheticSourceLanding(t, ctx, db, symbols[0], "fixture_secondary", "fixture_secondary", "synthetic provider B", day.Format("2006-01-02"), 101)
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=101,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], badCloseID); err != nil {
		t.Fatal(err)
	}
	mismatchID := newRun("close-mismatch")
	mismatchReport, mismatchErr := RunPostgresGate(ctx, db, mismatchID, day)
	if !errors.Is(mismatchErr, ErrBlocked) || !strings.Contains(strings.Join(mismatchReport.Blocking, " "), "cross-source close mismatch "+symbols[0]) {
		t.Fatalf("verified cross-source close mismatch did not block: report=%+v err=%v", mismatchReport, mismatchErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE ops.dq_cross_source_samples SET secondary_close=100,secondary_landing_id=$3
		WHERE trade_date=$1 AND symbol=$2`, day, symbols[0], secondaryLandingIDs[0]); err != nil {
		t.Fatal(err)
	}
	// A price jump beyond the exchange limit is quarantined and blocks the
	// persisted gate unless verified first-public-trade evidence exempts it.
	if _, err = db.ExecContext(ctx, `UPDATE core.bars_daily SET h=108,c=108 WHERE symbol_id=$1 AND trade_date=$2`, ids[0], day); err != nil {
		t.Fatal(err)
	}
	actionID := newRun("action")
	actionReport, actionErr := RunPostgresGate(ctx, db, actionID, day)
	actionWarnings := strings.Join(actionReport.Warnings, " ")
	if actionErr != nil || len(actionReport.Blocking) != 0 || !strings.Contains(actionWarnings, "suspected unadjusted corporate action "+symbols[0]) || !strings.Contains(strings.Join(actionReport.Quarantined, " "), symbols[0]) {
		t.Fatalf("action fault should warn and quarantine without blocking a healthy gate: %+v err=%v", actionReport, actionErr)
	}
	if _, err = db.ExecContext(ctx, `UPDATE core.bars_daily SET h=101,c=100 WHERE symbol_id=$1 AND trade_date=$2`, ids[0], day); err != nil {
		t.Fatal(err)
	}
	// A historical partial backfill does not invalidate an otherwise valid
	// expected session. Date-local source-quality findings still block.
	qualityPayload := `{"fixture":"` + fixtureID + `"}`
	if err = db.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES(gen_random_uuid(),'vci','equity_ohlcv',now(),$1,$2::jsonb,
		       encode(sha256(convert_to($3,'UTF8')),'hex'),convert_to($3,'UTF8'))
		RETURNING landing_id`, symbols[0], qualityPayload, qualityPayload).Scan(&qualityLandingID); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRowContext(ctx, `INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to,state,last_error_type,landed_id)
		VALUES($1,'equity_ohlcv',$2,'vci',$3,$4,'PARTIAL','fixture_old_partial',$5) RETURNING job_id`, qualityJobKey, symbols[0], day.AddDate(0, 0, -30), day.AddDate(0, 0, -1), qualityLandingID).Scan(&qualityJobID); err != nil {
		t.Fatal(err)
	}
	oldPartialID := newRun("old-partial")
	oldPartialReport, oldPartialErr := RunPostgresGate(ctx, db, oldPartialID, day)
	if oldPartialErr != nil || len(oldPartialReport.Blocking) != 0 {
		t.Fatalf("historical partial job should not block current session: %+v err=%v", oldPartialReport, oldPartialErr)
	}
	if _, err = db.ExecContext(ctx, `DELETE FROM ops.ingest_jobs WHERE job_id=$1`, qualityJobID); err != nil {
		t.Fatal(err)
	}
	qualityJobID = 0
	if err = db.QueryRowContext(ctx, `INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to,state,last_error_type,landed_id)
		VALUES($1,'equity_ohlcv',$2,'vci',$3,$3,'PARTIAL','fixture_exact_day',$4) RETURNING job_id`, qualityJobKey+"-exact", symbols[0], day, qualityLandingID).Scan(&qualityJobID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.ExecContext(ctx, `INSERT INTO ops.bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
		VALUES($1,$2,0,$3,'INVALID_OHLC','fixture invalid range')`, qualityJobID, qualityLandingID, day); err != nil {
		t.Fatal(err)
	}
	qualityID := newRun("quality")
	qualityReport, qualityErr := RunPostgresGate(ctx, db, qualityID, day)
	qualityReasons := strings.Join(qualityReport.Blocking, " ")
	if !errors.Is(qualityErr, ErrBlocked) || !strings.Contains(qualityReasons, "invalid source bar "+symbols[0]+" INVALID_OHLC") || strings.Contains(qualityReasons, "PARTIAL equity OHLCV job") {
		t.Fatalf("date-local invalid finding should block without job-state blockers: %+v err=%v", qualityReport, qualityErr)
	}
	if _, err = db.ExecContext(ctx, `DELETE FROM ops.bar_quality_issues WHERE job_id=$1`, qualityJobID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.ExecContext(ctx, `DELETE FROM ops.ingest_jobs WHERE job_id=$1`, qualityJobID); err != nil {
		t.Fatal(err)
	}
	// The source landing remains as immutable audit evidence after its mutable
	// disposable test job and quality rows are cleaned up.
	qualityJobID, qualityLandingID = 0, 0
	// Removing one of 30 current fixture bars breaches the stale-share threshold.
	if _, err = db.ExecContext(ctx, `DELETE FROM core.bars_daily WHERE symbol_id=ANY($1) AND trade_date=$2`, ids[:1], day); err != nil {
		t.Fatal(err)
	}
	failID := newRun("stale")
	report, err = RunPostgresGate(ctx, db, failID, day)
	if !errors.Is(err, ErrBlocked) || len(report.Blocking) == 0 {
		t.Fatalf("expected blocked report=%+v err=%v", report, err)
	}
	if err = db.QueryRowContext(ctx, `SELECT g.status,p.status FROM ops.dq_gate_results g JOIN ops.pipeline_runs p USING(run_id) WHERE g.run_id=$1`, failID).Scan(&savedStatus, &pipelineStatus); err != nil || savedStatus != "STALE" || pipelineStatus != "STALE" {
		t.Fatalf("saved=%s pipeline=%s err=%v", savedStatus, pipelineStatus, err)
	}
	if _, err = db.ExecContext(ctx, `INSERT INTO core.calendar(trade_date,is_session,source) VALUES($1,true,$2)`, missingDay, fixtureSource); err != nil {
		t.Fatal(err)
	}
	missingID := newRun("missing")
	missing, err := RunPostgresGate(ctx, db, missingID, missingDay)
	if !errors.Is(err, ErrBlocked) || !strings.Contains(strings.Join(missing.Blocking, " "), "Tier A universe unavailable") || !strings.Contains(strings.Join(missing.Blocking, " "), "cross-source sample unavailable") {
		t.Fatalf("missing evidence was not recorded as blocked: %+v err=%v", missing, err)
	}
	if err = db.QueryRowContext(ctx, `SELECT g.status,p.status FROM ops.dq_gate_results g JOIN ops.pipeline_runs p USING(run_id) WHERE g.run_id=$1`, missingID).Scan(&savedStatus, &pipelineStatus); err != nil || (savedStatus != "FAILED" && savedStatus != "STALE") || savedStatus != pipelineStatus {
		t.Fatalf("missing evidence status=%s pipeline=%s err=%v", savedStatus, pipelineStatus, err)
	}
}

func insertCorruptSourceLanding(t *testing.T, ctx context.Context, db *sql.DB, symbol, day string) int64 {
	t.Helper()
	good := []byte(`{"columns":["time","open","high","low","close","volume"],"count":1,"rows":[{"time":"` + day + `","open":119,"high":121,"low":118,"close":120,"volume":100}],"attributes":{"source":"fixture_secondary","organisation":"synthetic provider B"}}`)
	bad := []byte(`{"intentionally":"different archived bytes"}`)
	digest := sha256.Sum256(good)
	var id int64
	err := db.QueryRowContext(ctx, `INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
		VALUES(gen_random_uuid(),'fixture_secondary','equity_ohlcv',now(),$1,$2::jsonb,$3,$4) RETURNING landing_id`,
		symbol, string(good), hex.EncodeToString(digest[:]), bad).Scan(&id)
	if err != nil {
		t.Fatal(err)
	}
	return id
}

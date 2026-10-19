//go:build postgres_integration

package ingest

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/live"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/migrate"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/vndirect"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/worker"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func pgTestDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL is mandatory for postgres integration")
	}
	db, e := sql.Open("pgx", dsn)
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { db.Close() })
	if e = db.PingContext(context.Background()); e != nil {
		t.Fatal(e)
	}
	return db
}
func clearDB(t *testing.T, db *sql.DB) {
	t.Helper()
	// Each integration case gets fresh synthetic state. The guard restricts
	// schema reset to the local disposable test database; production raw
	// landings remain append-only throughout normal application operations.
	requireVNSignalTestDatabase(t)
	if _, e := db.Exec(`DROP SCHEMA IF EXISTS raw,core,feat,ml,ops CASCADE`); e != nil {
		t.Fatal(e)
	}
	if _, e := db.Exec(`DROP TABLE IF EXISTS public.vnpipe_migrations`); e != nil {
		t.Fatal(e)
	}
	_, source, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not locate integration test source for migration reset")
	}
	migrationDir := filepath.Join(filepath.Dir(source), "..", "..", "..", "sql", "migrations")
	if _, e := migrate.Apply(context.Background(), db, migrationDir); e != nil {
		t.Fatalf("reset disposable integration schema: %v", e)
	}
}

func TestPostgresIndexReservationAndLandingTransaction(t *testing.T) {
	requireVNSignalTestDatabase(t)
	t.Setenv("VNPIPE_DISABLE_LIVE", "0") // Gateway uses only the in-process fixture below.
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	installVerifiedQuota(t, store, 2)
	called := 0
	pacer, _ := quota.NewPacer(60000, 2)
	gate, _ := live.New(pacer, func(_ context.Context, job map[string]any) (worker.Response, error) {
		called++
		if job["op"] != "index_ohlcv" || job["symbol"] != "VNINDEX" || (job["source"] != "kbs" && job["source"] != "vci") {
			t.Fatalf("request differs from probe: %#v", job)
		}
		data := validIndex
		if job["source"] == "vci" {
			data = validIndexVCI
		}
		return worker.Response{ID: job["id"].(string), OK: true, Data: json.RawMessage(data)}, nil
	})
	r := Runner{Gateway: gate, Store: store, Now: time.Now}
	job := BackfillJob{Route: "index_ohlcv", Symbol: "VNINDEX", Start: "2026-10-16", End: "2026-10-16"}
	summary, err := r.RunIndexBackfill(context.Background(), []BackfillJob{job})
	if err != nil || summary.Committed != 1 || called != 1 {
		t.Fatalf("summary=%+v calls=%d err=%v", summary, called, err)
	}
	var landed, bars, succeeded int
	if err = db.QueryRow(`SELECT COUNT(*) FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id
		WHERE j.route='index_ohlcv' AND j.symbol='VNINDEX' AND j.source='kbs' AND l.payload_bytes IS NOT NULL`).Scan(&landed); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(`SELECT COUNT(*) FROM core.index_bars WHERE index_symbol='VNINDEX' AND trade_date='2026-10-16' AND source='kbs'`).Scan(&bars); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(`SELECT COUNT(*) FROM ops.api_reservations r JOIN ops.ingest_jobs j USING(job_id) WHERE j.route='index_ohlcv' AND r.outcome='SUCCEEDED'`).Scan(&succeeded); err != nil {
		t.Fatal(err)
	}
	if landed != 1 || bars != 1 || succeeded != 1 {
		t.Fatalf("landing=%d bars=%d audited=%d", landed, bars, succeeded)
	}
	// A repeat is an idempotent skip and cannot consume another reservation.
	summary, err = r.RunIndexBackfill(context.Background(), []BackfillJob{job})
	if err != nil || summary.Skipped != 1 || called != 1 {
		t.Fatalf("resume=%+v calls=%d err=%v", summary, called, err)
	}
	vciJob := job
	vciJob.Source = "vci"
	summary, err = r.RunIndexBackfill(context.Background(), []BackfillJob{vciJob})
	if err != nil || summary.Committed != 1 || called != 2 {
		t.Fatalf("VCI summary=%+v calls=%d err=%v", summary, called, err)
	}
	var vciBars, totalBars int
	if err = db.QueryRow(`SELECT COUNT(*) FROM core.index_bars WHERE index_symbol='VNINDEX' AND trade_date='2026-10-16' AND source='vci'`).Scan(&vciBars); err != nil {
		t.Fatal(err)
	}
	if err = db.QueryRow(`SELECT COUNT(*) FROM core.index_bars WHERE index_symbol='VNINDEX' AND trade_date='2026-10-16'`).Scan(&totalBars); err != nil {
		t.Fatal(err)
	}
	if vciBars != 1 || totalBars != 2 {
		t.Fatalf("provider-keyed bars vci=%d total=%d", vciBars, totalBars)
	}
}
func installVerifiedQuota(t *testing.T, s *PostgresStore, budget int) {
	t.Helper()
	// DailyRemaining=budget*2 means floor(80%) >= budget for budget>=2.
	e := s.InstallQuota(context.Background(), QuotaSnapshot{DailyRemaining: budget * 2, MonthlyRemaining: 10000, TradingDaysRemaining: 2, VerifiedRPM: 60, ObservedAt: time.Now().Add(-500 * time.Millisecond)})
	if e != nil {
		t.Fatal(e)
	}
}
func TestPostgresIngestionTransactionAndResume(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "0")
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	installVerifiedQuota(t, store, 3)
	_, err := db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES('FPT','HOSE',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	p, _ := quota.NewPacer(60, 3)
	calls := 0
	gate, _ := live.New(p, func(_ context.Context, job map[string]any) (worker.Response, error) {
		calls++
		return worker.Response{ID: job["id"].(string), OK: true, Data: json.RawMessage(payload("["+two+"]", 1))}, nil
	})
	runner := Runner{Gateway: gate, Store: store, Now: time.Now}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	sum, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job, job}, "vci")
	if err != nil || sum.Committed != 1 || sum.Skipped != 1 || calls != 1 {
		t.Fatalf("sum=%+v err=%v calls=%d", sum, err, calls)
	}
	var n int
	for _, q := range []string{
		`SELECT COUNT(*) FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id
		  WHERE j.route='equity_ohlcv' AND j.symbol='FPT' AND j.source='vci'
	            AND j.date_from='2026-10-15' AND j.date_to='2026-10-16'`,
		`SELECT COUNT(*) FROM core.bars_daily`,
		`SELECT COUNT(*) FROM ops.ingest_jobs WHERE state='COMPLETED' AND landed_id IS NOT NULL`,
		`SELECT COUNT(*) FROM ops.api_reservations WHERE outcome='SUCCEEDED'`,
	} {
		if err = db.QueryRow(q).Scan(&n); err != nil || n != 1 {
			t.Fatalf("query=%s n=%d err=%v", q, n, err)
		}
	}
	// JSONB is intentionally queryable, but exact bytes must also survive
	// normalization for provenance/hash verification.
	var original []byte
	if err = db.QueryRow(`SELECT payload_bytes FROM raw.landings WHERE route='equity_ohlcv' AND symbol='FPT' ORDER BY landing_id DESC LIMIT 1`).Scan(&original); err != nil ||
		!bytes.Equal(original, []byte(payload("["+two+"]", 1))) {
		t.Fatalf("vendor payload byte parity: %v", err)
	}
	again, err := runner.RunBarsBackfill(context.Background(), []BackfillJob{job}, "vci")
	if err != nil || again.Skipped != 1 || calls != 1 {
		t.Fatalf("resume=%+v err=%v calls=%d", again, err, calls)
	}
}

func TestPostgresVNDIRECTCommitPersistsReferenceInputs(t *testing.T) {
	requireVNSignalTestDatabase(t)
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
		VALUES('TSTVND','UPCOM',now(),now())`); err != nil {
		t.Fatal(err)
	}
	const requestURL = "https://api-finfo.vndirect.com.vn/v4/stock_prices?fixture=1"
	call, err := store.BeginExternalMarketCall(context.Background(), "vndirect", "TSTVND", "2024-01-02", "2024-01-02", requestURL, false)
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte(`{"currentPage":1,"size":5000,"totalElements":1,"totalPages":1,"data":[{"code":"TSTVND","date":"2024-01-02","open":9.2,"high":9.3,"low":9.1,"close":9.2,"basicPrice":9.1,"average":9.2,"floor":" upcom ","adOpen":8.1,"adHigh":8.2,"adLow":8.0,"adClose":8.1,"nmVolume":0,"ptVolume":1200}]}`)
	rows, err := vndirect.ParseHistory(raw, "TSTVND", "2024-01-02", "2024-01-02")
	if err != nil {
		t.Fatal(err)
	}
	summary, err := store.CommitVNDIRECTHistory(context.Background(), call, time.Now(), vndirect.History{
		Rows: rows, Raw: raw, RequestURL: requestURL, HTTPStatus: http.StatusOK,
	})
	if err != nil || summary.Rows != 1 || summary.NoTrade != 1 || summary.Invalid != 0 {
		t.Fatalf("summary=%+v err=%v", summary, err)
	}
	var referencePrice, averagePrice float64
	var exchangeCode string
	var isTraded bool
	err = db.QueryRow(`SELECT basic_price,average_price,exchange_code,is_traded
		FROM core.bars_daily_sources WHERE source='vndirect' AND trade_date='2024-01-02' AND symbol_id=(
			SELECT symbol_id FROM core.symbols WHERE symbol='TSTVND')`).
		Scan(&referencePrice, &averagePrice, &exchangeCode, &isTraded)
	if err != nil {
		t.Fatal(err)
	}
	if referencePrice != 9.1 || averagePrice != 9.2 || exchangeCode != "UPCOM" || isTraded {
		t.Fatalf("reference inputs were not persisted: basic=%v average=%v exchange=%q traded=%v",
			referencePrice, averagePrice, exchangeCode, isTraded)
	}
}

func TestPostgresDurableQuotaAndRollback(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	installVerifiedQuota(t, s, 1)
	ctx := context.Background()
	a := BackfillJob{Route: "equity_ohlcv", Symbol: "FPT", Start: "2026-10-15", End: "2026-10-16"}
	b := BackfillJob{Route: "equity_ohlcv", Symbol: "HPG", Start: "2026-10-15", End: "2026-10-16"}
	at := time.Now().Add(time.Second)
	_, err := s.ReserveAttempt(ctx, a, "quota-test-A", "vci", at)
	if err != nil {
		t.Fatal(err)
	}
	_, err = s.ReserveAttempt(ctx, b, "quota-test-B", "vci", at)
	if !errors.Is(err, quota.ErrExhausted) {
		t.Fatalf("quota budget bypass: %v", err)
	}
	if err = s.MarkDispatch(ctx, "quota-test-A"); err != nil {
		t.Fatal(err)
	}
	if err = s.MarkOutcome(ctx, "quota-test-A", "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(payload("["+two+"]", 1))
	bars, err := NormalizeBars("FPT", raw)
	if err != nil {
		t.Fatal(err)
	}
	// No core.symbols FPT exists: every insert must roll back, including raw.
	var rawBefore int
	if err = db.QueryRow(`SELECT COUNT(*) FROM raw.landings`).Scan(&rawBefore); err != nil {
		t.Fatal(err)
	}
	land := Landing{JobID: "quota-test-A", Source: "vci", FetchedAt: time.Now(), Raw: raw, Bars: bars}
	land.SHA256 = checksum(raw)
	if err = s.CommitLanding(ctx, land); err == nil {
		t.Fatal("committed before listing")
	}
	var count int
	if err = db.QueryRow(`SELECT COUNT(*) FROM raw.landings`).Scan(&count); err != nil || count != rawBefore {
		t.Fatalf("failed transaction changed append-only raw landing count: before=%d after=%d %v", rawBefore, count, err)
	}
	if err = db.QueryRow(`SELECT COUNT(*) FROM core.bars_daily`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("partial bars: %d %v", count, err)
	}
	// Even after a restart a fresh store sees the same spent allowance.
	fresh, _ := NewPostgresStore(db)
	_, err = fresh.ReserveAttempt(ctx, b, "quota-test-B", "vci", at)
	if !errors.Is(err, quota.ErrExhausted) {
		t.Fatalf("restart reset quota: %v", err)
	}
}

func checksum(data []byte) string { x := sha256.Sum256(data); return hex.EncodeToString(x[:]) }

func TestPostgresQuarantinePreservesRawWithoutCanonicalBars(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	installVerifiedQuota(t, s, 1)
	ctx := context.Background()
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "A32", Start: "2026-10-15", End: "2026-10-16"}
	key := "equity_ohlcv:A32:vci:2026-10-15:2026-10-16"
	if _, err := s.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkDispatch(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err := s.MarkOutcome(ctx, key, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(payload(`[{"time":"2026-10-15","open":0,"high":105,"low":99,"close":103,"volume":100}]`, 1))
	reason := "InvalidFrame: row 0 date 2026-10-15: open price is nonpositive or nonfinite"
	if err := s.QuarantineFrame(ctx, key, "vci", reason, raw); err != nil {
		t.Fatal(err)
	}
	var state, recordedReason, route, digest string
	var archived []byte
	if err := db.QueryRow(`SELECT j.state,j.last_error_type,l.route,l.payload_bytes,l.payload_sha256
        FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id
        WHERE j.idempotency_key=$1`, key).Scan(&state, &recordedReason, &route, &archived, &digest); err != nil {
		t.Fatal(err)
	}
	if state != "BLOCKED" || recordedReason != reason || route != "equity_ohlcv_quarantine" ||
		!bytes.Equal(archived, []byte(raw)) || digest != checksum(raw) {
		t.Fatalf("quarantine lost provenance: state=%s reason=%s route=%s", state, recordedReason, route)
	}
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM core.bars_daily`).Scan(&count); err != nil || count != 0 {
		t.Fatalf("invalid bars entered canonical storage: %d %v", count, err)
	}
	if err := s.QuarantineFrame(ctx, key, "vci", reason, raw); err == nil {
		t.Fatal("duplicate quarantine unexpectedly succeeded")
	}
}

func TestMarketArchiveOfflineRecoveryPreservesInvalidRowsAndQuota(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	db := pgTestDB(t)
	clearDB(t, db)
	store, _ := NewPostgresStore(db)
	installVerifiedQuota(t, store, 2)
	ctx := context.Background()
	_, err := db.Exec(`INSERT INTO core.symbols (symbol,exchange,first_seen_at,last_seen_at)
        VALUES ('ABR','UPCOM',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "ABR", Start: "2019-01-10", End: "2019-01-14"}
	key := "equity_ohlcv:ABR:vci:2019-01-10:2019-01-14"
	if _, err = store.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err = store.MarkDispatch(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err = store.MarkOutcome(ctx, key, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	raw := json.RawMessage(payload(`[
        {"time":"2019-01-10","open":3.76,"high":3.38,"low":3.38,"close":3.38,"volume":0},
        {"time":"2019-01-11","open":10,"high":11,"low":9,"close":10.5,"volume":100},
        {"time":"2019-01-14","open":10,"high":7,"low":8,"close":9,"volume":100}]`, 3))
	if err = store.QuarantineFrame(ctx, key, "vci", "InvalidFrame", raw); err != nil {
		t.Fatal(err)
	}
	state, err := store.RecoverArchivedFrame(ctx, key)
	if err != nil || state != "PARTIAL" {
		t.Fatalf("recovery=%s err=%v", state, err)
	}
	for query, want := range map[string]int{
		"SELECT count(*) FROM ops.ingest_jobs j JOIN raw.landings l ON l.landing_id=j.landed_id WHERE j.route='equity_ohlcv' AND j.symbol='ABR' AND j.state='PARTIAL'": 1,
		"SELECT count(*) FROM core.bars_daily":                                                1,
		"SELECT count(*) FROM ops.bar_quality_issues":                                         2,
		"SELECT count(*) FROM ops.bar_quality_issues WHERE category='ZERO_VOLUME_UNVERIFIED'": 1,
		"SELECT count(*) FROM ops.bar_quality_issues WHERE category='INVALID_OHLC'":           1,
		"SELECT count(*) FROM ops.ingest_jobs WHERE state='PARTIAL'":                          1,
		"SELECT count(*) FROM ops.api_reservations":                                           1,
	} {
		var n int
		if err = db.QueryRow(query).Scan(&n); err != nil || n != want {
			t.Fatalf("%s: got %d want %d err=%v", query, n, want, err)
		}
	}
	var traded bool
	if err = db.QueryRow(`SELECT is_traded FROM core.bars_daily`).Scan(&traded); err != nil || !traded {
		t.Fatal("canonical bar is not an actual traded session")
	}
	if _, err = store.RecoverArchivedFrame(ctx, key); err == nil {
		t.Fatal("replayed already recovered frame")
	}
}

func TestLegacyUnarchivedRequeueIsAuditedAndDoesNotRefundQuota(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	s, _ := NewPostgresStore(db)
	installVerifiedQuota(t, s, 3)
	_, err := db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES ('A32','UPCOM',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "A32", Start: "2018-10-01", End: "2026-10-16"}
	key := "equity_ohlcv:A32:vci:2018-10-01:2026-10-16"
	if _, err = s.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err = s.MarkDispatch(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err = s.MarkOutcome(ctx, key, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}
	if err = s.BlockInvalid(ctx, key, "InvalidFrame"); err != nil {
		t.Fatal(err)
	}
	if err = s.RequeueUnarchivedLegacy(ctx, "A32", job.Start, job.End, "vci"); err != nil {
		t.Fatal(err)
	}
	var state string
	if err = db.QueryRow(`SELECT state FROM ops.ingest_jobs WHERE idempotency_key=$1`, key).Scan(&state); err != nil || state != "PENDING" {
		t.Fatalf("wrong post-requeue state %s: %v", state, err)
	}
	if err = s.RequeueUnarchivedLegacy(ctx, "A32", job.Start, job.End, "vci"); err == nil {
		t.Fatal("duplicate requeue accepted")
	}
	if _, err = s.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatalf("not safely retryable: %v", err)
	}
	for query, want := range map[string]int{
		"SELECT count(*) FROM ops.ingest_requeue_audit":           1,
		"SELECT count(*) FROM ops.api_reservations":               2,
		"SELECT attempts FROM ops.ingest_jobs WHERE symbol='A32'": 2,
		"SELECT spent FROM ops.quota_guard WHERE singleton=true":  2,
	} {
		var n int
		if err = db.QueryRow(query).Scan(&n); err != nil || n != want {
			t.Fatalf("audit quota mismatch %s got=%d want=%d err=%v", query, n, want, err)
		}
	}
}

func TestLifecycleZeroVolumeNeverImpliedListed(t *testing.T) {
	db := pgTestDB(t)
	clearDB(t, db)
	ctx := context.Background()
	_ = ctx
	_, err := db.Exec(`INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
        VALUES('LC1','UPCOM',now(),now())`)
	if err != nil {
		t.Fatal(err)
	}
	source := []byte(`{"official_notice":"first-ever public trade and dated status intervals","example_fixture":true}`)
	originalDigest := checksum(source)
	var landingID int64
	err = db.QueryRow(`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES('00000000-0000-0000-0000-000000000071','official',
               'security_lifecycle_notice',now(),'LC1',$1::jsonb,$2,$3)
        RETURNING landing_id`, string(source), originalDigest, source).Scan(&landingID)
	if err != nil {
		t.Fatal(err)
	}
	var jobID int64
	err = db.QueryRow(`INSERT INTO ops.ingest_jobs
        (idempotency_key,route,symbol,source,date_from,date_to,state)
        VALUES('equity_ohlcv:LC1:vci:2018-01-01:2020-04-15',
          'equity_ohlcv','LC1','vci','2018-01-01','2020-04-15','PENDING')
        RETURNING job_id`).Scan(&jobID)
	if err != nil {
		t.Fatal(err)
	}
	dates := []string{"2018-01-15", "2020-01-15", "2020-02-15", "2020-03-15", "2020-04-15"}
	for i, date := range dates {
		_, err = db.Exec(`INSERT INTO ops.bar_quality_issues
            (job_id,landing_id,source_row,trade_date,category,reason)
            VALUES($1,$2,$3,$4::date,'ZERO_VOLUME_UNVERIFIED','zero source volume')`,
			jobID, landingID, i, date)
		if err != nil {
			t.Fatal(err)
		}
	}
	var unknown int
	err = db.QueryRow(`SELECT count(*) FROM ops.zero_volume_lifecycle_status
        WHERE derived_lifecycle_status='LISTING_STATUS_UNVERIFIED'`).Scan(&unknown)
	if err != nil || unknown != 5 {
		t.Fatalf("premature tradability inference: %d %v", unknown, err)
	}
	var symbolID int64
	if err = db.QueryRow(`SELECT symbol_id FROM core.symbols WHERE symbol='LC1'`).Scan(&symbolID); err != nil {
		t.Fatal(err)
	}
	insert := func(kind, start, end string) {
		t.Helper()
		_, err = db.Exec(`INSERT INTO core.security_lifecycle_evidence
            (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
            VALUES ($1,'UPCOM',$2,$3::date,$4::date,$5,
             'https://www.hnx.vn/en-gb/co-phieu.html','2020-01-01')`,
			symbolID, kind, start, end, landingID)
		if err != nil {
			t.Fatalf("insert %s: %v", kind, err)
		}
	}
	insert("FIRST_EVER_PUBLIC_TRADE", "2020-01-01", "2020-01-01")
	insert("TRADE_ELIGIBLE", "2020-01-01", "2020-01-31")
	insert("TRADING_SUSPENDED", "2020-02-01", "2020-02-29")
	insert("DELISTED", "2020-03-01", "2020-03-31")
	expected := []string{"BEFORE_FIRST_PUBLIC_TRADE", "VERIFIED_ELIGIBLE_NO_MATCH",
		"VERIFIED_SUSPENDED", "VERIFIED_DELISTED", "LISTING_STATUS_UNVERIFIED"}
	rows, err := db.Query(`SELECT derived_lifecycle_status
        FROM ops.zero_volume_lifecycle_status ORDER BY trade_date`)
	if err != nil {
		t.Fatal(err)
	}
	got := []string{}
	for rows.Next() {
		var status string
		if err = rows.Scan(&status); err != nil {
			rows.Close()
			t.Fatal(err)
		}
		got = append(got, status)
	}
	if err = rows.Err(); err != nil {
		t.Fatal(err)
	}
	rows.Close()
	if len(got) != len(expected) {
		t.Fatalf("status coverage %+v", got)
	}
	for i, v := range expected {
		if got[i] != v {
			t.Fatalf("%s => %s, want %s", dates[i], got[i], v)
		}
	}
	insert("TRADE_ELIGIBLE", "2020-02-10", "2020-02-20")
	var conflicting string
	err = db.QueryRow(`SELECT derived_lifecycle_status FROM ops.zero_volume_lifecycle_status
        WHERE trade_date='2020-02-15'`).Scan(&conflicting)
	if err != nil || conflicting != "CONFLICTING_EVIDENCE" {
		t.Fatalf("contradictory trading windows silently accepted: %s %v", conflicting, err)
	}
	if _, err = db.Exec(`UPDATE core.security_lifecycle_evidence SET date_from='2000-01-01'
        WHERE symbol_id=$1`, symbolID); err == nil {
		t.Fatal("source lifecycle evidence was mutable")
	}
	_, err = db.Exec(`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES('00000000-0000-0000-0000-000000000072','official',
               'security_lifecycle_notice',now(),'LC1',$1::jsonb,$2,$3)`,
		string(source), "0000000000000000000000000000000000000000000000000000000000000000", source)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`INSERT INTO core.security_lifecycle_evidence
        (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
        SELECT $1,'UPCOM','TRADING_SUSPENDED','2020-04-01','2020-04-30',
               max(landing_id),'https://www.hnx.vn/en-gb/co-phieu.html','2020-01-01'
        FROM raw.landings`, symbolID)
	if err == nil {
		t.Fatal("tampered archived evidence digest accepted")
	}
}

func TestReclassifyPartialAuctionPriceRangeOffline(t *testing.T) {
	t.Setenv("VNPIPE_DISABLE_LIVE", "1")
	db := pgTestDB(t)
	clearDB(t, db)
	store, err := NewPostgresStore(db)
	if err != nil {
		t.Fatal(err)
	}
	installVerifiedQuota(t, store, 1)
	ctx := context.Background()
	if _, err = db.Exec(`INSERT INTO core.symbols (symbol,exchange,first_seen_at,last_seen_at)
        VALUES ('ABR','HOSE',now(),now())`); err != nil {
		t.Fatal(err)
	}
	job := BackfillJob{Route: "equity_ohlcv", Symbol: "ABR", Start: "2019-01-11", End: "2019-01-11"}
	key := "equity_ohlcv:ABR:vci:2019-01-11:2019-01-11"
	if _, err = store.ReserveAttempt(ctx, job, key, "vci", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err = store.MarkDispatch(ctx, key); err != nil {
		t.Fatal(err)
	}
	if err = store.MarkOutcome(ctx, key, "SUCCEEDED", ""); err != nil {
		t.Fatal(err)
	}

	rows := `[{"time":"2019-01-11","open":8,"high":11,"low":9,"close":8.5,"volume":100}]`
	raw := payloadWithAttribution(rows, 1, `{"source":"VCI","route":"equity_ohlcv","source_name":"VCI","organisation":"Provider One"}`)
	ingestID, err := newUUID()
	if err != nil {
		t.Fatal(err)
	}
	var landingID int64
	if err = db.QueryRow(`INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES($1::uuid,'vci','equity_ohlcv_quarantine',now(),'ABR',$2::jsonb,$3,$4)
        RETURNING landing_id`, ingestID, string(raw), checksum(raw), []byte(raw)).Scan(&landingID); err != nil {
		t.Fatal(err)
	}
	var jobID int64
	if err = db.QueryRow(`UPDATE ops.ingest_jobs
        SET state='PARTIAL',last_error_type='PartialInvalidTradedBars',landed_id=$2
        WHERE idempotency_key=$1 RETURNING job_id`, key, landingID).Scan(&jobID); err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO ops.bar_quality_issues
        (job_id,landing_id,source_row,trade_date,category,reason)
        VALUES($1,$2,0,'2019-01-11','INVALID_OHLC','low above open')`, jobID, landingID); err != nil {
		t.Fatal(err)
	}

	state, err := store.RecoverArchivedFrame(ctx, key)
	if err != nil || state != "COMPLETED" {
		t.Fatalf("reclassification=%s err=%v", state, err)
	}
	var open, high, low, close float64
	if err = db.QueryRow(`SELECT o,h,l,c FROM core.bars_daily WHERE trade_date='2019-01-11'`).
		Scan(&open, &high, &low, &close); err != nil {
		t.Fatal(err)
	}
	if open != 8 || high != 11 || low != 9 || close != 8.5 {
		t.Fatalf("source prices changed during reclassification: %v %v %v %v", open, high, low, close)
	}
	var got int
	if err = db.QueryRow(`SELECT count(*) FROM ops.bar_quality_issues WHERE landing_id=$1`, landingID).Scan(&got); err != nil || got != 0 {
		t.Fatalf("stale quality issues: got %d err=%v", got, err)
	}
	if err = db.QueryRow(`SELECT count(*) FROM ops.bar_quality_reprocess_audit
        WHERE landing_id=$1 AND previous_issue_count=1 AND resulting_issue_count=0`, landingID).Scan(&got); err != nil || got != 1 {
		t.Fatalf("reprocessing audit: got %d err=%v", got, err)
	}
	if err = db.QueryRow(`SELECT count(*) FROM ops.api_reservations`).Scan(&got); err != nil || got != 1 {
		t.Fatalf("quota reservation count changed: got %d err=%v", got, err)
	}
	if err = db.QueryRow(`SELECT count(*) FROM ops.ingest_jobs
        WHERE idempotency_key=$1 AND state='COMPLETED'`, key).Scan(&got); err != nil || got != 1 {
		t.Fatalf("job state: got %d err=%v", got, err)
	}
	if _, err = store.RecoverArchivedFrame(ctx, key); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("reprocessed frame again: %v", err)
	}
}

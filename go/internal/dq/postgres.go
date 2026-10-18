package dq

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

const RequiredCrossSourcePairs = 30

// RunPostgresGate assembles the gate inputs from the explicitly selected
// Tier A universe and persists both the report and pipeline state atomically.
// The dq-run CLI creates the RUNNING row and supplies the date. The evidence
// tables require independent population; missing inputs are a recorded block.
func RunPostgresGate(ctx context.Context, db *sql.DB, runID string, expected time.Time) (GateReport, error) {
	var report GateReport
	if db == nil || runID == "" || expected.IsZero() {
		return report, errors.New("database, run ID and expected session are required")
	}
	day := expected.Format("2006-01-02")
	// Gate comparisons use session dates, not the caller's wall-clock time.
	expected, _ = time.Parse("2006-01-02", day)
	tx, err := db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead})
	if err != nil {
		return report, err
	}
	defer tx.Rollback()
	var status string
	if err = tx.QueryRowContext(ctx, `SELECT status FROM ops.pipeline_runs WHERE run_id=$1 FOR UPDATE`, runID).Scan(&status); err != nil {
		return report, err
	}
	if status != "RUNNING" {
		return report, fmt.Errorf("pipeline run is not RUNNING: %s", status)
	}

	in := GateInput{Expected: expected, LatestBySymbol: map[string]time.Time{}}
	if err = tx.QueryRowContext(ctx, `SELECT coalesce(
		(SELECT is_session FROM core.calendar_overrides WHERE trade_date=$1),
		(SELECT is_session FROM core.calendar WHERE trade_date=$1),false)`, day).Scan(&in.IsSession); err != nil {
		return report, err
	}
	var universeCount int
	if err = tx.QueryRowContext(ctx, `SELECT count(*) FROM ops.dq_tier_a_symbols WHERE trade_date=$1`, day).Scan(&universeCount); err != nil {
		return report, err
	}
	if universeCount == 0 {
		report.Blocking = append(report.Blocking, "Tier A universe unavailable for expected session")
	}
	rows, err := tx.QueryContext(ctx, `SELECT s.symbol,
		(SELECT max(lb.trade_date) FROM core.bars_daily lb WHERE lb.symbol_id=s.symbol_id AND lb.trade_date<=$1),
		b.trade_date,b.o,b.h,b.l,b.c,b.v
		FROM ops.dq_tier_a_symbols u JOIN core.symbols s USING(symbol_id)
		LEFT JOIN core.bars_daily b ON b.symbol_id=s.symbol_id AND b.trade_date=$1
		WHERE u.trade_date=$1 ORDER BY s.symbol`, day)
	if err != nil {
		return report, err
	}
	for rows.Next() {
		var symbol string
		var latest, barDate sql.NullTime
		var o, h, l, c, v sql.NullFloat64
		if err = rows.Scan(&symbol, &latest, &barDate, &o, &h, &l, &c, &v); err != nil {
			rows.Close()
			return report, err
		}
		in.LatestBySymbol[symbol] = time.Time{}
		if latest.Valid {
			in.LatestBySymbol[symbol] = latest.Time
		}
		if barDate.Valid {
			in.Bars = append(in.Bars, Bar{Symbol: symbol, Date: barDate.Time.Format("2006-01-02"), Open: o.Float64, High: h.Float64, Low: l.Float64, Close: c.Float64, Volume: v.Float64})
		}
	}
	if err = rows.Err(); err != nil {
		rows.Close()
		return report, err
	}
	rows.Close()
	var previous sql.NullTime
	if err = tx.QueryRowContext(ctx, `WITH effective_calendar AS (
		SELECT c.trade_date,coalesce(o.is_session,c.is_session) AS is_session
		FROM core.calendar c LEFT JOIN core.calendar_overrides o USING(trade_date)
		UNION ALL
		SELECT o.trade_date,o.is_session FROM core.calendar_overrides o
		LEFT JOIN core.calendar c USING(trade_date) WHERE c.trade_date IS NULL
	) SELECT max(trade_date) FROM effective_calendar WHERE is_session AND trade_date<$1`, day).Scan(&previous); err != nil {
		return report, err
	}
	if previous.Valid {
		in.HasPrevious = true
		if err = tx.QueryRowContext(ctx, `SELECT count(*) FROM core.bars_daily b JOIN ops.dq_tier_a_symbols u USING(symbol_id) WHERE u.trade_date=$1 AND b.trade_date=$2`, day, previous.Time).Scan(&in.PreviousCount); err != nil {
			return report, err
		}
		if err = loadActionChecks(ctx, tx, day, previous.Time, &in); err != nil {
			return report, err
		}
	} else {
		report.Blocking = append(report.Blocking, "previous verified trading session unavailable for row-count comparison")
	}
	in.CurrentCount = len(in.Bars)
	if err = appendQualityIssues(ctx, tx, day, &report); err != nil {
		return report, err
	}
	if err = appendCrossSourceEvidence(ctx, tx, day, &in, &report); err != nil {
		return report, err
	}
	computed, gateErr := Gate(in)
	report.Warnings = append(report.Warnings, computed.Warnings...)
	report.Quarantined = append(report.Quarantined, computed.Quarantined...)
	report.Blocking = append(report.Blocking, computed.Blocking...)
	finalStatus := "PASSED"
	if len(report.Blocking) > 0 {
		finalStatus = "FAILED"
		for _, reason := range report.Blocking {
			if containsAny(reason, "stale", "session") {
				finalStatus = "STALE"
				break
			}
		}
	}
	encoded, err := json.Marshal(report)
	if err != nil {
		return report, err
	}
	if _, err = tx.ExecContext(ctx, `INSERT INTO ops.dq_gate_results(run_id,trade_date,status,report) VALUES($1,$2,$3,$4::jsonb)
		ON CONFLICT(run_id) DO UPDATE SET trade_date=excluded.trade_date,status=excluded.status,report=excluded.report,recorded_at=now()`, runID, day, finalStatus, string(encoded)); err != nil {
		return report, err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.pipeline_runs SET status=$2,step='data_quality',completed_at=now(),error_type=CASE WHEN $2='PASSED' THEN NULL ELSE 'DATA_QUALITY' END,error_message=CASE WHEN $2='PASSED' THEN NULL ELSE $3 END WHERE run_id=$1`, runID, finalStatus, joinReasons(report.Blocking)); err != nil {
		return report, err
	}
	if err = tx.Commit(); err != nil {
		return report, err
	}
	if gateErr != nil || len(report.Blocking) > 0 {
		return report, ErrBlocked
	}
	return report, nil
}

func loadActionChecks(ctx context.Context, tx *sql.Tx, day string, previous time.Time, in *GateInput) error {
	rows, err := tx.QueryContext(ctx, `SELECT s.symbol,s.exchange,prev.c,current.c,
		EXISTS (
			SELECT 1 FROM core.security_lifecycle_evidence e
			WHERE e.symbol_id=s.symbol_id AND e.evidence_type='FIRST_EVER_PUBLIC_TRADE'
			  AND e.date_from=$1
			  AND NOT EXISTS (
				SELECT 1 FROM core.security_lifecycle_evidence conflict
				WHERE conflict.symbol_id=s.symbol_id
				  AND conflict.evidence_type='FIRST_EVER_PUBLIC_TRADE'
				  AND conflict.date_from<>$1
			  )
		) AS verified_listing_day
		FROM ops.dq_tier_a_symbols u
		JOIN core.symbols s USING(symbol_id)
		JOIN core.bars_daily current ON current.symbol_id=s.symbol_id AND current.trade_date=$1 AND current.v>0
		JOIN core.bars_daily prev ON prev.symbol_id=s.symbol_id AND prev.trade_date=$2 AND prev.v>0
		WHERE u.trade_date=$1 ORDER BY s.symbol`, day, previous)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var check ActionCheck
		if err = rows.Scan(&check.Symbol, &check.Exchange, &check.Previous, &check.Current, &check.ListingDay); err != nil {
			return err
		}
		in.Actions = append(in.Actions, check)
	}
	return rows.Err()
}

func appendQualityIssues(ctx context.Context, tx *sql.Tx, day string, report *GateReport) error {
	rows, err := tx.QueryContext(ctx, `SELECT DISTINCT s.symbol,q.category,q.reason
		FROM ops.bar_quality_issues q
		JOIN ops.ingest_jobs j USING(job_id)
		JOIN core.symbols s ON s.symbol=j.symbol
		JOIN ops.dq_tier_a_symbols u ON u.symbol_id=s.symbol_id AND u.trade_date=$1
		WHERE q.trade_date=$1
		ORDER BY s.symbol,q.category,q.reason`, day)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var symbol, category, reason string
		if err = rows.Scan(&symbol, &category, &reason); err != nil {
			return err
		}
		switch category {
		case "INVALID_OHLC", "INVALID_PRICE", "INVALID_VOLUME":
			report.Quarantined = append(report.Quarantined, symbol)
			report.Blocking = append(report.Blocking, fmt.Sprintf("invalid source bar %s %s: %s", symbol, category, reason))
		case "ZERO_VOLUME_UNVERIFIED":
			report.Quarantined = append(report.Quarantined, symbol)
			report.Warnings = append(report.Warnings, "unverified zero-volume source observation "+symbol)
		}
	}
	return rows.Err()
}

func containsAny(s string, words ...string) bool {
	for _, w := range words {
		if strings.Contains(strings.ToLower(s), w) {
			return true
		}
	}
	return false
}
func joinReasons(reasons []string) string {
	b, _ := json.Marshal(reasons)
	s := string(b)
	if len(s) > 2000 {
		return s[:2000]
	}
	return s
}

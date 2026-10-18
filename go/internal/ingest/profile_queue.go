package ingest

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
)

var ErrProfileAlreadyHandled = errors.New("company profile already handled")
var ErrProfileUnknownOutcome = errors.New("previous profile call outcome unknown; explicit retry required")

type ProfileQueueItem struct {
	Symbol string `json:"symbol"`
	State  string `json:"state"`
}
type ProfileAttempt struct {
	ID         int64
	Symbol     string
	State      string
	ReportPath string
}
type ProfileBatchSummary struct {
	BatchID         int64  `json:"batch_id"`
	Candidates      int    `json:"candidates"`
	MaxCalls        int    `json:"max_calls"`
	Attempted       int    `json:"attempted"`
	Imported        int    `json:"imported"`
	MissingDate     int    `json:"missing_date"`
	Errors          int    `json:"errors"`
	SkippedExisting int    `json:"skipped_existing"`
	SkippedErrors   int    `json:"skipped_errors"`
	SkippedUnknown  int    `json:"skipped_unknown"`
	Deferred        int    `json:"deferred"`
	LastErrorType   string `json:"last_error_type,omitempty"`
}

// SeedProfileQueue is entirely offline. Every security is sourced from
// immutable full-universe VCI listings, including provider DELISTED entries.
// Already imported profiles (also those imported by the single-ticker CLI)
// are reconciled before selecting new calls. No fabricated membership dates.
func (p *PostgresStore) SeedProfileQueue(ctx context.Context) error {
	if p == nil || p.DB == nil {
		return errors.New("PostgreSQL required")
	}
	_, err := p.DB.ExecContext(ctx, `INSERT INTO ops.company_profile_jobs(security_id)
        SELECT security_id FROM core.security_master
        ON CONFLICT(security_id) DO NOTHING`)
	if err != nil {
		return err
	}
	_, err = p.DB.ExecContext(ctx, `WITH latest AS (
        SELECT DISTINCT ON(security_id) security_id,reported_listing_date
        FROM core.company_profile_observations
        ORDER BY security_id,observed_at DESC,profile_id DESC)
        UPDATE ops.company_profile_jobs j SET
          state=CASE WHEN l.reported_listing_date IS NULL THEN 'MISSING_DATE' ELSE 'IMPORTED' END,
          last_error_type=NULL, updated_at=now()
        FROM latest l
        WHERE j.security_id=l.security_id
          AND j.state IS DISTINCT FROM
           CASE WHEN l.reported_listing_date IS NULL THEN 'MISSING_DATE' ELSE 'IMPORTED' END`)
	return err
}

// ReclassifyLegacyProfileTimeouts corrects the earlier collector, which
// recorded worker timeouts as ERROR. A killed worker cannot prove whether its
// provider request was charged. The old safe error category remains recorded;
// statuses become UNKNOWN so --retry-errors cannot unknowingly repeat them.
// The migration is deliberately performed offline and idempotently on startup.
func (p *PostgresStore) ReclassifyLegacyProfileTimeouts(ctx context.Context) (int64, error) {
	if p == nil || p.DB == nil {
		return 0, errors.New("PostgreSQL required")
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	_, err = tx.ExecContext(ctx, `UPDATE ops.company_profile_attempts a
        SET status='UNKNOWN'
        WHERE a.status='ERROR' AND a.error_type='WorkerTimeout'
          AND EXISTS (
            SELECT 1 FROM ops.company_profile_jobs j
            WHERE j.security_id=a.security_id AND j.state='ERROR'
              AND j.last_error_type='WorkerTimeout'
          )`)
	if err != nil {
		return 0, err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.company_profile_jobs j
        SET state='UNKNOWN',updated_at=now()
        WHERE j.state='ERROR' AND j.last_error_type='WorkerTimeout'
          AND NOT EXISTS(
              SELECT 1 FROM core.company_profile_observations p
              WHERE p.security_id=j.security_id
          )
          AND EXISTS (
              SELECT 1 FROM ops.company_profile_attempts a
              WHERE a.security_id=j.security_id
                AND a.status='UNKNOWN' AND a.error_type='WorkerTimeout'
          )`)
	if err != nil {
		return 0, err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}
	return count, tx.Commit()
}

func (p *PostgresStore) ProfileQueue(ctx context.Context) ([]ProfileQueueItem, error) {
	if p == nil || p.DB == nil {
		return nil, errors.New("PostgreSQL required")
	}
	rows, err := p.DB.QueryContext(ctx, `SELECT m.symbol,j.state
         FROM ops.company_profile_jobs j JOIN core.security_master m USING(security_id)
         ORDER BY CASE j.state WHEN 'PENDING' THEN 0 ELSE 1 END,m.symbol`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ProfileQueueItem{}
	for rows.Next() {
		var r ProfileQueueItem
		if err := rows.Scan(&r.Symbol, &r.State); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

func (p *PostgresStore) UnfinishedProfileAttempts(ctx context.Context) ([]ProfileAttempt, error) {
	if p == nil || p.DB == nil {
		return nil, errors.New("PostgreSQL required")
	}
	rows, err := p.DB.QueryContext(ctx, `SELECT a.attempt_id,m.symbol,j.state,a.report_path
      FROM ops.company_profile_attempts a
      JOIN ops.company_profile_jobs j USING(security_id)
      JOIN core.security_master m USING(security_id)
      WHERE (a.status='RESERVED' AND j.state='IN_FLIGHT')
         OR (a.status='ERROR' AND j.state='ERROR')
      ORDER BY a.attempt_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []ProfileAttempt{}
	for rows.Next() {
		var a ProfileAttempt
		if err := rows.Scan(&a.ID, &a.Symbol, &a.State, &a.ReportPath); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// ReserveProfileCall commits quota expenditure, global pacing, a durable
// in-flight marker and the report path BEFORE invoking the Python worker.
// It shares ops.quota_guard with OHLCV ingestion. Once reserved, an
// interrupted/unknown call is NEVER automatically repeated.
func (p *PostgresStore) ReserveProfileCall(ctx context.Context, symbol, dir string,
	allowError, allowUnknown bool) (ProfileAttempt, time.Time, error) {
	var attempt ProfileAttempt
	if p == nil || p.DB == nil {
		return attempt, time.Time{}, errors.New("PostgreSQL required")
	}
	if symbol == "" || len(symbol) > 12 || strings.ContainsAny(symbol, "/\\.") ||
		dir == "" || !filepath.IsAbs(dir) {
		return attempt, time.Time{}, errors.New("invalid profile reservation")
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return attempt, time.Time{}, err
	}
	defer tx.Rollback()
	now := p.clock()
	var expires time.Time
	var day string
	var budget, spent int
	var spacing int64
	var previous sql.NullTime
	err = tx.QueryRowContext(ctx, `SELECT expires_at,day_key::text,call_budget,spent,
      min_spacing_ms,last_not_before FROM ops.quota_guard
      WHERE singleton=true FOR UPDATE`).
		Scan(&expires, &day, &budget, &spent, &spacing, &previous)
	if errors.Is(err, sql.ErrNoRows) {
		return attempt, time.Time{}, ErrNoQuotaSnapshot
	}
	if err != nil {
		return attempt, time.Time{}, err
	}
	if !now.Before(expires) || day != vietnamDate(now) {
		return attempt, time.Time{}, ErrNoQuotaSnapshot
	}
	if spent >= budget {
		return attempt, time.Time{}, quota.ErrExhausted
	}
	when := now
	if previous.Valid && previous.Time.Add(time.Duration(spacing)*time.Millisecond).After(when) {
		when = previous.Time.Add(time.Duration(spacing) * time.Millisecond)
	}
	if !when.Before(expires) || vietnamDate(when) != day {
		return attempt, time.Time{}, ErrNoQuotaSnapshot
	}
	var securityID int64
	var state string
	err = tx.QueryRowContext(ctx, `SELECT j.security_id,j.state
       FROM ops.company_profile_jobs j JOIN core.security_master m USING(security_id)
       WHERE m.symbol=$1 FOR UPDATE OF j`, symbol).Scan(&securityID, &state)
	if err != nil {
		return attempt, time.Time{}, err
	}
	permitted := state == "PENDING" || state == "ERROR" && allowError || state == "UNKNOWN" && allowUnknown
	if !permitted {
		if state == "IN_FLIGHT" || state == "UNKNOWN" {
			return attempt, time.Time{}, ErrProfileUnknownOutcome
		}
		return attempt, time.Time{}, ErrProfileAlreadyHandled
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.quota_guard
        SET spent=spent+1,last_not_before=$1 WHERE singleton=true`, when); err != nil {
		return attempt, time.Time{}, err
	}
	err = tx.QueryRowContext(ctx, `INSERT INTO ops.company_profile_attempts(
      security_id,not_before,report_path) VALUES($1,$2,$3) RETURNING attempt_id`,
		securityID, when, filepath.Join(dir, symbol+"-pending.json")).Scan(&attempt.ID)
	if err != nil {
		return attempt, time.Time{}, err
	}
	attempt.Symbol = symbol
	attempt.State = "IN_FLIGHT"
	attempt.ReportPath = filepath.Join(dir, fmt.Sprintf("%s-%012d.json", symbol, attempt.ID))
	if len(attempt.ReportPath) > 1024 {
		return attempt, time.Time{}, errors.New("report path too long")
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.company_profile_attempts SET report_path=$2
       WHERE attempt_id=$1`, attempt.ID, attempt.ReportPath); err != nil {
		return attempt, time.Time{}, err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE ops.company_profile_jobs
       SET state='IN_FLIGHT',attempts=attempts+1,last_error_type=NULL,updated_at=now()
       WHERE security_id=$1`, securityID); err != nil {
		return attempt, time.Time{}, err
	}
	return attempt, when, tx.Commit()
}

// ReserveProfileCallAudit links the already quota-spending profile attempt to
// CallRecorded's durable audit boundary. It records no additional quota spend:
// ReserveProfileCall has already incremented ops.quota_guard.spent atomically.
func (p *PostgresStore) ReserveProfileCallAudit(ctx context.Context, id int64, requested time.Time) (time.Time, error) {
	if p == nil || p.DB == nil || id <= 0 {
		return time.Time{}, errors.New("invalid profile call audit")
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return time.Time{}, err
	}
	defer tx.Rollback()
	var notBefore time.Time
	var attemptStatus, jobState string
	err = tx.QueryRowContext(ctx, `SELECT a.not_before,a.status,j.state
       FROM ops.company_profile_attempts a
       JOIN ops.company_profile_jobs j USING(security_id)
       WHERE a.attempt_id=$1 FOR UPDATE OF a,j`, id).Scan(&notBefore, &attemptStatus, &jobState)
	if err != nil {
		return time.Time{}, err
	}
	if attemptStatus != "RESERVED" || jobState != "IN_FLIGHT" {
		return time.Time{}, fmt.Errorf("profile attempt %d is not active", id)
	}
	durableAt := requested
	if notBefore.After(durableAt) {
		durableAt = notBefore
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO ops.company_profile_call_audit(attempt_id,not_before)
       VALUES($1,$2)`, id, durableAt)
	if err != nil {
		return time.Time{}, err
	}
	if err = tx.Commit(); err != nil {
		return time.Time{}, err
	}
	return durableAt, nil
}

// DispatchProfileCallAudit durably records that the worker is about to receive
// the request. A failed update prevents Gateway.CallRecorded from dispatching.
func (p *PostgresStore) DispatchProfileCallAudit(ctx context.Context, id int64) error {
	if p == nil || p.DB == nil || id <= 0 {
		return errors.New("invalid profile call audit")
	}
	result, err := p.DB.ExecContext(ctx, `UPDATE ops.company_profile_call_audit a
       SET status='DISPATCHED',dispatched_at=now()
       FROM ops.company_profile_attempts p,ops.company_profile_jobs j
       WHERE a.attempt_id=$1 AND a.status='RESERVED' AND p.attempt_id=a.attempt_id
         AND p.status='RESERVED' AND j.security_id=p.security_id AND j.state='IN_FLIGHT'`, id)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return fmt.Errorf("profile call audit %d is not dispatchable", id)
	}
	return nil
}

// FinishProfileCallAudit closes the API-call audit row. Profile job outcome is
// finalized separately, after the worker response has been archived/imported.
func (p *PostgresStore) FinishProfileCallAudit(ctx context.Context, id int64, status, reason string) error {
	if p == nil || p.DB == nil || id <= 0 {
		return errors.New("invalid profile call audit")
	}
	switch status {
	case "SUCCEEDED", "FAILED", "RATE_LIMITED", "CANCELLED":
	default:
		return errors.New("invalid profile call audit outcome")
	}
	if len(reason) > 120 {
		return errors.New("profile call audit reason too long")
	}
	result, err := p.DB.ExecContext(ctx, `UPDATE ops.company_profile_call_audit
       SET status=$2,finished_at=now(),reason=NULLIF($3,'')
       WHERE attempt_id=$1 AND status IN ('RESERVED','DISPATCHED')`, id, status, reason)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return fmt.Errorf("profile call audit %d is not finishable", id)
	}
	return nil
}

// EndProfileCall never refunds an API reservation. Successful states require
// a company profile that has actually been committed to raw/core storage.
func (p *PostgresStore) EndProfileCall(ctx context.Context, id int64, status, reason string) error {
	if p == nil || p.DB == nil || id <= 0 {
		return errors.New("invalid profile attempt")
	}
	switch status {
	case "IMPORTED", "MISSING_DATE", "ERROR", "UNKNOWN":
	default:
		return errors.New("invalid profile outcome")
	}
	if len(reason) > 120 {
		return errors.New("profile error type too long")
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var securityID int64
	var original, jobState string
	err = tx.QueryRowContext(ctx, `SELECT a.security_id,a.status,j.state
       FROM ops.company_profile_attempts a
       JOIN ops.company_profile_jobs j USING(security_id)
       WHERE a.attempt_id=$1 FOR UPDATE OF a,j`, id).Scan(&securityID, &original, &jobState)
	if err != nil {
		return err
	}
	if original != "RESERVED" || jobState != "IN_FLIGHT" {
		return fmt.Errorf("profile attempt %d no longer active", id)
	}
	var landingID any
	if status == "IMPORTED" || status == "MISSING_DATE" {
		var id int64
		var date sql.NullString
		err = tx.QueryRowContext(ctx, `SELECT p.landing_id,p.reported_listing_date::text
          FROM core.company_profile_observations p WHERE p.security_id=$1
          ORDER BY p.observed_at DESC,p.profile_id DESC LIMIT 1`,
			securityID).Scan(&id, &date)
		if err != nil {
			return fmt.Errorf("successful profile not archived: %w", err)
		}
		if (status == "MISSING_DATE") != (!date.Valid) {
			return errors.New("profile outcome differs from committed listing date")
		}
		landingID = id
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.company_profile_attempts SET
       status=$2,finished_at=now(),error_type=NULLIF($3,''),landing_id=$4
       WHERE attempt_id=$1`, id, status, reason, landingID)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.company_profile_jobs
       SET state=$2,updated_at=now(),last_error_type=NULLIF($3,'')
       WHERE security_id=$1`, securityID, status, reason)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (p *PostgresStore) StartProfileBatch(ctx context.Context, maxCalls int) (int64, error) {
	if p == nil || p.DB == nil || maxCalls < 1 {
		return 0, errors.New("invalid batch")
	}
	var id int64
	err := p.DB.QueryRowContext(ctx, `INSERT INTO ops.company_profile_batch_runs(max_calls)
       VALUES($1) RETURNING batch_id`, maxCalls).Scan(&id)
	return id, err
}
func (p *PostgresStore) FinishProfileBatch(ctx context.Context, s ProfileBatchSummary) error {
	if p == nil || p.DB == nil {
		return errors.New("PostgreSQL required")
	}
	_, err := p.DB.ExecContext(ctx, `UPDATE ops.company_profile_batch_runs SET
       finished_at=now(),attempted=$2,imported=$3,missing_date=$4,errors=$5,
       skipped_existing=$6,skipped_errors=$7,skipped_unknown=$8,
       deferred=$9,last_error_type=NULLIF($10,'')
       WHERE batch_id=$1`,
		s.BatchID, s.Attempted, s.Imported, s.MissingDate, s.Errors,
		s.SkippedExisting, s.SkippedErrors, s.SkippedUnknown, s.Deferred, s.LastErrorType)
	return err
}

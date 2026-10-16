package ingest

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
	"strings"
	"time"

	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/dq"
	"github.com/Kashumir-Kaiser/VN-Signal/go/internal/quota"
)

var (
	ErrNoQuotaSnapshot = errors.New("no fresh, absolute PostgreSQL quota guard: ingestion disabled")
	ErrInFlight        = errors.New("another worker owns the active job lease")
	ErrJobBlocked      = errors.New("job blocked by error: manual review required")
	ErrJobCompleted    = errors.New("job already completed")
)

// PostgresStore expects a PostgreSQL-backed database/sql connection. The
// database/sql adapter is intentionally injected: there is no sqlite fallback
// for authoritative ingestion and no silent in-memory store in production.
// Register github.com/jackc/pgx/v5/stdlib in the final executable when the
// dependency can be pinned and validated in a network-capable build.
type PostgresStore struct {
	DB  *sql.DB
	Now func() time.Time
}

func NewPostgresStore(db *sql.DB) (*PostgresStore, error) {
	if db == nil {
		return nil, errors.New("PostgreSQL database is required")
	}
	return &PostgresStore{DB: db, Now: time.Now}, nil
}
func (p *PostgresStore) clock() time.Time {
	if p.Now != nil {
		return p.Now().UTC()
	}
	return time.Now().UTC()
}
func vietnamDate(t time.Time) string {
	return t.In(time.FixedZone("Asia/Ho_Chi_Minh", 7*3600)).Format("2006-01-02")
}

// QuotaSnapshot MUST come from a newly observed, successful, absolute vnstock
// usage + tier reading. It is never loaded from a stale local saved probe.
type QuotaSnapshot struct {
	DailyRemaining       int
	MonthlyRemaining     int
	TradingDaysRemaining int
	VerifiedRPM          int
	ObservedAt           time.Time
}

// InstallQuota creates/refreshes the singleton cap with a short expiry.
// A repeated sample at the same timestamp is rejected to prevent quota reset.
// The caller must query real absolute account usage immediately beforehand.
func (p *PostgresStore) InstallQuota(ctx context.Context, q QuotaSnapshot) error {
	if p == nil || p.DB == nil || q.ObservedAt.IsZero() ||
		q.VerifiedRPM < 1 || q.VerifiedRPM > 60 {
		return ErrNoQuotaSnapshot
	}
	budget, err := quota.Budget(q.DailyRemaining, q.MonthlyRemaining, q.TradingDaysRemaining)
	if err != nil {
		return err
	}
	now := p.clock()
	observed := q.ObservedAt.UTC()
	if observed.After(now.Add(30*time.Second)) || now.Sub(observed) > time.Minute || observed.After(now) {
		return ErrNoQuotaSnapshot
	}
	spacing := int64(math.Ceil(float64(time.Minute/time.Millisecond) / (0.85 * float64(q.VerifiedRPM))))
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var previous time.Time
	var last sql.NullTime
	var oldBudget, oldSpent int
	var oldDay string
	err = tx.QueryRowContext(ctx, `SELECT verified_at,last_not_before,call_budget,spent,day_key::text
        FROM ops.quota_guard WHERE singleton=true FOR UPDATE`).Scan(&previous, &last, &oldBudget, &oldSpent, &oldDay)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if err == nil {
		if !observed.After(previous) {
			return ErrNoQuotaSnapshot
		}
		if oldDay == vietnamDate(observed) {
			// Never restore previously spent calls merely because an upstream
			// usage endpoint returned a cached or delayed reading.
			previousLeft := oldBudget - oldSpent
			if previousLeft < budget {
				budget = previousLeft
			}
		}
	}
	// Retain the previous scheduled send time on quota refresh to prevent a
	// burst when the process restarts while a previous call is still paced.
	var prev any
	if last.Valid {
		prev = last.Time
	} else {
		prev = nil
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO ops.quota_guard
         (singleton,verified_at,expires_at,day_key,call_budget,spent,min_spacing_ms,last_not_before)
         VALUES (true,$1,$2,$3,$4,0,$5,$6)
         ON CONFLICT(singleton) DO UPDATE SET
            verified_at=EXCLUDED.verified_at,
            expires_at=EXCLUDED.expires_at,
            day_key=EXCLUDED.day_key,
            call_budget=EXCLUDED.call_budget,
            spent=0,
            min_spacing_ms=EXCLUDED.min_spacing_ms,
            last_not_before=EXCLUDED.last_not_before`,
		observed, observed.Add(5*time.Minute), vietnamDate(observed), budget, spacing, prev)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (p *PostgresStore) Completed(ctx context.Context, jobID string) (bool, error) {
	if p == nil || p.DB == nil {
		return false, errors.New("database missing")
	}
	var completed bool
	err := p.DB.QueryRowContext(ctx, `SELECT state='COMPLETED' FROM ops.ingest_jobs WHERE idempotency_key=$1`, jobID).Scan(&completed)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return completed, err
}

// ReserveAttempt is the database-wide serialized budget + per-job reservation.
// Unknown, expired, spent or cross-date limits block before dispatch.
func (p *PostgresStore) ReserveAttempt(ctx context.Context, job BackfillJob, key, source string, at time.Time) (time.Time, error) {
	zero := time.Time{}
	if p == nil || p.DB == nil || job.Route != "equity_ohlcv" || source == "" ||
		key == "" || job.Symbol == "" || job.Start > job.End || job.Start == "" || job.End == "" {
		return zero, errors.New("invalid database reservation request")
	}
	now := p.clock()
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return zero, err
	}
	defer tx.Rollback()
	var expires time.Time
	var day string
	var budget, spent int
	var space int64
	var last sql.NullTime
	err = tx.QueryRowContext(ctx, `SELECT expires_at,day_key::text,call_budget,spent,min_spacing_ms,last_not_before
        FROM ops.quota_guard WHERE singleton=true FOR UPDATE`).Scan(&expires, &day, &budget, &spent, &space, &last)
	if errors.Is(err, sql.ErrNoRows) {
		return zero, ErrNoQuotaSnapshot
	}
	if err != nil {
		return zero, err
	}
	if !now.Before(expires) || day != vietnamDate(now) {
		return zero, ErrNoQuotaSnapshot
	}
	if spent >= budget {
		return zero, quota.ErrExhausted
	}
	// A reservation always waits at least until NOW, even if the in-memory
	// pacer was initialized earlier or the wall clock changed.
	when := at.UTC()
	if when.Before(now) {
		when = now
	}
	if last.Valid {
		next := last.Time.Add(time.Duration(space) * time.Millisecond)
		if next.After(when) {
			when = next
		}
	}
	if !when.Before(expires) || vietnamDate(when) != day {
		return zero, ErrNoQuotaSnapshot
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
        VALUES($1,'equity_ohlcv',$2,$3,$4::date,$5::date)
        ON CONFLICT(idempotency_key) DO NOTHING`, key, job.Symbol, source, job.Start, job.End)
	if err != nil {
		return zero, err
	}
	var id int64
	var state string
	var attempts int
	var updated time.Time
	var storedSymbol, storedSource, storedStart, storedEnd string
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,attempts,updated_at,symbol,source,date_from::text,date_to::text
        FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, key).
		Scan(&id, &state, &attempts, &updated, &storedSymbol, &storedSource, &storedStart, &storedEnd)
	if err != nil {
		return zero, err
	}
	if storedSymbol != job.Symbol || storedSource != source || storedStart != job.Start || storedEnd != job.End {
		return zero, errors.New("job idempotency key collides with different parameters")
	}
	if state == "COMPLETED" {
		return zero, ErrJobCompleted
	}
	if state == "BLOCKED" {
		return zero, ErrJobBlocked
	}
	if (state == "RESERVED" || state == "RUNNING") && now.Sub(updated) < 15*time.Minute {
		return zero, ErrInFlight
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.quota_guard SET spent=spent+1,last_not_before=$1 WHERE singleton=true`, when)
	if err != nil {
		return zero, err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO ops.api_reservations(job_id,attempt_no,reserved_at,not_before)
        VALUES($1,$2,now(),GREATEST(now(),$3))`, id, attempts+1, when)
	if err != nil {
		return zero, err
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET attempts=$2,state='RESERVED',updated_at=now(),last_error_type=NULL WHERE job_id=$1`, id, attempts+1)
	if err != nil {
		return zero, err
	}
	if err = tx.Commit(); err != nil {
		return zero, err
	}
	return when, nil
}

func (p *PostgresStore) transition(ctx context.Context, key, expected, to, jobState, reason string) error {
	if p == nil || p.DB == nil {
		return errors.New("database missing")
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var id int64
	var attempt int
	var state string
	err = tx.QueryRowContext(ctx, `SELECT job_id,attempts,state FROM ops.ingest_jobs WHERE idempotency_key=$1 FOR UPDATE`, key).Scan(&id, &attempt, &state)
	if err != nil {
		return err
	}
	if state != "RESERVED" && state != "RUNNING" {
		return fmt.Errorf("job cannot transition from %s", state)
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.api_reservations SET outcome=$3,error_type=NULLIF($4,'')
        WHERE job_id=$1 AND attempt_no=$2 AND outcome=$5`, id, attempt, to, reason, expected)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("reservation transition not found or already advanced")
	}
	_, err = tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state=$2,last_error_type=NULLIF($3,''),updated_at=now() WHERE job_id=$1`, id, jobState, reason)
	if err != nil {
		return err
	}
	return tx.Commit()
}
func (p *PostgresStore) MarkDispatch(ctx context.Context, key string) error {
	return p.transition(ctx, key, "RESERVED", "SENT", "RUNNING", "")
}
func (p *PostgresStore) MarkOutcome(ctx context.Context, key, status, reason string) error {
	var jobState string
	expected := "SENT"
	switch status {
	case "SUCCEEDED":
		jobState = "RUNNING"
	case "FAILED":
		jobState = "PENDING"
		if reason == "EntitlementError" {
			jobState = "BLOCKED"
		}
	case "RATE_LIMITED":
		// A temporary 429 consumes quota, but may be retried after the vendor
		// cool-down and a NEW authoritative quota observation.
		jobState = "PENDING"
	case "CANCELLED":
		jobState = "PENDING"
		expected = "RESERVED"
	default:
		return errors.New("unknown vendor outcome")
	}
	if len(reason) > 120 {
		reason = reason[:120]
	}
	return p.transition(ctx, key, expected, status, jobState, reason)
}

func newUUID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	s := hex.EncodeToString(b)
	return s[:8] + "-" + s[8:12] + "-" + s[12:16] + "-" + s[16:20] + "-" + s[20:], nil
}

// CommitLanding writes raw, core and the resume marker under one transaction.
// A completed job is a no-op, never a second raw landing. Unknown symbols are
// rejected: listing snapshots must be loaded before backfill.
func (p *PostgresStore) CommitLanding(ctx context.Context, land Landing) error {
	if p == nil || p.DB == nil || land.JobID == "" || land.Source == "" || !json.Valid(land.Raw) || land.FetchedAt.IsZero() || land.Bars.Count == 0 || land.Bars.Count != len(land.Bars.Rows) {
		return errors.New("invalid landing")
	}
	decoded, err := NormalizeBars(land.Bars.Symbol, land.Raw)
	if err != nil || !reflect.DeepEqual(decoded, land.Bars) {
		return errors.New("raw landing and canonical data disagree")
	}
	digest := sha256.Sum256(land.Raw)
	if hex.EncodeToString(digest[:]) != strings.ToLower(land.SHA256) {
		return errors.New("raw checksum mismatch")
	}
	if err := dq.Validate(land.Bars.Rows); err != nil {
		return fmt.Errorf("core validation: %w", err)
	}
	for i, row := range land.Bars.Rows {
		if row.Symbol != land.Bars.Symbol || (i > 0 && row.Date <= land.Bars.Rows[i-1].Date) {
			return errors.New("landing symbol mismatch or non-chronological rows")
		}
	}
	idstr, err := newUUID()
	if err != nil {
		return err
	}
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var jobID int64
	var state, source, symbol string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,state,attempts,source,symbol FROM ops.ingest_jobs
        WHERE idempotency_key=$1 FOR UPDATE`, land.JobID).Scan(&jobID, &state, &attempts, &source, &symbol)
	if err != nil {
		return err
	}
	if state == "COMPLETED" {
		return tx.Commit()
	}
	if state != "RUNNING" || source != land.Source || symbol != land.Bars.Symbol || attempts < 1 {
		return errors.New("landing has no matched dispatched job")
	}
	var status string
	err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations WHERE job_id=$1 AND attempt_no=$2`, jobID, attempts).Scan(&status)
	if err != nil {
		return err
	}
	if status != "SUCCEEDED" {
		return errors.New("vendor call not recorded as successful")
	}
	var symbolID int64
	err = tx.QueryRowContext(ctx, `SELECT symbol_id FROM core.symbols WHERE symbol=$1`, symbol).Scan(&symbolID)
	if errors.Is(err, sql.ErrNoRows) {
		return errors.New("unknown ticker; load listing before bars")
	}
	if err != nil {
		return err
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings
         (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
         VALUES($1::uuid,$2,'equity_ohlcv',$3,$4,$5::jsonb,$6,$7) RETURNING landing_id`,
		idstr, land.Source, land.FetchedAt, symbol, string(land.Raw), land.SHA256, []byte(land.Raw)).Scan(&landingID)
	if err != nil {
		return err
	}
	for _, bar := range land.Bars.Rows {
		_, err = tx.ExecContext(ctx, `INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
           VALUES($1,$2::date,$3,$4,$5,$6,$7,'unknown',$8,$9::uuid,$10)
           ON CONFLICT (symbol_id,trade_date) DO UPDATE SET
             o=EXCLUDED.o,h=EXCLUDED.h,l=EXCLUDED.l,c=EXCLUDED.c,v=EXCLUDED.v,
             adj_basis=EXCLUDED.adj_basis,source=EXCLUDED.source,
             ingest_id=EXCLUDED.ingest_id,fetched_at=EXCLUDED.fetched_at
           WHERE core.bars_daily.fetched_at <= EXCLUDED.fetched_at`,
			symbolID, bar.Date, bar.Open, bar.High, bar.Low, bar.Close, bar.Volume, land.Source, idstr, land.FetchedAt)
		if err != nil {
			return fmt.Errorf("upsert %s/%s: %w", symbol, bar.Date, err)
		}
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='COMPLETED',landed_id=$2,updated_at=now()
         WHERE job_id=$1 AND state='RUNNING'`, jobID, landingID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("completion update failed")
	}
	return tx.Commit()
}

// BlockInvalid quarantines an already-metered SUCCESSFUL vendor response that
// failed local validation. Do not repeatedly charge quota for a bad schema.
func (p *PostgresStore) BlockInvalid(ctx context.Context, key, reason string) error {
	if p == nil || p.DB == nil {
		return errors.New("database missing")
	}
	if reason == "" || len(reason) > 120 {
		return errors.New("invalid block reason")
	}
	r, err := p.DB.ExecContext(ctx, `UPDATE ops.ingest_jobs SET state='BLOCKED',last_error_type=$2,updated_at=now()
        WHERE idempotency_key=$1 AND state='RUNNING' AND EXISTS
        (SELECT 1 FROM ops.api_reservations a WHERE a.job_id=ops.ingest_jobs.job_id
           AND a.attempt_no=ops.ingest_jobs.attempts AND a.outcome='SUCCEEDED')`, key, reason)
	if err != nil {
		return err
	}
	n, err := r.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("cannot quarantine unverified job")
	}
	return nil
}
// QuarantineFrame retains the exact successful vendor response, even if some
// bars are invalid. It never inserts into core.bars_daily. The state transition
// and raw-byte archival share one transaction, so a DB failure stops the run.
func (p *PostgresStore) QuarantineFrame(ctx context.Context, key, source, reason string, raw json.RawMessage) error {
	if p == nil || p.DB == nil || key == "" || source == "" || reason == "" ||
		len(reason) > 120 || len(raw) == 0 || len(raw) > 10*1024*1024 || !json.Valid(raw) {
		return errors.New("invalid quarantine request")
	}
	idstr, err := newUUID()
	if err != nil {
		return err
	}
	digest := sha256.Sum256(raw)
	tx, err := p.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelSerializable})
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var id int64
	var symbol, storedSource, state string
	var attempts int
	err = tx.QueryRowContext(ctx, `SELECT job_id,symbol,source,state,attempts FROM ops.ingest_jobs
        WHERE idempotency_key=$1 FOR UPDATE`, key).Scan(&id, &symbol, &storedSource, &state, &attempts)
	if err != nil {
		return err
	}
	if state != "RUNNING" || storedSource != source || attempts < 1 {
		return errors.New("quarantine requires dispatched matching job")
	}
	var outcome string
	if err = tx.QueryRowContext(ctx, `SELECT outcome FROM ops.api_reservations
        WHERE job_id=$1 AND attempt_no=$2`, id, attempts).Scan(&outcome); err != nil {
		return err
	}
	if outcome != "SUCCEEDED" {
		return errors.New("cannot quarantine a call without successful audited response")
	}
	var landingID int64
	err = tx.QueryRowContext(ctx, `INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        VALUES ($1::uuid,$2,'equity_ohlcv_quarantine',$3,$4,$5::jsonb,$6,$7)
        RETURNING landing_id`,
		idstr, source, p.clock(), symbol, string(raw), hex.EncodeToString(digest[:]), []byte(raw)).Scan(&landingID)
	if err != nil {
		return err
	}
	res, err := tx.ExecContext(ctx, `UPDATE ops.ingest_jobs
        SET state='BLOCKED',last_error_type=$2,landed_id=$3,updated_at=now()
        WHERE job_id=$1 AND state='RUNNING'`, id, reason, landingID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil || n != 1 {
		return errors.New("quarantine state transition failed")
	}
	return tx.Commit()
}

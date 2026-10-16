-- Phase 1: durable backfill plan and reservation audit. Additive to 001_init.sql.
-- Mark a job COMPLETE only in the same transaction that commits raw.landings.
-- A reservation is not refundable on timeout, vendor error, or process crash.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.ingest_jobs (
    job_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    idempotency_key text NOT NULL UNIQUE CHECK (length(idempotency_key) >= 8),
    route text NOT NULL CHECK (route IN
        ('equity_list','equity_ohlcv','index_ohlcv','income_statement',
         'balance_sheet','cash_flow','market_calendar')),
    symbol text,
    source text NOT NULL,
    date_from date,
    date_to date,
    state text NOT NULL DEFAULT 'PENDING' CHECK
        (state IN ('PENDING','RESERVED','RUNNING','COMPLETED','BLOCKED')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error_type text,
    landed_id bigint REFERENCES raw.landings(landing_id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (date_from IS NULL OR date_to IS NULL OR date_from <= date_to),
    CHECK (state <> 'COMPLETED' OR landed_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS ingest_jobs_pending_idx
    ON ops.ingest_jobs(state,job_id) WHERE state <> 'COMPLETED';
CREATE TABLE IF NOT EXISTS ops.api_reservations (
    reservation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    attempt_no integer NOT NULL CHECK (attempt_no >= 1),
    reserved_at timestamptz NOT NULL DEFAULT now(),
    not_before timestamptz NOT NULL,
    outcome text NOT NULL DEFAULT 'RESERVED' CHECK
        (outcome IN ('RESERVED','SENT','SUCCEEDED','FAILED','RATE_LIMITED','CANCELLED')),
    error_type text,
    UNIQUE(job_id,attempt_no),
    CHECK (not_before >= reserved_at)
);
CREATE INDEX IF NOT EXISTS api_reservations_reserved_idx
    ON ops.api_reservations(reserved_at);
COMMIT;

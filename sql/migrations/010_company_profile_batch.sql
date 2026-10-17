-- Phase 1: durable, single-account company profile collection queue.
-- Provider metadata cannot establish first-ever tradability or a delisting date.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.company_profile_jobs (
    security_id bigint PRIMARY KEY REFERENCES core.security_master(security_id),
    state text NOT NULL DEFAULT 'PENDING'
        CHECK (state IN ('PENDING','IN_FLIGHT','IMPORTED','MISSING_DATE',
                        'ERROR','UNKNOWN')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts>=0),
    last_error_type text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (length(coalesce(last_error_type,''))<=120)
);
CREATE INDEX IF NOT EXISTS company_profile_jobs_state_idx
    ON ops.company_profile_jobs(state,updated_at);
CREATE TABLE IF NOT EXISTS ops.company_profile_attempts (
    attempt_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    security_id bigint NOT NULL REFERENCES core.security_master(security_id),
    reserved_at timestamptz NOT NULL DEFAULT now(),
    not_before timestamptz NOT NULL,
    finished_at timestamptz,
    status text NOT NULL DEFAULT 'RESERVED'
        CHECK (status IN ('RESERVED','IMPORTED','MISSING_DATE','ERROR','UNKNOWN')),
    error_type text,
    report_path text NOT NULL,
    landing_id bigint REFERENCES raw.landings(landing_id),
    CHECK (length(coalesce(error_type,''))<=120),
    CHECK (length(report_path) BETWEEN 1 AND 1024),
    CHECK (finished_at IS NULL OR finished_at>=reserved_at)
);
CREATE INDEX IF NOT EXISTS company_profile_attempts_symbol_idx
    ON ops.company_profile_attempts(security_id,attempt_id DESC);
CREATE TABLE IF NOT EXISTS ops.company_profile_batch_runs (
    batch_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    max_calls integer NOT NULL CHECK(max_calls BETWEEN 1 AND 100000),
    attempted integer NOT NULL DEFAULT 0,
    imported integer NOT NULL DEFAULT 0,
    missing_date integer NOT NULL DEFAULT 0,
    errors integer NOT NULL DEFAULT 0,
    skipped_existing integer NOT NULL DEFAULT 0,
    skipped_errors integer NOT NULL DEFAULT 0,
    skipped_unknown integer NOT NULL DEFAULT 0,
    deferred integer NOT NULL DEFAULT 0,
    last_error_type text,
    CHECK (length(coalesce(last_error_type,''))<=120)
);
-- Source observed zero-volume sessions remain unverified unless separate,
-- authoritative dated exchange records provide lifecycle proof.
CREATE OR REPLACE VIEW ops.company_profile_coverage_review AS
WITH latest_profile AS (
    SELECT DISTINCT ON (p.security_id) p.security_id,p.reported_listing_date,
           p.observed_at,p.landing_id
    FROM core.company_profile_observations p
    ORDER BY p.security_id,p.observed_at DESC,p.profile_id DESC
), bars AS (
    SELECT s.symbol, min(b.trade_date) AS first_bar,
           max(b.trade_date) AS last_bar,
           min(b.trade_date) FILTER (WHERE b.v>0) AS first_traded_bar,
           count(*) AS bar_rows,
           count(*) FILTER (WHERE b.v=0) AS canonical_zero_volume_rows
    FROM core.bars_daily b JOIN core.symbols s USING(symbol_id)
    GROUP BY s.symbol
), quality AS (
    SELECT j.symbol,
       count(*) FILTER (WHERE q.category='ZERO_VOLUME_UNVERIFIED') AS source_zero_unverified,
       min(q.trade_date) FILTER (WHERE q.category='ZERO_VOLUME_UNVERIFIED') AS first_unverified_zero,
       max(q.trade_date) FILTER (WHERE q.category='ZERO_VOLUME_UNVERIFIED') AS last_unverified_zero
    FROM ops.bar_quality_issues q JOIN ops.ingest_jobs j USING(job_id)
    GROUP BY j.symbol
), evidence AS (
    SELECT s.symbol,
       count(*) FILTER (WHERE e.evidence_type='FIRST_EVER_PUBLIC_TRADE') AS verified_first_trade_records
    FROM core.security_lifecycle_evidence e
    JOIN core.symbols s USING(symbol_id) GROUP BY s.symbol
)
SELECT m.symbol, cp.reported_listing_date,cp.observed_at AS profile_observed_at,
       cp.landing_id AS profile_landing_id,
       coalesce(j.state,CASE WHEN cp.security_id IS NOT NULL THEN 'IMPORTED' ELSE 'PENDING' END) AS profile_job_state,
       b.first_bar,b.last_bar,b.first_traded_bar,
       coalesce(b.bar_rows,0) AS bar_rows,
       coalesce(b.canonical_zero_volume_rows,0) AS canonical_zero_volume_rows,
       coalesce(q.source_zero_unverified,0) AS source_zero_unverified,
       q.first_unverified_zero,q.last_unverified_zero,
       coalesce(e.verified_first_trade_records,0) AS verified_first_trade_records,
       array_remove(ARRAY[
         CASE WHEN cp.security_id IS NULL THEN 'PROFILE_NOT_COLLECTED'::text END,
         CASE WHEN cp.security_id IS NOT NULL AND cp.reported_listing_date IS NULL
              THEN 'PROVIDER_LISTING_DATE_MISSING'::text END,
         CASE WHEN b.first_bar IS NULL THEN 'NO_VALID_OHLCV_ROWS'::text END,
         CASE WHEN cp.reported_listing_date IS NOT NULL
              AND b.first_traded_bar < cp.reported_listing_date
              THEN 'OHLCV_BEFORE_PROVIDER_REPORTED_DATE'::text END,
         CASE WHEN cp.reported_listing_date IS NOT NULL
              AND b.first_bar > cp.reported_listing_date
              THEN 'OHLCV_BEGINS_AFTER_PROVIDER_REPORTED_DATE'::text END,
         CASE WHEN coalesce(q.source_zero_unverified,0)>0
              THEN 'ZERO_VOLUME_LIFECYCLE_UNVERIFIED'::text END,
         CASE WHEN coalesce(e.verified_first_trade_records,0)=0
              THEN 'FIRST_EVER_PUBLIC_TRADE_UNVERIFIED'::text END
       ],NULL) AS review_flags
FROM core.security_master m
LEFT JOIN latest_profile cp USING(security_id)
LEFT JOIN ops.company_profile_jobs j USING(security_id)
LEFT JOIN bars b ON b.symbol=m.symbol
LEFT JOIN quality q ON q.symbol=m.symbol
LEFT JOIN evidence e ON e.symbol=m.symbol;
COMMIT;

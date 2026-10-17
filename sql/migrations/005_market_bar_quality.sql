-- Phase 1: record source-observed no-trade sessions separately from true traded bars.
-- No synthetic OHLC repairs; all source bytes remain archived unchanged.
BEGIN;
ALTER TABLE ops.ingest_jobs DROP CONSTRAINT IF EXISTS ingest_jobs_state_check;
ALTER TABLE ops.ingest_jobs ADD CONSTRAINT ingest_jobs_state_check
    CHECK (state IN ('PENDING','RESERVED','RUNNING','COMPLETED','PARTIAL','BLOCKED'));

ALTER TABLE core.bars_daily ADD COLUMN IF NOT EXISTS is_traded boolean NOT NULL DEFAULT true;
UPDATE core.bars_daily SET is_traded = false WHERE v = 0;
ALTER TABLE core.bars_daily DROP CONSTRAINT IF EXISTS bars_daily_is_traded_check;
-- Enforce the meaning at the database boundary even for older callers that
-- insert zero-volume rows without explicitly passing is_traded.
CREATE OR REPLACE FUNCTION core.derive_is_traded() RETURNS trigger
LANGUAGE plpgsql AS $
BEGIN
    NEW.is_traded := (NEW.v > 0);
    RETURN NEW;
END;
$;
DROP TRIGGER IF EXISTS bars_daily_derive_is_traded ON core.bars_daily;
CREATE TRIGGER bars_daily_derive_is_traded
BEFORE INSERT OR UPDATE ON core.bars_daily
FOR EACH ROW EXECUTE FUNCTION core.derive_is_traded();
ALTER TABLE core.bars_daily ADD CONSTRAINT bars_daily_is_traded_check CHECK (is_traded = (v > 0));

CREATE TABLE IF NOT EXISTS ops.bar_quality_issues (
    issue_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    trade_date date NOT NULL,
    category text NOT NULL CHECK (category IN
        ('NO_TRADE','INVALID_OHLC','INVALID_PRICE','INVALID_VOLUME')),
    reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 120),
    observed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (landing_id, source_row)
);
CREATE INDEX IF NOT EXISTS bar_quality_job_idx ON ops.bar_quality_issues(job_id, trade_date);
COMMIT;

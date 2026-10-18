-- Phase 1: preserve independent OHLCV sources as separate, auditable series.
-- Never coalesce alternate-provider prices into the canonical VCI date key.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.external_market_calls (
    call_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    attempt_no integer NOT NULL CHECK (attempt_no >= 1),
    source text NOT NULL CHECK (source IN ('dnse','ssi')),
    route text NOT NULL CHECK (route = 'equity_ohlcv'),
    symbol text NOT NULL,
    request_url text NOT NULL CHECK (length(request_url) BETWEEN 1 AND 2048),
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    http_status integer CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
    outcome text NOT NULL CHECK (outcome IN ('STARTED','SUCCEEDED','EMPTY','FAILED','RATE_LIMITED')),
    error_type text,
    response_sha256 text CHECK (response_sha256 IS NULL OR length(response_sha256)=64),
    row_count integer CHECK (row_count IS NULL OR row_count >= 0),
    landing_id bigint REFERENCES raw.landings(landing_id),
    UNIQUE (job_id,attempt_no),
    CHECK (finished_at IS NULL OR finished_at >= started_at),
    CHECK ((outcome='STARTED') = (finished_at IS NULL))
);
CREATE INDEX IF NOT EXISTS external_market_calls_source_started_idx
    ON ops.external_market_calls(source,started_at);

CREATE TABLE IF NOT EXISTS core.bars_daily_sources (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    source text NOT NULL CHECK (source IN ('dnse','ssi')),
    o double precision NOT NULL CHECK (o > 0),
    h double precision NOT NULL CHECK (h > 0),
    l double precision NOT NULL CHECK (l > 0),
    c double precision NOT NULL CHECK (c > 0),
    v double precision NOT NULL CHECK (v >= 0),
    adj_basis text NOT NULL CHECK (adj_basis IN ('unknown','adjusted','unadjusted')),
    is_traded boolean NOT NULL,
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    ingest_id uuid NOT NULL,
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY (symbol_id,trade_date,source),
    UNIQUE (landing_id,source_row),
    CHECK (h >= l),
    CHECK (is_traded = (v > 0))
);
CREATE INDEX IF NOT EXISTS bars_daily_sources_date_idx
    ON core.bars_daily_sources(source,trade_date);
CREATE INDEX IF NOT EXISTS bars_daily_sources_landing_idx
    ON core.bars_daily_sources(landing_id);

CREATE TABLE IF NOT EXISTS ops.alternate_bar_quality_issues (
    issue_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job_id bigint NOT NULL REFERENCES ops.ingest_jobs(job_id),
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    trade_date date NOT NULL,
    category text NOT NULL CHECK (length(category) BETWEEN 1 AND 64),
    reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 240),
    observed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS alternate_bar_quality_job_idx
    ON ops.alternate_bar_quality_issues(job_id,trade_date);

COMMIT;

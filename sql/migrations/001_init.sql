-- VN-Signal PostgreSQL 16+. No seed data or live predictions.
BEGIN;
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS feat;
CREATE SCHEMA IF NOT EXISTS ml;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE IF NOT EXISTS ops.pipeline_runs (
    run_id uuid PRIMARY KEY,
    idempotency_key text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz,
    status text NOT NULL CHECK (status IN ('RUNNING','PASSED','FAILED','STALE')),
    step text NOT NULL,
    error_type text, error_message text
);
CREATE TABLE IF NOT EXISTS ops.api_calls (
    call_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id uuid REFERENCES ops.pipeline_runs(run_id),
    route text NOT NULL, symbol text, source text,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    outcome text NOT NULL,
    error_type text,
    quota_before jsonb, quota_after jsonb
);
CREATE INDEX IF NOT EXISTS api_calls_attempted_at_idx ON ops.api_calls(attempted_at);

CREATE TABLE IF NOT EXISTS raw.landings (
    landing_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ingest_id uuid NOT NULL,
    source text NOT NULL, route text NOT NULL,
    fetched_at timestamptz NOT NULL,
    symbol text, payload jsonb NOT NULL,
    payload_sha256 text NOT NULL CHECK (length(payload_sha256) = 64)
);
CREATE INDEX IF NOT EXISTS landings_fetched_at_idx ON raw.landings USING BRIN(fetched_at);
CREATE INDEX IF NOT EXISTS landings_ingest_id_idx ON raw.landings(ingest_id);

-- Enforce one canonical exchange spelling at the database boundary.
CREATE OR REPLACE FUNCTION core.canonical_exchange() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.exchange := upper(NEW.exchange);
    RETURN NEW;
END;
$$;
CREATE TABLE IF NOT EXISTS core.symbols (
    symbol_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol text NOT NULL UNIQUE,
    exchange text NOT NULL CHECK (exchange IN ('HOSE','HNX','UPCOM')),
    industry text,
    first_seen_at timestamptz NOT NULL,
    last_seen_at timestamptz NOT NULL,
    active boolean NOT NULL DEFAULT true
);
DROP TRIGGER IF EXISTS symbols_canonical_exchange ON core.symbols;
CREATE TRIGGER symbols_canonical_exchange BEFORE INSERT OR UPDATE ON core.symbols
FOR EACH ROW EXECUTE FUNCTION core.canonical_exchange();
CREATE TABLE IF NOT EXISTS core.listing_snapshots (
    snapshot_date date NOT NULL,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    exchange text NOT NULL CHECK (exchange IN ('HOSE','HNX','UPCOM')),
    industry text,
    PRIMARY KEY(snapshot_date,symbol_id)
);
DROP TRIGGER IF EXISTS listing_canonical_exchange ON core.listing_snapshots;
CREATE TRIGGER listing_canonical_exchange BEFORE INSERT OR UPDATE ON core.listing_snapshots
FOR EACH ROW EXECUTE FUNCTION core.canonical_exchange();
CREATE TABLE IF NOT EXISTS core.bars_daily (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    o double precision NOT NULL CHECK(o > 0),
    h double precision NOT NULL CHECK(h > 0),
    l double precision NOT NULL CHECK(l > 0),
    c double precision NOT NULL CHECK(c > 0),
    v double precision NOT NULL CHECK(v >= 0),
    traded_value double precision CHECK(traded_value >= 0),
    adj_basis text NOT NULL CHECK(adj_basis IN ('unknown','adjusted','unadjusted')),
    source text NOT NULL,
    ingest_id uuid NOT NULL,
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY(symbol_id,trade_date),
    CHECK(h >= l AND h >= o AND h >= c AND l <= o AND l <= c)
);
CREATE INDEX IF NOT EXISTS bars_daily_date_idx ON core.bars_daily(trade_date);
CREATE TABLE IF NOT EXISTS core.index_bars (
    index_symbol text NOT NULL, trade_date date NOT NULL,
    o double precision NOT NULL CHECK(o > 0),
    h double precision NOT NULL CHECK(h > 0),
    l double precision NOT NULL CHECK(l > 0),
    c double precision NOT NULL CHECK(c > 0),
    v double precision CHECK(v >= 0),
    source text NOT NULL, ingest_id uuid NOT NULL,
    fetched_at timestamptz NOT NULL,
    PRIMARY KEY(index_symbol,trade_date)
);
CREATE TABLE IF NOT EXISTS core.fundamentals_pit (
    snapshot_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    line_item text NOT NULL, period_end date NOT NULL,
    period_type text NOT NULL CHECK(period_type IN ('quarter','year')),
    value numeric, source text NOT NULL, payload jsonb NOT NULL,
    first_seen_at timestamptz NOT NULL,
    available_at timestamptz NOT NULL,
    last_seen_at timestamptz,
    restated boolean NOT NULL DEFAULT false,
    -- period_end in exchange-local date; explicit timezone avoids DB session drift.
    CHECK(available_at >= (period_end::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')),
    CHECK(last_seen_at IS NULL OR last_seen_at >= first_seen_at)
);
CREATE INDEX IF NOT EXISTS fundamentals_pit_lookup ON core.fundamentals_pit(symbol_id,available_at,period_end);
CREATE TABLE IF NOT EXISTS core.calendar (
    trade_date date PRIMARY KEY,
    is_session boolean NOT NULL,
    source text NOT NULL,
    notes text
);
CREATE TABLE IF NOT EXISTS core.calendar_overrides (
    trade_date date PRIMARY KEY,
    is_session boolean NOT NULL,
    reason text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
COMMIT;

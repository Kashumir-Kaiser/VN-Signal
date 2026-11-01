-- Point-in-time source observations needed by the Phase 2 feature matrix.
-- This migration defines storage only; it contains no seeded market data and
-- does not add or invoke a vendor data route.
BEGIN;

CREATE TABLE IF NOT EXISTS core.listed_share_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    source text NOT NULL CHECK (source <> ''),
    trade_date date NOT NULL,
    listed_shares numeric(24,0) NOT NULL CHECK (listed_shares > 0),
    available_at timestamptz NOT NULL,
    fetched_at timestamptz NOT NULL,
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    row_payload jsonb NOT NULL CHECK (jsonb_typeof(row_payload) = 'object'),
    UNIQUE (raw_landing_id,source_row)
);
CREATE INDEX IF NOT EXISTS listed_share_observations_pit_idx
    ON core.listed_share_observations(symbol_id,available_at DESC,trade_date DESC);

CREATE TABLE IF NOT EXISTS core.daily_price_limit_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    source text NOT NULL CHECK (source <> ''),
    trade_date date NOT NULL,
    limit_up numeric(20,6) NOT NULL CHECK (limit_up > 0),
    limit_down numeric(20,6) NOT NULL CHECK (limit_down > 0),
    available_at timestamptz NOT NULL,
    fetched_at timestamptz NOT NULL,
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    row_payload jsonb NOT NULL CHECK (jsonb_typeof(row_payload) = 'object'),
    CHECK (limit_up >= limit_down),
    UNIQUE (raw_landing_id,source_row)
);
CREATE INDEX IF NOT EXISTS daily_price_limit_observations_pit_idx
    ON core.daily_price_limit_observations(symbol_id,available_at DESC,trade_date DESC);

-- Forward collected intraday observations are usable only from the instant
-- the response was fetched. This prevents a later historical backfill from
-- being presented as information available during the old session.
CREATE TABLE IF NOT EXISTS core.bars_1m_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    source text NOT NULL CHECK (source <> ''),
    bar_start timestamptz NOT NULL,
    o numeric(20,6) NOT NULL CHECK (o > 0),
    h numeric(20,6) NOT NULL CHECK (h > 0),
    l numeric(20,6) NOT NULL CHECK (l > 0),
    c numeric(20,6) NOT NULL CHECK (c > 0),
    v numeric(24,4) NOT NULL CHECK (v >= 0),
    available_at timestamptz NOT NULL,
    fetched_at timestamptz NOT NULL,
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    row_payload jsonb NOT NULL CHECK (jsonb_typeof(row_payload) = 'object'),
    CHECK (date_trunc('minute',bar_start) = bar_start),
    CHECK (h >= greatest(o,c) AND l <= least(o,c) AND h >= l),
    CHECK (available_at = fetched_at),
    UNIQUE (raw_landing_id,source_row),
    UNIQUE (symbol_id,source,bar_start,raw_landing_id,source_row)
);
CREATE INDEX IF NOT EXISTS bars_1m_observations_pit_idx
    ON core.bars_1m_observations(symbol_id,bar_start,available_at);

-- Exchange calendar and event observations are versioned: corrections append
-- another row with a later availability timestamp and the same event key.
CREATE TABLE IF NOT EXISTS core.calendar_event_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source text NOT NULL CHECK (source <> ''),
    event_key text NOT NULL CHECK (event_key <> ''),
    event_type text NOT NULL CHECK (event_type IN ('HOLIDAY','TET','QUARTER_END','CORPORATE_EVENT','OTHER')),
    event_date date NOT NULL,
    event_end_date date,
    is_trading_day boolean,
    event_payload jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(event_payload) = 'object'),
    available_at timestamptz NOT NULL,
    fetched_at timestamptz NOT NULL,
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    row_payload jsonb NOT NULL CHECK (jsonb_typeof(row_payload) = 'object'),
    CHECK (event_end_date IS NULL OR event_end_date >= event_date),
    CHECK ((event_type = 'HOLIDAY' AND is_trading_day IS NOT NULL) OR event_type <> 'HOLIDAY'),
    UNIQUE (raw_landing_id,source_row)
);
CREATE INDEX IF NOT EXISTS calendar_event_observations_pit_idx
    ON core.calendar_event_observations(event_key,available_at DESC,event_date);

-- Every projected row must exactly match a row in its immutable landing.
-- Source, fetch time, response route, and symbol are checked at insert time.
CREATE OR REPLACE FUNCTION core.verify_phase2_source_input_lineage()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    landing raw.landings%ROWTYPE;
    expected_symbol text;
    landing_rows jsonb;
BEGIN
    SELECT * INTO landing FROM raw.landings WHERE landing_id=NEW.raw_landing_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'source observation raw landing does not exist'; END IF;
    IF NEW.source IS DISTINCT FROM landing.source OR NEW.fetched_at IS DISTINCT FROM landing.fetched_at THEN
        RAISE EXCEPTION 'source observation source/fetched_at must match raw landing';
    END IF;
    IF NEW.available_at < NEW.fetched_at THEN
        RAISE EXCEPTION 'source observation cannot be available before it was fetched';
    END IF;
    IF TG_TABLE_NAME <> 'calendar_event_observations' THEN
        SELECT symbol INTO expected_symbol FROM core.symbols WHERE symbol_id=NEW.symbol_id;
        IF expected_symbol IS DISTINCT FROM upper(landing.symbol) THEN
            RAISE EXCEPTION 'source observation symbol does not match raw landing';
        END IF;
    END IF;
    IF landing.payload->'rows' IS NULL OR jsonb_typeof(landing.payload->'rows') <> 'array' THEN
        RAISE EXCEPTION 'raw landing must contain a rows array';
    END IF;
    landing_rows := landing.payload->'rows';
    IF NEW.source_row >= jsonb_array_length(landing_rows) OR
       landing_rows->NEW.source_row IS DISTINCT FROM NEW.row_payload THEN
        RAISE EXCEPTION 'source_row/row_payload do not match raw landing';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS listed_share_observations_verify_lineage ON core.listed_share_observations;
CREATE TRIGGER listed_share_observations_verify_lineage BEFORE INSERT ON core.listed_share_observations
FOR EACH ROW EXECUTE FUNCTION core.verify_phase2_source_input_lineage();
DROP TRIGGER IF EXISTS daily_price_limit_observations_verify_lineage ON core.daily_price_limit_observations;
CREATE TRIGGER daily_price_limit_observations_verify_lineage BEFORE INSERT ON core.daily_price_limit_observations
FOR EACH ROW EXECUTE FUNCTION core.verify_phase2_source_input_lineage();
DROP TRIGGER IF EXISTS bars_1m_observations_verify_lineage ON core.bars_1m_observations;
CREATE TRIGGER bars_1m_observations_verify_lineage BEFORE INSERT ON core.bars_1m_observations
FOR EACH ROW EXECUTE FUNCTION core.verify_phase2_source_input_lineage();
DROP TRIGGER IF EXISTS calendar_event_observations_verify_lineage ON core.calendar_event_observations;
CREATE TRIGGER calendar_event_observations_verify_lineage BEFORE INSERT ON core.calendar_event_observations
FOR EACH ROW EXECUTE FUNCTION core.verify_phase2_source_input_lineage();

CREATE OR REPLACE FUNCTION core.reject_phase2_source_input_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Phase 2 source observations are append-only; archive a new observation'; END;
$$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['listed_share_observations','daily_price_limit_observations','bars_1m_observations','calendar_event_observations'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON core.%I',t||'_append_only',t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON core.%I FOR EACH ROW EXECUTE FUNCTION core.reject_phase2_source_input_mutation()',t||'_append_only',t);
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON core.%I',t||'_no_truncate',t);
    EXECUTE format('CREATE TRIGGER %I BEFORE TRUNCATE ON core.%I FOR EACH STATEMENT EXECUTE FUNCTION core.reject_phase2_source_input_mutation()',t||'_no_truncate',t);
  END LOOP;
END $$;

COMMENT ON TABLE core.listed_share_observations IS 'Point-in-time listed-share observations, linked to immutable raw rows; no inferred historical shares outstanding.';
COMMENT ON TABLE core.daily_price_limit_observations IS 'Source-reported daily price limits with point-in-time availability and raw-row lineage.';
COMMENT ON TABLE core.bars_1m_observations IS 'Forward-collected one-minute bars; historical backfills are excluded from point-in-time use.';
COMMENT ON TABLE core.calendar_event_observations IS 'Append-only, versioned holiday and event observations; later corrections retain their own availability time.';

COMMIT;

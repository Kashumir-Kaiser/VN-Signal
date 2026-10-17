-- Phase 1: observed securities master. Not a guessed historical listing timeline.
-- The raw landing's original bytes and digest are the only input to the builder.
BEGIN;
CREATE TABLE IF NOT EXISTS core.security_master (
    security_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol text NOT NULL UNIQUE CHECK (symbol ~ '^[A-Z0-9]{1,12}$'),
    first_observed_at timestamptz NOT NULL,
    last_observed_at timestamptz NOT NULL,
    CHECK (last_observed_at >= first_observed_at)
);
CREATE TABLE IF NOT EXISTS core.security_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    security_id bigint NOT NULL REFERENCES core.security_master(security_id),
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    provider_row_index integer NOT NULL CHECK (provider_row_index >= 0),
    observed_on date NOT NULL,
    observed_at timestamptz NOT NULL,
    source text NOT NULL CHECK(source='vci'),
    category text NOT NULL CHECK(category IN ('EXCHANGE_LISTED','PROVIDER_DELISTED_UNDATED')),
    exchange text CHECK(exchange IN ('HOSE','HNX','UPCOM')),
    legal_name text,
    short_name text,
    icb_lv2 text,
    CHECK (
       (category='EXCHANGE_LISTED' AND exchange IS NOT NULL)
       OR (category='PROVIDER_DELISTED_UNDATED' AND exchange IS NULL)
    ),
    UNIQUE (landing_id,provider_row_index),
    UNIQUE (landing_id,security_id)
);
CREATE INDEX IF NOT EXISTS security_observed_asof_idx
    ON core.security_observations(observed_on,security_id);
CREATE INDEX IF NOT EXISTS security_observed_symbol_idx
    ON core.security_observations(security_id,observed_on);

CREATE OR REPLACE FUNCTION core.security_observation_immutable() RETURNS trigger
LANGUAGE plpgsql AS $securityimmutable$
BEGIN
    RAISE EXCEPTION 'observed security history is append-only';
END;
$securityimmutable$;
DROP TRIGGER IF EXISTS security_observation_immutable ON core.security_observations;
CREATE TRIGGER security_observation_immutable
BEFORE UPDATE OR DELETE ON core.security_observations
FOR EACH ROW EXECUTE FUNCTION core.security_observation_immutable();

-- A dated observation is evidence only for its own observation date.
-- Missing earlier dates are UNKNOWN, not delisted or pre-IPO. Never derive
-- membership from a current exchange, a ticker's first OHLCV, or a profile.
CREATE OR REPLACE VIEW core.security_observed_sessions AS
SELECT m.symbol, o.observed_on, o.observed_at, o.category, o.exchange,
       o.landing_id, o.legal_name, o.short_name, o.icb_lv2
FROM core.security_master m
JOIN core.security_observations o USING(security_id);

-- A conflict can arise if two archived provider pulls disagree on a day.
-- No ordering-based tie breaker: callers must see a distinct conflict.
CREATE OR REPLACE VIEW core.security_observed_days AS
SELECT symbol,observed_on,
    CASE WHEN count(DISTINCT category || ':' || coalesce(exchange,'')) > 1
      THEN 'CONFLICTING_OBSERVATIONS'
      WHEN min(category)='EXCHANGE_LISTED' THEN 'EXCHANGE_LISTED'
      ELSE 'PROVIDER_DELISTED_UNDATED'
    END AS observation_status,
    CASE WHEN count(DISTINCT exchange)=1 THEN min(exchange) END AS exchange,
    count(*) AS observations
FROM core.security_observed_sessions GROUP BY symbol,observed_on;
COMMIT;

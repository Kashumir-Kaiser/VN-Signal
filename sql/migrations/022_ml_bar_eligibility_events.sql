-- Preserve source-row corrections as append-only eligibility events.
-- Historical observations remain immutable; ML-facing views apply the latest decision.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.ml_bar_eligibility_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    source text NOT NULL CHECK (source IN ('vci','dnse','ssi','vndirect')),
    trade_date date NOT NULL,
    decision text NOT NULL CHECK (decision IN ('EXCLUDE','ALLOW')),
    reason text NOT NULL CHECK (length(reason) BETWEEN 1 AND 500),
    evidence_id bigint NOT NULL REFERENCES core.security_lifecycle_evidence(evidence_id),
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_row integer NOT NULL CHECK (source_row >= 0),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source,symbol_id,trade_date,decision,evidence_id,raw_landing_id,source_row)
);

CREATE INDEX IF NOT EXISTS ml_bar_eligibility_latest_idx
    ON ops.ml_bar_eligibility_events(source,symbol_id,trade_date,recorded_at DESC,event_id DESC);

CREATE OR REPLACE FUNCTION ops.verify_ml_bar_eligibility_event() RETURNS trigger
LANGUAGE plpgsql AS $verify_ml_bar_eligibility$
DECLARE
    ticker text;
    raw_time text;
BEGIN
    SELECT symbol INTO ticker FROM core.symbols WHERE symbol_id=NEW.symbol_id;
    IF ticker IS NULL THEN
        RAISE EXCEPTION 'eligibility event references an unknown security';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM core.security_lifecycle_evidence e
        WHERE e.evidence_id=NEW.evidence_id
          AND e.symbol_id=NEW.symbol_id
          AND NEW.trade_date BETWEEN e.date_from AND COALESCE(e.date_to,'infinity'::date)
          AND ((NEW.decision='EXCLUDE' AND e.evidence_type IN ('DELISTED','TRADING_SUSPENDED'))
            OR (NEW.decision='ALLOW' AND e.evidence_type IN ('TRADE_ELIGIBLE','FIRST_EVER_PUBLIC_TRADE')))
    ) THEN
        RAISE EXCEPTION 'eligibility decision must be supported by matching dated lifecycle evidence';
    END IF;

    SELECT l.payload->'rows'->NEW.source_row->>'time'
      INTO raw_time
      FROM raw.landings l
     WHERE l.landing_id=NEW.raw_landing_id
       AND l.source=NEW.source
       AND l.symbol=ticker
       AND l.route IN ('equity_ohlcv','market.equity.ohlcv');
    IF raw_time IS NULL OR substring(raw_time,1,10)::date <> NEW.trade_date THEN
        RAISE EXCEPTION 'eligibility event must map to the dated row in its source landing';
    END IF;

    IF NEW.source='vci' THEN
        PERFORM 1 FROM core.bars_daily b
        JOIN raw.landings l ON l.ingest_id=b.ingest_id
        WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
          AND b.source=NEW.source AND l.landing_id=NEW.raw_landing_id;
    ELSE
        PERFORM 1 FROM core.bars_daily_sources b
        WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
          AND b.source=NEW.source AND b.landing_id=NEW.raw_landing_id
          AND b.source_row=NEW.source_row;
    END IF;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'eligibility event must reference an ingested source observation';
    END IF;
    RETURN NEW;
END;
$verify_ml_bar_eligibility$;

DROP TRIGGER IF EXISTS ml_bar_eligibility_verify_source ON ops.ml_bar_eligibility_events;
CREATE TRIGGER ml_bar_eligibility_verify_source
BEFORE INSERT ON ops.ml_bar_eligibility_events
FOR EACH ROW EXECUTE FUNCTION ops.verify_ml_bar_eligibility_event();

CREATE OR REPLACE FUNCTION ops.reject_ml_bar_eligibility_mutation() RETURNS trigger
LANGUAGE plpgsql AS $ml_bar_eligibility$
BEGIN
    RAISE EXCEPTION 'ML bar eligibility events are append-only; add a new decision event';
END;
$ml_bar_eligibility$;
DROP TRIGGER IF EXISTS ml_bar_eligibility_append_only ON ops.ml_bar_eligibility_events;
CREATE TRIGGER ml_bar_eligibility_append_only
BEFORE UPDATE OR DELETE ON ops.ml_bar_eligibility_events
FOR EACH ROW EXECUTE FUNCTION ops.reject_ml_bar_eligibility_mutation();

CREATE OR REPLACE VIEW ops.latest_ml_bar_eligibility AS
SELECT DISTINCT ON (source,symbol_id,trade_date)
       event_id,source,symbol_id,trade_date,decision,reason,evidence_id,
       raw_landing_id,source_row,recorded_at
FROM ops.ml_bar_eligibility_events
ORDER BY source,symbol_id,trade_date,recorded_at DESC,event_id DESC;

CREATE OR REPLACE VIEW core.bars_daily_ml_eligible AS
SELECT b.*
FROM core.bars_daily b
LEFT JOIN ops.latest_ml_bar_eligibility e
  ON e.source=b.source AND e.symbol_id=b.symbol_id AND e.trade_date=b.trade_date
WHERE e.event_id IS NULL OR e.decision <> 'EXCLUDE';

CREATE OR REPLACE VIEW core.bars_daily_sources_ml_eligible AS
SELECT b.*
FROM core.bars_daily_sources b
LEFT JOIN ops.latest_ml_bar_eligibility e
  ON e.source=b.source AND e.symbol_id=b.symbol_id AND e.trade_date=b.trade_date
WHERE e.event_id IS NULL OR e.decision <> 'EXCLUDE';

COMMENT ON TABLE ops.ml_bar_eligibility_events IS
    'Append-only, source-row-linked decisions controlling ML eligibility; raw market observations remain unchanged.';
COMMENT ON VIEW core.bars_daily_ml_eligible IS
    'VCI canonical bars with the latest source-specific ML eligibility decision applied.';
COMMENT ON VIEW core.bars_daily_sources_ml_eligible IS
    'Alternate-source bars with the latest source-specific ML eligibility decision applied.';

COMMIT;

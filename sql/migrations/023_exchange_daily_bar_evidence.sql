-- Preserve exchange-reported daily execution evidence independently from
-- vendor OHLCV bars. A zero total can verify a no-match session without
-- manufacturing a price bar; a positive total conflicting with a zero-volume
-- vendor issue remains an explicit conflict for review.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.exchange_daily_bar_evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source text NOT NULL CHECK (source = 'hnx'),
    market text NOT NULL CHECK (market IN ('HNX','UPCOM')),
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    source_row integer NOT NULL CHECK (source_row >= 0),
    buy_order_count integer NOT NULL CHECK (buy_order_count >= 0),
    buy_order_volume numeric(24,0) NOT NULL CHECK (buy_order_volume >= 0),
    sell_order_count integer NOT NULL CHECK (sell_order_count >= 0),
    sell_order_volume numeric(24,0) NOT NULL CHECK (sell_order_volume >= 0),
    total_matched_volume numeric(24,0) NOT NULL CHECK (total_matched_volume >= 0),
    total_matched_value_vnd numeric(30,0) NOT NULL CHECK (total_matched_value_vnd >= 0),
    landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_url text NOT NULL CHECK (source_url ~ '^https://(www\.)?hnx\.vn/[^[:space:]]+$'),
    observed_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (landing_id, source_row)
);

CREATE INDEX IF NOT EXISTS exchange_daily_bar_evidence_symbol_date_idx
    ON ops.exchange_daily_bar_evidence(symbol_id,trade_date,observed_at);

CREATE OR REPLACE FUNCTION ops.verify_exchange_daily_bar_evidence() RETURNS trigger
LANGUAGE plpgsql AS $verify_exchange_evidence$
DECLARE
    landing_source text;
    landing_route text;
    landing_symbol text;
    landing_payload jsonb;
    original bytea;
    recorded_sha text;
BEGIN
    SELECT source,route,symbol,payload,payload_bytes,payload_sha256
      INTO landing_source,landing_route,landing_symbol,landing_payload,original,recorded_sha
      FROM raw.landings WHERE landing_id=NEW.landing_id;
    IF NOT FOUND OR landing_source <> 'hnx' OR landing_route <> 'exchange_daily_report'
       OR original IS NULL OR octet_length(original) < 2
       OR encode(sha256(original),'hex') <> lower(recorded_sha) THEN
        RAISE EXCEPTION 'exchange evidence must cite an intact HNX exchange_daily_report landing';
    END IF;
    IF landing_symbol IS DISTINCT FROM (SELECT symbol FROM core.symbols WHERE symbol_id=NEW.symbol_id)
       OR landing_payload->>'symbol' IS DISTINCT FROM landing_symbol
       OR landing_payload->>'market' IS DISTINCT FROM NEW.market
       OR landing_payload->>'trade_date' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD')
       OR landing_payload->>'source_row' IS DISTINCT FROM NEW.source_row::text
       OR landing_payload->>'source_url' IS DISTINCT FROM NEW.source_url
       OR (landing_payload->>'buy_order_count')::integer IS DISTINCT FROM NEW.buy_order_count
       OR (landing_payload->>'buy_order_volume')::numeric IS DISTINCT FROM NEW.buy_order_volume
       OR (landing_payload->>'sell_order_count')::integer IS DISTINCT FROM NEW.sell_order_count
       OR (landing_payload->>'sell_order_volume')::numeric IS DISTINCT FROM NEW.sell_order_volume
       OR (landing_payload->>'total_matched_volume')::numeric IS DISTINCT FROM NEW.total_matched_volume
       OR (landing_payload->>'total_matched_value_vnd')::numeric IS DISTINCT FROM NEW.total_matched_value_vnd THEN
        RAISE EXCEPTION 'exchange evidence fields do not match the archived landing summary';
    END IF;
    RETURN NEW;
END;
$verify_exchange_evidence$;

DROP TRIGGER IF EXISTS exchange_daily_bar_evidence_verify_source ON ops.exchange_daily_bar_evidence;
CREATE TRIGGER exchange_daily_bar_evidence_verify_source
BEFORE INSERT ON ops.exchange_daily_bar_evidence
FOR EACH ROW EXECUTE FUNCTION ops.verify_exchange_daily_bar_evidence();

CREATE OR REPLACE FUNCTION ops.reject_exchange_daily_bar_evidence_mutation() RETURNS trigger
LANGUAGE plpgsql AS $exchange_evidence$
BEGIN
    RAISE EXCEPTION 'exchange daily evidence is append-only; archive a new observation';
END;
$exchange_evidence$;
DROP TRIGGER IF EXISTS exchange_daily_bar_evidence_append_only ON ops.exchange_daily_bar_evidence;
CREATE TRIGGER exchange_daily_bar_evidence_append_only
BEFORE UPDATE OR DELETE ON ops.exchange_daily_bar_evidence
FOR EACH ROW EXECUTE FUNCTION ops.reject_exchange_daily_bar_evidence_mutation();

CREATE OR REPLACE VIEW ops.zero_volume_lifecycle_status AS
WITH zeros AS (
    SELECT q.issue_id, q.trade_date, j.symbol, s.symbol_id, q.landing_id,
           q.source_row, q.category
    FROM ops.bar_quality_issues q
    JOIN ops.ingest_jobs j ON j.job_id=q.job_id
    JOIN core.symbols s ON s.symbol=j.symbol
    WHERE q.category='ZERO_VOLUME_UNVERIFIED'
), exchange_evidence AS (
    SELECT symbol_id,trade_date,count(*) AS report_count,
           min(total_matched_volume) AS min_matched_volume,
           max(total_matched_volume) AS max_matched_volume
    FROM ops.exchange_daily_bar_evidence
    GROUP BY symbol_id,trade_date
), positive_alternates AS (
    SELECT symbol_id,trade_date,count(DISTINCT source) AS source_count
    FROM core.bars_daily_sources
    WHERE is_traded AND v > 0
    GROUP BY symbol_id,trade_date
), evidence AS (
    SELECT z.*,
        (SELECT count(DISTINCT e.date_from) FROM core.security_lifecycle_evidence e
         WHERE e.symbol_id=z.symbol_id
           AND e.evidence_type='FIRST_EVER_PUBLIC_TRADE') AS initial_dates,
        (SELECT min(e.date_from) FROM core.security_lifecycle_evidence e
         WHERE e.symbol_id=z.symbol_id
           AND e.evidence_type='FIRST_EVER_PUBLIC_TRADE') AS first_public_trade,
        (SELECT count(DISTINCT e.evidence_type) FROM core.security_lifecycle_evidence e
         WHERE e.symbol_id=z.symbol_id AND e.evidence_type <> 'FIRST_EVER_PUBLIC_TRADE'
           AND z.trade_date BETWEEN e.date_from AND COALESCE(e.date_to, 'infinity'::date)) AS interval_kinds,
        (SELECT min(e.evidence_type) FROM core.security_lifecycle_evidence e
         WHERE e.symbol_id=z.symbol_id AND e.evidence_type <> 'FIRST_EVER_PUBLIC_TRADE'
           AND z.trade_date BETWEEN e.date_from AND COALESCE(e.date_to, 'infinity'::date)) AS interval_kind,
        x.report_count,x.min_matched_volume,x.max_matched_volume,
        a.source_count AS positive_alternate_source_count
    FROM zeros z
    LEFT JOIN exchange_evidence x ON x.symbol_id=z.symbol_id AND x.trade_date=z.trade_date
    LEFT JOIN positive_alternates a ON a.symbol_id=z.symbol_id AND a.trade_date=z.trade_date
)
SELECT symbol, trade_date, landing_id, source_row, category AS source_observation,
    first_public_trade,
    CASE
      WHEN initial_dates > 1 OR interval_kinds > 1 THEN 'CONFLICTING_EVIDENCE'
      WHEN first_public_trade IS NOT NULL AND trade_date < first_public_trade
           AND interval_kinds <> 0 THEN 'CONFLICTING_EVIDENCE'
      WHEN first_public_trade IS NOT NULL AND trade_date < first_public_trade
           THEN 'BEFORE_FIRST_PUBLIC_TRADE'
      WHEN positive_alternate_source_count > 0 THEN 'CONFLICTING_EVIDENCE'
      WHEN report_count > 0 AND (min_matched_volume <> max_matched_volume OR max_matched_volume > 0)
           THEN 'CONFLICTING_EVIDENCE'
      WHEN interval_kind='TRADING_SUSPENDED' THEN 'VERIFIED_SUSPENDED'
      WHEN interval_kind='DELISTED' THEN 'VERIFIED_DELISTED'
      WHEN report_count > 0 AND max_matched_volume = 0 THEN 'VERIFIED_ELIGIBLE_NO_MATCH'
      WHEN interval_kind='TRADE_ELIGIBLE' THEN 'VERIFIED_ELIGIBLE_NO_MATCH'
      ELSE 'LISTING_STATUS_UNVERIFIED'
    END AS derived_lifecycle_status
FROM evidence;

COMMENT ON TABLE ops.exchange_daily_bar_evidence IS
    'Append-only exchange-reported daily execution evidence linked to exact raw reports; it never creates or repairs OHLCV bars.';
COMMENT ON VIEW ops.zero_volume_lifecycle_status IS
    'Classifies vendor zero-volume issues using dated lifecycle evidence and source-row-linked exchange daily reports; absent evidence remains unverified.';

COMMIT;

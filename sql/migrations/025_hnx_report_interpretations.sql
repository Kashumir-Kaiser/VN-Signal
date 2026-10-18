-- HNX daily UPCoM reports separate order-book matching sessions from
-- negotiated transactions. Preserve corrected parses as append-only
-- interpretations because earlier evidence rows stored total-market volume
-- in the matched-volume fields.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.exchange_daily_bar_evidence_interpretations (
    interpretation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evidence_id bigint NOT NULL REFERENCES ops.exchange_daily_bar_evidence(evidence_id),
    parser_version text NOT NULL CHECK (length(parser_version) BETWEEN 1 AND 80),
    total_matched_volume numeric(24,0) NOT NULL CHECK (total_matched_volume >= 0),
    total_matched_value_vnd numeric(30,0) NOT NULL CHECK (total_matched_value_vnd >= 0),
    total_negotiated_volume numeric(24,0) NOT NULL CHECK (total_negotiated_volume >= 0),
    total_negotiated_value_vnd numeric(30,0) NOT NULL CHECK (total_negotiated_value_vnd >= 0),
    total_market_volume numeric(24,0) NOT NULL CHECK (total_market_volume >= 0),
    total_market_value_vnd numeric(30,0) NOT NULL CHECK (total_market_value_vnd >= 0),
    source_field_map jsonb NOT NULL CHECK (jsonb_typeof(source_field_map) = 'object'),
    interpretation_note text NOT NULL CHECK (length(btrim(interpretation_note)) > 0),
    interpreted_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (evidence_id, parser_version),
    CHECK (total_matched_volume + total_negotiated_volume = total_market_volume),
    CHECK (total_matched_value_vnd + total_negotiated_value_vnd = total_market_value_vnd)
);

CREATE INDEX IF NOT EXISTS exchange_evidence_interpretations_latest_idx
    ON ops.exchange_daily_bar_evidence_interpretations(evidence_id, interpreted_at DESC, interpretation_id DESC);

CREATE OR REPLACE FUNCTION ops.verify_exchange_daily_bar_evidence_interpretation() RETURNS trigger
LANGUAGE plpgsql AS $verify_exchange_interpretation$
DECLARE
    evidence_row record;
BEGIN
    SELECT e.source,e.market,e.symbol_id,e.trade_date,e.source_row,
           e.total_matched_volume,e.total_matched_value_vnd,
           l.source AS landing_source,l.route,l.symbol AS landing_symbol,
           l.payload_sha256,l.payload_bytes
      INTO evidence_row
      FROM ops.exchange_daily_bar_evidence e
      JOIN raw.landings l ON l.landing_id=e.landing_id
     WHERE e.evidence_id=NEW.evidence_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'interpretation must reference stored exchange evidence';
    END IF;
    IF evidence_row.source <> 'hnx' OR evidence_row.market <> 'UPCOM'
       OR evidence_row.landing_source <> 'hnx'
       OR evidence_row.route <> 'exchange_daily_report'
       OR evidence_row.landing_symbol IS DISTINCT FROM
          (SELECT symbol FROM core.symbols WHERE symbol_id=evidence_row.symbol_id)
       OR evidence_row.payload_bytes IS NULL
       OR octet_length(evidence_row.payload_bytes) < 2
       OR encode(sha256(evidence_row.payload_bytes),'hex') <> lower(evidence_row.payload_sha256)
       OR evidence_row.total_matched_volume <> NEW.total_market_volume
       OR evidence_row.total_matched_value_vnd <> NEW.total_market_value_vnd THEN
        RAISE EXCEPTION 'interpretation must reconcile to the intact source row and its stored market totals';
    END IF;
    RETURN NEW;
END;
$verify_exchange_interpretation$;

DROP TRIGGER IF EXISTS exchange_evidence_interpretation_verify ON ops.exchange_daily_bar_evidence_interpretations;
CREATE TRIGGER exchange_evidence_interpretation_verify
BEFORE INSERT ON ops.exchange_daily_bar_evidence_interpretations
FOR EACH ROW EXECUTE FUNCTION ops.verify_exchange_daily_bar_evidence_interpretation();

CREATE OR REPLACE FUNCTION ops.reject_exchange_daily_bar_evidence_interpretation_mutation() RETURNS trigger
LANGUAGE plpgsql AS $reject_interpretation_mutation$
BEGIN
    RAISE EXCEPTION 'exchange evidence interpretations are append-only';
END;
$reject_interpretation_mutation$;

DROP TRIGGER IF EXISTS exchange_evidence_interpretation_append_only ON ops.exchange_daily_bar_evidence_interpretations;
CREATE TRIGGER exchange_evidence_interpretation_append_only
BEFORE UPDATE OR DELETE ON ops.exchange_daily_bar_evidence_interpretations
FOR EACH ROW EXECUTE FUNCTION ops.reject_exchange_daily_bar_evidence_interpretation_mutation();

CREATE OR REPLACE VIEW ops.exchange_daily_bar_evidence_current AS
SELECT e.evidence_id,e.source,e.market,e.symbol_id,e.trade_date,e.source_row,
       e.buy_order_count,e.buy_order_volume,e.sell_order_count,e.sell_order_volume,
       COALESCE(i.total_matched_volume,e.total_matched_volume) AS total_matched_volume,
       COALESCE(i.total_matched_value_vnd,e.total_matched_value_vnd) AS total_matched_value_vnd,
       i.total_negotiated_volume,i.total_negotiated_value_vnd,
       i.total_market_volume,i.total_market_value_vnd,
       CASE WHEN i.interpretation_id IS NULL THEN 'legacy_v0' ELSE i.parser_version END AS parser_version,
       e.landing_id,e.source_url,e.observed_at
FROM ops.exchange_daily_bar_evidence e
LEFT JOIN LATERAL (
    SELECT v.*
    FROM ops.exchange_daily_bar_evidence_interpretations v
    WHERE v.evidence_id=e.evidence_id
    ORDER BY v.interpreted_at DESC,v.interpretation_id DESC
    LIMIT 1
) i ON true;

CREATE OR REPLACE VIEW ops.zero_volume_lifecycle_status AS
WITH zeros AS (
    SELECT q.issue_id,q.trade_date,j.symbol,s.symbol_id,q.landing_id,
           q.source_row,q.category
    FROM ops.bar_quality_issues q
    JOIN ops.ingest_jobs j ON j.job_id=q.job_id
    JOIN core.symbols s ON s.symbol=j.symbol
    WHERE q.category='ZERO_VOLUME_UNVERIFIED'
), exchange_evidence AS (
    SELECT symbol_id,trade_date,count(*) AS report_count,
           min(total_matched_volume) AS min_matched_volume,
           max(total_matched_volume) AS max_matched_volume,
           bool_or(COALESCE(total_negotiated_volume,0) > 0) AS has_negotiated_volume
    FROM ops.exchange_daily_bar_evidence_current
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
        x.report_count,x.min_matched_volume,x.max_matched_volume,x.has_negotiated_volume,
        a.source_count AS positive_alternate_source_count
    FROM zeros z
    LEFT JOIN exchange_evidence x ON x.symbol_id=z.symbol_id AND x.trade_date=z.trade_date
    LEFT JOIN positive_alternates a ON a.symbol_id=z.symbol_id AND a.trade_date=z.trade_date
)
SELECT symbol,trade_date,landing_id,source_row,category AS source_observation,
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
      WHEN report_count > 0 AND max_matched_volume = 0 AND has_negotiated_volume
           THEN 'VERIFIED_NEGOTIATED_ONLY'
      WHEN interval_kind='TRADING_SUSPENDED' THEN 'VERIFIED_SUSPENDED'
      WHEN interval_kind='DELISTED' THEN 'VERIFIED_DELISTED'
      WHEN report_count > 0 AND max_matched_volume = 0 THEN 'VERIFIED_ELIGIBLE_NO_MATCH'
      WHEN interval_kind='TRADE_ELIGIBLE' THEN 'VERIFIED_ELIGIBLE_NO_MATCH'
      ELSE 'LISTING_STATUS_UNVERIFIED'
    END AS derived_lifecycle_status
FROM evidence;

COMMENT ON TABLE ops.exchange_daily_bar_evidence_interpretations IS
    'Append-only interpretation of exchange report columns; preserves matched, negotiated, and total-market quantities without changing the captured source bytes or initial parse.';
COMMENT ON VIEW ops.exchange_daily_bar_evidence_current IS
    'Latest parser interpretation per immutable HNX report row. Legacy rows without an interpretation retain their original parsed matched values.';
COMMENT ON VIEW ops.zero_volume_lifecycle_status IS
    'Classifies zero-volume bars using current interpreted matched volume; negotiated-only trade activity is reported separately from matched-session activity.';

COMMIT;

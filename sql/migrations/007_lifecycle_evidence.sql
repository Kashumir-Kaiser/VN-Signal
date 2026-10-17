-- Preserve provider observation separately from provable historical market eligibility.
-- Historical zeros alone do NOT demonstrate that a security was listed.
BEGIN;
ALTER TABLE ops.bar_quality_issues
    DROP CONSTRAINT IF EXISTS bar_quality_issues_category_check;
UPDATE ops.bar_quality_issues
  SET category='ZERO_VOLUME_UNVERIFIED',
      reason='zero source volume; historical listing/trading eligibility unverified'
  WHERE category='NO_TRADE';
ALTER TABLE ops.bar_quality_issues ADD CONSTRAINT bar_quality_issues_category_check
    CHECK(category IN ('ZERO_VOLUME_UNVERIFIED','INVALID_OHLC','INVALID_PRICE','INVALID_VOLUME'));

-- No evidence exists yet for the current 1519-symbol universe. Evidence must
-- reference archived original source bytes, not a guessed date or OHLCV first row.
CREATE TABLE IF NOT EXISTS core.security_lifecycle_evidence (
    evidence_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    exchange text CHECK (exchange IN ('HOSE','HNX','UPCOM')),
    evidence_type text NOT NULL CHECK (evidence_type IN (
        'FIRST_EVER_PUBLIC_TRADE','TRADE_ELIGIBLE','TRADING_SUSPENDED','DELISTED')),
    date_from date NOT NULL,
    date_to date,
    source_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source_url text NOT NULL CHECK (source_url ~ '^https://[^[:space:]]+$'),
    source_document_date date NOT NULL,
    first_observed_at timestamptz NOT NULL DEFAULT now(),
    recorded_at timestamptz NOT NULL DEFAULT now(),
    CHECK (date_to IS NULL OR date_from <= date_to),
    CHECK (evidence_type <> 'FIRST_EVER_PUBLIC_TRADE' OR date_to = date_from),
    CHECK (evidence_type = 'FIRST_EVER_PUBLIC_TRADE' OR exchange IS NOT NULL),
    UNIQUE(symbol_id,evidence_type,date_from,source_landing_id)
);
CREATE INDEX IF NOT EXISTS security_lifecycle_period_idx
    ON core.security_lifecycle_evidence(symbol_id,date_from,date_to);

-- An event cannot cite arbitrary stock-price data as official first-trade proof.
-- The archived document must have its own route and verified SHA-256 bytes.
CREATE OR REPLACE FUNCTION core.verify_lifecycle_evidence_source() RETURNS trigger
LANGUAGE plpgsql AS $verifylifecycle$
DECLARE
    original bytea;
    recorded_sha text;
    original_route text;
BEGIN
    SELECT payload_bytes,payload_sha256,route
      INTO original,recorded_sha,original_route
      FROM raw.landings WHERE landing_id=NEW.source_landing_id;
    IF original IS NULL OR length(original)<2
       OR original_route<>'security_lifecycle_notice'
       OR encode(sha256(original),'hex')<>lower(recorded_sha) THEN
        RAISE EXCEPTION 'lifecycle evidence must cite an intact archived security_lifecycle_notice';
    END IF;
    RETURN NEW;
END;
$verifylifecycle$;
DROP TRIGGER IF EXISTS security_lifecycle_verify_source ON core.security_lifecycle_evidence;
CREATE TRIGGER security_lifecycle_verify_source
BEFORE INSERT ON core.security_lifecycle_evidence
FOR EACH ROW EXECUTE FUNCTION core.verify_lifecycle_evidence_source();

CREATE OR REPLACE FUNCTION core.reject_lifecycle_evidence_mutation() RETURNS trigger
LANGUAGE plpgsql AS $lifecycle$
BEGIN
    RAISE EXCEPTION 'lifecycle evidence is append-only; add a new documented observation';
END;
$lifecycle$;
DROP TRIGGER IF EXISTS security_lifecycle_append_only ON core.security_lifecycle_evidence;
CREATE TRIGGER security_lifecycle_append_only
BEFORE UPDATE OR DELETE ON core.security_lifecycle_evidence
FOR EACH ROW EXECUTE FUNCTION core.reject_lifecycle_evidence_mutation();

-- Explicitly independent of current 2026 exchange membership and
-- company incorporation date. Ambiguous/contradictory evidence fails closed.
CREATE OR REPLACE VIEW ops.zero_volume_lifecycle_status AS
WITH zeros AS (
    SELECT q.issue_id, q.trade_date, j.symbol, s.symbol_id, q.landing_id,
           q.source_row, q.category
    FROM ops.bar_quality_issues q
    JOIN ops.ingest_jobs j ON j.job_id=q.job_id
    JOIN core.symbols s ON s.symbol=j.symbol
    WHERE q.category='ZERO_VOLUME_UNVERIFIED'
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
           AND z.trade_date BETWEEN e.date_from AND COALESCE(e.date_to, 'infinity'::date)) AS interval_kind
    FROM zeros z
)
SELECT symbol, trade_date, landing_id, source_row, category AS source_observation,
    first_public_trade,
    CASE
      WHEN initial_dates > 1 OR interval_kinds > 1 THEN 'CONFLICTING_EVIDENCE'
      WHEN first_public_trade IS NOT NULL AND trade_date < first_public_trade
           AND interval_kinds <> 0 THEN 'CONFLICTING_EVIDENCE'
      WHEN first_public_trade IS NOT NULL AND trade_date < first_public_trade
           THEN 'BEFORE_FIRST_PUBLIC_TRADE'
      WHEN interval_kind='TRADING_SUSPENDED' THEN 'VERIFIED_SUSPENDED'
      WHEN interval_kind='DELISTED' THEN 'VERIFIED_DELISTED'
      WHEN interval_kind='TRADE_ELIGIBLE' THEN 'VERIFIED_ELIGIBLE_NO_MATCH'
      ELSE 'LISTING_STATUS_UNVERIFIED'
    END AS derived_lifecycle_status
FROM evidence;
COMMIT;

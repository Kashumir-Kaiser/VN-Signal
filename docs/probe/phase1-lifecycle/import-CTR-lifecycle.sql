\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE ctr_lifecycle_stage (
  symbol text,
  source_url text,
  source_document_date date,
  title text,
  payload_json jsonb,
  payload_sha256 text,
  body_b64 text
);
\copy ctr_lifecycle_stage FROM 'C:/Users/HP/VN-Signal/docs/probe/phase1-lifecycle/CTR-lifecycle-landing.csv' WITH (FORMAT csv, HEADER true)
DO $$ BEGIN
  IF (SELECT count(*) FROM ctr_lifecycle_stage) <> 1 THEN
    RAISE EXCEPTION 'expected one archived HNX CTR lifecycle notice';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM ctr_lifecycle_stage
    WHERE symbol='CTR' AND lower(payload_sha256)=lower(encode(sha256(decode(body_b64,'base64')),'hex'))
  ) THEN
    RAISE EXCEPTION 'CTR lifecycle bytes do not match the recorded SHA-256';
  END IF;
END $$;

WITH inserted AS (
  INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
  SELECT gen_random_uuid(),'hnx','security_lifecycle_notice',clock_timestamp(),d.symbol,
         d.payload_json,d.payload_sha256,decode(d.body_b64,'base64')
  FROM ctr_lifecycle_stage d
  WHERE NOT EXISTS (
    SELECT 1 FROM raw.landings l
    WHERE l.source='hnx' AND l.route='security_lifecycle_notice'
      AND lower(l.payload_sha256)=lower(d.payload_sha256)
  )
  RETURNING landing_id,payload_sha256
), resolved AS (
  SELECT landing_id,payload_sha256 FROM inserted
  UNION ALL
  SELECT l.landing_id,l.payload_sha256
  FROM raw.landings l JOIN ctr_lifecycle_stage d
    ON lower(l.payload_sha256)=lower(d.payload_sha256)
  WHERE l.source='hnx' AND l.route='security_lifecycle_notice'
)
INSERT INTO core.security_lifecycle_evidence
  (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
SELECT s.symbol_id,'UPCOM','DELISTED',DATE '2022-02-15',DATE '2022-02-22',
       r.landing_id,d.source_url,d.source_document_date
FROM ctr_lifecycle_stage d
JOIN resolved r ON lower(r.payload_sha256)=lower(d.payload_sha256)
JOIN core.symbols s ON s.symbol=d.symbol
ON CONFLICT(symbol_id,evidence_type,date_from,source_landing_id) DO NOTHING;

DO $$
DECLARE matched integer;
BEGIN
  SELECT count(*) INTO matched
  FROM core.bars_daily b
  JOIN core.symbols s ON s.symbol_id=b.symbol_id
  JOIN raw.landings l ON l.ingest_id=b.ingest_id AND l.source=b.source AND l.symbol=s.symbol
  CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') WITH ORDINALITY AS r(obj,ord)
  WHERE s.symbol='CTR' AND b.source='vci'
    AND b.trade_date BETWEEN DATE '2022-02-16' AND DATE '2022-02-22'
    AND l.route IN ('equity_ohlcv','market.equity.ohlcv')
    AND substring(r.obj->>'time',1,10)::date=b.trade_date;
  IF matched <> 5 THEN
    RAISE EXCEPTION 'expected exactly five source-row-mapped CTR VCI bars for 2022-02-16..22, found %',matched;
  END IF;
END $$;

INSERT INTO ops.ml_bar_eligibility_events
  (symbol_id,source,trade_date,decision,reason,evidence_id,raw_landing_id,source_row)
SELECT b.symbol_id,b.source,b.trade_date,'EXCLUDE',
       'The HNX 89/TB-SGDHN notice ended CTR UPCoM trading on 2022-02-14 and canceled registration on 2022-02-15; SSC records the first HOSE trading day as 2022-02-23, leaving no venue for this repeated VCI bar.',
       e.evidence_id,l.landing_id,(r.ord-1)::integer
FROM core.bars_daily b
JOIN core.symbols s ON s.symbol_id=b.symbol_id
JOIN raw.landings l ON l.ingest_id=b.ingest_id AND l.source=b.source AND l.symbol=s.symbol
CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') WITH ORDINALITY AS r(obj,ord)
JOIN core.security_lifecycle_evidence e
  ON e.symbol_id=b.symbol_id AND e.evidence_type='DELISTED'
 AND e.exchange='UPCOM' AND b.trade_date BETWEEN e.date_from AND e.date_to
WHERE s.symbol='CTR' AND b.source='vci'
  AND b.trade_date BETWEEN DATE '2022-02-16' AND DATE '2022-02-22'
  AND l.route IN ('equity_ohlcv','market.equity.ohlcv')
  AND substring(r.obj->>'time',1,10)::date=b.trade_date
ON CONFLICT DO NOTHING;

DO $$
DECLARE excluded integer;
BEGIN
  SELECT count(*) INTO excluded
  FROM ops.ml_bar_eligibility_events x
  JOIN core.symbols s ON s.symbol_id=x.symbol_id
  WHERE s.symbol='CTR' AND x.source='vci' AND x.decision='EXCLUDE'
    AND x.trade_date BETWEEN DATE '2022-02-16' AND DATE '2022-02-22'
    AND x.raw_landing_id=(SELECT max(landing_id) FROM raw.landings
      WHERE source='vci' AND symbol='CTR' AND payload_sha256='9631b5e1ea8c48beb69d0dd8915bb81e1926620067b0aa89f51b3e9a8a30d00f');
  IF excluded <> 5 THEN
    RAISE EXCEPTION 'expected five durable CTR source-row eligibility exclusions, found %',excluded;
  END IF;
  IF (SELECT count(*) FROM core.bars_daily_ml_eligible b
      JOIN core.symbols s USING(symbol_id)
      WHERE s.symbol='CTR' AND b.trade_date BETWEEN DATE '2022-02-16' AND DATE '2022-02-22') <> 0 THEN
    RAISE EXCEPTION 'lifecycle-conflicting CTR bars remain ML eligible';
  END IF;
  IF (SELECT count(*) FROM core.bars_daily b
      JOIN core.symbols s USING(symbol_id)
      WHERE s.symbol='CTR' AND b.trade_date BETWEEN DATE '2022-02-16' AND DATE '2022-02-22') <> 5 THEN
    RAISE EXCEPTION 'canonical CTR observations were unexpectedly modified';
  END IF;
END $$;
COMMIT;

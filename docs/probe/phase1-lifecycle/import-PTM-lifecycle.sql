\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE ptm_lifecycle_stage (
  symbol text,
  source_url text,
  source_document_date date,
  title text,
  payload_json jsonb,
  payload_sha256 text,
  body_b64 text
);
\copy ptm_lifecycle_stage FROM 'C:/Users/HP/VN-Signal/docs/probe/phase1-lifecycle/PTM-lifecycle-landing.csv' WITH (FORMAT csv, HEADER true)
DO $$ BEGIN
  IF (SELECT count(*) FROM ptm_lifecycle_stage) <> 2 THEN
    RAISE EXCEPTION 'expected two archived PTM source documents';
  END IF;
  IF EXISTS (
    SELECT 1 FROM ptm_lifecycle_stage
    WHERE symbol IS DISTINCT FROM 'PTM'
       OR lower(payload_sha256) IS DISTINCT FROM lower(encode(sha256(decode(body_b64,'base64')),'hex'))
  ) OR (SELECT count(DISTINCT lower(payload_sha256)) FROM ptm_lifecycle_stage) <> 2 THEN
    RAISE EXCEPTION 'PTM lifecycle staging identity or source bytes are invalid';
  END IF;
END $$;
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),'hnx','security_lifecycle_notice',clock_timestamp(),d.symbol,
       d.payload_json,d.payload_sha256,decode(d.body_b64,'base64')
FROM ptm_lifecycle_stage d
WHERE NOT EXISTS (
  SELECT 1 FROM raw.landings l
  WHERE l.source='hnx' AND l.route='security_lifecycle_notice'
    AND l.symbol=d.symbol AND lower(l.payload_sha256)=lower(d.payload_sha256)
);
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM ptm_lifecycle_stage d
    WHERE (SELECT count(*) FROM raw.landings l
           WHERE l.source='hnx' AND l.route='security_lifecycle_notice'
             AND l.symbol=d.symbol AND lower(l.payload_sha256)=lower(d.payload_sha256)) <> 1
  ) THEN
    RAISE EXCEPTION 'each PTM lifecycle document must resolve to exactly one same-symbol landing';
  END IF;
END $$;
WITH events AS (
  SELECT 'DDF3FFB354A7CEE923085B10FFF59FCC2CD4EDEA3825744FDB39C00C50FFE197'::text AS sha,
         'TRADE_ELIGIBLE'::text AS evidence_type,DATE '2018-11-27' AS date_from,
         DATE '2018-11-27' AS date_to,DATE '2018-10-30' AS doc_date
  UNION ALL
  SELECT 'DDF3FFB354A7CEE923085B10FFF59FCC2CD4EDEA3825744FDB39C00C50FFE197',
         'DELISTED',DATE '2018-11-28',DATE '2025-08-21',DATE '2018-10-30'
  UNION ALL
  SELECT '2385B5965B458AC71012BE7F4F301B8A430BD9FD5F490F507450D444BF14E163',
         'TRADE_ELIGIBLE',DATE '2025-08-22',NULL::date,DATE '2025-08-18'
)
INSERT INTO core.security_lifecycle_evidence
  (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
SELECT s.symbol_id,'UPCOM',e.evidence_type,e.date_from,e.date_to,l.landing_id,d.source_url,e.doc_date
FROM events e
JOIN ptm_lifecycle_stage d ON lower(d.payload_sha256)=lower(e.sha)
JOIN raw.landings l
  ON l.source='hnx' AND l.route='security_lifecycle_notice'
 AND l.symbol=d.symbol AND lower(l.payload_sha256)=lower(d.payload_sha256)
JOIN core.symbols s ON s.symbol=d.symbol
ON CONFLICT(symbol_id,evidence_type,date_from,source_landing_id) DO NOTHING;
COMMIT;

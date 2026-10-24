\set ON_ERROR_STOP on
\pset pager off
SELECT current_database()='vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
\echo 'Refusing to import outside the disposable report clone'
\quit 2
\endif
BEGIN;
CREATE TEMP TABLE transfer_stage(
 symbol text,source text,fetched_at timestamptz,source_url text,local_file text,
 payload_sha256 text,payload_size bigint,metadata_json jsonb,body_b64 text
) ON COMMIT DROP;
\copy transfer_stage FROM 'C:/Users/HP/VN-Signal/docs/evidence/phase2/spi_transfer_sources_20261024/landing_stage.csv' WITH(FORMAT csv,HEADER true,ENCODING 'UTF8')
CREATE TEMP TABLE transfer_expected(LIKE transfer_stage) ON COMMIT DROP;
INSERT INTO transfer_expected(symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json) VALUES
__EXPECTED__;
DO $$
BEGIN
 IF (SELECT count(*) FROM transfer_stage)<>3 OR (SELECT count(DISTINCT local_file) FROM transfer_stage)<>3
 OR EXISTS (
  (SELECT symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json FROM transfer_stage
   EXCEPT SELECT symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json FROM transfer_expected)
  UNION ALL
  (SELECT symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json FROM transfer_expected
   EXCEPT SELECT symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json FROM transfer_stage)
 ) THEN RAISE EXCEPTION 'staging identity or metadata differs from embedded source manifest'; END IF;
 IF EXISTS(SELECT 1 FROM transfer_stage s WHERE body_b64 IS NULL
    OR encode(sha256(decode(body_b64,'base64')),'hex') IS DISTINCT FROM payload_sha256
    OR octet_length(decode(body_b64,'base64')) IS DISTINCT FROM payload_size
    OR s.symbol<>'SPI'
    OR NOT EXISTS(SELECT 1 FROM core.symbols c WHERE c.symbol=s.symbol)) THEN
  RAISE EXCEPTION 'source bytes, checksum, size, or ticker validation failed';
 END IF;
END $$;
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),s.source,'security_lifecycle_notice',s.fetched_at,s.symbol,s.metadata_json,s.payload_sha256,decode(s.body_b64,'base64')
FROM transfer_stage s WHERE NOT EXISTS(
 SELECT 1 FROM raw.landings l WHERE l.source=s.source AND l.route='security_lifecycle_notice'
 AND l.symbol=s.symbol AND l.payload_sha256=s.payload_sha256
);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM transfer_stage s WHERE
  (SELECT count(*) FROM raw.landings l WHERE l.source=s.source AND l.route='security_lifecycle_notice'
   AND l.symbol=s.symbol AND l.payload_sha256=s.payload_sha256)<>1) THEN
  RAISE EXCEPTION 'source must resolve to exactly one same-ticker landing';
 END IF;
 IF EXISTS(SELECT 1 FROM transfer_stage s JOIN raw.landings l
    ON l.source=s.source AND l.route='security_lifecycle_notice' AND l.symbol=s.symbol AND l.payload_sha256=s.payload_sha256
    WHERE l.payload_bytes IS DISTINCT FROM decode(s.body_b64,'base64')
       OR l.payload IS DISTINCT FROM s.metadata_json OR l.fetched_at IS DISTINCT FROM s.fetched_at) THEN
  RAISE EXCEPTION 'stored source bytes or metadata differ from checked source';
 END IF;
END $$;
-- Archival only. These source-specific claims do not classify individual
-- sessions, establish a suspension, or assert any daily bar/trade event.
COMMIT;

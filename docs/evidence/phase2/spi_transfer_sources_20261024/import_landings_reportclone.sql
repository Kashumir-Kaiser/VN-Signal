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
('SPI','hnx','2026-10-24T04:59:27Z','https://owa.hnx.vn/ftp///cims/2025/6_W3/000000015061781_2642tb_0001.pdf','spi_hnx_delisting_notice_2642_2025-06-13.pdf','dc07f82346abb7f3ea36f4b1e90fae5358ee2e4d7690bf9fe4ec13a6c4a7c96f','479081','{"source_url":"https://owa.hnx.vn/ftp///cims/2025/6_W3/000000015061781_2642tb_0001.pdf","local_file":"spi_hnx_delisting_notice_2642_2025-06-13.pdf","source_attribution":"Hanoi Stock Exchange (HNX)","capture_time_basis":"UTC timestamp recorded at local file capture; see source manifest","document_date":"2025-06-13","claim_last_hnx_trade_date":"2025-07-09","claim_delisting_effective_date":"2025-07-10","claim_first_upcom_trade_date":null,"claim_custody_transfer_effective_date":null,"source_claim":"Official signed HNX Notice 2642/TB-SGDHN names SPI and states final HNX trading day 2025-07-09, delisting effective 2025-07-10, and reason for mandatory delisting.","source_limitation":"This notice establishes HNX-side lifecycle dates only; it does not establish UPCoM first-trading date, suspension status, or trading activity on individual intervening sessions."}'),
('SPI','vsdc','2026-10-24T04:59:27Z','https://vsdc.vn/vi/ad1/184158','spi_vsdc_hnx_upcom_transfer_2025-06-19.html','543f8f808e2a01857f797776f98a3d8ed1b2d913a8cbd54f482f18921466401b','71701','{"source_url":"https://vsdc.vn/vi/ad1/184158","local_file":"spi_vsdc_hnx_upcom_transfer_2025-06-19.html","source_attribution":"Vietnam Securities Depository and Clearing Corporation (VSDC)","capture_time_basis":"UTC timestamp recorded at local file capture; see source manifest","document_date":"2025-06-19","claim_last_hnx_trade_date":null,"claim_delisting_effective_date":null,"claim_first_upcom_trade_date":null,"claim_custody_transfer_effective_date":"2025-07-14","source_claim":"Official VSDC notice identifies old market HNX, new market UPCoM, transfer effective 2025-07-14, and cites HNX Decision 733/QD-SGDHN.","source_limitation":"Custody-data transfer effective date is not a final HNX trade date or first UPCoM trade date; this notice alone does not establish activity on intervening sessions."}'),
('SPI','hnx','2026-10-24T04:59:30Z','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-spi.html','spi_hnx_upcom_profile.html','e9b26570f76cffe3a2586b5909eace430e3b4c09c522fd756ffe668049a617ae','253951','{"source_url":"https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-spi.html","local_file":"spi_hnx_upcom_profile.html","source_attribution":"Hanoi Stock Exchange (HNX)","capture_time_basis":"UTC timestamp recorded at local file capture; see source manifest","document_date":null,"claim_last_hnx_trade_date":null,"claim_delisting_effective_date":null,"claim_first_upcom_trade_date":"2025-07-25","claim_custody_transfer_effective_date":null,"source_claim":"Official current HNX issuer profile identifies SPI / CTCP Spiral Galaxy, UPCoM, and historical first trading date 2025-07-25.","source_limitation":"This is a current profile captured in 2026; the profile field gives historical first trading date but does not establish a contemporaneous publication date, suspension status, or trading activity on individual intervening sessions."}');
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

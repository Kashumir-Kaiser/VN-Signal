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
\copy transfer_stage FROM 'C:/Users/HP/VN-Signal/docs/evidence/phase2/pom_qbs_transfer_sources_20261024/landing_stage.csv' WITH(FORMAT csv,HEADER true,ENCODING 'UTF8')
CREATE TEMP TABLE transfer_expected(LIKE transfer_stage) ON COMMIT DROP;
INSERT INTO transfer_expected(symbol,source,fetched_at,source_url,local_file,payload_sha256,payload_size,metadata_json) VALUES
('POM','cafef','2026-10-24T04:21:43Z','https://cafef1.mediacdn.vn/download/110424/pom-quyet-dinh-huy-niem-yet-co-phieu-0.pdf','pom_hose_delisting_decision_208_2024-04-10.pdf','e6e39abd5e3d606cf917a6aeb9cacaf74c0bd00061f9e511ed3381e3d48163bd','446848','{"source_url":"https://cafef1.mediacdn.vn/download/110424/pom-quyet-dinh-huy-niem-yet-co-phieu-0.pdf","local_file":"pom_hose_delisting_decision_208_2024-04-10.pdf","capture_time_basis":"actual HTTP capture UTC recorded in source manifest","source_attribution":"Ho Chi Minh Stock Exchange (HOSE), original decision carried by CafeF","document_date":"2024-04-10","last_hose_trade_date":"2024-05-09","delisting_effective_date":"2024-05-10","first_upcom_trade_date":null,"custody_transfer_effective_date":null,"evidence_claim":"Signed ticker-specific HOSE decision; page 2 gives final HOSE trade, page 1 gives delisting effective date."}'),
('POM','hnx','2026-10-24T04:21:43Z','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-pom.html','pom_hnx_upcom_profile.html','9d70a9e16f17063d038c46b2bc0f0c2b5c03d34c9cb39ed7fcca7abcb7e09b2c','259454','{"source_url":"https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-pom.html","local_file":"pom_hnx_upcom_profile.html","capture_time_basis":"actual HTTP capture UTC recorded in source manifest","source_attribution":"Hanoi Stock Exchange (HNX)","document_date":null,"last_hose_trade_date":null,"delisting_effective_date":null,"first_upcom_trade_date":"2024-05-23","custody_transfer_effective_date":null,"evidence_claim":"Current official issuer profile records historical first UPCoM trading date; contemporaneous publication date is not established."}'),
('QBS','cafef','2026-10-24T04:22:57Z','https://cafef1.mediacdn.vn/download/110424/qbs-quyet-dinh-huy-niem-yet-co-phieu-0.pdf','qbs_hose_delisting_decision_209_2024-04-10.pdf','88cf2e3d24c769441df68dc4e72bfc8fe94da54eb347e7fba8139c794b31ae16','453973','{"source_url":"https://cafef1.mediacdn.vn/download/110424/qbs-quyet-dinh-huy-niem-yet-co-phieu-0.pdf","local_file":"qbs_hose_delisting_decision_209_2024-04-10.pdf","capture_time_basis":"actual HTTP capture UTC recorded in source manifest","source_attribution":"Ho Chi Minh Stock Exchange (HOSE), original decision carried by CafeF","document_date":"2024-04-10","last_hose_trade_date":"2024-05-09","delisting_effective_date":"2024-05-10","first_upcom_trade_date":null,"custody_transfer_effective_date":null,"evidence_claim":"Signed ticker-specific HOSE decision; page 2 gives final HOSE trade, page 1 gives delisting effective date."}'),
('QBS','vsdc','2026-10-24T04:22:37Z','https://vsdc.vn/vi/ad/169876','qbs_vsdc_hose_upcom_transfer_2024-04-16.html','1fe32b0553ae556abccb5bd94053a3e32e9ccae99a50d4aaea49a0585dc352f0','72033','{"source_url":"https://vsdc.vn/vi/ad/169876","local_file":"qbs_vsdc_hose_upcom_transfer_2024-04-16.html","capture_time_basis":"actual HTTP capture UTC recorded in source manifest","source_attribution":"Vietnam Securities Depository and Clearing Corporation (VSDC)","document_date":"2024-04-16","last_hose_trade_date":null,"delisting_effective_date":null,"first_upcom_trade_date":null,"custody_transfer_effective_date":"2024-05-14","evidence_claim":"QBS custody transfer from HOSE to UPCoM, citing HOSE decision 209; does not establish final or first trading date."}'),
('QBS','hnx','2026-10-24T04:23:08Z','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-qbs.html','qbs_hnx_upcom_profile.html','c35761ab68b2d239e4f877e55ae24fd189827690421cfe7cf379f62bee8bc3c6','258081','{"source_url":"https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-qbs.html","local_file":"qbs_hnx_upcom_profile.html","capture_time_basis":"actual HTTP capture UTC recorded in source manifest","source_attribution":"Hanoi Stock Exchange (HNX)","document_date":null,"last_hose_trade_date":null,"delisting_effective_date":null,"first_upcom_trade_date":"2024-05-23","custody_transfer_effective_date":null,"evidence_claim":"Current official issuer profile records historical first UPCoM trading date; contemporaneous publication date is not established."}');
DO $$
BEGIN
 IF (SELECT count(*) FROM transfer_stage)<>5 OR (SELECT count(DISTINCT local_file) FROM transfer_stage)<>5
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
-- Archival only. No market bars, lifecycle events, interval classifications,
-- historical availability times, or price features are inferred or changed.
COMMIT;

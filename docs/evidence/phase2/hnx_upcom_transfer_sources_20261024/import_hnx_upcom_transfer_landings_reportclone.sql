\set ON_ERROR_STOP on
\pset pager off

-- Review-only archival of six primary HNX source files for the APP/C92/VIE
-- venue handoffs. Guarded to the disposable report clone. This inserts raw
-- source bytes only; it creates no lifecycle events and no synthetic bars.
SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

BEGIN;
CREATE TEMP TABLE hnx_upcom_stage (
  symbol text,
  source text,
  route text,
  retrieved_at_utc timestamptz,
  document_date date,
  last_hnx_trade_date date,
  delisting_effective_date date,
  first_upcom_trade_date date,
  evidence_claim text,
  source_url text,
  local_file text,
  payload_sha256 text,
  payload_size bigint,
  media_type text,
  source_attribution text,
  capture_time_basis text,
  body_b64 text
) ON COMMIT DROP;
\copy hnx_upcom_stage FROM 'C:/Users/HP/VN-Signal/docs/evidence/phase2/hnx_upcom_transfer_sources_20261024/landing_stage.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8', FORCE_NULL (document_date))

CREATE TEMP TABLE hnx_upcom_expected (
  symbol text NOT NULL,
  local_file text NOT NULL,
  source_url text NOT NULL,
  payload_sha256 text NOT NULL,
  payload_size bigint NOT NULL
) ON COMMIT DROP;
INSERT INTO hnx_upcom_expected(symbol,local_file,source_url,payload_sha256,payload_size) VALUES
  ('APP','APP_HNX_delisting_notice_2022-07.jpg','https://owa.hnx.vn/ftp///cims/2022/7_W2/000000011710185_APP_Huy.jpg','b2ca90b2cc00012cd4e1cb4e094ca334d8ec25097ab6f46b0773b217d0c89208',327716),
  ('APP','APP_HNX_UPCoM_profile.html','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-app.html','a55b45f2f85fe831c2586178e07a4cdb879a5d0ed1640fc846266d7c31f6d1f5',258225),
  ('C92','C92_HNX_delisting_notice_2022-07.jpg','https://owa.hnx.vn/ftp///cims/2022/7_W2/000000011710161_C92__Huy.jpg','09018f02465d1cac33ace27f25d2b77aa033e7d0c1116696f89b9426e6e5ee4f',327445),
  ('C92','C92_HNX_UPCoM_profile.html','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-C92.html','5549340ecdf76170346678b333623ffe4d2da6e1048e37b418db2c3a2279e3d9',258368),
  ('VIE','VIE_HNX_delisting_notice_2022-07.pdf','https://owa.hnx.vn/ftp///cims/2022/7_W2/000000011710053_Scan_6_Jul_2022_at_15.26.pdf','b89b337424035764494d951ab007778a91fd96186a32b0649b060b21b4b8336d',929040),
  ('VIE','VIE_HNX_UPCoM_profile.html','https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-vie.html','3a7b4c94911c44ff50968b0601a0a7852029725e8984692d4488202765f2d180',259381);

DO $$
BEGIN
  IF (SELECT count(*) FROM hnx_upcom_stage) <> 6
     OR (SELECT count(DISTINCT local_file) FROM hnx_upcom_stage) <> 6 THEN
    RAISE EXCEPTION 'expected six unique HNX source documents';
  END IF;
  IF EXISTS (
    (SELECT coalesce(symbol,''),local_file,source_url,lower(payload_sha256),payload_size
       FROM hnx_upcom_stage
     EXCEPT
     SELECT symbol,local_file,source_url,payload_sha256,payload_size FROM hnx_upcom_expected)
    UNION ALL
    (SELECT symbol,local_file,source_url,payload_sha256,payload_size FROM hnx_upcom_expected
     EXCEPT
     SELECT coalesce(symbol,''),local_file,source_url,lower(payload_sha256),payload_size
       FROM hnx_upcom_stage)
  ) THEN
    RAISE EXCEPTION 'staged ticker, URL, filename, size, or SHA-256 differs from the checked-in source manifest';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hnx_upcom_stage d
    WHERE coalesce(d.source,'') <> 'hnx'
       OR coalesce(d.route,'') <> 'security_lifecycle_notice'
       OR d.payload_sha256 !~ '^[0-9a-fA-F]{64}$'
       OR d.payload_size < 2
       OR d.body_b64 IS NULL
       OR octet_length(decode(d.body_b64,'base64')) <> d.payload_size
       OR lower(d.payload_sha256) <> lower(encode(sha256(decode(d.body_b64,'base64')),'hex'))
       OR coalesce(d.source_url,'') !~ '^https?://[^[:space:]]+$'
       OR d.retrieved_at_utc IS NULL
       OR d.last_hnx_trade_date IS DISTINCT FROM DATE '2022-07-15'
       OR d.delisting_effective_date IS DISTINCT FROM DATE '2022-07-18'
       OR d.first_upcom_trade_date IS DISTINCT FROM DATE '2022-08-03'
       OR coalesce(d.evidence_claim,'') = ''
       OR coalesce(d.source_attribution,'') <> 'Hanoi Stock Exchange (HNX)'
       OR coalesce(d.capture_time_basis,'') !~ 'original HTTP retrieval time was not recorded'
  ) THEN
    RAISE EXCEPTION 'HNX source identity, date claims, or original-byte SHA-256 validation failed';
  END IF;
  IF (SELECT count(*) FROM hnx_upcom_stage
      WHERE coalesce(local_file,'') LIKE '%delisting_notice%'
        AND document_date IS NOT DISTINCT FROM DATE '2022-07-05') <> 3
     OR (SELECT count(*) FROM hnx_upcom_stage WHERE document_date IS NULL) <> 3
     OR EXISTS (SELECT 1 FROM hnx_upcom_stage WHERE coalesce(symbol,'') NOT IN ('APP','C92','VIE'))
     OR EXISTS (SELECT 1 FROM hnx_upcom_stage WHERE coalesce(local_file,'') LIKE '%UPCoM_profile%' AND document_date IS NOT NULL)
     OR EXISTS (SELECT 1 FROM hnx_upcom_stage WHERE coalesce(local_file,'') LIKE '%delisting_notice%' AND document_date IS DISTINCT FROM DATE '2022-07-05') THEN
    RAISE EXCEPTION 'ticker-specific notice/profile date metadata is incomplete';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hnx_upcom_stage d
    WHERE NOT EXISTS (SELECT 1 FROM core.symbols s WHERE s.symbol=coalesce(d.symbol,''))
  ) THEN
    RAISE EXCEPTION 'one or more HNX ticker records do not match a security in the report clone';
  END IF;
END $$;

INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),coalesce(d.source,''),coalesce(d.route,''),d.retrieved_at_utc,
       NULLIF(d.symbol,''),
       jsonb_build_object(
         'document_date',d.document_date,
         'last_hnx_trade_date',d.last_hnx_trade_date,
         'delisting_effective_date',d.delisting_effective_date,
         'first_upcom_trade_date',d.first_upcom_trade_date,
         'evidence_claim',d.evidence_claim,
         'source_url',d.source_url,
         'local_file',d.local_file,
         'media_type',d.media_type,
         'source_attribution',d.source_attribution,
         'capture_time_basis',d.capture_time_basis,
         'original_payload_encoding','base64 staging decoded to original bytes'
       ),
       lower(d.payload_sha256),decode(d.body_b64,'base64')
FROM hnx_upcom_stage d
WHERE NOT EXISTS (
  SELECT 1 FROM raw.landings l
  WHERE l.source=coalesce(d.source,'') AND l.route=coalesce(d.route,'')
    AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
    AND lower(l.payload_sha256)=lower(coalesce(d.payload_sha256,''))
);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM hnx_upcom_stage d
    WHERE (SELECT count(*) FROM raw.landings l
           WHERE l.source=coalesce(d.source,'') AND l.route=coalesce(d.route,'')
             AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
             AND lower(l.payload_sha256)=lower(coalesce(d.payload_sha256,''))) <> 1
  ) THEN
    RAISE EXCEPTION 'each archived HNX source must resolve to exactly one same-ticker landing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hnx_upcom_stage d
    JOIN raw.landings l
      ON l.source=coalesce(d.source,'') AND l.route=coalesce(d.route,'')
     AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
     AND lower(l.payload_sha256)=lower(coalesce(d.payload_sha256,''))
    WHERE l.payload_bytes IS NULL
       OR encode(sha256(l.payload_bytes),'hex')<>lower(d.payload_sha256)
       OR octet_length(l.payload_bytes)<>d.payload_size
  ) THEN
    RAISE EXCEPTION 'raw landing bytes failed post-insert source validation';
  END IF;
END $$;

-- The dates above remain source evidence claims only. This file does not
-- classify the venue-transfer interval as a suspension or create FIRST_EVER
-- lifecycle evidence, interval rows, or synthetic market bars.
COMMIT;

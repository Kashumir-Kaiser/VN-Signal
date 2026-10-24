\set ON_ERROR_STOP on
\pset pager off

-- Review-only import of 13 ticker-specific first-HOSE notices plus the HNX
-- cohort notice. This file is restricted to the disposable report clone.
-- It inserts raw archived source bytes only. It deliberately adds no
-- TRADING_SUSPENDED lifecycle intervals: transfer/venue-gap semantics are not
-- represented by that event type, and the cohort notice is not ticker-specific.
SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

BEGIN;
CREATE TEMP TABLE hose_transfer_stage (
  symbol text,
  source text,
  route text,
  retrieved_at_utc timestamptz,
  document_date date,
  first_hose_date date,
  evidence_claim text,
  source_url text,
  source_context_url text,
  local_file text,
  payload_sha256 text,
  payload_size bigint,
  media_type text,
  source_attribution text,
  body_b64 text
) ON COMMIT DROP;
\copy hose_transfer_stage FROM 'C:/Users/HP/VN-Signal/docs/evidence/phase2/hose_transfer_sources_20261023/landing_stage.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE hose_transfer_expected (
  symbol text, local_file text NOT NULL, source_url text NOT NULL, payload_sha256 text NOT NULL
) ON COMMIT DROP;
INSERT INTO hose_transfer_expected(symbol,local_file,source_url,payload_sha256) VALUES
  (NULL,'HNX_2021-08-27_transfer_notice.html','https://www.hnx.vn/vi-vn/chi-tiet-su-kien-60012723-0-hnx.html?_page=1','02faa61c6bb49dfc53c69d66a1c24638f6acca89bc45d228ce881b66e39492b1'),
  ('ABT','ABT_HOSE_first_day_notice_2021-08-27.pdf','https://static2.vietstock.vn/vietstock/2021/8/27/20210827_ABT%20210827%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf','ef7ba29ec1cb8b884c326edcb9935dc2f0bbb98851d351094fa4d0823a90227a'),
  ('BSI','BSI_HOSE_first_day_notice_2021-08-30.pdf','https://static2.vietstock.vn/vietstock/2021/8/30/20210830_BSI%20210830%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf','71977570f96a0bd536d186635dfc1772e77ac46301327353cae2e92f317f0d61'),
  ('DXS','DXS_HOSE_first_day_notice_2021-08-25.pdf','https://datxanhservices.vn/wp-content/uploads/2021/08/DXS-TB-ngay-giao-dich-dau-tien-tren-HOSE.pdf','9a8ace97866ad0c5ed8fdb429c6007e2d0e3e98c9a1a8040c9d3b8b94399d4e5'),
  ('VND','VND_HOSE_first_day_notice_2021-08-30.pdf','https://static2.vietstock.vn/vietstock/2021/8/30/20210830_VNDS%20210830%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf','14a293ab947bb3f40afd3375f60d5e8642b51f1b90e9bcebbd38620939ca8ef6'),
  ('HAP','HAP_HOSE_first_day_notice_2021-08-26.pdf','http://cafefnew.mediacdn.vn/download/260821/hap-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose.pdf','015dc0eab40b94ef422d3da5e99fc147acc292a4b6716818e97cfe54f63924cf'),
  ('KHG','KHG_HOSE_first_day_notice_2021-08-27.pdf','http://cafefnew.mediacdn.vn/download/270821/khg-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose.pdf','7c3671be17b833a109983d8f821c8c5db1f6c4cc895922824b6ffa28420adef8'),
  ('LAF','LAF_HOSE_first_day_notice_2021-08-30.pdf','http://cafefnew.mediacdn.vn/download/300821/laf-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','f11167dc61bed38e8e50ab3b5d8e7228041b52b0c8ba81996e48ef008b84979d'),
  ('NSC','NSC_HOSE_first_day_notice_2021-08-30.pdf','http://cafefnew.mediacdn.vn/download/300821/nsc-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','5641fbcac616bcbdef1623912bc5cee2e24fc79a64e9072981256f98c4d27139'),
  ('PAN','PAN_HOSE_first_day_notice_2021-08-27.pdf','http://cafefnew.mediacdn.vn/download/270821/pan-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','87cb6b40046f2d192afcdcfb9b2fc2fb2a98f5bdac90fa3f3181abe5ed9a7527'),
  ('QBS','QBS_HOSE_first_day_notice_2021-08-27.pdf','http://cafefnew.mediacdn.vn/download/270821/qbs-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','604dcbb88af3e51396cf7ed63795eb0580d2032a33dc736b7e1af1716176edfb'),
  ('SSC','SSC_HOSE_first_day_notice_2021-08-30.pdf','http://cafefnew.mediacdn.vn/download/300821/ssc-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','fe9548f2ea441771879cef324f6b4a2571fc6d86c066adba4c83cb2c91155a8c'),
  ('TVB','TVB_HOSE_first_day_notice_2021-08-27.pdf','http://cafefnew.mediacdn.vn/download/270821/tvb-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose-cua-co-phieu-chuyen-giao-dich.pdf','006d2329fec946d3ef158f6e76d55f6e57756ffb3d2abd4fa232138bb7d6836b'),
  ('VFG','VFG_HOSE_first_day_notice_2021-08-27.pdf','http://cafefnew.mediacdn.vn/download/270821/vfg-thong-bao-ve-ngay-giao-dich-dau-tien-tren-hose.pdf','cd04dd4935c3bab6282f482eb5b7b2075b1ed2a45137ff2816aeb3d49c31e742');

DO $$
BEGIN
  IF (SELECT count(*) FROM hose_transfer_stage) <> 14
     OR (SELECT count(DISTINCT local_file) FROM hose_transfer_stage) <> 14 THEN
    RAISE EXCEPTION 'expected 14 unique HNX/HOSE transfer source documents';
  END IF;
  IF EXISTS (
    (SELECT NULLIF(symbol,'') AS symbol,local_file,source_url,lower(payload_sha256) AS payload_sha256
       FROM hose_transfer_stage
     EXCEPT
     SELECT symbol,local_file,source_url,payload_sha256 FROM hose_transfer_expected)
    UNION ALL
    (SELECT symbol,local_file,source_url,payload_sha256 FROM hose_transfer_expected
     EXCEPT
     SELECT NULLIF(symbol,'') AS symbol,local_file,source_url,lower(payload_sha256) AS payload_sha256
       FROM hose_transfer_stage)
  ) THEN
    RAISE EXCEPTION 'staged URLs, filenames, or SHA-256 values differ from the checked-in source manifest';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    WHERE d.route <> 'security_lifecycle_notice'
       OR d.payload_sha256 !~ '^[0-9a-fA-F]{64}$'
       OR d.payload_size < 2
       OR octet_length(decode(d.body_b64,'base64')) <> d.payload_size
       OR lower(d.payload_sha256) <> lower(encode(sha256(decode(d.body_b64,'base64')),'hex'))
       OR d.source_url !~ '^https?://[^[:space:]]+$'
       OR (d.source_context_url <> '' AND d.source_context_url !~ '^https://[^[:space:]]+$')
       OR d.retrieved_at_utc IS NULL
       OR d.document_date IS NULL
       OR d.evidence_claim IS NULL
       OR d.source_attribution IS NULL
  ) THEN
    RAISE EXCEPTION 'transfer source identity, metadata, or original-byte SHA-256 validation failed';
  END IF;
  IF (SELECT count(*) FROM hose_transfer_stage WHERE coalesce(symbol,'')='') <> 1
     OR EXISTS (SELECT 1 FROM hose_transfer_stage WHERE coalesce(symbol,'')='' AND first_hose_date IS NOT NULL)
     OR EXISTS (SELECT 1 FROM hose_transfer_stage WHERE symbol<>'' AND first_hose_date IS NULL)
     OR (SELECT count(*) FROM hose_transfer_stage WHERE symbol<>'' AND first_hose_date IS NOT NULL) <> 13 THEN
    RAISE EXCEPTION 'ticker-specific first-HOSE date staging is incomplete or cohort attribution is ambiguous';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    WHERE d.symbol<>'' AND NOT EXISTS (
      SELECT 1 FROM core.symbols s WHERE s.symbol=d.symbol
    )
  ) THEN
    RAISE EXCEPTION 'one or more ticker-specific notices do not match a security in the report clone';
  END IF;
END $$;

INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),d.source,d.route,d.retrieved_at_utc,NULLIF(d.symbol,''),
       jsonb_build_object(
         'document_date',d.document_date,
         'first_hose_date',d.first_hose_date,
         'evidence_claim',d.evidence_claim,
         'source_url',d.source_url,
         'source_context_url',NULLIF(d.source_context_url,''),
         'local_file',d.local_file,
         'media_type',d.media_type,
         'source_attribution',d.source_attribution,
         'original_payload_encoding','base64 staging decoded to original bytes'
       ),
       lower(d.payload_sha256),decode(d.body_b64,'base64')
FROM hose_transfer_stage d
WHERE NOT EXISTS (
  SELECT 1 FROM raw.landings l
  WHERE l.source=d.source AND l.route=d.route
    AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
    AND lower(l.payload_sha256)=lower(d.payload_sha256)
);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    WHERE (SELECT count(*) FROM raw.landings l
           WHERE l.source=d.source AND l.route=d.route
             AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
             AND lower(l.payload_sha256)=lower(d.payload_sha256)) <> 1
  ) THEN
    RAISE EXCEPTION 'each archived source must resolve to exactly one same-symbol landing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    JOIN raw.landings l
      ON l.source=d.source AND l.route=d.route
     AND l.symbol IS NOT DISTINCT FROM NULLIF(d.symbol,'')
     AND lower(l.payload_sha256)=lower(d.payload_sha256)
    WHERE l.payload_bytes IS NULL
       OR encode(sha256(l.payload_bytes),'hex')<>lower(d.payload_sha256)
       OR octet_length(l.payload_bytes)<>d.payload_size
  ) THEN
    RAISE EXCEPTION 'raw landing bytes failed post-insert source validation';
  END IF;
END $$;

-- Deliberately no INSERT into core.security_lifecycle_evidence and no updates
-- to bars/features. A transfer-window lifecycle event needs an audited event
-- type whose meaning covers venue migration without asserting suspension.
COMMIT;

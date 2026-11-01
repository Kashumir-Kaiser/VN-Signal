\set ON_ERROR_STOP on
\pset pager off

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing batch 12 import outside disposable report clone vnsignal_phase2_report_20261019'
  \quit 2
\endif

BEGIN;

CREATE TEMP TABLE phase2_batch12_source_stage (
  symbol text, source text, route text, fetched_at text, source_url text,
  local_file text, document_date text, last_trade_date text,
  prior_ceased_from text, first_trade_date text, payload_sha256 text,
  payload_size text, media_type text, source_attribution text, source_claim text,
  source_limitation text, capture_time_basis text, metadata_json text, body_hex text
) ON COMMIT DROP;
\copy phase2_batch12_source_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/batch12_signed_source_capture_20261031/landing_stage_batch12_20261031.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE TEMP TABLE phase2_batch12_event_stage (
  symbol text, prior_venue text, venue text, prior_trade_date date,
  suspension_effective_date date, prior_ceased_from date, effective_date date,
  prior_feature_row_date date, next_feature_row_date date,
  missing_effective_sessions integer, share_count bigint,
  source_article_id text, notice_article_id text, continuity_article_id text,
  decision_date date, notice_date date, continuity_date date,
  source_file text, continuity_file text, reviewed_claim text
) ON COMMIT DROP;
\copy phase2_batch12_event_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/batch12_signed_source_capture_20261031/transfer_event_stage_batch12_20261031.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE TEMP TABLE phase2_batch12_expected (
  symbol text, prior_trade_date date, suspension_effective_date date,
  prior_ceased_from date, effective_date date, prior_feature_row_date date,
  next_feature_row_date date, missing_effective_sessions integer, share_count bigint,
  source_article_id text, notice_article_id text, continuity_article_id text,
  decision_date date, notice_date date, continuity_date date,
  source_file text, continuity_file text
) ON COMMIT DROP;
INSERT INTO phase2_batch12_expected VALUES
('DAG',DATE '2024-08-14',DATE '2024-08-15',DATE '2024-10-22',DATE '2024-11-01',DATE '2024-10-21',DATE '2024-11-01',8,60314112,'1733994','1733993','60019787',DATE '2024-10-15',DATE '2024-10-15',DATE '2024-10-25','batch12_signed_source_capture_20261031/hose_dag_decision_1733994.pdf','batch12_signed_source_capture_20261031/hnx_dag_first_trade_60019787.pdf'),
('HTT',DATE '2020-05-21',NULL,DATE '2020-06-18',DATE '2020-06-26',DATE '2020-06-17',DATE '2020-06-26',6,20000000,'1188489','1187025','60008745',DATE '2020-06-11',DATE '2020-06-11',DATE '2020-06-19','batch12_signed_source_capture_20261031/hose_htt_decision_1188489.pdf','batch12_signed_source_capture_20261031/hnx_htt_first_trade_60008745.pdf'),
('ITA',DATE '2024-09-25',DATE '2024-09-26',DATE '2025-02-04',DATE '2025-02-13',DATE '2025-02-03',DATE '2025-02-13',7,938463607,'1745490','1745784','60020444',DATE '2025-01-21',DATE '2025-01-21',DATE '2025-02-06','batch12_signed_source_capture_20261031/hose_ita_decision_1745490.pdf','batch12_signed_source_capture_20261031/hnx_ita_first_trade_60020444.pdf'),
('LEC',DATE '2024-09-13',DATE '2024-09-16',DATE '2025-04-29',DATE '2025-05-13',DATE '2025-04-28',DATE '2025-05-13',7,26100000,'2270980','2272810','60021001',DATE '2025-04-23',DATE '2025-04-23',DATE '2025-05-06','batch12_signed_source_capture_20261031/hose_lec_decision_2270980.pdf','batch12_signed_source_capture_20261031/hnx_lec_first_trade_60021001.pdf'),
('SJF',DATE '2023-11-10',DATE '2023-11-13',DATE '2024-11-01',DATE '2024-11-13',DATE '2024-10-31',DATE '2024-11-13',8,79200000,'1724483','1723687','60019853',DATE '2024-10-25',DATE '2024-10-25',DATE '2024-11-06','batch12_signed_source_capture_20261031/hose_sjf_decision_1724483.pdf','batch12_signed_source_capture_20261031/hnx_sjf_first_trade_60019853.pdf'),
('TCD',DATE '2025-10-09',NULL,DATE '2026-07-15',DATE '2026-07-24',DATE '2026-07-14',DATE '2026-07-24',7,335820641,'2478114','2478116','60023071',DATE '2026-07-08',DATE '2026-07-08',DATE '2026-07-17','batch12_signed_source_capture_20261031/hose_tcd_decision_2478114.pdf','batch12_signed_source_capture_20261031/hnx_tcd_first_trade_60023071.pdf');

DO $$
DECLARE
  expected_feature_hash text := '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b';
BEGIN
  IF feat.phase2_feature_set_hash_v3() <> expected_feature_hash THEN
    RAISE EXCEPTION 'batch 12 evidence was staged for a different V3 feature hash';
  END IF;
  IF (SELECT count(*) FROM phase2_batch12_source_stage) <> 12
     OR (SELECT count(DISTINCT local_file) FROM phase2_batch12_source_stage) <> 12
     OR (SELECT count(*) FROM phase2_batch12_event_stage) <> 6
     OR (SELECT count(DISTINCT symbol) FROM phase2_batch12_event_stage) <> 6
     OR (SELECT count(*) FROM phase2_batch12_expected) <> 6 THEN
    RAISE EXCEPTION 'batch 12 requires twelve unique signed endpoint documents and six events';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_expected x
    LEFT JOIN phase2_batch12_event_stage e USING (symbol)
    WHERE e.symbol IS NULL
       OR e.prior_venue IS DISTINCT FROM 'HOSE'
       OR e.venue IS DISTINCT FROM 'UPCOM'
       OR e.prior_trade_date IS DISTINCT FROM x.prior_trade_date
       OR e.suspension_effective_date IS DISTINCT FROM x.suspension_effective_date
       OR e.prior_ceased_from IS DISTINCT FROM x.prior_ceased_from
       OR e.effective_date IS DISTINCT FROM x.effective_date
       OR e.prior_feature_row_date IS DISTINCT FROM x.prior_feature_row_date
       OR e.next_feature_row_date IS DISTINCT FROM x.next_feature_row_date
       OR e.missing_effective_sessions IS DISTINCT FROM x.missing_effective_sessions
       OR e.share_count IS DISTINCT FROM x.share_count
       OR e.source_article_id IS DISTINCT FROM x.source_article_id
       OR e.notice_article_id IS DISTINCT FROM x.notice_article_id
       OR e.continuity_article_id IS DISTINCT FROM x.continuity_article_id
       OR e.decision_date IS DISTINCT FROM x.decision_date
       OR e.notice_date IS DISTINCT FROM x.notice_date
       OR e.continuity_date IS DISTINCT FROM x.continuity_date
       OR e.source_file IS DISTINCT FROM x.source_file
       OR e.continuity_file IS DISTINCT FROM x.continuity_file
       OR e.prior_trade_date >= e.prior_ceased_from
       OR e.prior_ceased_from >= e.effective_date
       OR e.prior_feature_row_date >= e.prior_ceased_from
       OR e.next_feature_row_date <> e.effective_date
       OR (e.suspension_effective_date IS NOT NULL
           AND (e.suspension_effective_date <= e.prior_trade_date
                OR e.suspension_effective_date > e.prior_ceased_from))
       OR length(trim(e.reviewed_claim)) < 120
  ) OR EXISTS (
    SELECT 1 FROM phase2_batch12_event_stage e
    LEFT JOIN phase2_batch12_expected x USING (symbol)
    WHERE x.symbol IS NULL
  ) THEN
    RAISE EXCEPTION 'batch 12 event facts differ from reviewed signed records or expected intervals';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_source_stage d
    LEFT JOIN phase2_batch12_expected x USING (symbol)
    WHERE x.symbol IS NULL
       OR d.route <> 'security_lifecycle_notice'
       OR d.source NOT IN ('hose','hnx')
       OR d.payload_sha256 !~ '^[0-9a-f]{64}$'
       OR octet_length(decode(d.body_hex,'hex')) <> d.payload_size::bigint
       OR lower(d.payload_sha256) <> encode(sha256(decode(d.body_hex,'hex')),'hex')
       OR d.media_type NOT ILIKE 'application/pdf%'
       OR substring(decode(d.body_hex,'hex') from 1 for 5) <> convert_to('%PDF-','UTF8')
       OR d.metadata_json::jsonb->>'source_url' IS DISTINCT FROM d.source_url
       OR d.metadata_json::jsonb->>'captured_source_url' IS DISTINCT FROM d.source_url
       OR d.metadata_json::jsonb->>'capture_time_basis' IS DISTINCT FROM d.capture_time_basis
       OR d.capture_time_basis IS DISTINCT FROM 'actual HTTP capture UTC recorded per response'
       OR (d.metadata_json::jsonb->>'captured_at_utc')::timestamptz IS DISTINCT FROM d.fetched_at::timestamptz
       OR d.metadata_json::jsonb->>'document_date' IS DISTINCT FROM d.document_date
       OR d.metadata_json::jsonb->>'share_count' IS DISTINCT FROM x.share_count::text
       OR d.source_url !~ '^https://[^[:space:]]+$'
       OR (d.source='hose' AND (
            d.metadata_json::jsonb->>'article_id' IS DISTINCT FROM x.source_article_id
            OR d.local_file IS DISTINCT FROM x.source_file
            OR d.source_url !~ '^https://staticfile[.]hsx[.]vn/Uploads/(News|UploadDocuments)/'
            OR d.document_date::date IS DISTINCT FROM x.decision_date
            OR d.last_trade_date::date IS DISTINCT FROM x.prior_trade_date
            OR d.prior_ceased_from::date IS DISTINCT FROM x.prior_ceased_from
            OR nullif(d.first_trade_date,'') IS NOT NULL
            OR d.metadata_json::jsonb->>'final_hose_trade_date' IS DISTINCT FROM x.prior_trade_date::text
            OR nullif(d.metadata_json::jsonb->>'suspension_effective_date','') IS DISTINCT FROM x.suspension_effective_date::text
            OR d.metadata_json::jsonb->>'prior_ceased_from' IS DISTINCT FROM x.prior_ceased_from::text
            OR d.metadata_json::jsonb->'corroborating_notice'->>'article_id' IS DISTINCT FROM x.notice_article_id
            OR d.metadata_json::jsonb->'corroborating_notice'->>'sha256' !~ '^[0-9a-f]{64}$'
          ))
       OR (d.source='hnx' AND (
            d.metadata_json::jsonb->>'article_id' IS DISTINCT FROM x.continuity_article_id
            OR d.local_file IS DISTINCT FROM x.continuity_file
            OR d.source_url !~ '^https://owa[.]hnx[.]vn/ftp/'
            OR d.document_date::date IS DISTINCT FROM x.continuity_date
            OR nullif(d.last_trade_date,'') IS NOT NULL
            OR nullif(d.prior_ceased_from,'') IS NOT NULL
            OR d.first_trade_date::date IS DISTINCT FROM x.effective_date
            OR d.metadata_json::jsonb->>'first_trade_date' IS DISTINCT FROM x.effective_date::text
            OR d.metadata_json::jsonb->>'article_detail_sha256' !~ '^[0-9a-f]{64}$'
          ))
  ) THEN
    RAISE EXCEPTION 'batch 12 source identity, hashes, timestamps, MIME, host, or endpoint facts failed validation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_expected x
    WHERE (SELECT count(*) FROM phase2_batch12_source_stage d WHERE d.symbol=x.symbol) <> 2
       OR (SELECT count(*) FROM phase2_batch12_source_stage d WHERE d.symbol=x.symbol AND d.source='hose') <> 1
       OR (SELECT count(*) FROM phase2_batch12_source_stage d WHERE d.symbol=x.symbol AND d.source='hnx') <> 1
  ) THEN
    RAISE EXCEPTION 'each batch 12 event requires one HOSE and one HNX signed endpoint';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_expected x
    WHERE NOT EXISTS (
      SELECT 1 FROM core.effective_trading_sessions s
      WHERE s.is_session AND s.trade_date=x.prior_ceased_from
    ) OR NOT EXISTS (
      SELECT 1 FROM core.effective_trading_sessions s
      WHERE s.is_session AND s.trade_date=x.effective_date
    ) OR (
      SELECT count(*) FROM core.effective_trading_sessions s
      WHERE s.is_session AND s.trade_date>=x.prior_ceased_from AND s.trade_date<x.effective_date
    ) <> x.missing_effective_sessions
    ) THEN
    RAISE EXCEPTION 'a batch 12 cessation/first-trade pair differs from the effective-session calendar';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_expected x
    JOIN core.symbols s ON s.symbol=x.symbol
    WHERE NOT EXISTS (
      SELECT 1 FROM feat.features_daily f
      WHERE f.symbol_id=s.symbol_id AND f.feature_version='phase2-v3'
        AND f.feature_set_hash=expected_feature_hash AND f.trade_date=x.prior_feature_row_date
    ) OR NOT EXISTS (
      SELECT 1 FROM feat.features_daily f
      WHERE f.symbol_id=s.symbol_id AND f.feature_version='phase2-v3'
        AND f.feature_set_hash=expected_feature_hash AND f.trade_date=x.next_feature_row_date
    ) OR EXISTS (
      SELECT 1 FROM feat.features_daily f
      WHERE f.symbol_id=s.symbol_id AND f.feature_version='phase2-v3'
        AND f.feature_set_hash=expected_feature_hash
        AND f.trade_date>x.prior_feature_row_date AND f.trade_date<x.next_feature_row_date
    ) OR EXISTS (
      SELECT 1 FROM core.bars_daily b
      WHERE b.symbol_id=s.symbol_id AND b.trade_date>x.prior_feature_row_date AND b.trade_date<x.next_feature_row_date
    ) OR EXISTS (
      SELECT 1 FROM core.bars_daily_sources bs
      WHERE bs.symbol_id=s.symbol_id AND bs.trade_date>x.prior_feature_row_date AND bs.trade_date<x.next_feature_row_date
    )
  ) THEN
    RAISE EXCEPTION 'a batch 12 feature gap changed or has intervening features, bars, or source rows';
  END IF;
END $$;

INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),d.source,d.route,d.fetched_at::timestamptz,d.symbol,
       d.metadata_json::jsonb,lower(d.payload_sha256),decode(d.body_hex,'hex')
  FROM phase2_batch12_source_stage d
 WHERE NOT EXISTS (
       SELECT 1 FROM raw.landings l
        WHERE l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
          AND l.fetched_at=d.fetched_at::timestamptz
          AND lower(l.payload_sha256)=lower(d.payload_sha256)
          AND l.payload->>'source_url'=d.source_url
          AND l.payload_bytes=decode(d.body_hex,'hex')
 );

CREATE TEMP TABLE phase2_batch12_landing_map ON COMMIT DROP AS
SELECT d.local_file,l.landing_id,l.fetched_at,d.symbol,d.source,
       d.document_date::date AS document_date,
       nullif(d.last_trade_date,'')::date AS last_trade_date,
       nullif(d.prior_ceased_from,'')::date AS prior_ceased_from,
       nullif(d.first_trade_date,'')::date AS first_trade_date,
       d.metadata_json::jsonb->>'article_id' AS article_id,
       d.metadata_json::jsonb->>'share_count' AS share_count
  FROM phase2_batch12_source_stage d
  JOIN raw.landings l
    ON l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
   AND l.fetched_at=d.fetched_at::timestamptz
   AND lower(l.payload_sha256)=lower(d.payload_sha256)
   AND l.payload->>'source_url'=d.source_url
   AND l.payload_bytes=decode(d.body_hex,'hex');

DO $$
BEGIN
  IF (SELECT count(*) FROM phase2_batch12_landing_map) <> 12
     OR (SELECT count(DISTINCT local_file) FROM phase2_batch12_landing_map) <> 12 THEN
    RAISE EXCEPTION 'each batch 12 signed endpoint must resolve to one immutable raw landing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_batch12_event_stage e
    JOIN phase2_batch12_expected x USING (symbol)
    LEFT JOIN phase2_batch12_landing_map source ON source.local_file=e.source_file
    LEFT JOIN phase2_batch12_landing_map continuity ON continuity.local_file=e.continuity_file
    WHERE source.landing_id IS NULL OR continuity.landing_id IS NULL
       OR source.symbol <> e.symbol OR continuity.symbol <> e.symbol
       OR source.source <> 'hose' OR continuity.source <> 'hnx'
       OR source.document_date <> x.decision_date
       OR continuity.document_date <> x.continuity_date
       OR source.last_trade_date IS DISTINCT FROM e.prior_trade_date
       OR source.prior_ceased_from IS DISTINCT FROM e.prior_ceased_from
       OR continuity.first_trade_date IS DISTINCT FROM e.effective_date
       OR source.article_id IS DISTINCT FROM e.source_article_id
       OR continuity.article_id IS DISTINCT FROM e.continuity_article_id
       OR source.share_count IS DISTINCT FROM e.share_count::text
       OR continuity.share_count IS DISTINCT FROM e.share_count::text
  ) THEN
    RAISE EXCEPTION 'batch 12 signed endpoints, article IDs, dates, or share counts differ from reviewed events';
  END IF;
END $$;

WITH event_inputs AS (
  SELECT s.symbol_id,e.symbol,e.venue,e.prior_venue,e.effective_date,e.prior_ceased_from,
         source.landing_id AS source_landing_id,
         continuity.landing_id AS continuity_landing_id,
         source.document_date,
         greatest(source.fetched_at,continuity.fetched_at,
           ((source.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'),
           ((continuity.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')) AS available_at,
         source_payload.payload->>'source_url' AS source_url,e.reviewed_claim,
         coalesce((
           SELECT prior.episode_id FROM core.security_listing_events prior
            WHERE prior.symbol_id=s.symbol_id AND prior.event_type='ADMISSION'
              AND prior.venue=e.prior_venue AND prior.effective_date<=e.prior_ceased_from
            ORDER BY prior.effective_date DESC,prior.event_id DESC LIMIT 1
         ),md5('PHASE2-E4-'||e.symbol||'-'||e.effective_date::text)::uuid) AS episode_id
    FROM phase2_batch12_event_stage e
    JOIN core.symbols s ON s.symbol=e.symbol
    JOIN phase2_batch12_landing_map source ON source.local_file=e.source_file
    JOIN phase2_batch12_landing_map continuity ON continuity.local_file=e.continuity_file
    JOIN raw.landings source_payload ON source_payload.landing_id=source.landing_id
), inserted AS (
  INSERT INTO core.security_listing_events(
    symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
    prior_ceased_from,source_landing_id,continuity_landing_id,
    document_date,available_at,availability_basis,source_url,reviewed_claim
  )
  SELECT symbol_id,episode_id,'TRANSFER',venue,effective_date,prior_venue,
         prior_ceased_from,source_landing_id,continuity_landing_id,
         document_date,available_at,'ARCHIVE_FETCH',source_url,reviewed_claim
    FROM event_inputs
  ON CONFLICT(symbol_id,episode_id,event_type,effective_date,source_landing_id)
    DO NOTHING
  RETURNING event_id
)
SELECT count(*) AS inserted_batch12_transfer_events FROM inserted;

DO $$
BEGIN
  IF (SELECT count(*)
        FROM phase2_batch12_event_stage e
        JOIN phase2_batch12_expected x USING (symbol)
        JOIN core.symbols s ON s.symbol=e.symbol
        JOIN phase2_batch12_landing_map source ON source.local_file=e.source_file
        JOIN phase2_batch12_landing_map continuity ON continuity.local_file=e.continuity_file
        JOIN core.security_listing_events event
          ON event.symbol_id=s.symbol_id
         AND event.source_landing_id=source.landing_id
         AND event.continuity_landing_id=continuity.landing_id
         AND event.prior_venue=e.prior_venue AND event.venue=e.venue
         AND event.effective_date=e.effective_date
         AND event.prior_ceased_from=e.prior_ceased_from
        JOIN ops.phase2_verified_security_transfers verified ON verified.event_id=event.event_id
       WHERE verified.prior_ceased_from=x.prior_ceased_from
         AND verified.effective_date=x.effective_date
         AND verified.prior_ceased_from>x.prior_feature_row_date
         AND verified.effective_date=x.next_feature_row_date) <> 6 THEN
    RAISE EXCEPTION 'batch 12 did not produce six strict verified transfers on the exact current-hash gaps';
  END IF;
END $$;

COMMIT;

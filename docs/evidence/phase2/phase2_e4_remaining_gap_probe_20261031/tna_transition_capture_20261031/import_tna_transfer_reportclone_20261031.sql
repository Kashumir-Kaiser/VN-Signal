\set ON_ERROR_STOP on
\pset pager off

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing TNA transfer import outside disposable report clone vnsignal_phase2_report_20261019'
  \quit 2
\endif

BEGIN;

CREATE TEMP TABLE phase2_tna_source_stage (
  symbol text, source text, route text, fetched_at text, source_url text,
  local_file text, document_date text, last_trade_date text,
  prior_ceased_from text, first_trade_date text, payload_sha256 text,
  payload_size text, media_type text, source_attribution text, source_claim text,
  source_limitation text, capture_time_basis text, metadata_json text, body_hex text
) ON COMMIT DROP;
\copy phase2_tna_source_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/tna_transition_capture_20261031/landing_stage_tna_20261031.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE TEMP TABLE phase2_tna_event_stage (
  symbol text, prior_venue text, venue text, prior_trade_date date,
  suspension_effective_date date, prior_ceased_from date, effective_date date,
  prior_feature_row_date date, next_feature_row_date date,
  missing_effective_sessions integer, share_count bigint,
  source_article_id text, continuity_article_id text,
  source_file text, continuity_file text, reviewed_claim text
) ON COMMIT DROP;
\copy phase2_tna_event_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/tna_transition_capture_20261031/transfer_event_stage_tna_20261031.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

DO $$
DECLARE
  expected_feature_hash text := '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b';
BEGIN
  IF feat.phase2_feature_set_hash_v3() <> expected_feature_hash THEN
    RAISE EXCEPTION 'TNA evidence was staged for a different V3 feature hash';
  END IF;
  IF (SELECT count(*) FROM phase2_tna_source_stage) <> 2
     OR (SELECT count(DISTINCT local_file) FROM phase2_tna_source_stage) <> 2
     OR (SELECT count(*) FROM phase2_tna_event_stage) <> 1 THEN
    RAISE EXCEPTION 'TNA import requires two unique endpoint documents and one event';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_tna_source_stage d
     WHERE d.symbol <> 'TNA'
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
        OR d.metadata_json::jsonb->>'article_id' IS NULL
        OR d.metadata_json::jsonb->>'share_count' IS DISTINCT FROM '49576264'
        OR length(trim(d.source_claim)) < 40
        OR d.source_url !~ '^https://[^[:space:]]+$'
        OR (d.source='hose' AND (
             d.metadata_json::jsonb->>'article_id' <> '1724218'
             OR d.local_file <> 'tna_transition_capture_20261031/hose_tna_decision_1724218.pdf'
             OR d.source_url !~ '^https://staticfile[.]hsx[.]vn/Uploads/News/'
             OR d.document_date <> '2024-11-12'
             OR d.last_trade_date <> '2024-09-13'
             OR d.prior_ceased_from <> '2024-11-19'
             OR nullif(d.first_trade_date,'') IS NOT NULL
             OR d.metadata_json::jsonb->>'final_hose_trade_date' <> '2024-09-13'
             OR d.metadata_json::jsonb->>'suspension_effective_date' <> '2024-09-16'
             OR d.metadata_json::jsonb->>'prior_ceased_from' <> '2024-11-19'
             OR d.metadata_json::jsonb->'corroborating_notice'->>'article_id' <> '1725517'
             OR d.metadata_json::jsonb->'corroborating_notice'->>'sha256' !~ '^[0-9a-f]{64}$'
           ))
        OR (d.source='hnx' AND (
             d.metadata_json::jsonb->>'article_id' <> '60019952'
             OR d.local_file <> 'tna_transition_capture_20261031/hnx_tna_first_trade_notice_60019952.pdf'
             OR d.source_url !~ '^https://owa[.]hnx[.]vn/ftp/'
             OR d.document_date <> '2024-11-22'
             OR nullif(d.last_trade_date,'') IS NOT NULL
             OR nullif(d.prior_ceased_from,'') IS NOT NULL
             OR d.first_trade_date <> '2024-11-29'
             OR d.metadata_json::jsonb->>'first_trade_date' <> '2024-11-29'
             OR d.metadata_json::jsonb->>'article_detail_sha256' !~ '^[0-9a-f]{64}$'
           ))
  ) THEN
    RAISE EXCEPTION 'TNA endpoint source identity, hashes, timestamps, or dates failed validation';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_tna_event_stage e
     WHERE e.symbol <> 'TNA'
        OR e.prior_venue <> 'HOSE' OR e.venue <> 'UPCOM'
        OR e.prior_trade_date <> DATE '2024-09-13'
        OR e.suspension_effective_date <> DATE '2024-09-16'
        OR e.prior_ceased_from <> DATE '2024-11-19'
        OR e.effective_date <> DATE '2024-11-29'
        OR e.prior_feature_row_date <> DATE '2024-11-18'
        OR e.next_feature_row_date <> DATE '2024-11-29'
        OR e.missing_effective_sessions <> 8
        OR e.share_count <> 49576264
        OR e.source_article_id <> '1724218'
        OR e.continuity_article_id <> '60019952'
        OR e.source_file <> 'tna_transition_capture_20261031/hose_tna_decision_1724218.pdf'
        OR e.continuity_file <> 'tna_transition_capture_20261031/hnx_tna_first_trade_notice_60019952.pdf'
        OR e.prior_trade_date >= e.suspension_effective_date
        OR e.suspension_effective_date >= e.prior_ceased_from
        OR e.prior_feature_row_date >= e.prior_ceased_from
        OR e.prior_ceased_from >= e.effective_date
        OR e.next_feature_row_date <> e.effective_date
        OR length(trim(e.reviewed_claim)) < 120
  ) THEN
    RAISE EXCEPTION 'TNA event differs from reviewed HOSE/HNX facts or the exact current gap';
  END IF;
  IF (SELECT count(*) FROM phase2_tna_source_stage WHERE source='hose') <> 1
     OR (SELECT count(*) FROM phase2_tna_source_stage WHERE source='hnx') <> 1 THEN
    RAISE EXCEPTION 'TNA requires exactly one HOSE and one HNX endpoint landing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM core.effective_trading_sessions
     WHERE is_session AND trade_date=DATE '2024-11-19'
  ) OR NOT EXISTS (
    SELECT 1 FROM core.effective_trading_sessions
     WHERE is_session AND trade_date=DATE '2024-11-29'
  ) OR (
    SELECT count(*) FROM core.effective_trading_sessions
     WHERE is_session AND trade_date>=DATE '2024-11-19' AND trade_date<DATE '2024-11-29'
  ) <> 8 THEN
    RAISE EXCEPTION 'TNA legal cessation/first-trade dates do not match the eight-session gap calendar';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM core.symbols s
    JOIN feat.features_daily prior
      ON prior.symbol_id=s.symbol_id AND prior.feature_version='phase2-v3'
     AND prior.feature_set_hash=expected_feature_hash
     AND prior.trade_date=DATE '2024-11-18'
    JOIN feat.features_daily next
      ON next.symbol_id=s.symbol_id AND next.feature_version='phase2-v3'
     AND next.feature_set_hash=expected_feature_hash
     AND next.trade_date=DATE '2024-11-29'
    WHERE s.symbol='TNA'
      AND NOT EXISTS (
        SELECT 1 FROM feat.features_daily between_rows
         WHERE between_rows.symbol_id=s.symbol_id
           AND between_rows.feature_version='phase2-v3'
           AND between_rows.feature_set_hash=expected_feature_hash
           AND between_rows.trade_date>DATE '2024-11-18'
           AND between_rows.trade_date<DATE '2024-11-29'
      )
      AND NOT EXISTS (
        SELECT 1 FROM core.bars_daily b WHERE b.symbol_id=s.symbol_id
          AND b.trade_date>DATE '2024-11-18' AND b.trade_date<DATE '2024-11-29'
      )
      AND NOT EXISTS (
        SELECT 1 FROM core.bars_daily_sources bs WHERE bs.symbol_id=s.symbol_id
          AND bs.trade_date>DATE '2024-11-18' AND bs.trade_date<DATE '2024-11-29'
      )
  ) THEN
    RAISE EXCEPTION 'TNA gap endpoints or the zero-row interval changed after evidence review';
  END IF;
END $$;

INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),d.source,d.route,d.fetched_at::timestamptz,d.symbol,
       d.metadata_json::jsonb,lower(d.payload_sha256),decode(d.body_hex,'hex')
  FROM phase2_tna_source_stage d
 WHERE NOT EXISTS (
       SELECT 1 FROM raw.landings l
        WHERE l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
          AND l.fetched_at=d.fetched_at::timestamptz
          AND lower(l.payload_sha256)=lower(d.payload_sha256)
          AND l.payload->>'source_url'=d.source_url
          AND l.payload_bytes=decode(d.body_hex,'hex')
 );

CREATE TEMP TABLE phase2_tna_landing_map ON COMMIT DROP AS
SELECT d.local_file,l.landing_id,l.fetched_at,d.symbol,d.source,
       d.document_date::date AS document_date,
       nullif(d.last_trade_date,'')::date AS last_trade_date,
       nullif(d.prior_ceased_from,'')::date AS prior_ceased_from,
       nullif(d.first_trade_date,'')::date AS first_trade_date,
       d.metadata_json::jsonb->>'article_id' AS article_id,
       d.metadata_json::jsonb->>'share_count' AS share_count
  FROM phase2_tna_source_stage d
  JOIN raw.landings l
    ON l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
   AND l.fetched_at=d.fetched_at::timestamptz
   AND lower(l.payload_sha256)=lower(d.payload_sha256)
   AND l.payload->>'source_url'=d.source_url
   AND l.payload_bytes=decode(d.body_hex,'hex');

DO $$
BEGIN
  IF (SELECT count(*) FROM phase2_tna_landing_map) <> 2
     OR (SELECT count(DISTINCT local_file) FROM phase2_tna_landing_map) <> 2 THEN
    RAISE EXCEPTION 'each TNA signed endpoint must resolve to one immutable raw landing';
  END IF;
  IF EXISTS (
    SELECT 1 FROM phase2_tna_event_stage e
    LEFT JOIN phase2_tna_landing_map source ON source.local_file=e.source_file
    LEFT JOIN phase2_tna_landing_map continuity ON continuity.local_file=e.continuity_file
    WHERE source.landing_id IS NULL OR continuity.landing_id IS NULL
       OR source.symbol <> e.symbol OR continuity.symbol <> e.symbol
       OR source.source <> 'hose' OR continuity.source <> 'hnx'
       OR source.document_date <> DATE '2024-11-12'
       OR continuity.document_date <> DATE '2024-11-22'
       OR source.last_trade_date IS DISTINCT FROM e.prior_trade_date
       OR source.prior_ceased_from IS DISTINCT FROM e.prior_ceased_from
       OR continuity.first_trade_date IS DISTINCT FROM e.effective_date
       OR source.article_id IS DISTINCT FROM e.source_article_id
       OR continuity.article_id IS DISTINCT FROM e.continuity_article_id
       OR source.share_count IS DISTINCT FROM e.share_count::text
       OR continuity.share_count IS DISTINCT FROM e.share_count::text
  ) THEN
    RAISE EXCEPTION 'TNA signed endpoints, article IDs, or share counts differ from the reviewed event';
  END IF;
END $$;

WITH event_inputs AS (
  SELECT s.symbol_id,e.symbol,e.venue,e.prior_venue,e.effective_date,e.prior_ceased_from,
         source.landing_id AS source_landing_id,
         continuity.landing_id AS continuity_landing_id,
         source.document_date,
         greatest(
           source.fetched_at,
           continuity.fetched_at,
           ((source.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'),
           ((continuity.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
         ) AS available_at,
         source_payload.payload->>'source_url' AS source_url,e.reviewed_claim,
         coalesce((
           SELECT prior.episode_id
             FROM core.security_listing_events prior
            WHERE prior.symbol_id=s.symbol_id AND prior.event_type='ADMISSION'
              AND prior.venue=e.prior_venue AND prior.effective_date<=e.prior_ceased_from
            ORDER BY prior.effective_date DESC,prior.event_id DESC LIMIT 1
         ),md5('PHASE2-E4-'||e.symbol||'-'||e.effective_date::text)::uuid) AS episode_id
    FROM phase2_tna_event_stage e
    JOIN core.symbols s ON s.symbol=e.symbol
    JOIN phase2_tna_landing_map source ON source.local_file=e.source_file
    JOIN phase2_tna_landing_map continuity ON continuity.local_file=e.continuity_file
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
SELECT count(*) AS inserted_tna_transfer_events FROM inserted;

DO $$
BEGIN
  IF (SELECT count(*)
        FROM phase2_tna_event_stage e
        JOIN core.symbols s ON s.symbol=e.symbol
        JOIN phase2_tna_landing_map source ON source.local_file=e.source_file
        JOIN phase2_tna_landing_map continuity ON continuity.local_file=e.continuity_file
        JOIN core.security_listing_events event
          ON event.symbol_id=s.symbol_id
         AND event.source_landing_id=source.landing_id
         AND event.continuity_landing_id=continuity.landing_id
         AND event.prior_venue=e.prior_venue AND event.venue=e.venue
         AND event.effective_date=e.effective_date
         AND event.prior_ceased_from=e.prior_ceased_from
        JOIN ops.phase2_verified_security_transfers verified ON verified.event_id=event.event_id
       WHERE verified.prior_ceased_from>e.prior_feature_row_date
         AND verified.effective_date=e.next_feature_row_date) <> 1 THEN
    RAISE EXCEPTION 'TNA transfer failed strict evidence or exact-gap verification';
  END IF;
END $$;

COMMIT;

\set ON_ERROR_STOP on
\pset pager off

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing GDW transfer import outside disposable report clone vnsignal_phase2_report_20261019'
  \quit 2
\endif

BEGIN;

CREATE TEMP TABLE gdw_hnx_source_stage (
  symbol text,
  source text,
  route text,
  fetched_at text,
  source_url text,
  local_file text,
  document_date text,
  last_trade_date text,
  prior_ceased_from text,
  first_trade_date text,
  payload_sha256 text,
  payload_size text,
  media_type text,
  source_attribution text,
  source_claim text,
  source_limitation text,
  capture_time_basis text,
  metadata_json text,
  body_hex text
) ON COMMIT DROP;

\copy gdw_hnx_source_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/landing_stage_gdw_20261102.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

CREATE TEMP TABLE gdw_hnx_event_stage (
  symbol text,
  prior_venue text,
  venue text,
  prior_trade_date date,
  effective_date date,
  prior_ceased_from date,
  source_notice_id text,
  continuity_notice_id text,
  source_file text,
  continuity_file text,
  reviewed_claim text
) ON COMMIT DROP;

\copy gdw_hnx_event_stage FROM 'docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/transfer_event_stage_gdw_20261102.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

DO $validate$
BEGIN
  IF (SELECT count(*) FROM gdw_hnx_source_stage) <> 2
     OR (SELECT count(DISTINCT local_file) FROM gdw_hnx_source_stage) <> 2
     OR (SELECT count(DISTINCT source_url) FROM gdw_hnx_source_stage) <> 2
     OR (SELECT count(*) FROM gdw_hnx_event_stage) <> 1 THEN
    RAISE EXCEPTION 'GDW import requires two distinct official HNX endpoint notices and one transfer event';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM gdw_hnx_source_stage d
    WHERE d.symbol <> 'GDW'
       OR d.source <> 'hnx'
       OR d.route <> 'security_lifecycle_notice'
       OR d.source_url !~ '^https://owa[.]hnx[.]vn/'
       OR d.media_type <> 'application/pdf'
       OR d.payload_sha256 !~ '^[0-9a-f]{64}$'
       OR octet_length(decode(d.body_hex,'hex')) <> d.payload_size::bigint
       OR lower(d.payload_sha256) <> encode(sha256(decode(d.body_hex,'hex')),'hex')
       OR d.capture_time_basis <> 'actual HTTP capture UTC recorded in source manifest'
       OR d.metadata_json::jsonb->>'source_url' IS DISTINCT FROM d.source_url
       OR d.metadata_json::jsonb->>'local_file' IS DISTINCT FROM d.local_file
       OR d.metadata_json::jsonb->>'capture_time_basis' IS DISTINCT FROM d.capture_time_basis
       OR (d.metadata_json::jsonb->>'captured_at_utc')::timestamptz IS DISTINCT FROM d.fetched_at::timestamptz
       OR d.metadata_json::jsonb->>'document_date' IS DISTINCT FROM d.document_date
       OR d.metadata_json::jsonb->>'last_trade_date' IS DISTINCT FROM nullif(d.last_trade_date,'')
       OR d.metadata_json::jsonb->>'prior_ceased_from' IS DISTINCT FROM nullif(d.prior_ceased_from,'')
       OR d.metadata_json::jsonb->>'first_trade_date' IS DISTINCT FROM nullif(d.first_trade_date,'')
       OR d.metadata_json::jsonb->>'notice_id' NOT IN ('1385/TB-SGDHN','1458/TB-SGDHN')
       OR length(trim(d.source_claim)) < 40
  ) THEN
    RAISE EXCEPTION 'GDW HNX source bytes, capture metadata, or notice identity are invalid';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM gdw_hnx_source_stage d
    WHERE d.local_file='hnx_gdw_deregistration_1385tb_sgdhn_2018-11-21.pdf'
      AND d.document_date='2018-11-21'
      AND d.last_trade_date='2018-12-06'
      AND d.prior_ceased_from='2018-12-07'
      AND d.first_trade_date IS NULL
      AND d.metadata_json::jsonb->>'notice_id'='1385/TB-SGDHN'
  ) OR NOT EXISTS (
    SELECT 1 FROM gdw_hnx_source_stage d
    WHERE d.local_file='hnx_gdw_first_hnx_trade_1458tb_sgdhn_2018-12-06.pdf'
      AND d.document_date='2018-12-06'
      AND d.last_trade_date IS NULL
      AND d.prior_ceased_from IS NULL
      AND d.first_trade_date='2018-12-18'
      AND d.metadata_json::jsonb->>'notice_id'='1458/TB-SGDHN'
  ) THEN
    RAISE EXCEPTION 'GDW HNX notice claims do not match the visual source review';
  END IF;

  IF EXISTS (
    SELECT 1 FROM gdw_hnx_event_stage e
    LEFT JOIN gdw_hnx_source_stage source ON source.local_file=e.source_file
    LEFT JOIN gdw_hnx_source_stage continuity ON continuity.local_file=e.continuity_file
    WHERE e.symbol<>'GDW' OR e.prior_venue<>'UPCOM' OR e.venue<>'HNX'
       OR e.prior_trade_date<>DATE '2018-12-06'
       OR e.prior_ceased_from<>DATE '2018-12-07'
       OR e.effective_date<>DATE '2018-12-18'
       OR e.source_notice_id<>'1385/TB-SGDHN'
       OR e.continuity_notice_id<>'1458/TB-SGDHN'
       OR source.local_file IS NULL OR continuity.local_file IS NULL
       OR source.metadata_json::jsonb->>'last_trade_date' IS DISTINCT FROM to_char(e.prior_trade_date,'YYYY-MM-DD')
       OR source.metadata_json::jsonb->>'prior_ceased_from' IS DISTINCT FROM to_char(e.prior_ceased_from,'YYYY-MM-DD')
       OR continuity.metadata_json::jsonb->>'first_trade_date' IS DISTINCT FROM to_char(e.effective_date,'YYYY-MM-DD')
       OR length(trim(e.reviewed_claim))<180
  ) THEN
    RAISE EXCEPTION 'GDW event dates or source pair do not match the two official HNX notices';
  END IF;

  IF EXISTS (
    SELECT 1 FROM gdw_hnx_event_stage e
    JOIN core.symbols s USING(symbol)
    WHERE e.prior_ceased_from IS DISTINCT FROM (
      SELECT min(c.trade_date) FROM core.effective_trading_sessions c
      WHERE c.is_session AND c.trade_date>e.prior_trade_date
    )
    OR (SELECT count(*) FROM core.effective_trading_sessions c
        WHERE c.is_session AND c.trade_date>e.prior_trade_date AND c.trade_date<e.effective_date)<>7
    OR NOT EXISTS (
      SELECT 1 FROM feat.features_daily f
      WHERE f.symbol_id=s.symbol_id AND f.feature_version='phase2-v3'
        AND f.feature_set_hash='28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b'
        AND f.trade_date=e.prior_trade_date
    )
    OR NOT EXISTS (
      SELECT 1 FROM feat.features_daily f
      WHERE f.symbol_id=s.symbol_id AND f.feature_version='phase2-v3'
        AND f.feature_set_hash='28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b'
        AND f.trade_date=e.effective_date
    )
    OR EXISTS (
      SELECT 1 FROM core.bars_daily b
      WHERE b.symbol_id=s.symbol_id AND b.trade_date>e.prior_trade_date AND b.trade_date<e.effective_date
    )
    OR EXISTS (
      SELECT 1 FROM core.bars_daily_sources bs
      WHERE bs.symbol_id=s.symbol_id AND bs.trade_date>e.prior_trade_date AND bs.trade_date<e.effective_date
    )
  ) THEN
    RAISE EXCEPTION 'GDW dates do not match the seven-session current-hash gap or intervening rows exist';
  END IF;

  IF EXISTS (
    SELECT 1 FROM core.security_listing_events existing
    JOIN core.symbols s USING(symbol_id)
    JOIN gdw_hnx_event_stage e USING(symbol)
    WHERE existing.event_type='TRANSFER'
      AND existing.prior_venue=e.prior_venue AND existing.venue=e.venue
      AND (existing.prior_ceased_from,existing.effective_date)
          IS DISTINCT FROM (e.prior_ceased_from,e.effective_date)
  ) THEN
    RAISE EXCEPTION 'A conflicting GDW UPCoM-to-HNX transfer exists; inspect before importing';
  END IF;
END
$validate$;

INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),d.source,d.route,d.fetched_at::timestamptz,d.symbol,
       d.metadata_json::jsonb,lower(d.payload_sha256),decode(d.body_hex,'hex')
FROM gdw_hnx_source_stage d
WHERE NOT EXISTS (
  SELECT 1 FROM raw.landings l
  WHERE l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
    AND l.fetched_at=d.fetched_at::timestamptz
    AND lower(l.payload_sha256)=lower(d.payload_sha256)
    AND l.payload->>'source_url'=d.source_url
    AND l.payload_bytes=decode(d.body_hex,'hex')
);

CREATE TEMP TABLE gdw_hnx_landing_map ON COMMIT DROP AS
SELECT d.local_file,l.landing_id,l.fetched_at,d.symbol,d.source,
       d.document_date::date AS document_date,
       nullif(d.last_trade_date,'')::date AS last_trade_date,
       nullif(d.prior_ceased_from,'')::date AS prior_ceased_from,
       nullif(d.first_trade_date,'')::date AS first_trade_date,
       d.metadata_json::jsonb->>'notice_id' AS notice_id,
       d.source_url
FROM gdw_hnx_source_stage d
JOIN raw.landings l
  ON l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
 AND l.fetched_at=d.fetched_at::timestamptz
 AND lower(l.payload_sha256)=lower(d.payload_sha256)
 AND l.payload->>'source_url'=d.source_url
 AND l.payload_bytes=decode(d.body_hex,'hex');

DO $mapcheck$
BEGIN
  IF (SELECT count(*) FROM gdw_hnx_landing_map)<>2
     OR (SELECT count(DISTINCT local_file) FROM gdw_hnx_landing_map)<>2 THEN
    RAISE EXCEPTION 'Each captured GDW HNX endpoint notice must resolve to exactly one immutable raw landing';
  END IF;
END
$mapcheck$;

DO $conflict$
BEGIN
  IF EXISTS (
    SELECT 1 FROM core.security_listing_events e
    JOIN core.symbols s USING(symbol_id)
    JOIN gdw_hnx_event_stage staged USING(symbol)
    JOIN gdw_hnx_landing_map source ON source.local_file=staged.source_file
    JOIN gdw_hnx_landing_map continuity ON continuity.local_file=staged.continuity_file
    WHERE e.event_type='TRANSFER' AND e.prior_venue=staged.prior_venue AND e.venue=staged.venue
      AND e.prior_ceased_from=staged.prior_ceased_from AND e.effective_date=staged.effective_date
      AND (e.source_landing_id,e.continuity_landing_id)
          IS DISTINCT FROM (source.landing_id,continuity.landing_id)
  ) THEN
    RAISE EXCEPTION 'The exact GDW endpoint event already exists with a different source pair';
  END IF;
END
$conflict$;

INSERT INTO core.security_listing_events (
  symbol_id,episode_id,event_type,venue,effective_date,prior_venue,prior_ceased_from,
  source_landing_id,continuity_landing_id,document_date,available_at,
  availability_basis,source_url,reviewed_claim
)
SELECT s.symbol_id,
       coalesce((SELECT prior.episode_id FROM core.security_listing_events prior
                  WHERE prior.symbol_id=s.symbol_id AND prior.event_type='ADMISSION'
                    AND prior.venue=e.prior_venue AND prior.effective_date<=e.prior_ceased_from
                  ORDER BY prior.effective_date DESC,prior.event_id DESC LIMIT 1),
                md5('PHASE2-E4-'||e.symbol||'-'||e.effective_date::text)::uuid),
       'TRANSFER',e.venue,e.effective_date,e.prior_venue,e.prior_ceased_from,
       source.landing_id,continuity.landing_id,source.document_date,
       greatest(source.fetched_at,continuity.fetched_at,
                ((source.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')),
       'ARCHIVE_FETCH',source.source_url,e.reviewed_claim
FROM gdw_hnx_event_stage e
JOIN gdw_hnx_landing_map source ON source.local_file=e.source_file
JOIN gdw_hnx_landing_map continuity ON continuity.local_file=e.continuity_file
JOIN core.symbols s ON s.symbol=e.symbol
WHERE NOT EXISTS (
  SELECT 1 FROM core.security_listing_events existing
  WHERE existing.symbol_id=s.symbol_id AND existing.event_type='TRANSFER'
    AND existing.prior_venue=e.prior_venue AND existing.venue=e.venue
    AND existing.prior_ceased_from=e.prior_ceased_from
    AND existing.effective_date=e.effective_date
    AND existing.source_landing_id=source.landing_id
    AND existing.continuity_landing_id=continuity.landing_id
);

DO $verify$
BEGIN
  IF EXISTS (
    SELECT 1 FROM gdw_hnx_event_stage e
    JOIN core.symbols s USING(symbol)
    WHERE (SELECT count(*) FROM ops.phase2_verified_security_transfers t
            WHERE t.symbol_id=s.symbol_id AND t.prior_venue=e.prior_venue AND t.venue=e.venue
              AND t.prior_ceased_from=e.prior_ceased_from AND t.effective_date=e.effective_date)<>1
  ) THEN
    RAISE EXCEPTION 'GDW event failed ops.phase2_verified_security_transfers';
  END IF;
END
$verify$;

COMMIT;

SELECT current_database() AS target_database,s.symbol,e.event_id,e.prior_venue,e.venue,
       e.prior_ceased_from,e.effective_date,verified.source_sha256,verified.continuity_sha256
FROM core.security_listing_events e
JOIN core.symbols s USING(symbol_id)
JOIN ops.phase2_verified_security_transfers verified ON verified.event_id=e.event_id
WHERE s.symbol='GDW' AND e.event_type='TRANSFER'
  AND e.prior_venue='UPCOM' AND e.venue='HNX'
  AND e.prior_ceased_from=DATE '2018-12-07' AND e.effective_date=DATE '2018-12-18';

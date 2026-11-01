\set ON_ERROR_STOP on
\pset pager off

-- Archive HTTPS-verified byte-identical copies where the original CafeF CDN
-- URL used HTTP, link the exact ticker rows in HNX's 16-security cohort, then
-- record the paired venue-transfer endpoints. This never creates bars,
-- suspension events, or trainable rows.
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
  body_hex text
) ON COMMIT DROP;
\copy hose_transfer_stage FROM 'docs/evidence/phase2/hose_transfer_sources_20261023/landing_stage.csv' WITH (FORMAT csv, HEADER true, NULL '')

CREATE TEMP TABLE hose_transfer_https (
  symbol text,
  input_https_url text,
  final_url text,
  retrieved_at_utc timestamptz,
  http_status integer,
  bytes bigint,
  sha256 text,
  matches_manifest boolean
) ON COMMIT DROP;
\copy hose_transfer_https FROM 'docs/evidence/phase2/hose_transfer_sources_20261023/https_revalidation_20261025.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE hnx_member_stage (
  symbol text,
  source_locator text,
  source_excerpt text
) ON COMMIT DROP;
\copy hnx_member_stage FROM 'docs/evidence/phase2/hose_transfer_sources_20261023/hnx_cohort_membership_stage.csv' WITH (FORMAT csv, HEADER true)

DO $$
BEGIN
  IF (SELECT count(*) FROM hose_transfer_stage)<>14
     OR (SELECT count(*) FROM hose_transfer_https)<>13
     OR (SELECT count(*) FROM hnx_member_stage)<>13 THEN
    RAISE EXCEPTION 'HNX/HOSE transfer source stages have unexpected row counts';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    WHERE d.route<>'security_lifecycle_notice'
       OR d.payload_sha256 !~ '^[0-9a-fA-F]{64}$'
       OR octet_length(decode(d.body_hex,'hex'))<>d.payload_size
       OR lower(d.payload_sha256)<>lower(encode(sha256(decode(d.body_hex,'hex')),'hex'))
  ) THEN
    RAISE EXCEPTION 'an archived transfer document does not match its recorded SHA-256';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    JOIN hose_transfer_https h ON h.symbol=d.symbol
    WHERE d.symbol IS NOT NULL
      AND (h.input_https_url IS DISTINCT FROM regexp_replace(d.source_url,'^http://','https://')
           OR h.http_status NOT BETWEEN 200 AND 299
           OR NOT h.matches_manifest
           OR h.sha256 IS DISTINCT FROM lower(d.payload_sha256)
           OR h.bytes<>d.payload_size
           OR h.final_url !~ '^https://')
  ) OR (SELECT count(DISTINCT symbol) FROM hose_transfer_https)<>13 THEN
    RAISE EXCEPTION 'HTTPS retrieval did not return the exact archived bytes for all 13 HOSE notices';
  END IF;
  IF EXISTS (
    SELECT symbol FROM hnx_member_stage GROUP BY symbol HAVING count(*)<>1
  ) OR EXISTS (
    SELECT 1 FROM hnx_member_stage m
    WHERE NOT EXISTS (SELECT 1 FROM hose_transfer_stage d WHERE d.symbol=m.symbol)
       OR m.source_locator !~ '^html[.]tr[.][1-9][0-9]*$'
       OR length(m.source_excerpt) NOT BETWEEN 16 AND 4096
  ) THEN
    RAISE EXCEPTION 'HNX cohort membership staging is incomplete or malformed';
  END IF;
  IF (SELECT min(trade_date) FROM core.effective_trading_sessions
       WHERE is_session AND trade_date>DATE '2021-08-27') IS DISTINCT FROM DATE '2021-08-30' THEN
    RAISE EXCEPTION 'the first effective no-HNX session after 2021-08-27 is not 2021-08-30';
  END IF;
  IF (SELECT count(*) FROM raw.landings
      WHERE source='hnx' AND route='security_lifecycle_notice'
        AND symbol IS NULL
        AND payload_sha256='02faa61c6bb49dfc53c69d66a1c24638f6acca89bc45d228ce881b66e39492b1')<>1 THEN
    RAISE EXCEPTION 'the official HNX cohort source must resolve to exactly one intact landing';
  END IF;
  IF EXISTS (
    SELECT s.symbol
    FROM hose_transfer_stage d
    JOIN core.symbols s ON s.symbol=d.symbol
    JOIN core.security_listing_events e ON e.symbol_id=s.symbol_id
    WHERE e.event_type='ADMISSION' AND e.venue='HNX'
      AND e.effective_date<=DATE '2021-08-27'
    GROUP BY s.symbol
    HAVING count(DISTINCT e.episode_id)>1
  ) THEN
    RAISE EXCEPTION 'a transfer ticker has conflicting pre-transfer HNX admission episodes';
  END IF;
END $$;

-- Add new append-only raw landings for the nine documents whose original
-- capture used HTTP. The HTTPS re-fetch returned the same byte count and SHA.
INSERT INTO raw.landings
  (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),d.source,d.route,h.retrieved_at_utc,d.symbol,
       jsonb_build_object(
         'document_date',d.document_date,
         'first_hose_date',d.first_hose_date,
         'evidence_claim',d.evidence_claim,
         'source_url',h.input_https_url,
         'retrieval_final_url',h.final_url,
         'source_context_url',NULLIF(d.source_context_url,''),
         'local_file',d.local_file,
         'media_type',d.media_type,
         'source_attribution',d.source_attribution,
         'retrieval_transport','HTTPS',
         'retrieval_sha256',h.sha256
       ),
       lower(d.payload_sha256),decode(d.body_hex,'hex')
FROM hose_transfer_stage d
JOIN hose_transfer_https h ON h.symbol=d.symbol
WHERE d.source_url LIKE 'http://%'
  AND NOT EXISTS (
    SELECT 1 FROM raw.landings l
    WHERE l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
      AND lower(l.payload_sha256)=lower(d.payload_sha256)
      AND l.payload->>'source_url'=h.input_https_url
  );

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM hose_transfer_stage d
    JOIN hose_transfer_https h ON h.symbol=d.symbol
    WHERE d.symbol IS NOT NULL
      AND (SELECT count(*) FROM raw.landings l
           WHERE l.source=d.source AND l.route=d.route AND l.symbol=d.symbol
             AND lower(l.payload_sha256)=lower(d.payload_sha256)
             AND l.payload->>'source_url'=h.input_https_url)<>1
  ) THEN
    RAISE EXCEPTION 'each HOSE notice must resolve to one intact HTTPS-addressed landing';
  END IF;
END $$;

INSERT INTO core.security_listing_source_membership
  (source_landing_id,symbol_id,source_locator,source_excerpt)
SELECT h.landing_id,s.symbol_id,m.source_locator,m.source_excerpt
FROM hnx_member_stage m
JOIN core.symbols s ON s.symbol=m.symbol
JOIN hose_transfer_stage d ON d.symbol IS NULL
JOIN raw.landings h ON h.source=d.source AND h.route=d.route
  AND h.symbol IS NULL AND lower(h.payload_sha256)=lower(d.payload_sha256)
  AND h.payload->>'source_url'=d.source_url
ON CONFLICT(source_landing_id,symbol_id) DO NOTHING;

DO $$
BEGIN
  IF (SELECT count(*) FROM core.security_listing_source_membership m
      JOIN raw.landings h ON h.landing_id=m.source_landing_id
      WHERE h.source='hnx' AND h.payload_sha256='02faa61c6bb49dfc53c69d66a1c24638f6acca89bc45d228ce881b66e39492b1')<>13 THEN
    RAISE EXCEPTION 'all 13 exact HNX cohort membership links were not preserved';
  END IF;
  IF EXISTS (
    SELECT 1 FROM hnx_member_stage m
    WHERE NOT EXISTS (
      SELECT 1 FROM core.security_listing_source_membership x
      JOIN raw.landings h ON h.landing_id=x.source_landing_id
      JOIN core.symbols s ON s.symbol_id=x.symbol_id
      WHERE h.payload_sha256='02faa61c6bb49dfc53c69d66a1c24638f6acca89bc45d228ce881b66e39492b1'
        AND s.symbol=m.symbol AND x.source_locator=m.source_locator
        AND x.source_excerpt=m.source_excerpt
    )
  ) THEN
    RAISE EXCEPTION 'an HNX membership link differs from the exact archived table row';
  END IF;
END $$;

WITH cohort AS (
    SELECT landing_id,payload,payload_sha256,fetched_at
    FROM raw.landings
    WHERE source='hnx' AND route='security_lifecycle_notice'
      AND symbol IS NULL
      AND payload_sha256='02faa61c6bb49dfc53c69d66a1c24638f6acca89bc45d228ce881b66e39492b1'
), events AS (
    SELECT s.symbol_id,
           coalesce((SELECT e.episode_id
                     FROM core.security_listing_events e
                     WHERE e.symbol_id=s.symbol_id AND e.event_type='ADMISSION'
                       AND e.venue='HNX' AND e.effective_date<=DATE '2021-08-27'
                     ORDER BY e.effective_date DESC,e.event_id DESC LIMIT 1),
                    md5('HNX-HOSE-2021-08-27-'||d.symbol)::uuid) AS episode_id,
           'TRANSFER'::text AS event_type,
           'HOSE'::text AS venue,
           d.first_hose_date AS effective_date,
           'HNX'::text AS prior_venue,
           DATE '2021-08-30' AS prior_ceased_from,
           source_landing.landing_id AS source_landing_id,
           cohort.landing_id AS continuity_landing_id,
           d.document_date,
           greatest(
             source_landing.fetched_at,cohort.fetched_at,
             member_link.recorded_at,
             ((d.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'),
             (((cohort.payload->>'document_date')::date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
           ) AS available_at,
           'ARCHIVE_FETCH'::text AS availability_basis,
           source_landing.payload->>'source_url' AS source_url,
           'HNX 2021-08-27 cohort row names '||d.symbol||'; paired ticker-specific HOSE notice states first trading day '||d.first_hose_date::text||'. This records legal venue context only; no bars, suspension, or label are inferred.' AS reviewed_claim
    FROM hose_transfer_stage d
    JOIN hose_transfer_https h ON h.symbol=d.symbol
    JOIN core.symbols s ON s.symbol=d.symbol
    JOIN raw.landings source_landing
      ON source_landing.source=d.source AND source_landing.route=d.route
     AND source_landing.symbol=d.symbol
     AND lower(source_landing.payload_sha256)=lower(d.payload_sha256)
     AND source_landing.payload->>'source_url'=h.input_https_url
    CROSS JOIN cohort
    JOIN core.security_listing_source_membership member_link
      ON member_link.source_landing_id=cohort.landing_id
     AND member_link.symbol_id=s.symbol_id
    WHERE d.symbol IS NOT NULL
      AND d.first_hose_date IS NOT NULL
), inserted AS (
    INSERT INTO core.security_listing_events(
      symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
      prior_ceased_from,source_landing_id,continuity_landing_id,
      document_date,available_at,availability_basis,source_url,reviewed_claim
    )
    SELECT symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
           prior_ceased_from,source_landing_id,continuity_landing_id,
           document_date,available_at,availability_basis,source_url,reviewed_claim
    FROM events
    ON CONFLICT(symbol_id,episode_id,event_type,effective_date,source_landing_id)
      DO NOTHING
    RETURNING event_id
)
SELECT count(*) AS inserted_transfer_events FROM inserted;

DO $$
BEGIN
  IF (SELECT count(*) FROM hose_transfer_stage d
      JOIN core.symbols s ON s.symbol=d.symbol
      JOIN ops.phase2_verified_security_transfers t ON t.symbol_id=s.symbol_id
      WHERE d.symbol IS NOT NULL AND t.prior_venue='HNX' AND t.venue='HOSE'
        AND t.prior_ceased_from=DATE '2021-08-30'
        AND t.effective_date=d.first_hose_date)<>13 THEN
    RAISE EXCEPTION 'the 13 source-verified transfer endpoint records are incomplete or conflicting';
  END IF;
END $$;

COMMIT;

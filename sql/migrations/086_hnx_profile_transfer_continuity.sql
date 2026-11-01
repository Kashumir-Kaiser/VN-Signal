BEGIN;

-- Identify current HNX issuer-profile landings that may be offered as a
-- continuity endpoint. A profile has no publication date; it must never be
-- treated as a dated legal notice or as the primary event source.
CREATE OR REPLACE FUNCTION core.is_hnx_profile_continuity_candidate(
    p_source text,
    p_route text,
    p_payload jsonb
)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $hnxprofilecandidate$
    SELECT coalesce(p_payload->>'source_url','') ~
               '^https://hnx[.]vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-[a-z0-9]{1,12}[.]html$'
        OR (p_source='hnx' AND p_route='security_lifecycle_notice'
            AND ((p_payload->>'first_upcom_trade_date') IS NOT NULL
                 OR p_payload->'document_date'='null'::jsonb));
$hnxprofilecandidate$;

-- The issuer code is an exact ASCII field in the preserved HTML bytes. Match
-- one unique field without decoding arbitrary raw bytes as UTF-8.
CREATE OR REPLACE FUNCTION core.hnx_profile_payload_has_exact_ticker(
    p_payload_bytes bytea,
    p_symbol text
)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $hnxprofileticker$
    WITH marker AS (
        SELECT convert_to('id="StockCode" value="'||p_symbol||'"','UTF8') AS needle_bytes
    ), first_match AS (
        SELECT needle_bytes,
               position(needle_bytes IN p_payload_bytes) AS byte_offset
        FROM marker
    )
    SELECT p_payload_bytes IS NOT NULL
       AND p_symbol ~ '^[A-Z0-9]{1,12}$'
       AND byte_offset>0
       AND position(needle_bytes IN substring(
           p_payload_bytes FROM byte_offset+octet_length(needle_bytes)
       ))=0
    FROM first_match;
$hnxprofileticker$;

-- Retain migration 085's exact cohort-member exception and add only a
-- current-profile continuity endpoint for a HOSE-to-UPCoM transfer. The
-- dated primary source still supplies the event document date. The profile
-- contributes historical first-trading metadata only from its real capture
-- time, never from a fabricated publication date.
CREATE OR REPLACE FUNCTION core.verify_listing_event_source()
RETURNS trigger LANGUAGE plpgsql AS $listingeventsource$
DECLARE
    l record;
    expected_symbol text;
    lid bigint;
    prior_event record;
    cohort_member boolean;
    cohort_recorded_at timestamptz;
    profile_candidate boolean;
    expected_profile_url text;
BEGIN
    SELECT symbol INTO STRICT expected_symbol FROM core.symbols
      WHERE symbol_id=NEW.symbol_id;
    IF NEW.supersedes_event_id IS NOT NULL THEN
        SELECT * INTO STRICT prior_event FROM core.security_listing_events
          WHERE event_id=NEW.supersedes_event_id;
        IF prior_event.symbol_id<>NEW.symbol_id
           OR prior_event.available_at>NEW.available_at THEN
            RAISE EXCEPTION 'listing correction must preserve security and cannot predate original knowledge';
        END IF;
    END IF;

    FOREACH lid IN ARRAY array_remove(
        ARRAY[NEW.source_landing_id,NEW.continuity_landing_id],NULL
    ) LOOP
        SELECT * INTO STRICT l FROM raw.landings WHERE landing_id=lid;
        cohort_member:=false;
        cohort_recorded_at:=NULL;
        IF lid=NEW.continuity_landing_id
           AND lid<>NEW.source_landing_id
           AND NEW.event_type='TRANSFER'
           AND NEW.prior_venue='HNX' AND NEW.venue='HOSE'
           AND l.source='hnx' AND l.symbol IS NULL THEN
            SELECT m.recorded_at INTO cohort_recorded_at
              FROM core.security_listing_source_membership m
             WHERE m.source_landing_id=lid AND m.symbol_id=NEW.symbol_id;
            cohort_member:=FOUND;
        END IF;

        IF (l.symbol IS DISTINCT FROM expected_symbol AND NOT cohort_member)
           OR l.route<>'security_lifecycle_notice'
           OR l.payload_bytes IS NULL OR octet_length(l.payload_bytes)<2
           OR encode(sha256(l.payload_bytes),'hex')<>lower(l.payload_sha256) THEN
            RAISE EXCEPTION 'listing event requires intact same-security source or verified HNX cohort membership';
        END IF;

        profile_candidate:=core.is_hnx_profile_continuity_candidate(
            l.source,l.route,l.payload
        );
        IF profile_candidate THEN
            IF lid<>NEW.continuity_landing_id OR lid=NEW.source_landing_id
               OR NEW.event_type<>'TRANSFER'
               OR NEW.prior_venue IS DISTINCT FROM 'HOSE'
               OR NEW.venue IS DISTINCT FROM 'UPCOM' THEN
                RAISE EXCEPTION 'HNX current profile is allowed only as a distinct HOSE-to-UPCoM transfer continuity source';
            END IF;
            expected_profile_url:='https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-'
                                  ||lower(expected_symbol)||'.html';
            IF l.source<>'hnx' OR l.symbol IS DISTINCT FROM expected_symbol
               OR l.payload->>'source_url' IS DISTINCT FROM expected_profile_url
               OR NOT (l.payload ? 'document_date')
               OR l.payload->'document_date' IS DISTINCT FROM 'null'::jsonb
               OR l.payload->>'capture_time_basis' IS DISTINCT FROM
                    'actual HTTP capture UTC recorded in source manifest'
               OR l.payload->>'first_upcom_trade_date' IS DISTINCT FROM
                    to_char(NEW.effective_date,'YYYY-MM-DD') THEN
                RAISE EXCEPTION 'HNX profile URL, ticker metadata, null publication date, capture basis, or first UPCoM date is invalid';
            END IF;
            IF NOT core.hnx_profile_payload_has_exact_ticker(
                l.payload_bytes,expected_symbol
            ) THEN
                RAISE EXCEPTION 'HNX profile bytes must contain exactly one matching StockCode field';
            END IF;
            IF NEW.availability_basis<>'ARCHIVE_FETCH' THEN
                RAISE EXCEPTION 'HNX current profile availability must use its archive capture time';
            END IF;
        ELSE
            IF coalesce(l.payload->>'source_url','') !~ '^https://[^[:space:]]+$'
               OR coalesce(l.payload->>'document_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
               OR NOT isfinite((l.payload->>'document_date')::date)
               OR NEW.available_at<(((l.payload->>'document_date')::date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
               OR (lid=NEW.source_landing_id AND (
                    l.payload->>'source_url' IS DISTINCT FROM NEW.source_url
                    OR (l.payload->>'document_date')::date<>NEW.document_date
               )) THEN
                RAISE EXCEPTION 'listing claim URL/date/availability must match archived notice metadata';
            END IF;
        END IF;

        IF NEW.availability_basis='ARCHIVE_FETCH'
           AND NEW.available_at<l.fetched_at THEN
            RAISE EXCEPTION 'archive-fetch availability precedes source capture';
        END IF;
        IF cohort_member AND NEW.available_at<cohort_recorded_at THEN
            RAISE EXCEPTION 'transfer availability predates the reviewed cohort-to-security link';
        END IF;
    END LOOP;

    IF NEW.available_at<((NEW.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh') THEN
        RAISE EXCEPTION 'listing notice availability must follow its document date';
    END IF;
    RETURN NEW;
END;
$listingeventsource$;

DROP TRIGGER IF EXISTS security_listing_event_source
    ON core.security_listing_events;
CREATE TRIGGER security_listing_event_source
BEFORE INSERT ON core.security_listing_events
FOR EACH ROW EXECUTE FUNCTION core.verify_listing_event_source();

-- Keep ordinary dated same-ticker endpoints and exact HNX cohort membership.
-- Current HNX profile endpoints are a third, tightly checked class; malformed
-- profile-like sources are not allowed to fall through as ordinary notices.
CREATE OR REPLACE VIEW ops.phase2_verified_security_transfers AS
SELECT e.event_id, e.symbol_id, e.episode_id, e.prior_venue, e.venue,
       e.prior_ceased_from, e.effective_date, e.available_at,
       e.source_landing_id, e.continuity_landing_id,
       source.payload_sha256 AS source_sha256,
       continuity.payload_sha256 AS continuity_sha256,
       membership.source_locator AS cohort_source_locator
FROM core.security_listing_events e
JOIN core.symbols s ON s.symbol_id=e.symbol_id
JOIN raw.landings source ON source.landing_id=e.source_landing_id
JOIN raw.landings continuity ON continuity.landing_id=e.continuity_landing_id
LEFT JOIN core.security_listing_source_membership membership
  ON membership.source_landing_id=e.continuity_landing_id
 AND membership.symbol_id=e.symbol_id
WHERE e.event_type='TRANSFER'
  AND source.symbol=s.symbol
  AND source.route='security_lifecycle_notice'
  AND source.payload_bytes IS NOT NULL
  AND encode(sha256(source.payload_bytes),'hex')=lower(source.payload_sha256)
  AND source.payload->>'source_url'=e.source_url
  AND source.payload->>'document_date'=to_char(e.document_date,'YYYY-MM-DD')
  AND continuity.route='security_lifecycle_notice'
  AND continuity.payload_bytes IS NOT NULL
  AND encode(sha256(continuity.payload_bytes),'hex')=lower(continuity.payload_sha256)
  AND (
      (continuity.symbol=s.symbol
       AND NOT core.is_hnx_profile_continuity_candidate(
           continuity.source,continuity.route,continuity.payload
       ))
      OR
      (e.prior_venue='HOSE' AND e.venue='UPCOM'
       AND continuity.source='hnx'
       AND continuity.symbol=s.symbol
       AND continuity.payload->>'source_url'=
           'https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-'
             ||lower(s.symbol)||'.html'
       AND continuity.payload ? 'document_date'
       AND continuity.payload->'document_date'='null'::jsonb
       AND continuity.payload->>'capture_time_basis'=
           'actual HTTP capture UTC recorded in source manifest'
       AND continuity.payload->>'first_upcom_trade_date'=
           to_char(e.effective_date,'YYYY-MM-DD')
       AND e.availability_basis='ARCHIVE_FETCH'
       AND e.available_at>=continuity.fetched_at
       AND core.hnx_profile_payload_has_exact_ticker(
           continuity.payload_bytes,s.symbol
       ))
      OR
      (membership.symbol_id=e.symbol_id
       AND e.prior_venue='HNX' AND e.venue='HOSE'
       AND continuity.source='hnx' AND continuity.symbol IS NULL)
  );

COMMENT ON VIEW ops.phase2_verified_security_transfers IS
    'Intact dated endpoints, exact HNX cohort-row endpoints, or HNX current-profile endpoints for HOSE-to-UPCoM transfers with capture-time availability. Retrospective evidence only; no bars or labels are imputed.';

COMMIT;

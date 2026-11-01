BEGIN;

-- A transfer notice can name a cohort instead of one security. Preserve the
-- exact ticker row from the immutable HNX landing as an explicit, append-only
-- source-to-security link; do not relax ticker checks for ordinary landings.
CREATE TABLE IF NOT EXISTS core.security_listing_source_membership (
    source_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    source_locator text NOT NULL CHECK (source_locator ~ '^html[.]tr[.][1-9][0-9]{0,5}$'),
    source_excerpt text NOT NULL CHECK (length(source_excerpt) BETWEEN 16 AND 4096),
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (source_landing_id, symbol_id)
);

CREATE OR REPLACE FUNCTION core.verify_listing_source_membership()
RETURNS trigger LANGUAGE plpgsql AS $listingmembership$
DECLARE
    l raw.landings%ROWTYPE;
    expected_symbol text;
    source_row_no integer;
    source_text text;
    source_row_start integer;
    preceding_row_count integer;
    row_open_count integer;
    row_close_count integer;
    ticker_cell_count integer;
BEGIN
    NEW.recorded_at:=clock_timestamp();
    SELECT upper(symbol) INTO STRICT expected_symbol
      FROM core.symbols WHERE symbol_id=NEW.symbol_id;
    SELECT * INTO STRICT l FROM raw.landings
      WHERE landing_id=NEW.source_landing_id;

    source_row_no:=substring(NEW.source_locator FROM
        '^html[.]tr[.]([1-9][0-9]{0,5})$')::integer;
    IF expected_symbol !~ '^[A-Z0-9]{1,12}$'
       OR source_row_no IS NULL
       OR l.source<>'hnx'
       OR l.route<>'security_lifecycle_notice'
       OR l.symbol IS NOT NULL
       OR l.payload_bytes IS NULL
       OR length(l.payload_bytes)<2
       OR encode(sha256(l.payload_bytes),'hex')<>lower(l.payload_sha256)
       OR coalesce(l.payload->>'source_url','') !~ '^https://www[.]hnx[.]vn/'
       OR coalesce(l.payload->>'document_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN
        RAISE EXCEPTION 'listing cohort membership must cite the exact ticker row in intact HNX source bytes';
    END IF;

    source_text:=convert_from(l.payload_bytes,'UTF8');
    source_row_start:=strpos(source_text,NEW.source_excerpt);
    IF source_row_start=0
       OR strpos(substring(source_text FROM source_row_start+1),NEW.source_excerpt)>0
       OR position(convert_to(NEW.source_excerpt,'UTF8') IN l.payload_bytes)=0
       OR left(lower(NEW.source_excerpt),3)<>'<tr'
       OR right(lower(NEW.source_excerpt),5)<>'</tr>' THEN
        RAISE EXCEPTION 'listing cohort excerpt must be one unique complete row in the intact source bytes';
    END IF;

    SELECT count(*) INTO preceding_row_count
    FROM regexp_matches(
        substring(source_text FROM 1 FOR source_row_start-1),
        '<tr([[:space:]][^>]*)?>','gi'
    );
    SELECT count(*) INTO row_open_count
    FROM regexp_matches(NEW.source_excerpt,'<tr([[:space:]][^>]*)?>','gi');
    SELECT count(*) INTO row_close_count
    FROM regexp_matches(NEW.source_excerpt,'</tr[[:space:]]*>','gi');
    SELECT count(*) INTO ticker_cell_count
    FROM regexp_matches(
        NEW.source_excerpt,
        '<td([[:space:]][^>]*)?>[[:space:]]*'||expected_symbol||'[[:space:]]*</td>',
        'gi'
    );
    IF preceding_row_count+1<>source_row_no
       OR row_open_count<>1 OR row_close_count<>1
       OR ticker_cell_count<>1 THEN
        RAISE EXCEPTION 'listing cohort locator must identify one complete source row with exactly one matching ticker cell';
    END IF;
    RETURN NEW;
END;
$listingmembership$;

DROP TRIGGER IF EXISTS security_listing_source_membership_verify
    ON core.security_listing_source_membership;
CREATE TRIGGER security_listing_source_membership_verify
BEFORE INSERT ON core.security_listing_source_membership
FOR EACH ROW EXECUTE FUNCTION core.verify_listing_source_membership();

CREATE OR REPLACE FUNCTION core.reject_listing_source_membership_mutation()
RETURNS trigger LANGUAGE plpgsql AS $listingmembershipappendonly$
BEGIN
    RAISE EXCEPTION 'listing cohort membership is append-only; add a new source observation';
END;
$listingmembershipappendonly$;

DROP TRIGGER IF EXISTS security_listing_source_membership_append_only
    ON core.security_listing_source_membership;
CREATE TRIGGER security_listing_source_membership_append_only
BEFORE UPDATE OR DELETE ON core.security_listing_source_membership
FOR EACH ROW EXECUTE FUNCTION core.reject_listing_source_membership_mutation();

DROP TRIGGER IF EXISTS security_listing_source_membership_no_truncate
    ON core.security_listing_source_membership;
CREATE TRIGGER security_listing_source_membership_no_truncate
BEFORE TRUNCATE ON core.security_listing_source_membership
FOR EACH STATEMENT EXECUTE FUNCTION core.reject_listing_source_membership_mutation();

-- Keep the original same-ticker rule for both endpoints. The only exception
-- is an explicit HNX-to-HOSE transfer whose continuity endpoint has a
-- separately verified membership row in the archived HNX cohort document.
CREATE OR REPLACE FUNCTION core.verify_listing_event_source()
RETURNS trigger LANGUAGE plpgsql AS $listingeventsource$
DECLARE
    l record;
    expected_symbol text;
    lid bigint;
    prior_event record;
    cohort_member boolean;
    cohort_recorded_at timestamptz;
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
           OR l.payload_bytes IS NULL OR length(l.payload_bytes)<2
           OR encode(sha256(l.payload_bytes),'hex')<>lower(l.payload_sha256) THEN
            RAISE EXCEPTION 'listing event requires intact same-security source or verified HNX cohort membership';
        END IF;
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

-- Source-verified transfer endpoints for the E4 retrospective integrity
-- report. This view never fills bars or changes historical model availability.
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
  AND continuity.route='security_lifecycle_notice'
  AND continuity.payload_bytes IS NOT NULL
  AND encode(sha256(continuity.payload_bytes),'hex')=lower(continuity.payload_sha256)
  AND (continuity.symbol=s.symbol OR membership.symbol_id=e.symbol_id)
  AND (continuity.symbol=s.symbol OR
       (e.prior_venue='HNX' AND e.venue='HOSE'
        AND continuity.source='hnx' AND continuity.symbol IS NULL));

COMMENT ON VIEW ops.phase2_verified_security_transfers IS
    'Intact, ticker-matched transfer endpoint sources; cohort endpoints require exact append-only ticker-row membership. Retrospective evidence only; no bars or labels are imputed.';

COMMIT;

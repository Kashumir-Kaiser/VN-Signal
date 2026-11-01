BEGIN;

-- Some HNX transfer notices state the prior venue's final trade date in a
-- group article rather than a per-security notice. Keep the landing group-level
-- and require an exact, uniquely located content block plus a ticker-specific
-- claim excerpt before linking it to a security.
ALTER TABLE core.security_listing_source_membership
    ADD COLUMN IF NOT EXISTS source_claim_excerpt text;

ALTER TABLE core.security_listing_source_membership
    DROP CONSTRAINT IF EXISTS security_listing_source_membership_source_locator_check;
ALTER TABLE core.security_listing_source_membership
    ADD CONSTRAINT security_listing_source_membership_source_locator_check
    CHECK (
        source_locator ~ '^html[.]tr[.][1-9][0-9]{0,5}$'
        OR source_locator ~ '^html[.]div[.]justify[.][1-9][0-9]{0,5}$'
    );

COMMENT ON COLUMN core.security_listing_source_membership.source_claim_excerpt IS
    'For an HNX group-article source endpoint, the exact unique HTML text excerpt that names one ticker, HOSE, and its dated final-trade claim. Table-row continuity links leave this NULL.';

CREATE OR REPLACE FUNCTION core.verify_listing_source_membership()
RETURNS trigger LANGUAGE plpgsql AS $listingmembership$
DECLARE
    l raw.landings%ROWTYPE;
    expected_symbol text;
    locator_number integer;
    source_text text;
    source_start integer;
    claim_start integer;
    preceding_count integer;
    element_open_count integer;
    element_close_count integer;
    ticker_cell_count integer;
    claim_symbol_count integer;
    claim_date_count integer;
    row_mode boolean;
    article_mode boolean;
BEGIN
    NEW.recorded_at:=clock_timestamp();
    SELECT upper(symbol) INTO STRICT expected_symbol
      FROM core.symbols WHERE symbol_id=NEW.symbol_id;
    SELECT * INTO STRICT l FROM raw.landings
      WHERE landing_id=NEW.source_landing_id;

    row_mode:=NEW.source_locator ~ '^html[.]tr[.][1-9][0-9]{0,5}$';
    article_mode:=NEW.source_locator ~ '^html[.]div[.]justify[.][1-9][0-9]{0,5}$';
    IF row_mode THEN
        locator_number:=substring(NEW.source_locator FROM
            '^html[.]tr[.]([1-9][0-9]{0,5})$')::integer;
    ELSIF article_mode THEN
        locator_number:=substring(NEW.source_locator FROM
            '^html[.]div[.]justify[.]([1-9][0-9]{0,5})$')::integer;
    END IF;

    IF expected_symbol !~ '^[A-Z0-9]{1,12}$'
       OR locator_number IS NULL
       OR l.source<>'hnx'
       OR l.route<>'security_lifecycle_notice'
       OR l.payload_bytes IS NULL
       OR length(l.payload_bytes)<2
       OR encode(sha256(l.payload_bytes),'hex')<>lower(l.payload_sha256)
       OR coalesce(l.payload->>'source_url','') !~ '^https://(www[.])?hnx[.]vn/'
       OR coalesce(l.payload->>'document_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       OR (row_mode AND (l.symbol IS NOT NULL OR NEW.source_claim_excerpt IS NOT NULL))
       OR (article_mode AND (l.symbol IS NOT NULL OR NEW.source_claim_excerpt IS NULL)) THEN
        RAISE EXCEPTION 'listing cohort membership must cite intact HNX group bytes with a valid row or article-block claim';
    END IF;

    source_text:=convert_from(l.payload_bytes,'UTF8');
    source_start:=strpos(source_text,NEW.source_excerpt);
    IF source_start=0
       OR strpos(substring(source_text FROM source_start+1),NEW.source_excerpt)>0
       OR position(convert_to(NEW.source_excerpt,'UTF8') IN l.payload_bytes)=0 THEN
        RAISE EXCEPTION 'listing cohort excerpt must be one unique exact fragment in intact source bytes';
    END IF;

    IF row_mode THEN
        IF left(lower(NEW.source_excerpt),3)<>'<tr'
           OR right(lower(NEW.source_excerpt),5)<>'</tr>' THEN
            RAISE EXCEPTION 'listing cohort row excerpt must be one complete table row';
        END IF;
        SELECT count(*) INTO preceding_count
          FROM regexp_matches(
              substring(source_text FROM 1 FOR source_start-1),
              '<tr([[:space:]][^>]*)?>','gi'
          );
        SELECT count(*) INTO element_open_count
          FROM regexp_matches(NEW.source_excerpt,'<tr([[:space:]][^>]*)?>','gi');
        SELECT count(*) INTO element_close_count
          FROM regexp_matches(NEW.source_excerpt,'</tr[[:space:]]*>','gi');
        SELECT count(*) INTO ticker_cell_count
          FROM regexp_matches(
              NEW.source_excerpt,
              '<td([[:space:]][^>]*)?>[[:space:]]*'||expected_symbol||'[[:space:]]*</td>',
              'gi'
          );
        IF preceding_count+1<>locator_number
           OR element_open_count<>1 OR element_close_count<>1
           OR ticker_cell_count<>1 THEN
            RAISE EXCEPTION 'listing cohort locator must identify one complete source row with exactly one matching ticker cell';
        END IF;
    ELSE
        IF NEW.source_excerpt !~* '^<div[[:space:]][^>]*text-align[[:space:]]*:[[:space:]]*justify[^>]*>'
           OR right(lower(NEW.source_excerpt),6)<>'</div>'
           OR NEW.source_claim_excerpt IS NULL
           OR length(NEW.source_claim_excerpt) NOT BETWEEN 16 AND 2048
           OR position(NEW.source_claim_excerpt IN NEW.source_excerpt)=0
           OR position(
                NEW.source_claim_excerpt IN substring(
                    NEW.source_excerpt FROM position(NEW.source_claim_excerpt IN NEW.source_excerpt)
                    + length(NEW.source_claim_excerpt)
                )
              )>0
           OR position(convert_to(NEW.source_claim_excerpt,'UTF8') IN l.payload_bytes)=0
           OR NEW.source_claim_excerpt !~* '(^|[^A-Z0-9])HOSE([^A-Z0-9]|$)' THEN
            RAISE EXCEPTION 'listing article membership requires an exact unique ticker-specific HOSE claim inside one intact article block';
        END IF;
        SELECT count(*) INTO preceding_count
          FROM regexp_matches(
              substring(source_text FROM 1 FOR source_start-1),
              '<div[[:space:]][^>]*text-align[[:space:]]*:[[:space:]]*justify[^>]*>',
              'gi'
          );
        SELECT count(*) INTO element_open_count
          FROM regexp_matches(
              NEW.source_excerpt,
              '<div[[:space:]][^>]*text-align[[:space:]]*:[[:space:]]*justify[^>]*>',
              'gi'
          );
        SELECT count(*) INTO element_close_count
          FROM regexp_matches(NEW.source_excerpt,'</div[[:space:]]*>','gi');
        SELECT count(*) INTO claim_symbol_count
          FROM regexp_matches(
              NEW.source_claim_excerpt,
              '(^|[^A-Z0-9])'||expected_symbol||'([^A-Z0-9]|$)',
              'gi'
          );
        SELECT count(*) INTO claim_date_count
          FROM regexp_matches(
              NEW.source_claim_excerpt,
              '(^|[^0-9])([0-3]?[0-9]/[01]?[0-9]/20[0-9]{2})([^0-9]|$)',
              'g'
          );
        IF preceding_count+1<>locator_number
           OR element_open_count<>1 OR element_close_count<>1
           OR claim_symbol_count<>1 OR claim_date_count<>1 THEN
            RAISE EXCEPTION 'listing article locator must identify one exact block with one ticker-specific dated claim';
        END IF;
    END IF;
    RETURN NEW;
END;
$listingmembership$;

CREATE OR REPLACE FUNCTION core.verify_listing_event_source()
RETURNS trigger LANGUAGE plpgsql AS $listingeventsource$
DECLARE
    l record;
    expected_symbol text;
    lid bigint;
    prior_event record;
    cohort_member boolean;
    cohort_recorded_at timestamptz;
    cohort_locator text;
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
        cohort_locator:=NULL;
        IF lid=NEW.continuity_landing_id
           AND lid<>NEW.source_landing_id
           AND NEW.event_type='TRANSFER'
           AND NEW.prior_venue='HNX' AND NEW.venue='HOSE'
           AND l.source='hnx' AND l.symbol IS NULL THEN
            SELECT m.recorded_at,m.source_locator
              INTO cohort_recorded_at,cohort_locator
              FROM core.security_listing_source_membership m
             WHERE m.source_landing_id=lid AND m.symbol_id=NEW.symbol_id
               AND m.source_locator ~ '^html[.]tr[.]';
            cohort_member:=FOUND;
        ELSIF lid=NEW.source_landing_id
           AND NEW.event_type='TRANSFER'
           AND NEW.prior_venue='HOSE' AND NEW.venue='HNX'
           AND l.source='hnx' AND l.symbol IS NULL THEN
            SELECT m.recorded_at,m.source_locator
              INTO cohort_recorded_at,cohort_locator
              FROM core.security_listing_source_membership m
             WHERE m.source_landing_id=lid AND m.symbol_id=NEW.symbol_id
               AND m.source_locator ~ '^html[.]div[.]justify[.]'
               AND m.source_claim_excerpt IS NOT NULL;
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
               OR (NEW.prior_venue IS DISTINCT FROM 'HOSE'
                   AND NEW.prior_venue IS DISTINCT FROM 'HNX')
               OR NEW.venue IS DISTINCT FROM 'UPCOM' THEN
                RAISE EXCEPTION 'HNX current profile is allowed only as a distinct HNX/HOSE-to-UPCoM transfer continuity source';
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
                RAISE EXCEPTION 'HNX profile URL, ticker metadata, capture basis, or first UPCoM date is invalid';
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

CREATE OR REPLACE VIEW ops.phase2_verified_security_transfers AS
SELECT e.event_id, e.symbol_id, e.episode_id, e.prior_venue, e.venue,
       e.prior_ceased_from, e.effective_date, e.available_at,
       e.source_landing_id, e.continuity_landing_id,
       source.payload_sha256 AS source_sha256,
       continuity.payload_sha256 AS continuity_sha256,
       coalesce(source_membership.source_locator,
                continuity_membership.source_locator) AS cohort_source_locator
FROM core.security_listing_events e
JOIN core.symbols s ON s.symbol_id=e.symbol_id
JOIN raw.landings source ON source.landing_id=e.source_landing_id
JOIN raw.landings continuity ON continuity.landing_id=e.continuity_landing_id
LEFT JOIN core.security_listing_source_membership source_membership
  ON source_membership.source_landing_id=e.source_landing_id
 AND source_membership.symbol_id=e.symbol_id
LEFT JOIN core.security_listing_source_membership continuity_membership
  ON continuity_membership.source_landing_id=e.continuity_landing_id
 AND continuity_membership.symbol_id=e.symbol_id
WHERE e.event_type='TRANSFER'
  AND (
      source.symbol=s.symbol
      OR (source_membership.symbol_id=e.symbol_id
          AND source.source='hnx' AND source.symbol IS NULL
          AND source_membership.source_locator ~ '^html[.]div[.]justify[.]'
          AND source_membership.source_claim_excerpt IS NOT NULL
          AND e.prior_venue='HOSE' AND e.venue='HNX')
  )
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
      (e.prior_venue IN ('HOSE','HNX') AND e.venue='UPCOM'
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
      (continuity_membership.symbol_id=e.symbol_id
       AND continuity_membership.source_locator ~ '^html[.]tr[.]'
       AND e.prior_venue='HNX' AND e.venue='HOSE'
       AND continuity.source='hnx' AND continuity.symbol IS NULL)
  );

COMMENT ON VIEW ops.phase2_verified_security_transfers IS
    'Intact ticker-matched endpoints, exact HNX cohort-row continuity, exact HNX article-block source claims, or HNX current-profile UPCoM endpoints. Retrospective evidence only; no bars or labels are imputed.';

COMMIT;

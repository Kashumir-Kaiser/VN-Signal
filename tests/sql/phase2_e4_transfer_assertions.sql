\set ON_ERROR_STOP on
-- Synthetic-only proof that a cohort notice requires an exact append-only
-- ticker-row link before it can support a transfer event. No real event is
-- classified and the complete fixture rolls back.
BEGIN;
DO $$
DECLARE
    sid bigint;
    other_sid bigint;
    cohort_landing bigint;
    ticker_landing bigint;
    other_ticker_landing bigint;
    wrong_route_landing bigint;
    wrong_hash_landing bigint;
    duplicate_ticker_landing bigint;
    old_cohort_landing bigint;
    old_ticker_landing bigint;
    old_sid bigint;
    cohort_body text := '<table><tr><td>1</td><td>Example Corp</td><td>P2E4M</td></tr><tr><td>2</td><td>Other Corp</td><td>P2E4N</td></tr></table>';
    cohort_excerpt text := '<tr><td>1</td><td>Example Corp</td><td>P2E4M</td></tr>';
    duplicate_ticker_body text := '<table><tr><td>1</td><td>Example Corp</td><td>P2E4M</td><td>P2E4M</td></tr></table>';
    duplicate_ticker_excerpt text := '<tr><td>1</td><td>Example Corp</td><td>P2E4M</td><td>P2E4M</td></tr>';
    source_url text := 'https://example.invalid/p2e4m-first-hose-day';
    source_body text := '<html>P2E4M first HOSE trading day</html>';
    payload jsonb;
    now_at timestamptz := '2097-01-03 09:00:00+07';
    membership_recorded_at timestamptz;
    old_membership_recorded_at timestamptz;
    rejected boolean;
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4M','HNX',now_at,now_at) RETURNING symbol_id INTO sid;
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4N','HNX',now_at,now_at) RETURNING symbol_id INTO other_sid;

    payload:=jsonb_build_object(
        'source_url','https://www.hnx.vn/fixture/cohort',
        'document_date','2097-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4m-cohort')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-02 09:00:00+07',NULL,payload,
        encode(sha256(convert_to(cohort_body,'UTF8')),'hex'),
        convert_to(cohort_body,'UTF8')
    ) RETURNING landing_id INTO cohort_landing;

    payload:=jsonb_build_object('source_url',source_url,'document_date','2097-01-01');
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4m-hose')::uuid,'hose','security_lifecycle_notice',
        '2097-01-02 09:00:00+07','P2E4M',payload,
        encode(sha256(convert_to(source_body,'UTF8')),'hex'),
        convert_to(source_body,'UTF8')
    ) RETURNING landing_id INTO ticker_landing;

    INSERT INTO core.security_listing_source_membership(
        source_landing_id,symbol_id,source_locator,source_excerpt,recorded_at
    ) VALUES(cohort_landing,sid,'html.tr.1',cohort_excerpt,'1900-01-01 00:00:00+00')
    RETURNING recorded_at INTO membership_recorded_at;
    IF membership_recorded_at<'2020-01-01 00:00:00+00' THEN
        RAISE EXCEPTION 'cohort membership recording time was backdated';
    END IF;

    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt
        ) VALUES(cohort_landing,sid,'html.tr.2',cohort_excerpt);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'listing cohort locator must identify%' THEN
            rejected:=true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'wrong cohort row locator was accepted'; END IF;

    payload:=jsonb_build_object(
        'source_url','https://www.hnx.vn/fixture/cohort',
        'document_date','2097-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4m-duplicate-ticker')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-02 09:00:00+07',NULL,payload,
        encode(sha256(convert_to(duplicate_ticker_body,'UTF8')),'hex'),
        convert_to(duplicate_ticker_body,'UTF8')
    ) RETURNING landing_id INTO duplicate_ticker_landing;
    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt
        ) VALUES(duplicate_ticker_landing,sid,'html.tr.1',duplicate_ticker_excerpt);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'listing cohort locator must identify%' THEN
            rejected:=true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'ambiguous duplicate-ticker row was accepted'; END IF;

    INSERT INTO core.security_listing_events(
        symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
        prior_ceased_from,source_landing_id,continuity_landing_id,
        document_date,available_at,availability_basis,source_url,reviewed_claim
    ) VALUES(
        sid,'12345678-1234-5678-1234-567812345678','TRANSFER','HOSE',
        DATE '2097-01-03','HNX',DATE '2097-01-02',ticker_landing,
        cohort_landing,DATE '2097-01-01',now_at,'ARCHIVE_FETCH',source_url,
        'Synthetic test: exact HNX cohort ticker row plus ticker-specific first-HOSE notice.'
    );

    IF (SELECT count(*) FROM ops.phase2_verified_security_transfers
         WHERE symbol_id=sid AND source_landing_id=ticker_landing
           AND continuity_landing_id=cohort_landing)<>1 THEN
        RAISE EXCEPTION 'verified HNX cohort transfer is absent from the audit view';
    END IF;

    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt
        ) VALUES(cohort_landing,other_sid,'html.tr.1',cohort_excerpt);
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'wrong-ticker cohort membership was accepted'; END IF;

    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4m-wrong-route')::uuid,'hnx','equity_ohlcv',
        '2097-01-02 09:00:00+07',NULL,
        jsonb_build_object('source_url','https://www.hnx.vn/fixture/cohort','document_date','2097-01-01'),
        encode(sha256(convert_to(cohort_body,'UTF8')),'hex'),convert_to(cohort_body,'UTF8')
    ) RETURNING landing_id INTO wrong_route_landing;
    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt
        ) VALUES(wrong_route_landing,sid,'html.tr.1',cohort_excerpt);
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'wrong-route cohort source was accepted'; END IF;

    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4m-wrong-hash')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-02 09:00:00+07',NULL,
        jsonb_build_object('source_url','https://www.hnx.vn/fixture/cohort','document_date','2097-01-01'),
        repeat('0',64),convert_to(cohort_body,'UTF8')
    ) RETURNING landing_id INTO wrong_hash_landing;
    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt
        ) VALUES(wrong_hash_landing,sid,'html.tr.1',cohort_excerpt);
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'bad cohort source hash was accepted'; END IF;

    payload:=jsonb_build_object(
        'source_url','https://example.invalid/p2e4n-first-hose-day',
        'document_date','2097-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4n-hose')::uuid,'hose','security_lifecycle_notice',
        '2097-01-02 09:00:00+07','P2E4N',payload,
        encode(sha256(convert_to('<html>P2E4N first HOSE trading day</html>','UTF8')),'hex'),
        convert_to('<html>P2E4N first HOSE trading day</html>','UTF8')
    ) RETURNING landing_id INTO other_ticker_landing;

    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_events(
            symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
            prior_ceased_from,source_landing_id,continuity_landing_id,
            document_date,available_at,availability_basis,source_url,reviewed_claim
        ) VALUES(
            other_sid,'22345678-1234-5678-1234-567812345678','TRANSFER','HOSE',
            DATE '2097-01-03','HNX',DATE '2097-01-02',other_ticker_landing,
            cohort_landing,DATE '2097-01-01',now_at,'ARCHIVE_FETCH',
            'https://example.invalid/p2e4n-first-hose-day',
            'Synthetic negative: cohort source does not list this ticker.'
        );
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'unlinked cohort transfer event was accepted'; END IF;

    -- The source and document dates alone cannot backdate knowledge of a
    -- cohort membership link. This event is available one second too early.
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4O','HNX','2000-01-01 00:00:00+00','2000-01-01 00:00:00+00')
    RETURNING symbol_id INTO old_sid;
    payload:=jsonb_build_object(
        'source_url','https://www.hnx.vn/fixture/old-cohort',
        'document_date','2000-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4o-cohort')::uuid,'hnx','security_lifecycle_notice',
        '2000-01-02 09:00:00+00',NULL,payload,
        encode(sha256(convert_to('<table><tr><td>P2E4O</td></tr></table>','UTF8')),'hex'),
        convert_to('<table><tr><td>P2E4O</td></tr></table>','UTF8')
    ) RETURNING landing_id INTO old_cohort_landing;
    INSERT INTO core.security_listing_source_membership(
        source_landing_id,symbol_id,source_locator,source_excerpt
    ) VALUES(old_cohort_landing,old_sid,'html.tr.1','<tr><td>P2E4O</td></tr>')
    RETURNING recorded_at INTO old_membership_recorded_at;
    payload:=jsonb_build_object(
        'source_url','https://example.invalid/p2e4o-first-hose-day',
        'document_date','2000-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4o-hose')::uuid,'hose','security_lifecycle_notice',
        '2000-01-02 09:00:00+00','P2E4O',payload,
        encode(sha256(convert_to('<html>P2E4O first HOSE day</html>','UTF8')),'hex'),
        convert_to('<html>P2E4O first HOSE day</html>','UTF8')
    ) RETURNING landing_id INTO old_ticker_landing;
    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_events(
            symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
            prior_ceased_from,source_landing_id,continuity_landing_id,
            document_date,available_at,availability_basis,source_url,reviewed_claim
        ) VALUES(
            old_sid,'32345678-1234-5678-1234-567812345678','TRANSFER','HOSE',
            DATE '2000-01-03','HNX',DATE '2000-01-02',old_ticker_landing,
            old_cohort_landing,DATE '2000-01-01',old_membership_recorded_at-interval '1 second',
            'ARCHIVE_FETCH','https://example.invalid/p2e4o-first-hose-day',
            'Synthetic negative: transfer cannot predate recorded cohort membership.'
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'transfer availability predates the reviewed cohort-to-security link%' THEN
            rejected:=true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'cohort transfer knowledge was backdated'; END IF;

    rejected:=false;
    BEGIN
        UPDATE core.security_listing_source_membership
           SET source_locator='html.tr.2'
         WHERE source_landing_id=cohort_landing AND symbol_id=sid;
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'cohort membership update was accepted'; END IF;

    rejected:=false;
    BEGIN
        DELETE FROM core.security_listing_source_membership
         WHERE source_landing_id=cohort_landing AND symbol_id=sid;
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'cohort membership delete was accepted'; END IF;

    rejected:=false;
    BEGIN
        TRUNCATE core.security_listing_source_membership;
    EXCEPTION WHEN raise_exception THEN rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'cohort membership truncate was accepted'; END IF;
END;
$$;

-- Current HNX issuer profiles are undated observations. They may support only
-- a HOSE-to-UPCoM transfer continuity endpoint, with knowledge beginning at
-- the actual profile capture time. All fixtures below roll back.
CREATE TEMP TABLE phase2_e4_profile_fixture_scope(marker integer) ON COMMIT DROP;

CREATE FUNCTION pg_temp.assert_hnx_profile_case_rejected(
    p_case text,
    p_symbol_id bigint,
    p_primary_landing_id bigint,
    p_overrides jsonb
)
RETURNS void LANGUAGE plpgsql AS $expectprofile$
DECLARE
    expected_symbol text;
    profile_source text := coalesce(p_overrides->>'source','hnx');
    profile_route text := coalesce(p_overrides->>'route','security_lifecycle_notice');
    profile_symbol text;
    profile_url text;
    profile_body text := coalesce(p_overrides->>'body',
        '<html><input id="StockCode" value="P2E4P"/></html>');
    profile_payload jsonb;
    profile_bytes bytea;
    profile_sha text;
    profile_id bigint;
    event_source_id bigint;
    event_continuity_id bigint;
    event_type text := coalesce(p_overrides->>'event_type','TRANSFER');
    prior_venue text := coalesce(p_overrides->>'prior_venue','HOSE');
    venue text := coalesce(p_overrides->>'venue','UPCOM');
    basis text := coalesce(p_overrides->>'availability_basis','ARCHIVE_FETCH');
    available_at timestamptz := coalesce(
        (p_overrides->>'available_at')::timestamptz,
        '2097-01-03 09:00:00+07'::timestamptz
    );
    profile_fetched_at timestamptz := coalesce(
        (p_overrides->>'fetched_at')::timestamptz,
        '2097-01-03 08:59:00+07'::timestamptz
    );
    profile_primary boolean := coalesce((p_overrides->>'profile_primary')::boolean,false);
    same_endpoints boolean := coalesce((p_overrides->>'same_endpoints')::boolean,false);
    rejected boolean := false;
BEGIN
    SELECT symbol INTO STRICT expected_symbol FROM core.symbols
     WHERE symbol_id=p_symbol_id;
    profile_symbol:=CASE WHEN p_overrides ? 'symbol'
                         THEN p_overrides->>'symbol' ELSE expected_symbol END;
    profile_url:=coalesce(p_overrides->>'source_url',
        'https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-'
         ||lower(expected_symbol)||'.html');
    profile_payload:=jsonb_build_object(
        'source_url',profile_url,
        'capture_time_basis','actual HTTP capture UTC recorded in source manifest',
        'document_date',NULL,
        'first_upcom_trade_date','2097-01-03'
    );
    IF p_overrides ? 'capture_time_basis' THEN
        profile_payload:=profile_payload||jsonb_build_object(
            'capture_time_basis',p_overrides->'capture_time_basis'
        );
    END IF;
    IF coalesce((p_overrides->>'remove_capture_time_basis')::boolean,false) THEN
        profile_payload:=profile_payload-'capture_time_basis';
    END IF;
    IF p_overrides ? 'document_date' THEN
        profile_payload:=profile_payload||jsonb_build_object(
            'document_date',p_overrides->'document_date'
        );
    END IF;
    IF coalesce((p_overrides->>'remove_document_date')::boolean,false) THEN
        profile_payload:=profile_payload-'document_date';
    END IF;
    IF p_overrides ? 'first_upcom_trade_date' THEN
        profile_payload:=profile_payload||jsonb_build_object(
            'first_upcom_trade_date',p_overrides->'first_upcom_trade_date'
        );
    END IF;
    IF coalesce((p_overrides->>'remove_source_url')::boolean,false) THEN
        profile_payload:=profile_payload-'source_url';
    END IF;

    profile_bytes:=convert_to(profile_body,'UTF8');
    profile_sha:=CASE WHEN coalesce((p_overrides->>'bad_hash')::boolean,false)
                      THEN repeat('f',64)
                      ELSE encode(sha256(profile_bytes),'hex') END;
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('phase2-e4-profile-'||p_case)::uuid,profile_source,profile_route,
        profile_fetched_at,profile_symbol,profile_payload,profile_sha,profile_bytes
    ) RETURNING landing_id INTO profile_id;

    IF profile_primary THEN
        event_source_id:=profile_id;
        event_continuity_id:=CASE WHEN same_endpoints THEN profile_id
                                  ELSE p_primary_landing_id END;
    ELSE
        event_source_id:=p_primary_landing_id;
        event_continuity_id:=profile_id;
    END IF;
    IF event_type<>'TRANSFER' THEN
        event_continuity_id:=NULL;
    END IF;

    BEGIN
        INSERT INTO core.security_listing_events(
            symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
            prior_ceased_from,source_landing_id,continuity_landing_id,
            document_date,available_at,availability_basis,source_url,reviewed_claim
        ) VALUES(
            p_symbol_id,md5('phase2-e4-profile-event-'||p_case)::uuid,
            event_type,venue,DATE '2097-01-03',
            CASE WHEN event_type='TRANSFER' THEN prior_venue END,
            CASE WHEN event_type='TRANSFER' THEN DATE '2097-01-02' END,
            event_source_id,event_continuity_id,DATE '2097-01-01',available_at,basis,
            CASE WHEN profile_primary THEN profile_url
                 ELSE 'https://example.invalid/p2e4p-hose-decision' END,
            'Synthetic negative case for strict HNX current-profile continuity validation.'
        );
    EXCEPTION WHEN raise_exception THEN
        rejected:=true;
    END;
    IF NOT rejected THEN
        RAISE EXCEPTION 'invalid HNX profile case was accepted: %',p_case;
    END IF;
END;
$expectprofile$;

DO $hnxprofilepositive$
DECLARE
    sid bigint;
    hose_landing bigint;
    profile_landing bigint;
    undated_hose_landing bigint;
    mismatched_hose_landing bigint;
    source_url text:='https://example.invalid/p2e4p-hose-decision';
    profile_url text:='https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-p2e4p.html';
    profile_body text:='<html><input id="StockCode" value="P2E4P"/></html>';
    payload jsonb;
    rejected boolean:=false;
    event_available timestamptz:='2097-01-03 09:00:00+07';
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4P','UPCOM',event_available,event_available)
    RETURNING symbol_id INTO sid;

    payload:=jsonb_build_object('source_url',source_url,'document_date','2097-01-01');
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('phase2-e4-p2e4p-hose')::uuid,'hose','security_lifecycle_notice',
        '2097-01-02 09:00:00+07','P2E4P',payload,
        encode(sha256(convert_to('<html>P2E4P signed HOSE decision</html>','UTF8')),'hex'),
        convert_to('<html>P2E4P signed HOSE decision</html>','UTF8')
    ) RETURNING landing_id INTO hose_landing;

    payload:=jsonb_build_object(
        'source_url',profile_url,
        'capture_time_basis','actual HTTP capture UTC recorded in source manifest',
        'document_date',NULL,
        'first_upcom_trade_date','2097-01-03'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('phase2-e4-p2e4p-hnx-profile')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-03 08:59:00+07','P2E4P',payload,
        encode(sha256(convert_to(profile_body,'UTF8')),'hex'),
        convert_to(profile_body,'UTF8')
    ) RETURNING landing_id INTO profile_landing;

    INSERT INTO core.security_listing_events(
        symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
        prior_ceased_from,source_landing_id,continuity_landing_id,
        document_date,available_at,availability_basis,source_url,reviewed_claim
    ) VALUES(
        sid,'42345678-1234-5678-1234-567812345678','TRANSFER','UPCOM',
        DATE '2097-01-03','HOSE',DATE '2097-01-02',hose_landing,
        profile_landing,DATE '2097-01-01',event_available,'ARCHIVE_FETCH',source_url,
        'Synthetic positive: dated HOSE decision and captured HNX profile establish transfer continuity.'
    );
    IF (SELECT count(*) FROM ops.phase2_verified_security_transfers
         WHERE symbol_id=sid AND source_landing_id=hose_landing
           AND continuity_landing_id=profile_landing)<>1 THEN
        RAISE EXCEPTION 'valid HNX profile-backed HOSE-to-UPCoM transfer is absent from the audit view';
    END IF;

    -- The undated profile is not accepted as the primary notice, including
    -- when the same landing is supplied for both endpoints.
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'profile-as-primary',sid,hose_landing,'{"profile_primary":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'profile-as-both-endpoints',sid,hose_landing,
        '{"profile_primary":true,"same_endpoints":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'profile-on-admission',sid,hose_landing,
        '{"profile_primary":true,"event_type":"ADMISSION"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-venue-direction',sid,hose_landing,
        '{"prior_venue":"UPCOM","venue":"HOSE"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-profile-source',sid,hose_landing,'{"source":"cafef"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-profile-route',sid,hose_landing,'{"route":"equity_ohlcv"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-profile-symbol',sid,hose_landing,'{"symbol":"P2E4Q"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-profile-symbol',sid,hose_landing,'{"symbol":null}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-profile-url',sid,hose_landing,
        '{"source_url":"https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-p2e4q.html"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-profile-url',sid,hose_landing,'{"remove_source_url":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-capture-marker',sid,hose_landing,
        '{"remove_capture_time_basis":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-capture-marker',sid,hose_landing,
        '{"capture_time_basis":"estimated publication time"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-first-upcom-date',sid,hose_landing,
        '{"first_upcom_trade_date":null}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'invalid-first-upcom-date',sid,hose_landing,
        '{"first_upcom_trade_date":"2097-02-30"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'mismatched-first-upcom-date',sid,hose_landing,
        '{"first_upcom_trade_date":"2097-01-04"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-json-document-date-null',sid,hose_landing,
        '{"remove_document_date":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'non-null-profile-document-date',sid,hose_landing,
        '{"document_date":"2097-01-01"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'malformed-profile-document-date',sid,hose_landing,
        '{"document_date":"not-a-date"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'wrong-stockcode-bytes',sid,hose_landing,
        '{"body":"<html><input id=\"StockCode\" value=\"P2E4Q\"/></html>"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'missing-stockcode-bytes',sid,hose_landing,
        '{"body":"<html><input id=\"OtherCode\" value=\"P2E4P\"/></html>"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'duplicate-stockcode-bytes',sid,hose_landing,
        '{"body":"<input id=\"StockCode\" value=\"P2E4P\"><input id=\"StockCode\" value=\"P2E4P\">"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'altered-profile-hash',sid,hose_landing,'{"bad_hash":true}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'archive-availability-before-profile-capture',sid,hose_landing,
        '{"fetched_at":"2097-01-03 09:00:01+07","available_at":"2097-01-03 09:00:00+07"}'::jsonb
    );
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'publication-availability-basis',sid,hose_landing,
        '{"availability_basis":"VERIFIED_PUBLICATION"}'::jsonb
    );

    -- A valid current profile does not make an undated or URL-mismatched HOSE
    -- primary source acceptable. The dated primary notice remains mandatory.
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('phase2-e4-p2e4p-undated-hose')::uuid,'hose','security_lifecycle_notice',
        '2097-01-02 09:00:00+07','P2E4P',
        jsonb_build_object('source_url',source_url,'document_date',NULL),
        encode(sha256(convert_to('<html>P2E4P undated HOSE source</html>','UTF8')),'hex'),
        convert_to('<html>P2E4P undated HOSE source</html>','UTF8')
    ) RETURNING landing_id INTO undated_hose_landing;
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'undated-hose-primary',sid,undated_hose_landing,'{}'::jsonb
    );

    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('phase2-e4-p2e4p-mismatched-hose')::uuid,'hose','security_lifecycle_notice',
        '2097-01-02 09:00:00+07','P2E4P',
        jsonb_build_object('source_url','https://example.invalid/wrong-hose-document','document_date','2097-01-01'),
        encode(sha256(convert_to('<html>P2E4P mismatched HOSE URL</html>','UTF8')),'hex'),
        convert_to('<html>P2E4P mismatched HOSE URL</html>','UTF8')
    ) RETURNING landing_id INTO mismatched_hose_landing;
    PERFORM pg_temp.assert_hnx_profile_case_rejected(
        'mismatched-hose-primary-url',sid,mismatched_hose_landing,'{}'::jsonb
    );

    -- raw.landings already enforces the minimum preserved-byte length. Keep
    -- this edge explicit so an empty bytea cannot become a profile source.
    BEGIN
        INSERT INTO raw.landings(
            ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
        ) VALUES(
            md5('phase2-e4-p2e4p-empty-profile')::uuid,'hnx','security_lifecycle_notice',
            '2097-01-03 08:59:00+07','P2E4P',
            jsonb_build_object('source_url',profile_url,'document_date',NULL),
            repeat('0',64),decode('','hex')
        );
    EXCEPTION WHEN check_violation THEN
        rejected:=true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'empty HNX profile bytes were accepted by raw landing storage'; END IF;
END;
$hnxprofilepositive$;

-- A grouped HNX source article can support a HOSE-to-HNX event only through
-- one exact article block and a ticker-specific dated claim excerpt.
DO $hnx_group_source$
DECLARE
    sid bigint;
    other_sid bigint;
    source_id bigint;
    continuity_id bigint;
    inserted_event_id bigint;
    membership_at timestamptz;
    article_url text:='https://hnx.vn/fixture/p2e4source-cohort';
    article_body text:='<html><div style="text-align: justify;">P2E4SRC last traded on HOSE on 02/01/2097.</div></html>';
    claim_excerpt text:='P2E4SRC last traded on HOSE on 02/01/2097';
    source_payload jsonb;
    continuity_payload jsonb;
    rejected boolean;
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4SRC','HNX','2097-01-01+07','2097-01-05+07')
    RETURNING symbol_id INTO sid;
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2E4SRC2','HNX','2097-01-01+07','2097-01-05+07')
    RETURNING symbol_id INTO other_sid;

    source_payload:=jsonb_build_object(
        'source_url',article_url,'document_date','2097-01-01'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4source-article')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-02 09:00:00+07',NULL,source_payload,
        encode(sha256(convert_to(article_body,'UTF8')),'hex'),
        convert_to(article_body,'UTF8')
    ) RETURNING landing_id INTO source_id;

    INSERT INTO core.security_listing_source_membership(
        source_landing_id,symbol_id,source_locator,source_excerpt,source_claim_excerpt
    ) VALUES(
        source_id,sid,'html.div.justify.1',
        '<div style="text-align: justify;">P2E4SRC last traded on HOSE on 02/01/2097.</div>',
        claim_excerpt
    ) RETURNING recorded_at INTO membership_at;

    rejected:=false;
    BEGIN
        INSERT INTO core.security_listing_source_membership(
            source_landing_id,symbol_id,source_locator,source_excerpt,source_claim_excerpt
        ) VALUES(
            source_id,other_sid,'html.div.justify.1',
            '<div style="text-align: justify;">P2E4SRC last traded on HOSE on 02/01/2097.</div>',
            claim_excerpt
        );
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'listing article locator must identify%' THEN
            rejected:=true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'article claim for another ticker was accepted'; END IF;

    continuity_payload:=jsonb_build_object(
        'source_url','https://www.hnx.vn/fixture/p2e4src-first-hnx-day',
        'document_date','2097-01-02',
        'source_claim','Synthetic ticker-specific signed HNX first-trading notice.'
    );
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        md5('p2e4source-first-hnx')::uuid,'hnx','security_lifecycle_notice',
        '2097-01-03 09:00:00+07','P2E4SRC',continuity_payload,
        encode(sha256(convert_to('<html>P2E4SRC first HNX trading day 05/01/2097</html>','UTF8')),'hex'),
        convert_to('<html>P2E4SRC first HNX trading day 05/01/2097</html>','UTF8')
    ) RETURNING landing_id INTO continuity_id;

    INSERT INTO core.security_listing_events(
        symbol_id,episode_id,event_type,venue,effective_date,prior_venue,
        prior_ceased_from,source_landing_id,continuity_landing_id,
        document_date,available_at,availability_basis,source_url,reviewed_claim
    ) VALUES(
        sid,'82345678-1234-5678-1234-567812345678','TRANSFER','HNX',
        DATE '2097-01-05','HOSE',DATE '2097-01-03',source_id,continuity_id,
        DATE '2097-01-01',greatest(membership_at+interval '1 second','2097-01-04 09:00:00+07'),
        'ARCHIVE_FETCH',article_url,
        'Synthetic-only: HNX group article names this security and its final HOSE session; separate HNX notice establishes the first HNX session.'
    ) RETURNING event_id INTO inserted_event_id;

    IF NOT EXISTS (
        SELECT 1 FROM ops.phase2_verified_security_transfers
         WHERE ops.phase2_verified_security_transfers.event_id=inserted_event_id
           AND cohort_source_locator='html.div.justify.1'
    ) THEN
        RAISE EXCEPTION 'exact HNX group-article source and ticker-specific first-trade notice failed the verified-transfer view';
    END IF;
END;
$hnx_group_source$;
ROLLBACK;

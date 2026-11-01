\set ON_ERROR_STOP on
BEGIN;
DO $$ BEGIN
    IF to_regclass('ops.company_profile_call_audit') IS NULL THEN
        RAISE EXCEPTION 'company profile CallRecorded audit table missing';
    END IF;
    IF to_regclass('ops.bar_quality_reprocess_audit') IS NULL THEN
        RAISE EXCEPTION 'archived bar reprocessing audit table missing';
    END IF;
END $$;
INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES ('FPT','HOSE','2026-10-01+07','2026-10-01+07'),('YEG','UPCoM','2026-10-01+07','2026-10-01+07'),
       ('SHC','UPCOM','2026-10-01+07','2026-10-01+07');
DO $$ BEGIN
    IF (SELECT exchange FROM core.symbols WHERE symbol='YEG') <> 'UPCOM' THEN
        RAISE EXCEPTION 'UPCoM not normalized';
    END IF;
END $$;
INSERT INTO core.listing_snapshots(snapshot_date,symbol_id,exchange)
SELECT '2026-10-15',symbol_id,'UPCoM' FROM core.symbols WHERE symbol='YEG';
DO $$ BEGIN
    IF (SELECT exchange FROM core.listing_snapshots LIMIT 1) <> 'UPCOM' THEN
        RAISE EXCEPTION 'listing exchange not normalized';
    END IF;
END $$;
INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
SELECT symbol_id,'2026-10-15',100,106,99,102,0,'unknown','vci','00000000-0000-0000-0000-000000000001','2026-10-15+07'
FROM core.symbols WHERE symbol='FPT';
DO $$ BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.calendar
        WHERE trade_date='2026-10-15' AND is_session
          AND position('observed_bars' in source)>0
    ) THEN RAISE EXCEPTION 'observed bar did not add a session to the effective calendar'; END IF;
END $$;
-- Calendar provenance follows the last canonical bar and preserves other
-- sources, notes, and session state when their independent evidence remains.
DO $$
DECLARE fpt_id bigint; yeg_id bigint;
BEGIN
    SELECT symbol_id INTO fpt_id FROM core.symbols WHERE symbol='FPT';
    SELECT symbol_id INTO yeg_id FROM core.symbols WHERE symbol='YEG';
    INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
    VALUES (yeg_id,'2026-10-15',100,101,99,100,100,'unknown','vci',
            '00000000-0000-4000-8000-000000000043',now());
    UPDATE core.bars_daily SET trade_date='2026-10-16'
     WHERE symbol_id=fpt_id AND trade_date='2026-10-15';
    IF NOT EXISTS (SELECT 1 FROM core.calendar WHERE trade_date='2026-10-15' AND is_session)
       OR NOT EXISTS (SELECT 1 FROM core.calendar WHERE trade_date='2026-10-16' AND is_session) THEN
        RAISE EXCEPTION 'calendar did not retain shared date and add moved bar date';
    END IF;
    DELETE FROM core.bars_daily WHERE symbol_id=yeg_id AND trade_date='2026-10-15';
    IF EXISTS (SELECT 1 FROM core.calendar WHERE trade_date='2026-10-15') THEN
        RAISE EXCEPTION 'calendar retained a date after its final observed bar moved';
    END IF;
    UPDATE core.bars_daily SET trade_date='2026-10-15'
     WHERE symbol_id=fpt_id AND trade_date='2026-10-16';
    IF EXISTS (SELECT 1 FROM core.calendar WHERE trade_date='2026-10-16')
       OR NOT EXISTS (SELECT 1 FROM core.calendar WHERE trade_date='2026-10-15' AND is_session) THEN
        RAISE EXCEPTION 'calendar did not remove the final old date and restore the new date';
    END IF;

    INSERT INTO core.calendar(trade_date,is_session,source,notes)
    VALUES ('2026-10-17',true,'official_calendar','exchange session');
    INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
    VALUES (yeg_id,'2026-10-17',100,101,99,100,100,'unknown','vci',
            '00000000-0000-4000-8000-000000000044',now());
    DELETE FROM core.bars_daily WHERE symbol_id=yeg_id AND trade_date='2026-10-17';
    IF NOT EXISTS (
        SELECT 1 FROM core.calendar
         WHERE trade_date='2026-10-17' AND is_session
           AND source='official_calendar' AND notes='exchange session'
    ) THEN RAISE EXCEPTION 'bar cleanup removed independent calendar provenance'; END IF;
END
$$;
INSERT INTO core.fundamentals_pit(symbol_id,line_item,period_end,period_type,value,source,payload,first_seen_at,available_at)
SELECT symbol_id,'revenue','2026-06-30','quarter',100,'vci','{}',
'2026-08-15 08:00:00+07','2026-08-15 08:00:00+07'
FROM core.symbols WHERE symbol='FPT';
-- Store the exact vendor byte sequence as well as queryable JSONB.
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,payload,payload_sha256,payload_bytes)
VALUES ('00000000-0000-4000-8000-000000000042','vci','equity_list',now(),
        '{"a":1}'::jsonb,repeat('0',64),convert_to(' { "a" : 1 } ','UTF8'));
DO $$ BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM raw.landings
      WHERE payload_bytes=convert_to(' { "a" : 1 } ','UTF8')
        AND payload='{"a":1}'::jsonb
    ) THEN RAISE EXCEPTION 'raw byte preservation failed'; END IF;
END $$;
-- Raw source evidence cannot be rewritten, removed, or truncated after insert.
DO $$
DECLARE v_landing_id bigint;
BEGIN
    SELECT max(raw.landings.landing_id) INTO v_landing_id FROM raw.landings;
    BEGIN
        UPDATE raw.landings SET payload_bytes=convert_to('{}','UTF8') WHERE raw.landings.landing_id=v_landing_id;
        RAISE EXCEPTION 'raw landing UPDATE accepted';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
    BEGIN
        DELETE FROM raw.landings WHERE raw.landings.landing_id=v_landing_id;
        RAISE EXCEPTION 'raw landing DELETE accepted';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
    BEGIN
        TRUNCATE raw.landings CASCADE;
        RAISE EXCEPTION 'raw landing TRUNCATE accepted';
    EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
END $$;
-- The durable quota guard rejects overspending and impossible expiry windows.
INSERT INTO ops.quota_guard(singleton,verified_at,expires_at,day_key,call_budget,spent,min_spacing_ms)
VALUES (true,'2026-10-15 15:00:00+07','2026-10-15 15:05:00+07','2026-10-15',2,1,1177);
DO $$ BEGIN
    BEGIN
        UPDATE ops.quota_guard SET spent=3 WHERE singleton=true;
        RAISE EXCEPTION 'overspend accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        UPDATE ops.quota_guard SET expires_at='2026-10-15 15:11:00+07' WHERE singleton=true;
        RAISE EXCEPTION 'overlong verification accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
-- A backfill job cannot be marked complete before its landing is committed.
INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
VALUES ('test-fpt-20261015-vci','equity_ohlcv','FPT','vci','2026-10-15','2026-10-16');
INSERT INTO ops.api_reservations(job_id,attempt_no,reserved_at,not_before)
SELECT job_id,1,'2026-10-15 15:00+07','2026-10-15 15:00+07' FROM ops.ingest_jobs
WHERE idempotency_key='test-fpt-20261015-vci';
DO $$ DECLARE n bigint; BEGIN
    SELECT job_id INTO n FROM ops.ingest_jobs WHERE idempotency_key='test-fpt-20261015-vci';
    BEGIN
        UPDATE ops.ingest_jobs SET state='COMPLETED' WHERE job_id=n;
        RAISE EXCEPTION 'job completed without landing';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        INSERT INTO ops.api_reservations(job_id,attempt_no,reserved_at,not_before)
        VALUES (n,1,'2026-10-15 15:00+07','2026-10-15 15:00+07');
        RAISE EXCEPTION 'reused reservation attempt accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    BEGIN
        INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
        VALUES ('invalid-range-fpt','equity_ohlcv','FPT','vci','2026-10-16','2026-10-15');
        RAISE EXCEPTION 'invalid date range accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
-- pg_temp runs inside this session; failed constraint violations are caught using PL/pgSQL.
DO $$ DECLARE n bigint; BEGIN
    SELECT symbol_id INTO n FROM core.symbols WHERE symbol='FPT';
    INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
    VALUES (n,'2026-10-16',98,106,99,98.5,100,'unknown','vci',
            '00000000-0000-4000-8000-000000000045',now());
    IF NOT EXISTS (SELECT 1 FROM core.bars_daily
                   WHERE symbol_id=n AND trade_date='2026-10-16' AND o=98 AND l=99 AND c=98.5) THEN
        RAISE EXCEPTION 'auction prices outside continuous-session extrema were rejected';
    END IF;
    BEGIN
        INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
        VALUES (n,'2026-10-15',100,105,99,101,100,'unknown','vci','00000000-0000-0000-0000-000000000001',now());
        RAISE EXCEPTION 'duplicate primary key accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    BEGIN
        INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
        VALUES (n,'2026-10-17',100,90,99,101,100,'unknown','vci','00000000-0000-0000-0000-000000000001',now());
        RAISE EXCEPTION 'invalid high < low accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
    BEGIN
        INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
        VALUES (-10,'2026-10-16',100,105,99,101,100,'unknown','vci','00000000-0000-0000-0000-000000000001',now());
        RAISE EXCEPTION 'missing symbol FK accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
    BEGIN
        INSERT INTO core.fundamentals_pit(symbol_id,line_item,period_end,period_type,value,source,payload,first_seen_at,available_at)
        VALUES (n,'revenue','2026-06-30','quarter',100,'vci','{}',now(),'2026-06-29 23:59:59+07');
        RAISE EXCEPTION 'future information accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
DO $$ BEGIN
    IF to_regclass('ops.external_market_calls') IS NULL OR to_regclass('core.bars_daily_sources') IS NULL
       OR to_regclass('ops.alternate_bar_quality_issues') IS NULL THEN
        RAISE EXCEPTION 'audited alternate-provider OHLCV schema missing';
    END IF;
END $$;
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES ('00000000-0000-4000-8000-000000000046','dnse','equity_ohlcv',now(),'FPT','{}',repeat('1',64),convert_to('{}','UTF8'));
INSERT INTO core.bars_daily_sources(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT symbol_id,'2026-10-18','dnse',98,106,99,98.5,100,'unknown',true,
       (SELECT max(landing_id) FROM raw.landings WHERE source='dnse'),0,
       '00000000-0000-4000-8000-000000000046',now()
FROM core.symbols WHERE symbol='FPT';
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES ('00000000-0000-4000-8000-000000000047','vndirect','equity_ohlcv',now(),'FPT','{}',repeat('2',64),convert_to('{}','UTF8'));
INSERT INTO core.bars_daily_sources(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT symbol_id,'2026-10-18','vndirect',98,106,99,98.5,100,'unadjusted',true,
       (SELECT max(landing_id) FROM raw.landings WHERE source='vndirect'),0,
       '00000000-0000-4000-8000-000000000047',now()
FROM core.symbols WHERE symbol='FPT';
DO $$ DECLARE n bigint; BEGIN
    SELECT symbol_id INTO n FROM core.symbols WHERE symbol='FPT';
    IF NOT EXISTS (SELECT 1 FROM core.bars_daily_sources
                   WHERE symbol_id=n AND trade_date='2026-10-18' AND source='dnse' AND o=98 AND l=99) THEN
        RAISE EXCEPTION 'alternate-source auction price outside continuous extrema was rejected';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.bars_daily_sources
                   WHERE symbol_id=n AND trade_date='2026-10-18' AND source='vndirect' AND o=98 AND l=99) THEN
        RAISE EXCEPTION 'VNDIRECT source series or auction-price support is missing';
    END IF;
    BEGIN
        INSERT INTO core.bars_daily_sources(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
        SELECT n,'2026-10-19','dnse',100,90,99,101,100,'unknown',true,
               (SELECT max(landing_id) FROM raw.landings WHERE source='dnse'),1,
               '00000000-0000-4000-8000-000000000046',now();
        RAISE EXCEPTION 'alternate-source high < low accepted';
    EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
DO $$ BEGIN
    IF (SELECT count(*) FROM information_schema.columns
        WHERE table_schema='ops' AND table_name='dq_cross_source_samples'
          AND column_name IN ('primary_landing_id','primary_source_row','secondary_landing_id','secondary_source_row')) <> 4 THEN
        RAISE EXCEPTION 'cross-source source-row lineage columns missing';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid='ops.dq_cross_source_samples'::regclass
                     AND conname='dq_cross_source_lineage_complete') THEN
        RAISE EXCEPTION 'cross-source complete-lineage constraint missing';
    END IF;
    IF position('primary_landing_id' in pg_get_viewdef('ops.dq_gate_input_readiness'::regclass)) = 0 THEN
        RAISE EXCEPTION 'cross-source readiness does not require lineage';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
        WHERE table_schema='core' AND table_name='bars_daily_with_proxy'
          AND column_name='traded_value_proxy_vnd' AND data_type='numeric') THEN
        RAISE EXCEPTION 'adjusted-close-volume proxy view field missing';
    END IF;
END $$;
DO $$
DECLARE
    vci_payload text := '{"rows":[{"time":"2026-10-16T07:00:00+07:00"}]}';
    notice_payload text := '{"notice":"test lifecycle evidence"}';
    sid bigint;
    other_sid bigint;
    landing bigint;
    delisted_evidence bigint;
    eligible_evidence bigint;
    mutation_blocked boolean := false;
    mismatched_symbol_rejected boolean := false;
BEGIN
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000045','vci','equity_ohlcv',now(),'FPT',vci_payload::jsonb,
            encode(sha256(convert_to(vci_payload,'UTF8')),'hex'),convert_to(vci_payload,'UTF8'));
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000048','hnx','security_lifecycle_notice',now(),'FPT',notice_payload::jsonb,
            encode(sha256(convert_to(notice_payload,'UTF8')),'hex'),convert_to(notice_payload,'UTF8'))
    RETURNING landing_id INTO landing;
    SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='FPT';
    SELECT symbol_id INTO other_sid FROM core.symbols WHERE symbol='YEG';
    INSERT INTO core.security_lifecycle_evidence
      (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
    VALUES (sid,'HOSE','DELISTED','2026-10-16','2026-10-16',landing,'https://example.com/test-notice','2026-10-16')
    RETURNING evidence_id INTO delisted_evidence;
    BEGIN
        INSERT INTO core.security_lifecycle_evidence
          (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
        VALUES (other_sid,'UPCOM','DELISTED','2026-10-16','2026-10-16',landing,
                'https://example.com/test-notice','2026-10-16');
    EXCEPTION WHEN raise_exception THEN
        mismatched_symbol_rejected := true;
    END;
    IF NOT mismatched_symbol_rejected THEN
        RAISE EXCEPTION 'lifecycle evidence accepted a landing for a different security';
    END IF;
    INSERT INTO ops.ml_bar_eligibility_events
      (symbol_id,source,trade_date,decision,reason,evidence_id,raw_landing_id,source_row)
    VALUES (sid,'vci','2026-10-16','EXCLUDE','test exclusion',delisted_evidence,
            (SELECT landing_id FROM raw.landings WHERE ingest_id='00000000-0000-4000-8000-000000000045'),0);
    IF EXISTS (SELECT 1 FROM core.bars_daily_ml_eligible WHERE symbol_id=sid AND trade_date='2026-10-16') THEN
        RAISE EXCEPTION 'latest EXCLUDE event did not filter the ML view';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM core.bars_daily WHERE symbol_id=sid AND trade_date='2026-10-16') THEN
        RAISE EXCEPTION 'eligibility correction modified canonical source history';
    END IF;
    BEGIN
        UPDATE ops.ml_bar_eligibility_events SET reason='mutated'
        WHERE symbol_id=sid AND trade_date='2026-10-16';
    EXCEPTION WHEN raise_exception THEN
        mutation_blocked := true;
    END;
    IF NOT mutation_blocked THEN
        RAISE EXCEPTION 'eligibility history accepted an update';
    END IF;
    INSERT INTO core.security_lifecycle_evidence
      (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
    VALUES (sid,'HOSE','TRADE_ELIGIBLE','2026-10-16','2026-10-16',landing,'https://example.com/test-notice','2026-10-16')
    RETURNING evidence_id INTO eligible_evidence;
    INSERT INTO ops.ml_bar_eligibility_events
      (symbol_id,source,trade_date,decision,reason,evidence_id,raw_landing_id,source_row)
    VALUES (sid,'vci','2026-10-16','ALLOW','test superseding decision',eligible_evidence,
            (SELECT landing_id FROM raw.landings WHERE ingest_id='00000000-0000-4000-8000-000000000045'),0);
    IF NOT EXISTS (SELECT 1 FROM core.bars_daily_ml_eligible WHERE symbol_id=sid AND trade_date='2026-10-16') THEN
        RAISE EXCEPTION 'latest ALLOW event did not supersede the prior exclusion';
    END IF;
END $$;
-- Exchange daily evidence retains the exact source report and can resolve a
-- zero-volume lifecycle row without synthesizing a canonical OHLCV bar.
DO $$
DECLARE
    sid bigint;
    vci_landing bigint;
    hnx_landing bigint;
    job bigint;
    report_bytes bytea := convert_to('<html><body>HNX UPCoM SHC no-match test</body></html>','UTF8');
    report_url text := 'https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM';
    bars_before bigint;
    mutation_blocked boolean;
    lifecycle text;
BEGIN
    SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='SHC';
    SELECT count(*) INTO bars_before FROM core.bars_daily
     WHERE symbol_id=sid AND trade_date='2026-09-16';
    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000061','vci','equity_ohlcv',now(),'SHC',
            '{"rows":[{"time":"2026-09-16","volume":0}]}'::jsonb,
            encode(sha256(convert_to('{"rows":[{"time":"2026-09-16","volume":0}]}','UTF8')),'hex'),
            convert_to('{"rows":[{"time":"2026-09-16","volume":0}]}','UTF8'))
    RETURNING landing_id INTO vci_landing;
    INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
    VALUES ('test-shc-zero-20260916-vci','equity_ohlcv','SHC','vci','2026-09-16','2026-09-16')
    RETURNING job_id INTO job;
    INSERT INTO ops.bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
    VALUES (job,vci_landing,0,'2026-09-16','ZERO_VOLUME_UNVERIFIED','test zero volume');

    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000062','hnx','exchange_daily_report',now(),'SHC',
            jsonb_build_object(
                'symbol','SHC','market','UPCOM','trade_date','2026-09-16','source_row',0,
                'buy_order_count',4,'buy_order_volume',5400,
                'sell_order_count',4,'sell_order_volume',12700,
                'total_matched_volume',0,'total_matched_value_vnd',0,'source_url',report_url),
            encode(sha256(report_bytes),'hex'),report_bytes)
    RETURNING landing_id INTO hnx_landing;
    INSERT INTO ops.exchange_daily_bar_evidence
        (source,market,symbol_id,trade_date,source_row,buy_order_count,buy_order_volume,
         sell_order_count,sell_order_volume,total_matched_volume,total_matched_value_vnd,
         landing_id,source_url)
    VALUES ('hnx','UPCOM',sid,'2026-09-16',0,4,5400,4,12700,0,0,hnx_landing,report_url);

    SELECT derived_lifecycle_status INTO lifecycle
      FROM ops.zero_volume_lifecycle_status
     WHERE symbol='SHC' AND trade_date='2026-09-16' AND landing_id=vci_landing;
    IF lifecycle IS DISTINCT FROM 'VERIFIED_ELIGIBLE_NO_MATCH' THEN
        RAISE EXCEPTION 'HNX explicit zero did not verify the no-match status: %', lifecycle;
    END IF;
    IF (SELECT count(*) FROM core.bars_daily
        WHERE symbol_id=sid AND trade_date='2026-09-16') <> bars_before THEN
        RAISE EXCEPTION 'HNX report evidence synthesized or modified an OHLCV bar';
    END IF;

    mutation_blocked := false;
    BEGIN
        UPDATE ops.exchange_daily_bar_evidence SET observed_at=now()
         WHERE landing_id=hnx_landing AND source_row=0;
    EXCEPTION WHEN raise_exception THEN mutation_blocked := true;
    END;
    IF NOT mutation_blocked THEN RAISE EXCEPTION 'exchange evidence UPDATE was accepted'; END IF;
    mutation_blocked := false;
    BEGIN
        DELETE FROM ops.exchange_daily_bar_evidence
         WHERE landing_id=hnx_landing AND source_row=0;
    EXCEPTION WHEN raise_exception THEN mutation_blocked := true;
    END;
    IF NOT mutation_blocked THEN RAISE EXCEPTION 'exchange evidence DELETE was accepted'; END IF;
END $$;
-- A positive HNX total-market amount must stay negotiated-only when the
-- report's continuous, closing-auction, and after-hours matched fields are 0.
DO $$
DECLARE
    report_url text := 'https://www.hnx.vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM';
    report_bytes bytea := convert_to('<table>negotiated-only fixture</table>','UTF8');
    vci_payload text := '{"rows":[{"time":"2026-09-17","volume":0}]}';
    sid bigint;
    vci_landing bigint;
    hnx_landing bigint;
    job bigint;
    evidence bigint;
    lifecycle text;
    mutation_blocked boolean := false;
BEGIN
    SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='SHC';
    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000064','vci','equity_ohlcv',now(),'SHC',
            vci_payload::jsonb,encode(sha256(convert_to(vci_payload,'UTF8')),'hex'),
            convert_to(vci_payload,'UTF8'))
    RETURNING landing_id INTO vci_landing;
    INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
    VALUES ('test-shc-negotiated-20260917-vci','equity_ohlcv','SHC','vci','2026-09-17','2026-09-17')
    RETURNING job_id INTO job;
    INSERT INTO ops.bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
    VALUES (job,vci_landing,0,'2026-09-17','ZERO_VOLUME_UNVERIFIED','test negotiated-only volume');

    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000065','hnx','exchange_daily_report',now(),'SHC',
            jsonb_build_object(
                'symbol','SHC','market','UPCOM','trade_date','2026-09-17','source_row',0,
                'buy_order_count',1,'buy_order_volume',100,
                'sell_order_count',1,'sell_order_volume',100,
                'total_matched_volume',100,'total_matched_value_vnd',500000,
                'source_url',report_url),
            encode(sha256(report_bytes),'hex'),report_bytes)
    RETURNING landing_id INTO hnx_landing;
    INSERT INTO ops.exchange_daily_bar_evidence
        (source,market,symbol_id,trade_date,source_row,buy_order_count,buy_order_volume,
         sell_order_count,sell_order_volume,total_matched_volume,total_matched_value_vnd,
         landing_id,source_url)
    VALUES ('hnx','UPCOM',sid,'2026-09-17',0,1,100,1,100,100,500000,hnx_landing,report_url)
    RETURNING evidence_id INTO evidence;

    INSERT INTO ops.exchange_daily_bar_evidence_interpretations
        (evidence_id,parser_version,total_matched_volume,total_matched_value_vnd,
         total_negotiated_volume,total_negotiated_value_vnd,total_market_volume,
         total_market_value_vnd,source_field_map,interpretation_note)
    VALUES (evidence,'hnx_upcom_report_columns_v1',0,0,100,500000,100,500000,
            '{"matched_volume_columns":["continuous","close_auction","after_hours"],"negotiated_volume_column":"deal"}'::jsonb,
            'matched components are zero; negotiated component carries total market activity');

    SELECT derived_lifecycle_status INTO lifecycle
      FROM ops.zero_volume_lifecycle_status
     WHERE symbol='SHC' AND trade_date='2026-09-17' AND landing_id=vci_landing;
    IF lifecycle IS DISTINCT FROM 'VERIFIED_NEGOTIATED_ONLY' THEN
        RAISE EXCEPTION 'negotiated-only report was not kept separate from matched activity: %', lifecycle;
    END IF;

    mutation_blocked := false;
    BEGIN
        UPDATE ops.exchange_daily_bar_evidence_interpretations
           SET interpretation_note='mutated'
         WHERE evidence_id=evidence;
    EXCEPTION WHEN raise_exception THEN mutation_blocked := true;
    END;
    IF NOT mutation_blocked THEN RAISE EXCEPTION 'exchange evidence interpretation UPDATE was accepted'; END IF;
END $$;
-- A positive independently attributed alternate row makes the VCI zero a
-- source conflict; it must never be classified as an exchange no-match.
DO $$
DECLARE
    payload_text text := '{"rows":[{"time":"2026-10-18","volume":0}]}';
    landing bigint;
    job bigint;
    lifecycle text;
BEGIN
    INSERT INTO raw.landings
        (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('00000000-0000-4000-8000-000000000063','vci','equity_ohlcv',now(),'FPT',
            payload_text::jsonb,encode(sha256(convert_to(payload_text,'UTF8')),'hex'),
            convert_to(payload_text,'UTF8'))
    RETURNING landing_id INTO landing;
    INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to)
    VALUES ('test-fpt-zero-20261018-vci','equity_ohlcv','FPT','vci','2026-10-18','2026-10-18')
    RETURNING job_id INTO job;
    INSERT INTO ops.bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
    VALUES (job,landing,0,'2026-10-18','ZERO_VOLUME_UNVERIFIED','test alternate conflict');
    SELECT derived_lifecycle_status INTO lifecycle
      FROM ops.zero_volume_lifecycle_status
     WHERE symbol='FPT' AND trade_date='2026-10-18' AND landing_id=landing;
    IF lifecycle IS DISTINCT FROM 'CONFLICTING_EVIDENCE' THEN
        RAISE EXCEPTION 'positive alternate execution was not classified as conflicting evidence: %', lifecycle;
    END IF;
END $$;
ROLLBACK;

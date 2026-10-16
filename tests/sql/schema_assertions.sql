\set ON_ERROR_STOP on
BEGIN;
INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES ('FPT','HOSE','2026-10-01+07','2026-10-01+07'),('YEG','UPCoM','2026-10-01+07','2026-10-01+07');
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
INSERT INTO core.fundamentals_pit(symbol_id,line_item,period_end,period_type,value,source,payload,first_seen_at,available_at)
SELECT symbol_id,'revenue','2026-06-30','quarter',100,'vci','{}',
'2026-08-15 08:00:00+07','2026-08-15 08:00:00+07'
FROM core.symbols WHERE symbol='FPT';
-- Store the exact vendor byte sequence as well as queryable JSONB.
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,payload,payload_sha256,payload_bytes)
VALUES ('00000000-0000-4000-8000-000000000042','vci','equity_list',now(),
        '{"a":1}'::jsonb,repeat('0',64),convert_to(' { "a" : 1 } ','UTF8'));
DO $ BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM raw.landings
      WHERE payload_bytes=convert_to(' { "a" : 1 } ','UTF8')
        AND payload='{"a":1}'::jsonb
    ) THEN RAISE EXCEPTION 'raw byte preservation failed'; END IF;
END $;
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
    BEGIN
        INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
        VALUES (n,'2026-10-15',100,105,99,101,100,'unknown','vci','00000000-0000-0000-0000-000000000001',now());
        RAISE EXCEPTION 'duplicate primary key accepted';
    EXCEPTION WHEN unique_violation THEN NULL; END;
    BEGIN
        INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
        VALUES (n,'2026-10-16',100,90,99,101,100,'unknown','vci','00000000-0000-0000-0000-000000000001',now());
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
ROLLBACK;

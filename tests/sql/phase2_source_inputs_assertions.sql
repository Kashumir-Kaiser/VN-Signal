-- Synthetic-only constraints and PIT assertions for migration 036.
BEGIN;
DO $$
DECLARE
    sid bigint;
    l1 bigint;
    l2 bigint;
    fetched timestamptz := '2098-03-01 10:00:00+07';
    late timestamptz := '2098-03-02 10:00:00+07';
    row1 jsonb := '{"kind":"shares","trade_date":"2098-02-27","listed_shares":1000000}'::jsonb;
    row2 jsonb := '{"kind":"limits","trade_date":"2098-02-27","limit_up":110,"limit_down":90}'::jsonb;
    row3 jsonb := '{"kind":"bar1m","bar_start":"2098-02-27T09:00:00+07:00","o":100,"h":101,"l":99,"c":100.5,"v":1000}'::jsonb;
    row4 jsonb := '{"kind":"holiday","event_key":"synthetic-tet","event_date":"2098-02-27","event_type":"HOLIDAY","is_trading_day":false}'::jsonb;
    rows1 jsonb;
    rows2 jsonb;
    failed boolean;
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2SRCFIX','HOSE',fetched,fetched) RETURNING symbol_id INTO sid;
    rows1 := jsonb_build_array(row1,row2,row3,row4);
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES('30000000-0000-4000-8000-000000000201','fixture','phase2_source_fixture',fetched,'P2SRCFIX',
           jsonb_build_object('rows',rows1),repeat('a',64),convert_to(jsonb_build_object('rows',rows1)::text,'UTF8'))
    RETURNING landing_id INTO l1;

    INSERT INTO core.listed_share_observations(symbol_id,source,trade_date,listed_shares,available_at,fetched_at,raw_landing_id,source_row,row_payload)
    VALUES(sid,'fixture','2098-02-27',1000000,fetched,fetched,l1,0,row1);
    INSERT INTO core.daily_price_limit_observations(symbol_id,source,trade_date,limit_up,limit_down,available_at,fetched_at,raw_landing_id,source_row,row_payload)
    VALUES(sid,'fixture','2098-02-27',110,90,fetched,fetched,l1,1,row2);
    INSERT INTO core.bars_1m_observations(symbol_id,source,bar_start,o,h,l,c,v,available_at,fetched_at,raw_landing_id,source_row,row_payload)
    VALUES(sid,'fixture','2098-02-27 09:00:00+07',100,101,99,100.5,1000,fetched,fetched,l1,2,row3);
    INSERT INTO core.calendar_event_observations(source,event_key,event_type,event_date,is_trading_day,event_payload,available_at,fetched_at,raw_landing_id,source_row,row_payload)
    VALUES('fixture','synthetic-tet','HOLIDAY','2098-02-27',false,row4,fetched,fetched,l1,3,row4);

    -- A changed calendar observation is a new version; an as-of read before it
    -- was fetched continues to see the original value.
    rows2 := jsonb_build_array(row4 || '{"is_trading_day":true}'::jsonb);
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES('30000000-0000-4000-8000-000000000202','fixture','phase2_source_fixture',late,'P2SRCFIX',
           jsonb_build_object('rows',rows2),repeat('b',64),convert_to(jsonb_build_object('rows',rows2)::text,'UTF8'))
    RETURNING landing_id INTO l2;
    INSERT INTO core.calendar_event_observations(source,event_key,event_type,event_date,is_trading_day,event_payload,available_at,fetched_at,raw_landing_id,source_row,row_payload)
    VALUES('fixture','synthetic-tet','HOLIDAY','2098-02-27',true,rows2->0,late,late,l2,0,rows2->0);
    IF (SELECT is_trading_day FROM core.calendar_event_observations
        WHERE event_key='synthetic-tet' AND available_at<=fetched ORDER BY available_at DESC LIMIT 1) IS DISTINCT FROM false THEN
        RAISE EXCEPTION 'calendar PIT lookup exposed a later version';
    END IF;
    IF (SELECT is_trading_day FROM core.calendar_event_observations
        WHERE event_key='synthetic-tet' AND available_at<=late ORDER BY available_at DESC LIMIT 1) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'calendar PIT lookup did not expose the later version';
    END IF;

    failed := false;
    BEGIN
        INSERT INTO core.listed_share_observations(symbol_id,source,trade_date,listed_shares,available_at,fetched_at,raw_landing_id,source_row,row_payload)
        VALUES(sid,'fixture','2098-02-27',2000000,fetched,fetched,l1,0,row1);
    EXCEPTION WHEN unique_violation THEN failed := true;
    END;
    IF NOT failed THEN RAISE EXCEPTION 'duplicate landing/source-row key was accepted'; END IF;

    failed := false;
    BEGIN
        INSERT INTO core.listed_share_observations(symbol_id,source,trade_date,listed_shares,available_at,fetched_at,raw_landing_id,source_row,row_payload)
        VALUES(sid,'fixture','2098-02-27',2000000,fetched-interval '1 second',fetched,l1,0,row1);
    EXCEPTION WHEN OTHERS THEN failed := true;
    END;
    IF NOT failed THEN RAISE EXCEPTION 'observation available before fetched_at was accepted'; END IF;

    failed := false;
    BEGIN
        INSERT INTO core.bars_1m_observations(symbol_id,source,bar_start,o,h,l,c,v,available_at,fetched_at,raw_landing_id,source_row,row_payload)
        VALUES(sid,'fixture','2098-02-27 09:00:00+07',100,101,99,100.5,1000,late,fetched,l1,2,row3);
    EXCEPTION WHEN check_violation THEN failed := true;
    END;
    IF NOT failed THEN RAISE EXCEPTION 'backfilled minute bar was accepted as historically available'; END IF;

    failed := false;
    BEGIN
        INSERT INTO core.daily_price_limit_observations(symbol_id,source,trade_date,limit_up,limit_down,available_at,fetched_at,raw_landing_id,source_row,row_payload)
        VALUES(sid,'fixture','2098-02-27',80,90,fetched,fetched,l1,1,row2);
    EXCEPTION WHEN check_violation THEN failed := true;
    END;
    IF NOT failed THEN RAISE EXCEPTION 'inverted daily price limits were accepted'; END IF;
END $$;

-- VNDIRECT Finfo uses data[] and its zero-based ordinal must match the daily
-- bar source row. The imported limits stay available only from fetch time.
DO $vndirect_data_lineage$
DECLARE
    sid bigint;
    lid bigint;
    fetched timestamptz := '2098-03-01 10:00:00+07';
    payload_row_0 jsonb := '{"code":"P2LIMFIX","date":"2098-02-27","open":100,"high":110,"low":90,"close":105,"ceilingPrice":110,"floorPrice":90}'::jsonb;
    payload_row_1 jsonb := '{"code":"P2LIMFIX","date":"2098-02-28","open":101,"high":111,"low":91,"close":106,"ceilingPrice":111,"floorPrice":91}'::jsonb;
    payload_row_2 jsonb := '{"code":"P2LIMFIX","date":"2098-03-01","open":102,"high":112,"low":92,"close":107,"ceilingPrice":112,"floorPrice":92}'::jsonb;
    imported bigint;
    failed boolean;
    error_message text;
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2LIMFIX','HOSE',fetched,fetched) RETURNING symbol_id INTO sid;

    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES('30000000-0000-4000-8000-000000000203','vndirect','equity_ohlcv',fetched,'P2LIMFIX',
           jsonb_build_object('data',jsonb_build_array(payload_row_0,payload_row_1,payload_row_2)),repeat('c',64),
           convert_to(jsonb_build_object('data',jsonb_build_array(payload_row_0,payload_row_1,payload_row_2))::text,'UTF8'))
    RETURNING landing_id INTO lid;

    INSERT INTO core.bars_daily_sources(
        symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,
        landing_id,source_row,ingest_id,fetched_at
    ) VALUES(
        sid,'2098-02-27','vndirect',100,110,90,105,1000,'unadjusted',true,
        lid,0,'30000000-0000-4000-8000-000000000203',fetched
    ),(
        sid,'2098-02-28','vndirect',101,111,91,106,1000,'unadjusted',true,
        lid,1,'30000000-0000-4000-8000-000000000203',fetched
    ),(
        sid,'2098-03-01','vndirect',102,112,92,107,1000,'unadjusted',true,
        lid,2,'30000000-0000-4000-8000-000000000203',fetched
    );

    imported := core.materialize_vndirect_daily_price_limits(
        '2098-02-27','2098-02-28',ARRAY[sid]
    );
    IF imported<>2 THEN
        RAISE EXCEPTION 'expected two exact VNDIRECT price-limit observations, got %',imported;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.daily_price_limit_observations o
         WHERE o.symbol_id=sid AND o.trade_date='2098-02-27'
           AND o.limit_up=110 AND o.limit_down=90
           AND o.available_at=fetched AND o.fetched_at=fetched
           AND o.raw_landing_id=lid AND o.source_row=0 AND o.row_payload=payload_row_0
    ) THEN
        RAISE EXCEPTION 'VNDIRECT data[0] row was not materialized with exact values and availability';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.daily_price_limit_observations o
         WHERE o.symbol_id=sid AND o.trade_date='2098-02-28'
           AND o.limit_up=111 AND o.limit_down=91
           AND o.available_at=fetched AND o.fetched_at=fetched
           AND o.raw_landing_id=lid AND o.source_row=1 AND o.row_payload=payload_row_1
    ) THEN
        RAISE EXCEPTION 'VNDIRECT nonzero data[] ordinal was not materialized with exact values and availability';
    END IF;
    IF core.materialize_vndirect_daily_price_limits(
           '2098-02-27','2098-02-28',ARRAY[sid]
       )<>0 THEN
        RAISE EXCEPTION 'VNDIRECT price-limit materialization is not idempotent';
    END IF;

    failed:=false;
    error_message:=NULL;
    BEGIN
        INSERT INTO core.daily_price_limit_observations(
            symbol_id,source,trade_date,limit_up,limit_down,
            available_at,fetched_at,raw_landing_id,source_row,row_payload
        ) VALUES(sid,'vndirect','2098-03-01',111,92,fetched,fetched,lid,2,payload_row_2);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        failed:=error_message='VNDIRECT price-limit values must equal the archived source row';
    END;
    IF NOT failed THEN
        RAISE EXCEPTION 'fresh VNDIRECT source-row price mismatch did not produce the expected lineage rejection';
    END IF;

    -- Seed a divergent observation for a fresh key so the materializer's
    -- idempotency path must detect it instead of silently skipping the row.
    ALTER TABLE core.daily_price_limit_observations
        DISABLE TRIGGER daily_price_limit_observations_verify_lineage;
    INSERT INTO core.daily_price_limit_observations(
        symbol_id,source,trade_date,limit_up,limit_down,
        available_at,fetched_at,raw_landing_id,source_row,row_payload
    ) VALUES(sid,'vndirect','2098-03-01',111,92,fetched,fetched,lid,2,payload_row_2);
    ALTER TABLE core.daily_price_limit_observations
        ENABLE TRIGGER daily_price_limit_observations_verify_lineage;

    failed:=false;
    error_message:=NULL;
    BEGIN
        PERFORM core.materialize_vndirect_daily_price_limits(
            '2098-03-01','2098-03-01',ARRAY[sid]
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS error_message = MESSAGE_TEXT;
        failed:=error_message='existing VNDIRECT price-limit observation conflicts with archived source row';
    END;
    IF NOT failed THEN
        RAISE EXCEPTION 'materializer did not reject a divergent existing linked observation';
    END IF;
END $vndirect_data_lineage$;
ROLLBACK;

\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    sid bigint;
    quarter_landing bigint;
    duplicate_landing bigint;
    revision_landing bigint;
    annual_landing bigint;
    bad_landing bigint;
    n integer;
    row_before core.fundamentals_pit%ROWTYPE;
    row_after core.fundamentals_pit%ROWTYPE;
    rejected boolean;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM core.fundamentals_pit f JOIN core.symbols s USING(symbol_id)
         WHERE s.symbol='PITLEGACY' AND f.line_item='legacy_fixture_line'
           AND NOT f.archive_managed AND f.value=123.45
    ) THEN RAISE EXCEPTION 'non-empty legacy fundamentals row was not preserved'; END IF;

    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES ('PITTEST','HOSE','2026-01-01+07','2026-01-01+07')
    RETURNING symbol_id INTO sid;

    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
    VALUES ('10000000-0000-4000-8000-000000000001','vci','fundamental.equity.income_statement',
            '2026-01-05 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100},{"period":"2024-Q2","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":200}]}'::jsonb,repeat('a',64))
    RETURNING landing_id INTO quarter_landing;
    n := core.archive_fundamental_rows(quarter_landing,sid,'income_statement','quarter',
        DATE '2024-03-31','2024-Q1','[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100},{"period":"2024-Q2","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":200}]'::jsonb,'backfill');
    IF n<>1 THEN RAISE EXCEPTION 'backfill did not insert one row'; END IF;
    SELECT * INTO row_before FROM core.fundamentals_pit WHERE symbol_id=sid AND row_id='REV' AND period_end=DATE '2024-03-31';
    IF row_before.available_at <> ('2024-05-15 00:00 Asia/Ho_Chi_Minh'::timestamptz)
       OR row_before.availability_basis <> 'assumed_backfill_lag'
       OR row_before.availability_is_assumed IS DISTINCT FROM true
       OR row_before.first_seen_at <> '2026-01-05 09:00+07'::timestamptz THEN
        RAISE EXCEPTION 'quarterly backfill availability/provenance incorrect';
    END IF;
    IF row_before.source_row<>0 THEN RAISE EXCEPTION 'source row ordinal was not retained'; END IF;
    n := core.archive_fundamental_rows(quarter_landing,sid,'income_statement','quarter',
        DATE '2024-06-30','2024-Q2','[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100},{"period":"2024-Q2","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":200}]'::jsonb,'backfill');
    IF n<>1 OR (SELECT count(*) FROM core.fundamentals_pit WHERE symbol_id=sid AND row_id='REV')<>2 THEN
        RAISE EXCEPTION 'same line ID from a separate period was collapsed';
    END IF;
    IF (SELECT source_row FROM core.fundamentals_pit WHERE symbol_id=sid AND row_id='REV' AND period_end=DATE '2024-06-30')<>1 THEN
        RAISE EXCEPTION 'second period did not retain its original source-row ordinal';
    END IF;
    IF (SELECT count(*) FROM core.fundamentals_pit_asof(sid,'income_statement','2024-05-14 23:59+07'))<>0 THEN
        RAISE EXCEPTION 'quarterly backfill leaked before its conservative 45-day lag';
    END IF;

    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
    VALUES ('10000000-0000-4000-8000-000000000002','vci','fundamental.equity.income_statement',
            '2026-01-12 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100},{"period":"2024-Q2","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":200}]}'::jsonb,repeat('b',64))
    RETURNING landing_id INTO duplicate_landing;
    n := core.archive_fundamental_rows(duplicate_landing,sid,'income_statement','quarter',
        DATE '2024-03-31','2024-Q1','[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100},{"period":"2024-Q2","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":200}]'::jsonb,'backfill');
    IF n<>0 THEN RAISE EXCEPTION 'unchanged repeated snapshot created a version'; END IF;
    IF (SELECT count(*) FROM core.fundamentals_pit_observations WHERE snapshot_id=row_before.snapshot_id)<>2
       OR (SELECT last_seen_at FROM core.fundamentals_pit WHERE snapshot_id=row_before.snapshot_id)
          <> '2026-01-12 09:00+07'::timestamptz THEN
        RAISE EXCEPTION 'duplicate snapshot was not retained as observation/last-seen';
    END IF;

    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
    VALUES ('10000000-0000-4000-8000-000000000003','vci','fundamental.equity.income_statement',
            '2026-02-01 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":125}]}'::jsonb,repeat('c',64))
    RETURNING landing_id INTO revision_landing;
    n := core.archive_fundamental_rows(revision_landing,sid,'income_statement','quarter',
        DATE '2024-03-31','2024-Q1','[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":125}]'::jsonb,'observed');
    IF n<>1 THEN RAISE EXCEPTION 'changed row did not create a revision'; END IF;
    SELECT * INTO row_after FROM core.fundamentals_pit_asof(sid,'income_statement','2026-01-31 23:59+07')
     WHERE period_end=DATE '2024-03-31';
    IF row_after.value<>100 OR row_after.restated THEN RAISE EXCEPTION 'future revision changed earlier as-of result'; END IF;
    SELECT * INTO row_after FROM core.fundamentals_pit_asof(sid,'income_statement','2026-02-01 09:00+07')
     WHERE period_end=DATE '2024-03-31';
    IF row_after.value<>125 OR NOT row_after.restated
       OR row_after.available_at<>'2026-02-01 09:00+07'::timestamptz
       OR row_after.availability_basis<>'observed_ingestion'
       OR row_after.availability_is_assumed THEN
        RAISE EXCEPTION 'revision was not available at observed ingestion time';
    END IF;

    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
    VALUES ('10000000-0000-4000-8000-000000000004','vci','fundamental.equity.balance_sheet',
            '2026-01-06 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2023","id":"ASSET","name":"Assets","order":1,"level":1,"value":500}]}'::jsonb,repeat('d',64))
    RETURNING landing_id INTO annual_landing;
    PERFORM core.archive_fundamental_rows(annual_landing,sid,'balance_sheet','year',DATE '2023-12-31',
        '2023','[{"period":"2023","id":"ASSET","name":"Assets","order":1,"level":1,"value":500}]'::jsonb,'backfill');
    IF (SELECT available_at FROM core.fundamentals_pit WHERE symbol_id=sid AND row_id='ASSET')
       <>'2024-04-09 00:00 Asia/Ho_Chi_Minh'::timestamptz THEN
        RAISE EXCEPTION 'annual backfill did not apply 100-day lag';
    END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000005','vci','fundamental.equity.income_statement',
            '2026-02-02 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"BAD","name":null,"order":2,"level":1,"value":1}]}'::jsonb,repeat('e',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'income_statement','quarter',DATE '2024-03-31',
            '2024-Q1','[{"period":"2024-Q1","id":"BAD","name":null,"order":2,"level":1,"value":1}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'null required line name was accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000006','vci','fundamental.equity.income_statement',
            '2026-02-03 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"BAD","name":"Bad","order":2,"level":2,"value":1}]}'::jsonb,repeat('f',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'income_statement','quarter',DATE '2024-03-31',
            '2024-Q1','[{"period":"2024-Q1","id":"BAD","name":"Bad","order":2,"level":2,"value":1}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'non-level-1 row was accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000007','vci','fundamental.equity.income_statement',
            '2026-02-04 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":"DUP","name":"A","order":2,"level":1,"value":1},{"period":"2024-Q1","id":"DUP","name":"B","order":3,"level":1,"value":2}]}'::jsonb,repeat('0',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'income_statement','quarter',DATE '2024-03-31',
            '2024-Q1','[{"period":"2024-Q1","id":"DUP","name":"A","order":2,"level":1,"value":1},{"period":"2024-Q1","id":"DUP","name":"B","order":3,"level":1,"value":2}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'duplicate line IDs were accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000008','vci','fundamental.equity.income_statement',
            '2026-02-05 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"2024-Q1","id":null,"name":"Bad","order":2,"level":1,"value":1}]}'::jsonb,repeat('1',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'income_statement','quarter',DATE '2024-03-31',
            '2024-Q1','[{"period":"2024-Q1","id":null,"name":"Bad","order":2,"level":1,"value":1}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'null line ID was accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000009','vci','fundamental.equity.balance_sheet',
            '2026-02-06 09:00+07','PITTEST','{"attributes":{"symbol":"PITTEST"},"rows":[{"period":"FY2023","id":"ASSET","name":"Assets","order":1,"level":1,"value":500}]}'::jsonb,repeat('2',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'balance_sheet','year',DATE '2023-12-31',
            'FY2023','[{"period":"FY2023","id":"ASSET","name":"Assets","order":1,"level":1,"value":500}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'unrecognized vendor period label was accepted'; END IF;

    rejected := false;
    BEGIN
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256)
        VALUES ('10000000-0000-4000-8000-000000000010','vci','fundamental.equity.income_statement',
            '2026-02-07 09:00+07','PITTEST','{"attributes":{"symbol":"OTHER"},"rows":[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100}]}'::jsonb,repeat('3',64))
        RETURNING landing_id INTO bad_landing;
        PERFORM core.archive_fundamental_rows(bad_landing,sid,'income_statement','quarter',DATE '2024-03-31',
            '2024-Q1','[{"period":"2024-Q1","id":"REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":100}]'::jsonb,'observed');
    EXCEPTION WHEN OTHERS THEN rejected := true;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'fundamental frame with a mismatched ticker was accepted'; END IF;
END $$;
ROLLBACK;

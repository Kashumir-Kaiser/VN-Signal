-- Synthetic-only input for feat.fundamental_features_daily tests.
-- Run after migration 079 in a disposable database; no provider is contacted.
BEGIN;

INSERT INTO feat.fundamental_line_item_map
    (source,statement_type,row_id,source_unit,value_multiplier,feature_key,mapping_scope,mapping_version)
VALUES
    ('vci','income_statement','SYN_REV','VND',1,'revenue','ALL','synthetic-map-v1'),
    ('vci','income_statement','SYN_GROSS','VND',1,'gross_profit','ALL','synthetic-map-v1'),
    ('vci','income_statement','SYN_OP','VND',1,'operating_profit','ALL','synthetic-map-v1'),
    ('vci','income_statement','SYN_PARENT_NP','VND',1,'parent_net_profit','ALL','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_PARENT_EQ','VND',1,'parent_equity','ALL','synthetic-map-v1'),
    ('vci','income_statement','SYN_NP','VND',1,'net_profit','ALL','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_ASSETS','VND',1,'total_assets','ALL','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_LIAB','VND',1,'total_liabilities','ALL','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_EQUITY','VND',1,'equity','ALL','synthetic-map-v1'),
    ('vci','cash_flow','SYN_CFO','VND',1,'operating_cash_flow','ALL','synthetic-map-v1'),
    ('vci','income_statement','SYN_BANK_INT','VND',1,'bank_interest_income','BANK','synthetic-map-v1'),
    ('vci','income_statement','SYN_BANK_EXP','VND',1,'bank_interest_expense','BANK','synthetic-map-v1'),
    ('vci','income_statement','SYN_BANK_NII','VND',1,'bank_net_interest_income','BANK','synthetic-map-v1'),
    ('vci','income_statement','SYN_BANK_NP','VND',1,'bank_net_profit','BANK','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_BANK_ASSETS','VND',1,'bank_total_assets','BANK','synthetic-map-v1'),
    ('vci','balance_sheet','SYN_BANK_EQUITY','VND',1,'bank_equity','BANK','synthetic-map-v1');

INSERT INTO feat.fundamental_industry_class_map(industry,industry_class,mapping_version)
VALUES('Synthetic Finance','BANK','synthetic-map-v1');

INSERT INTO core.listing_snapshots(snapshot_date,symbol_id,exchange,industry)
SELECT DATE '2098-01-02',symbol_id,'HOSE','Synthetic Finance'
  FROM core.symbols WHERE symbol IN ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE')
ON CONFLICT(snapshot_date,symbol_id) DO UPDATE SET industry=excluded.industry;

DO $$
DECLARE
    symbol_row record;
    statement_name text;
    symbol_no integer := 0;
    ingest text;
    frame_rows jsonb;
    frame_payload jsonb;
    landing bigint;
    period_record record;
BEGIN
    FOR symbol_row IN
        SELECT symbol,symbol_id FROM core.symbols
         WHERE symbol IN ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE')
         ORDER BY CASE symbol WHEN 'P2READY' THEN 0 WHEN 'P2ZERO' THEN 1 WHEN 'P2ENTRY' THEN 2
                   WHEN 'P2EXIT' THEN 3 WHEN 'P2MISS' THEN 4 ELSE 5 END
    LOOP
        IF symbol_row.symbol <> 'P2EPISODE' THEN
            frame_rows := jsonb_build_array(jsonb_build_object(
                'trade_date','2098-01-02','listed_shares',1000000+symbol_no*10000));
            ingest := md5('phase2-fundamental-shares:'||symbol_row.symbol);
            INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
            VALUES(ingest::uuid,'fixture','phase2_fundamental_shares','2098-01-02 12:00:00+07',symbol_row.symbol,
                   jsonb_build_object('rows',frame_rows),encode(sha256(convert_to(jsonb_build_object('rows',frame_rows)::text,'UTF8')),'hex'),
                   convert_to(jsonb_build_object('rows',frame_rows)::text,'UTF8'))
            RETURNING landing_id INTO landing;
            INSERT INTO core.listed_share_observations
                (symbol_id,source,trade_date,listed_shares,available_at,fetched_at,raw_landing_id,source_row,row_payload)
            VALUES(symbol_row.symbol_id,'fixture','2098-01-02',1000000+symbol_no*10000,
                   '2098-01-02 12:00:00+07','2098-01-02 12:00:00+07',landing,0,frame_rows->0);
        END IF;

        FOREACH statement_name IN ARRAY ARRAY['income_statement','balance_sheet','cash_flow'] LOOP
            SELECT jsonb_agg(jsonb_build_object(
                       'period',q.period_key,'id',item.row_id,'name',item.line_name,
                       'order',item.line_order,'level',1,'unit','VND','value',
                       CASE item.row_id
                         WHEN 'SYN_REV' THEN 100000000+symbol_no*10000000+q.quarter_no*5000000
                         WHEN 'SYN_GROSS' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.5
                         WHEN 'SYN_OP' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.3
                         WHEN 'SYN_PARENT_NP' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.1
                         WHEN 'SYN_PARENT_EQ' THEN 300000000+symbol_no*5000000
                         WHEN 'SYN_NP' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.2
                         WHEN 'SYN_ASSETS' THEN 1000000000+symbol_no*10000000
                         WHEN 'SYN_LIAB' THEN 600000000+symbol_no*5000000
                         WHEN 'SYN_EQUITY' THEN 400000000+symbol_no*5000000
                         WHEN 'SYN_CFO' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.15
                         WHEN 'SYN_BANK_INT' THEN 20000000+q.quarter_no*2000000
                         WHEN 'SYN_BANK_EXP' THEN 10000000+q.quarter_no*1000000
                         WHEN 'SYN_BANK_NII' THEN 10000000+q.quarter_no*1000000
                         WHEN 'SYN_BANK_NP' THEN (100000000+symbol_no*10000000+q.quarter_no*5000000)*0.2
                         WHEN 'SYN_BANK_ASSETS' THEN 1000000000+symbol_no*10000000
                         WHEN 'SYN_BANK_EQUITY' THEN 400000000+symbol_no*5000000
                       END
                   ) ORDER BY q.quarter_no,item.line_order)
              INTO frame_rows
              FROM generate_series(0,8) AS gs(quarter_no)
              CROSS JOIN LATERAL (
                  SELECT quarter_no,
                         (DATE '2095-10-01'+quarter_no*INTERVAL '3 months')::date AS quarter_start,
                         to_char(DATE '2095-10-01'+quarter_no*INTERVAL '3 months','YYYY')||'-Q'||
                         extract(quarter FROM DATE '2095-10-01'+quarter_no*INTERVAL '3 months')::integer AS period_key
              ) q
              CROSS JOIN LATERAL (
                  SELECT * FROM (VALUES
                    ('SYN_REV','Revenue',1,'income_statement'),
                    ('SYN_GROSS','Gross profit',2,'income_statement'),
                    ('SYN_OP','Operating profit',3,'income_statement'),
                    ('SYN_PARENT_NP','Parent profit',9,'income_statement'),
                    ('SYN_PARENT_EQ','Parent equity',6,'balance_sheet'),
                    ('SYN_NP','Net profit',4,'income_statement'),
                    ('SYN_BANK_INT','Bank interest income',5,'income_statement'),
                    ('SYN_BANK_EXP','Bank interest expense',6,'income_statement'),
                    ('SYN_BANK_NII','Bank net interest income',7,'income_statement'),
                    ('SYN_BANK_NP','Bank net profit',8,'income_statement'),
                    ('SYN_ASSETS','Total assets',1,'balance_sheet'),
                    ('SYN_LIAB','Total liabilities',2,'balance_sheet'),
                    ('SYN_EQUITY','Equity',3,'balance_sheet'),
                    ('SYN_BANK_ASSETS','Bank total assets',4,'balance_sheet'),
                    ('SYN_BANK_EQUITY','Bank equity',5,'balance_sheet'),
                    ('SYN_CFO','Operating cash flow',1,'cash_flow')
                  ) AS v(row_id,line_name,line_order,statement_type)
                  WHERE v.statement_type=statement_name
              ) item;

            ingest := md5('phase2-fundamental:'||symbol_row.symbol||':'||statement_name);
            frame_payload := jsonb_build_object(
                'attributes',jsonb_build_object('symbol',symbol_row.symbol),
                'columns',jsonb_build_array('period','id','name','order','level','unit','value'),
                'count',jsonb_array_length(frame_rows),
                'rows',frame_rows
            );
            INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
            VALUES(ingest::uuid,'vci','fundamental.equity.'||statement_name,'2098-01-02 12:00:00+07',symbol_row.symbol,
                   frame_payload,
                   encode(sha256(convert_to(frame_payload::text,'UTF8')),'hex'),
                   convert_to(frame_payload::text,'UTF8'))
            RETURNING landing_id INTO landing;

            FOR period_record IN
                SELECT DISTINCT value->>'period' AS period_key
                  FROM jsonb_array_elements(frame_rows) AS rows(value)
                 ORDER BY period_key
            LOOP
                PERFORM core.archive_fundamental_rows(
                    landing,symbol_row.symbol_id,statement_name,'quarter',
                    (make_date(split_part(period_record.period_key,'-Q',1)::integer,
                               split_part(period_record.period_key,'-Q',2)::integer*3,1)+INTERVAL '1 month')::date-1,
                    period_record.period_key,frame_rows,'observed');
            END LOOP;
        END LOOP;
        symbol_no := symbol_no+1;
    END LOOP;
END $$;

COMMIT;

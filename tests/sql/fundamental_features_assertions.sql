-- Synthetic-only PIT fundamentals matrix tests; no vendor route is invoked.
\set ON_ERROR_STOP on
BEGIN;
\ir fundamental_industry_helpers.sql
SELECT feat.build_price_features_v3(DATE '2098-01-06',DATE '2098-02-15');
DO $$
DECLARE
    made bigint;
    sid bigint;
    landing bigint;
    revision_payload jsonb;
    prior_ttm numeric;
    pre_revision numeric;
    on_revision_day numeric;
    post_revision numeric;
    output_row feat.fundamental_features_daily%ROWTYPE;
    revision_rows jsonb := '[{"period":"2097-Q4","id":"SYN_REV","name":"Revenue","order":1,"level":1,"unit":"VND","value":300000000}]'::jsonb;
BEGIN
    made := feat.build_fundamental_features(DATE '2098-01-06',DATE '2098-02-15');
    IF made < 20 THEN RAISE EXCEPTION 'synthetic PIT feature build unexpectedly sparse: %',made; END IF;

    SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2READY';
    SELECT * INTO output_row FROM feat.fundamental_features_daily
     WHERE symbol_id=sid AND trade_date=DATE '2098-01-06';
    IF NOT FOUND THEN RAISE EXCEPTION 'P2READY fundamental matrix row missing'; END IF;
    IF output_row.pit_quarter_count<>9 OR output_row.latest_quarter_end<>DATE '2097-12-31' THEN
        RAISE EXCEPTION 'PIT quarter coverage/latest period incorrect: count %, latest %',
            output_row.pit_quarter_count,output_row.latest_quarter_end;
    END IF;
    IF output_row.ttm_revenue<>530000000 OR output_row.ttm_gross_profit<>265000000 OR
       output_row.ttm_operating_profit<>159000000 OR output_row.ttm_net_profit<>106000000 OR
       output_row.ttm_operating_cash_flow<>79500000 THEN
        RAISE EXCEPTION 'TTM line-item sums are wrong: %, %, %, %, %',
            output_row.ttm_revenue,output_row.ttm_gross_profit,output_row.ttm_operating_profit,
            output_row.ttm_net_profit,output_row.ttm_operating_cash_flow;
    END IF;
    IF abs(output_row.gross_margin_ttm-0.5)>0.000000000001 OR
       abs(output_row.operating_margin_ttm-0.3)>0.000000000001 OR
       abs(output_row.net_margin_ttm-0.2)>0.000000000001 OR
       abs(output_row.roe_ttm-0.265)>0.000000000001 OR
       abs(output_row.roa_ttm-0.106)>0.000000000001 OR
       abs(output_row.liabilities_to_equity-1.5)>0.000000000001 OR
       abs(output_row.accruals_to_average_assets-0.0265)>0.000000000001 THEN
        RAISE EXCEPTION 'margin, return, leverage or accrual formula incorrect';
    END IF;
    IF output_row.ttm_parent_net_profit IS DISTINCT FROM 53000000::numeric OR
       output_row.parent_equity IS DISTINCT FROM 300000000::numeric OR
       output_row.pe_ratio IS NULL OR output_row.pb_ratio IS NULL THEN
        RAISE EXCEPTION 'explicit parent valuation inputs missing';
    END IF;
    IF output_row.listed_shares<>1000000 OR output_row.price_close_thousand_vnd<>101 OR
       abs(output_row.pe_ratio-(101000000000::numeric/53000000))>0.000000000001 OR
       abs(output_row.pb_ratio-(101000000000::numeric/300000000))>0.000000000001 THEN
        RAISE EXCEPTION 'valuation did not use same-day price and PIT listed shares';
    END IF;
    IF output_row.bank_ttm_interest_income<>132000000 OR
       output_row.bank_ttm_interest_expense<>66000000 OR
       output_row.bank_ttm_net_interest_income<>66000000 OR
       abs(output_row.bank_net_interest_to_interest_income-0.5)>0.000000000001 THEN
        RAISE EXCEPTION 'bank-specific item mapping/formula failed';
    END IF;
    IF output_row.rank_industry_net_margin IS NULL OR output_row.rank_industry_roe IS NULL OR
       output_row.rank_industry_revenue_growth IS NULL OR output_row.rank_industry_pe IS NULL OR
       output_row.rank_industry_pb IS NULL THEN
        RAISE EXCEPTION 'industry ranks were not emitted with five or more valid synthetic peers';
    END IF;
    SELECT * INTO output_row FROM feat.fundamental_features_daily
     WHERE symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='P2EPISODE')
       AND trade_date=DATE '2098-01-06';
    IF output_row.listed_shares IS NOT NULL OR output_row.pe_ratio IS NOT NULL OR output_row.pb_ratio IS NOT NULL THEN
        RAISE EXCEPTION 'missing listed-share input was replaced with an inferred valuation';
    END IF;

    prior_ttm := (SELECT ttm_revenue FROM feat.fundamental_features_daily
                   WHERE symbol_id=sid AND trade_date=DATE '2098-01-06');
    revision_payload := jsonb_build_object(
        'attributes',jsonb_build_object('symbol','P2READY'),
        'rows',revision_rows
    );
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES(md5('synthetic-fundamental-revision')::uuid,'vci','fundamental.equity.income_statement',
           '2098-01-20 12:00:00+07','P2READY',revision_payload,
           encode(sha256(convert_to(revision_payload::text,'UTF8')),'hex'),
           convert_to(revision_payload::text,'UTF8'))
    RETURNING landing_id INTO landing;
    PERFORM core.archive_fundamental_rows(landing,sid,'income_statement','quarter',DATE '2097-12-31',
        '2097-Q4',revision_rows,'observed');
    made := feat.build_fundamental_features(DATE '2098-01-06',DATE '2098-02-15');
    pre_revision := (SELECT ttm_revenue FROM feat.fundamental_features_daily
                      WHERE symbol_id=sid AND trade_date=DATE '2098-01-16');
    on_revision_day := (SELECT ttm_revenue FROM feat.fundamental_features_daily
                         WHERE symbol_id=sid AND trade_date=DATE '2098-01-20');
    post_revision := (SELECT ttm_revenue FROM feat.fundamental_features_daily
                       WHERE symbol_id=sid AND trade_date=DATE '2098-01-21');
    IF pre_revision IS DISTINCT FROM prior_ttm OR
       on_revision_day IS DISTINCT FROM prior_ttm+160000000 OR
       post_revision IS DISTINCT FROM prior_ttm+160000000 THEN
        RAISE EXCEPTION 'revision was visible before its 15:00 availability cutoff or missed afterward: prior %, pre %, on day %, post %',
            prior_ttm,pre_revision,on_revision_day,post_revision;
    END IF;

    -- A narrow incremental rebuild must seed its first in-range signal from
    -- every PIT version already available at that date, including old periods.
    made := feat.build_fundamental_features(DATE '2098-01-21',DATE '2098-01-21');
    post_revision := (SELECT ttm_revenue FROM feat.fundamental_features_daily
                       WHERE symbol_id=sid AND trade_date=DATE '2098-01-21');
    IF made<>6 OR post_revision IS DISTINCT FROM prior_ttm+160000000 THEN
        RAISE EXCEPTION 'incremental baseline omitted a previously available PIT revision: rows %, ttm %',made,post_revision;
    END IF;

    UPDATE feat.fundamental_line_item_map SET active=false
     WHERE source='vci' AND row_id='SYN_CFO' AND mapping_scope='ALL';
    made := feat.build_fundamental_features(DATE '2098-01-06',DATE '2098-02-15');
    SELECT * INTO output_row FROM feat.fundamental_features_daily
     WHERE symbol_id=sid AND trade_date=DATE '2098-01-06';
    IF output_row.ttm_net_profit IS NULL OR output_row.ttm_operating_cash_flow IS NOT NULL OR
       output_row.accruals_to_average_assets IS NOT NULL THEN
        RAISE EXCEPTION 'missing mapped cash-flow input was filled instead of remaining NULL';
    END IF;
END $$;
DO $$
DECLARE r feat.fundamental_features_daily%ROWTYPE;
BEGIN
 UPDATE feat.fundamental_line_item_map SET active=false WHERE feature_key IN ('parent_net_profit','parent_equity');
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-06');
 SELECT * INTO STRICT r FROM feat.fundamental_features_daily WHERE symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='P2READY') AND trade_date='2098-01-06';
 IF r.ttm_net_profit IS NULL OR r.roe_ttm IS NULL OR r.pe_ratio IS NOT NULL OR r.pb_ratio IS NOT NULL OR r.ttm_parent_net_profit IS NOT NULL OR r.parent_equity IS NOT NULL THEN
  RAISE EXCEPTION 'missing parent mappings fell back to group inputs or damaged group returns';
 END IF;
 UPDATE feat.fundamental_line_item_map SET active=true WHERE feature_key IN ('parent_net_profit','parent_equity');
END $$;
DO $$
DECLARE sid bigint; old_hash text; new_hash text:=repeat('a',64); old_mapping text;
 original_hash_function text; current_hash text;
BEGIN
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2READY';
 old_hash:=feat.phase2_feature_set_hash_v3();
 UPDATE feat.features_daily SET feature_set_hash=repeat('0',64)
 WHERE symbol_id=sid AND trade_date='2098-01-06' AND feature_version='phase2-v3';
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-06');
 IF EXISTS(SELECT 1 FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-06') THEN
  RAISE EXCEPTION 'stale V3 feature hash seeded the fundamental cohort';
 END IF;
 DELETE FROM feat.features_daily WHERE symbol_id=sid AND trade_date='2098-01-06' AND feature_version='phase2-v3';
 IF NOT EXISTS(SELECT 1 FROM feat.features_daily WHERE symbol_id=sid AND trade_date='2098-01-06' AND feature_version='phase2-v2') THEN
  RAISE EXCEPTION 'negative test requires the legacy V2 row';
 END IF;
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-06');
 IF EXISTS(SELECT 1 FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-06') THEN
  RAISE EXCEPTION 'V2-only feature row seeded the fundamental cohort';
 END IF;
 PERFORM feat.build_price_features_v3('2098-01-06','2098-01-06');
 PERFORM pg_temp.synthetic_industry_observation(NULL,'2098-01-06 14:00+07');
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-06');
 IF (SELECT count(net_margin_ttm)<5 OR count(roe_ttm)<5 OR count(roa_ttm)<5
       OR count(revenue_yoy_growth)<5 OR count(liabilities_to_equity)<5
       OR count(pe_ratio)<5 OR count(pb_ratio)<5
     FROM feat.fundamental_features_daily WHERE trade_date='2098-01-06') THEN
  RAISE EXCEPTION 'unknown-industry test requires five rankable peers for each of seven metrics';
 END IF;
 IF EXISTS(SELECT 1 FROM feat.fundamental_features_daily WHERE trade_date='2098-01-06' AND industry IS NULL
  AND (rank_industry_net_margin IS NOT NULL OR rank_industry_roe IS NOT NULL OR rank_industry_roa IS NOT NULL
    OR rank_industry_revenue_growth IS NOT NULL OR rank_industry_leverage IS NOT NULL
    OR rank_industry_pe IS NOT NULL OR rank_industry_pb IS NOT NULL)) THEN
  RAISE EXCEPTION 'unknown industries acquired synthetic peer ranks';
 END IF;
 SELECT mapping_hash INTO STRICT old_mapping FROM feat.fundamental_features_daily
 WHERE symbol_id=sid AND trade_date='2098-01-06';
 original_hash_function:=pg_get_functiondef('feat.phase2_feature_set_hash_v3()'::regprocedure);
 IF new_hash=old_hash THEN new_hash:=repeat('b',64); END IF;
 UPDATE feat.features_daily SET feature_set_hash=new_hash WHERE feature_version='phase2-v3' AND feature_set_hash=old_hash;
 EXECUTE format('CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3() RETURNS text LANGUAGE sql STABLE AS %L',
                format('SELECT %L::text',new_hash));
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-06');
 SELECT mapping_hash INTO STRICT current_hash FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-06';
 IF current_hash=old_mapping THEN RAISE EXCEPTION 'fundamental mapping identity omitted its price feature hash'; END IF;
 EXECUTE original_hash_function;
END $$;
SELECT feat.build_price_features_v3(DATE '2098-01-20',DATE '2098-01-21');
DO $$
DECLARE sid bigint; kind text; statement_name text; rows_json jsonb; payload_json jsonb;
 lid bigint; v numeric; r feat.fundamental_features_daily%ROWTYPE;
BEGIN
 SELECT symbol_id INTO STRICT sid FROM core.symbols WHERE symbol='P2READY';
 -- Each case replaces the last quarter only after the local signal cutoff.
 FOREACH kind IN ARRAY ARRAY['zero','negative','missing'] LOOP
  FOREACH statement_name IN ARRAY ARRAY['income_statement','balance_sheet'] LOOP
   v:=CASE WHEN kind='missing' THEN NULL WHEN statement_name='balance_sheet'
           THEN CASE WHEN kind='zero' THEN 0 ELSE -1 END
           ELSE CASE WHEN kind='zero' THEN -39000000 ELSE -40000000 END END;
   rows_json:=jsonb_build_array(jsonb_build_object('period','2097-Q4',
     'id',CASE WHEN statement_name='income_statement' THEN 'SYN_PARENT_NP' ELSE 'SYN_PARENT_EQ' END,
     'name','Synthetic parent revision','order',1,'level',1,'unit','VND','value',v));
   payload_json:=jsonb_build_object('attributes',jsonb_build_object('symbol','P2READY'),'rows',rows_json);
   INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
   VALUES(md5('synthetic-parent-revision:'||kind||':'||statement_name)::uuid,'vci','fundamental.equity.'||statement_name,
     ('2098-01-20 16:00:00+07'::timestamptz+CASE kind WHEN 'zero' THEN interval '0 minutes' WHEN 'negative' THEN interval '1 minute' ELSE interval '2 minutes' END),
     'P2READY',payload_json,encode(sha256(convert_to(payload_json::text,'UTF8')),'hex'),convert_to(payload_json::text,'UTF8')) RETURNING landing_id INTO lid;
   PERFORM core.archive_fundamental_rows(lid,sid,statement_name,'quarter','2097-12-31','2097-Q4',rows_json,'observed');
  END LOOP;
  PERFORM feat.build_fundamental_features('2098-01-20','2098-01-21');
  SELECT * INTO STRICT r FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-20';
  IF r.ttm_parent_net_profit IS DISTINCT FROM 53000000::numeric OR r.parent_equity IS DISTINCT FROM 300000000::numeric OR r.pe_ratio IS NULL OR r.pb_ratio IS NULL THEN
   RAISE EXCEPTION 'after-close parent revision leaked into same-day signal: %',kind;
  END IF;
  SELECT * INTO STRICT r FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-21';
  IF r.pe_ratio IS NOT NULL OR r.pb_ratio IS NOT NULL THEN RAISE EXCEPTION 'nonpositive/missing parent operand produced valuation: %',kind; END IF;
  IF kind='zero' AND (r.ttm_parent_net_profit IS DISTINCT FROM 0::numeric OR r.parent_equity IS DISTINCT FROM 0::numeric) THEN RAISE EXCEPTION 'zero parent revision not applied'; END IF;
  IF kind='negative' AND (r.ttm_parent_net_profit IS DISTINCT FROM -1000000::numeric OR r.parent_equity IS DISTINCT FROM -1::numeric) THEN RAISE EXCEPTION 'negative parent revision not applied'; END IF;
  IF kind='missing' AND (r.ttm_parent_net_profit IS NOT NULL OR r.parent_equity IS NOT NULL) THEN RAISE EXCEPTION 'missing quarter incorrectly formed parent TTM'; END IF;
 END LOOP;
END $$;
ROLLBACK;

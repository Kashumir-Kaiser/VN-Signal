\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='180s';
SET LOCAL lock_timeout='5s';

CREATE SCHEMA p2market_input;
CREATE SCHEMA p2market_output;
CREATE SCHEMA p2market_ops;

DO $market_projection$
DECLARE
    first_date date;
    last_date date;
    cut_date date;
    selected_symbol bigint;
    definition text;
    rejected boolean:=false;
BEGIN
    SELECT min(trade_date),max(trade_date) INTO first_date,last_date
      FROM core.bars_daily_sources WHERE source='vndirect';
    PERFORM feat.build_features_v2(first_date,last_date);
    CREATE TABLE p2market_input.symbols AS SELECT symbol_id,exchange FROM core.symbols;
    CREATE TABLE p2market_input.effective_trading_sessions AS
        SELECT trade_date,is_session FROM core.effective_trading_sessions;
    CREATE TABLE p2market_input.phase2_adjustment_rows AS
        SELECT * FROM pg_temp.phase2_adjustment_rows;
    ANALYZE p2market_input.phase2_adjustment_rows;
    CREATE TEMP TABLE market_projection_baseline ON COMMIT DROP AS
        SELECT * FROM feat.phase2_market_inputs_scoped(
            first_date,last_date,'p2market_input','p2market_output','p2market_ops');
    IF NOT EXISTS(SELECT 1 FROM market_projection_baseline) THEN
        RAISE EXCEPTION 'market projection fixture has no observations';
    END IF;
    IF EXISTS (
        SELECT 1 FROM market_projection_baseline m FULL JOIN (
            SELECT symbol_id,trade_date,ret_1,distance_52w_high,distance_52w_low,turnover_proxy_vnd
              FROM feat.features_daily WHERE feature_version='phase2-v2'
               AND trade_date BETWEEN first_date AND last_date
        ) f USING(symbol_id,trade_date)
        WHERE m.symbol_id IS NULL OR f.symbol_id IS NULL
           OR pg_catalog.record_send(ROW(m.ret_1,m.distance_52w_high,m.distance_52w_low,m.turnover_proxy_vnd))
              IS DISTINCT FROM pg_catalog.record_send(ROW(f.ret_1,f.distance_52w_high,f.distance_52w_low,f.turnover_proxy_vnd))
    ) THEN RAISE EXCEPTION 'narrow market projection differs from fresh production V2 output'; END IF;

    SELECT trade_date INTO cut_date FROM market_projection_baseline
     GROUP BY trade_date ORDER BY trade_date OFFSET 200 LIMIT 1;
    IF cut_date IS NULL THEN RAISE EXCEPTION 'market projection fixture needs more than 200 sessions'; END IF;
    SELECT min(symbol_id) INTO selected_symbol FROM market_projection_baseline;
    UPDATE p2market_input.phase2_adjustment_rows SET
        model_o=model_o*1.1,model_h=model_h*1.1,model_l=model_l*1.1,model_c=model_c*1.1,v=v*0.9
     WHERE trade_date>cut_date;
    CREATE TEMP TABLE market_projection_perturbed ON COMMIT DROP AS
        SELECT * FROM feat.phase2_market_inputs_scoped(
            first_date,last_date,'p2market_input','p2market_output','p2market_ops');
    IF EXISTS (
        SELECT 1 FROM market_projection_baseline a FULL JOIN market_projection_perturbed b
          USING(symbol_id,trade_date)
         WHERE coalesce(a.trade_date,b.trade_date)<=cut_date
           AND (a.symbol_id IS NULL OR b.symbol_id IS NULL
            OR pg_catalog.record_send(ROW(a.ret_1,a.distance_52w_high,a.distance_52w_low,a.turnover_proxy_vnd))
               IS DISTINCT FROM pg_catalog.record_send(ROW(b.ret_1,b.distance_52w_high,b.distance_52w_low,b.turnover_proxy_vnd)))
    ) THEN RAISE EXCEPTION 'market projection leaks future inputs'; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM market_projection_baseline a JOIN market_projection_perturbed b
          USING(symbol_id,trade_date)
         WHERE a.trade_date>cut_date AND a.symbol_id<>selected_symbol
           AND (a.ret_1,a.distance_52w_high,a.distance_52w_low,a.turnover_proxy_vnd)
               IS DISTINCT FROM (b.ret_1,b.distance_52w_high,b.distance_52w_low,b.turnover_proxy_vnd)
    ) THEN RAISE EXCEPTION 'non-cohort market support did not change after perturbation'; END IF;

    definition:=pg_get_functiondef('feat.build_features_v2_shared(date,date,bigint[])'::regprocedure);
    EXECUTE replace(definition,E'\nDECLARE',E'\n-- Intentional definition-drift fixture\nDECLARE');
    BEGIN
        PERFORM 1 FROM feat.phase2_market_inputs_scoped(
            first_date,last_date,'p2market_input','p2market_output','p2market_ops');
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM<>'production V2 changed; regenerate the shared market projection' THEN RAISE; END IF;
        rejected:=true;
    END;
    EXECUTE definition;
    IF NOT rejected THEN RAISE EXCEPTION 'market projection accepted production definition drift'; END IF;
END;
$market_projection$;
ROLLBACK;

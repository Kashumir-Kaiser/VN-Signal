\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    v_bad double precision;
    v_scaler_definition text:=pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure);
    v_validator_definition text:=pg_get_functiondef('feat.validate_phase2_cache_samples()'::regprocedure);
BEGIN
    IF feat.phase2_cache_sample_batch_ms(60,4000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(30,2000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(15,1000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(60,4000,25,1)<>2000
       OR feat.phase2_cache_sample_batch_ms(15,1000,60,0)<>4000
       OR feat.phase2_cache_sample_batch_ms(60,4000,60,1)<>4000 THEN
        RAISE EXCEPTION 'cache sample batch accounting differs from expected complete/partial/extrapolated costs';
    END IF;
    IF feat.phase2_cache_sample_batch_rows_ms(60,108331,4000,15,27082,1)<>1000
       OR feat.phase2_cache_sample_batch_rows_ms(30,53205,3822,15,30114,1)<=1911
       OR feat.phase2_cache_sample_batch_rows_ms(15,23765,1472,15,23765,1.18)<>1472 THEN
        RAISE EXCEPTION 'row-weighted cache batch projection does not use measured rows per configured batch';
    END IF;
    FOREACH v_bad IN ARRAY ARRAY[NULL,0,-1,'NaN'::float8,'Infinity'::float8] LOOP
        BEGIN
            PERFORM feat.phase2_cache_sample_batch_ms(15,v_bad,15,1);
            RAISE EXCEPTION 'invalid duration accepted';
        EXCEPTION WHEN raise_exception THEN
            IF SQLERRM='invalid duration accepted' THEN RAISE; END IF;
        END;
    END LOOP;
    IF position('IF v_exponent>1.3 THEN' IN v_scaler_definition)=0
       OR position('IF v_projected_ms>v_budget_minutes*60000.0 THEN' IN v_scaler_definition)=0
       OR position('max(b_15_30),max(b_30_60)' IN v_scaler_definition)=0
       OR position('feat.phase2_cache_sample_batch_rows_ms(15' IN v_scaler_definition)=0
       OR position('v_expected_batch_rows' IN v_scaler_definition)=0
       OR position('core.bars_daily_sources' IN v_scaler_definition)=0
       OR position('worst_block_mean_ms' IN v_validator_definition)=0
       OR position('rows_30::double precision/rows_15::double precision' IN v_validator_definition)=0
       OR position('stddev_pop(mean_ms)/avg(mean_ms)>0.20' IN v_validator_definition)=0 THEN
        RAISE EXCEPTION 'row-weighted scaling or budget guard missing';
    END IF;
END $$;
ROLLBACK;

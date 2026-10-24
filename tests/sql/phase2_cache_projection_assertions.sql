\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE v_bad double precision;
BEGIN
    IF feat.phase2_cache_sample_batch_ms(60,4000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(30,2000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(15,1000,15,1)<>1000
       OR feat.phase2_cache_sample_batch_ms(60,4000,25,1)<>2000
       OR feat.phase2_cache_sample_batch_ms(15,1000,60,0)<>4000
       OR feat.phase2_cache_sample_batch_ms(60,4000,60,1)<>4000 THEN
        RAISE EXCEPTION 'cache sample batch accounting differs from expected complete/partial/extrapolated costs';
    END IF;
    FOREACH v_bad IN ARRAY ARRAY[NULL,0,-1,'NaN'::float8,'Infinity'::float8] LOOP
        BEGIN
            PERFORM feat.phase2_cache_sample_batch_ms(15,v_bad,15,1);
            RAISE EXCEPTION 'invalid duration accepted';
        EXCEPTION WHEN raise_exception THEN
            IF SQLERRM='invalid duration accepted' THEN RAISE; END IF;
        END;
    END LOOP;
    IF position('IF v_exponent>1.3 THEN' IN pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure))=0
       OR position('IF v_projected_ms>v_budget_minutes*60000.0 THEN' IN pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure))=0 THEN
        RAISE EXCEPTION 'scaling or budget guard missing';
    END IF;
END $$;
ROLLBACK;

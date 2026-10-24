-- Normalize whole-probe durations before projecting production batch work.
BEGIN;
CREATE OR REPLACE FUNCTION feat.phase2_cache_sample_batch_ms(
    p_sample_symbols integer,p_duration_ms double precision,
    p_batch_size integer,p_exponent double precision
) RETURNS double precision LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF p_sample_symbols IS NULL OR p_sample_symbols NOT IN (15,30,60)
       OR p_duration_ms IS NULL OR NOT (p_duration_ms>0 AND p_duration_ms<'Infinity'::double precision)
       OR p_batch_size IS NULL OR p_batch_size NOT BETWEEN 1 AND 250
       OR p_exponent IS NULL OR NOT (p_exponent>=0 AND p_exponent<=1.3) THEN
        RAISE EXCEPTION 'invalid cache projection sample or strategy';
    END IF;
    IF p_batch_size<=p_sample_symbols THEN
        -- Attribute a partial final batch and all setup/finalization overhead
        -- to the complete batches. This intentionally overestimates fill cost.
        RETURN p_duration_ms / floor(p_sample_symbols::double precision/p_batch_size);
    END IF;
    -- Never extrapolate a larger batch at less than linear cost.
    RETURN p_duration_ms*power(p_batch_size::double precision/p_sample_symbols,greatest(1.0,p_exponent));
END;
$$;
DO $projection$
DECLARE
    v_definition text:=pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure);
    v_old text:=$old$    v_batch_ms:=greatest(
        v_t15*power(v_batch_size::double precision/15.0,v_exponent),
        v_t30*power(v_batch_size::double precision/30.0,v_exponent),
        v_t60*power(v_batch_size::double precision/60.0,v_exponent)
    );$old$;
    v_new text:=$new$    v_batch_ms:=greatest(
        feat.phase2_cache_sample_batch_ms(15,v_t15,v_batch_size,v_exponent),
        feat.phase2_cache_sample_batch_ms(30,v_t30,v_batch_size,v_exponent),
        feat.phase2_cache_sample_batch_ms(60,v_t60,v_batch_size,v_exponent)
    );$new$;
BEGIN
    IF position('feat.phase2_cache_sample_batch_ms(15' IN v_definition)>0 THEN RETURN; END IF;
    IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'cache projection migration anchor missing'; END IF;
    EXECUTE replace(v_definition,v_old,v_new);
END;
$projection$;
COMMENT ON FUNCTION feat.phase2_cache_sample_batch_ms(integer,double precision,integer,double precision) IS
    'Conservative per-full-batch cost from complete strategy samples, retaining setup/finalization overhead; not a measured runtime guarantee.';
COMMIT;

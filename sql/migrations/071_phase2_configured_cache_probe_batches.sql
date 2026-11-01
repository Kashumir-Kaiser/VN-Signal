-- Measure the selected bounded cache strategy at 15/30/60 total symbols.
-- Scaling thresholds, source rows, and the time-budget assertion are unchanged.
BEGIN;

CREATE OR REPLACE FUNCTION feat.probe_phase2_adjustment_cache(p_symbol_count integer)
RETURNS TABLE(symbol_count integer,row_count bigint,duration_ms bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_started_at timestamptz:=clock_timestamp();
    v_actual_symbols integer;
    v_batches integer;
    v_rows bigint;
    v_metrics_relation oid;
    v_batch_size integer;
    v_configured_batch_size integer;
    v_batch_no integer;
BEGIN
    IF p_symbol_count IS NULL OR p_symbol_count NOT IN (15,30,60) THEN
        RAISE EXCEPTION 'cache scaling probes require exactly 15, 30, or 60 symbols';
    END IF;
    v_batch_size:=coalesce(nullif(current_setting('vnpipe.phase2_symbol_batch_size',true),'')::integer,60);
    IF v_batch_size<1 OR v_batch_size>250 THEN
        RAISE EXCEPTION 'vnpipe.phase2_symbol_batch_size must be between 1 and 250';
    END IF;
    v_configured_batch_size:=v_batch_size;
    v_batch_size:=least(v_batch_size,p_symbol_count);
    PERFORM feat.begin_phase2_adjustment_rows(v_batch_size,p_symbol_count);
    SELECT count(*)::integer,count(DISTINCT batch_no)::integer
      INTO v_actual_symbols,v_batches
      FROM pg_temp.phase2_adjustment_symbol_batches;
    IF v_actual_symbols<>p_symbol_count OR v_batches<>ceil(p_symbol_count::numeric/v_batch_size)::integer THEN
        RAISE EXCEPTION 'cache scaling probe requested % symbols but found % in % batches',
            p_symbol_count,v_actual_symbols,v_batches;
    END IF;
    FOR v_batch_no IN
        SELECT DISTINCT batch_no FROM pg_temp.phase2_adjustment_symbol_batches ORDER BY batch_no
    LOOP
        PERFORM feat.populate_phase2_adjustment_rows(v_batch_no);
    END LOOP;
    v_rows:=feat.finish_phase2_adjustment_rows();

    v_metrics_relation:=to_regclass('pg_temp.phase2_adjustment_cache_probe_results');
    IF v_metrics_relation IS NULL THEN
        CREATE TEMP TABLE phase2_adjustment_cache_probe_results(
            symbol_count integer PRIMARY KEY,
            row_count bigint NOT NULL CHECK(row_count>0),
            duration_ms bigint NOT NULL CHECK(duration_ms>0)
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_adjustment_cache_probe_results IS
            'VN-Signal Phase 2 session-local cache scaling probe results';
    ELSIF obj_description(v_metrics_relation,'pg_class') IS DISTINCT FROM
          'VN-Signal Phase 2 session-local cache scaling probe results' THEN
        RAISE EXCEPTION 'temporary relation phase2_adjustment_cache_probe_results is reserved by the Phase 2 builder';
    END IF;
    ALTER TABLE pg_temp.phase2_adjustment_cache_probe_results
        ADD COLUMN IF NOT EXISTS configured_batch_size integer,
        ADD COLUMN IF NOT EXISTS work_memory text,
        ADD COLUMN IF NOT EXISTS maintenance_memory text;
    duration_ms:=GREATEST(1,(extract(epoch FROM (clock_timestamp()-v_started_at))*1000)::bigint);
    INSERT INTO pg_temp.phase2_adjustment_cache_probe_results(symbol_count,row_count,duration_ms,configured_batch_size,work_memory,maintenance_memory)
    VALUES(p_symbol_count,v_rows,duration_ms,v_configured_batch_size,current_setting('work_mem'),current_setting('maintenance_work_mem'))
    ON CONFLICT ON CONSTRAINT phase2_adjustment_cache_probe_results_pkey DO UPDATE
      SET row_count=EXCLUDED.row_count,duration_ms=EXCLUDED.duration_ms,
          configured_batch_size=EXCLUDED.configured_batch_size,
          work_memory=EXCLUDED.work_memory,maintenance_memory=EXCLUDED.maintenance_memory;
    symbol_count:=p_symbol_count;
    row_count:=v_rows;
    RETURN NEXT;
END;
$$;


DO $probe_configuration_guard$
DECLARE
    v_definition text:=pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure);
    v_anchor text:='    v_batch_count:=ceil(v_universe_symbols::double precision/v_batch_size)::integer;';
    v_guard text:=$body$
    IF EXISTS (
        SELECT 1 FROM pg_temp.phase2_adjustment_cache_probe_results
        WHERE configured_batch_size IS DISTINCT FROM v_batch_size
           OR work_memory IS DISTINCT FROM current_setting('work_mem')
           OR maintenance_memory IS DISTINCT FROM current_setting('maintenance_work_mem')
    ) THEN
        RAISE EXCEPTION 'cache probe configuration differs from the requested build; rerun all samples';
    END IF;
$body$;
BEGIN
    IF position('cache probe configuration differs' IN v_definition)>0 THEN RETURN; END IF;
    IF position(v_anchor IN v_definition)=0 THEN RAISE EXCEPTION 'cache scaling guard anchor missing'; END IF;
    EXECUTE replace(v_definition,v_anchor,v_guard||v_anchor);
END;
$probe_configuration_guard$;
COMMIT;

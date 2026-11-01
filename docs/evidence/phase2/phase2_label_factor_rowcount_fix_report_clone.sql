BEGIN;
DO $phase2_factor_count_order_fix$
DECLARE
    v_def text := pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure);
    v_pattern constant text :=
        'PERFORM set_config\(''enable_nestloop'',v_enable_nestloop,true\);[[:space:]]+'
        || 'GET DIAGNOSTICS v_step_rows = ROW_COUNT;';
    v_new constant text := 'GET DIAGNOSTICS v_step_rows = ROW_COUNT;'
        || E'\n     PERFORM set_config(''enable_nestloop'',v_enable_nestloop,true);';
    v_match_count integer;
BEGIN
    SELECT count(*) INTO v_match_count FROM regexp_matches(v_def,v_pattern,'g');
    IF v_match_count <> 1 THEN
        RAISE EXCEPTION 'report clone does not have the expected pre-fix planner/count sequence';
    END IF;
    v_def := regexp_replace(v_def,v_pattern,v_new);
    EXECUTE v_def;
END;
$phase2_factor_count_order_fix$;
COMMIT;

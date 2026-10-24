BEGIN;

-- The bad-factor filter is expected to return very few rows.  With 2.8M
-- cached adjustment rows PostgreSQL estimates that filter too low to choose a
-- sequential scan and can otherwise perform one cache index scan per symbol.
-- Keep the measured hash/sequence plan local to this validation query only.
DO $phase2_label_factor_hash_scan$
DECLARE
    v_def text := pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure);
    v_declaration_anchor constant text := '    v_step_rows bigint;';
    v_prequery_anchor constant text :=
        '    DROP TABLE IF EXISTS pg_temp.phase2_label_first_bad_factor;';
    v_postquery_anchor constant text :=
        E'     GROUP BY r.symbol_id;\n    GET DIAGNOSTICS v_step_rows = ROW_COUNT;';
BEGIN
    IF position('v_enable_nestloop' IN v_def) > 0
       OR length(v_def)-length(replace(v_def,v_declaration_anchor,'')) <> length(v_declaration_anchor)
       OR length(v_def)-length(replace(v_def,v_prequery_anchor,'')) <> length(v_prequery_anchor)
       OR length(v_def)-length(replace(v_def,v_postquery_anchor,'')) <> length(v_postquery_anchor) THEN
        RAISE EXCEPTION 'unexpected Phase 2 label builder definition; refuse planner-scope patch';
    END IF;

    v_def := replace(v_def, v_declaration_anchor,
        v_declaration_anchor || E'\n    v_enable_nestloop text;');
    v_def := replace(v_def, v_prequery_anchor,
        E'    v_step_started := clock_timestamp();\n'
        || E'    -- Use one sequential pass for the rare invalid-factor filter.\n'
        || E'    v_enable_nestloop := current_setting(''enable_nestloop'');\n'
        || E'    PERFORM set_config(''enable_nestloop'',''off'',true);\n'
        || v_prequery_anchor);
    v_def := replace(v_def, v_postquery_anchor,
        E'     GROUP BY r.symbol_id;\n'
        || E'    GET DIAGNOSTICS v_step_rows = ROW_COUNT;\n'
        || E'    PERFORM set_config(''enable_nestloop'',v_enable_nestloop,true);');

    IF position('PERFORM set_config(''enable_nestloop'',''off'',true);' IN v_def) = 0
       OR position('PERFORM set_config(''enable_nestloop'',v_enable_nestloop,true);' IN v_def) = 0 THEN
        RAISE EXCEPTION 'Phase 2 label planner override was not scoped around the bad-factor scan';
    END IF;

    EXECUTE v_def;
END;
$phase2_label_factor_hash_scan$;

COMMIT;

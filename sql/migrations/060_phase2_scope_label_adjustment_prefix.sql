BEGIN;

-- Label adjustment prefixes only need symbols represented by current targets.
-- Without this join, a scoped E2 rebuild materializes prefix rows for every
-- cached symbol before joining the selected label targets.
DO $phase2_scope_label_prefix$
DECLARE
    v_signature text;
    v_definition text;
    v_anchor text :=
        '      FROM pg_temp.phase2_adjustment_rows r'
        || E'\n      CROSS JOIN pg_temp.phase2_label_endpoint_bounds b';
    v_replacement text :=
        '      FROM pg_temp.phase2_adjustment_rows r'
        || E'\n      JOIN pg_temp.phase2_label_latest_exit active_symbols USING (symbol_id)'
        || E'\n      CROSS JOIN pg_temp.phase2_label_endpoint_bounds b';
BEGIN
    -- The public date-only entry point delegates to the shared implementation.
    -- Patch the shared implementation where the prefix query actually lives.
    FOREACH v_signature IN ARRAY ARRAY[
        'feat.build_labels_set_based_shared(date,date,bigint[])'
    ] LOOP
        v_definition := pg_get_functiondef(v_signature::regprocedure);
        IF position('phase2_label_latest_exit active_symbols' IN v_definition) > 0 THEN
            CONTINUE;
        END IF;
        IF length(v_definition)-length(replace(v_definition,v_anchor,'')) <> length(v_anchor) THEN
            RAISE EXCEPTION 'unexpected adjustment-prefix source in %',v_signature;
        END IF;
        EXECUTE replace(v_definition,v_anchor,v_replacement);
    END LOOP;
END;
$phase2_scope_label_prefix$;

DO $phase2_scope_label_prefix_assert$
BEGIN
    IF position('phase2_label_latest_exit active_symbols' IN
          pg_get_functiondef('feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure)) = 0
       OR position('build_labels_set_based_shared(p_date_from,p_date_to,NULL)' IN
          pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure)) = 0 THEN
        RAISE EXCEPTION 'shared Phase 2 label builder must scope adjustment prefixes to target symbols';
    END IF;
END;
$phase2_scope_label_prefix_assert$;

COMMIT;

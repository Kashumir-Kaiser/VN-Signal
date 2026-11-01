\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    v_before text;
    v_after text;
    v_rejected boolean:=false;
BEGIN
    PERFORM set_config('vnpipe.phase2_entry_ceiling_weight','0',true);
    PERFORM set_config('vnpipe.phase2_multiple_locked_weight','0.5',true);
    v_before:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');
    PERFORM set_config('vnpipe.phase2_entry_ceiling_weight','0.25',true);
    PERFORM set_config('vnpipe.phase2_multiple_locked_weight','0.75',true);
    IF feat.phase2_execution_weight_decision(true,100,100,3) IS DISTINCT FROM 0.25::double precision
       OR feat.phase2_execution_weight_decision(true,99,100,2) IS DISTINCT FROM 0.75::double precision
       OR feat.phase2_execution_weight_decision(true,99,100,1) IS DISTINCT FROM 1::double precision
       OR feat.phase2_execution_weight_decision(false,100,100,3) IS NOT NULL
       OR feat.phase2_execution_weight_decision(true,NULL,100,3) IS NOT NULL THEN
        RAISE EXCEPTION 'configured execution policy changed evidence or precedence semantics';
    END IF;
    v_after:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');
    IF v_before=v_after THEN RAISE EXCEPTION 'execution policy omitted from input hash'; END IF;
    PERFORM set_config('vnpipe.phase2_entry_ceiling_weight','0.2500',true);
    IF v_after<>ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02') THEN
        RAISE EXCEPTION 'equivalent numeric policies hash differently';
    END IF;
    BEGIN
        PERFORM set_config('vnpipe.phase2_entry_ceiling_weight','NaN',true);
        PERFORM ops.phase2_execution_weight_policy();
    EXCEPTION WHEN raise_exception THEN v_rejected:=true;
    END;
    IF NOT v_rejected THEN RAISE EXCEPTION 'nonfinite execution policy accepted'; END IF;
END
$$;
ROLLBACK;

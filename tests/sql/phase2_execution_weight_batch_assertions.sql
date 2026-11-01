DO $phase2_execution_weight_batch_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure
    );
    v_wrapper text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date)'::regprocedure
    );
    v_date_wrapper text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date,date)'::regprocedure
    );
    v_evidence_function text := pg_get_functiondef(
        'core.phase2_execution_limit_evidence_for_day(bigint,date)'::regprocedure
    );
BEGIN
    IF position('CREATE TEMP TABLE phase2_weight_windows_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_expected_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_unique_sessions_106' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_eligible_bars_106' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_verified_vndirect_landings_106' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_vndirect_payload_rows_108' IN v_definition)=0
       OR position('phase2_weight_payload_rows_selected_109' IN v_definition)=0
       OR position('array_agg(source_row ORDER BY source_row)' IN v_definition)=0
       OR position('=ANY(needed.source_rows)' IN v_definition)=0
       OR position('jsonb_array_elements' IN v_definition)=0
       OR position('p.row_payload=raw_bar.bar_row' IN v_definition)=0
       OR position('bar_l.payload->''data''->b.source_row' IN v_definition)>0
       OR position('limits_l.payload->''data''->p.source_row' IN v_definition)>0
       OR position('CREATE TEMP TABLE phase2_weight_evidence_days_106' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_evidence_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_values_102' IN v_definition)=0
       OR position('ANALYZE pg_temp.phase2_weight_windows_102' IN v_definition)=0
       OR position('ANALYZE pg_temp.phase2_weight_evidence_102' IN v_definition)=0
       OR position('feat.phase2_exact_execution_weight' IN v_definition)>0
       OR position('phase2_execution_weight_decision' IN v_definition)=0
       OR position('core.daily_price_limit_observations' IN v_definition)=0
       OR position('source=''bsc''' IN v_definition)=0
       OR position('payload_bytes' IN v_definition)=0
       OR position('NOT EXISTS' IN v_definition)=0
       OR position('ops.ml_bar_eligibility_events' IN v_definition)=0
       OR position('EXCLUDE' IN v_definition)=0
       OR position('p_evidence_trade_date' IN v_definition)=0
       OR position('p_symbol_ids' IN v_definition)=0
       OR position('changed_limit' IN v_definition)=0
       OR position('feat.refresh_phase2_execution_weights' IN v_wrapper)=0
       OR position('feat.refresh_phase2_execution_weights' IN v_date_wrapper)=0
       OR position('daily_price_limit_observations' IN v_evidence_function)=0
       OR position('source=''bsc''' IN v_evidence_function)=0
       OR position('NOT EXISTS' IN v_evidence_function)=0
       OR position('payload_bytes' IN v_evidence_function)=0 THEN
        RAISE EXCEPTION 'execution-weight refresh is not using the batched exact-evidence path';
    END IF;
END;
$phase2_execution_weight_batch_assertions$;

DO $phase2_execution_weight_reentrant_assertion$
DECLARE
    v_first bigint;
    v_second bigint;
BEGIN
    v_first:=feat.refresh_phase2_execution_weights(DATE '1900-01-01',DATE '1900-01-02');
    v_second:=feat.refresh_phase2_execution_weights(DATE '1900-01-01',DATE '1900-01-02');
    IF v_first<>0 OR v_second<>0 THEN
        RAISE EXCEPTION 'empty-range repeatability check unexpectedly updated % then % rows',v_first,v_second;
    END IF;
END;
$phase2_execution_weight_reentrant_assertion$;

DO $phase2_label_input_hash_window_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure
    );
    v_base_definition text := pg_get_functiondef(
        'ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure
    );
BEGIN
    IF position('ops.phase2_label_dependency_watermark()' IN v_definition)=0
       OR position('phase2_label_input_hash_tx_cache_107' IN v_definition)=0
       OR position('CROSS JOIN LATERAL' IN v_definition)>0
       OR position('daily_price_limit_observations' IN v_definition)>0
       OR position('used_limits' IN v_definition)>0 THEN
        RAISE EXCEPTION 'label input hash must use bounded dependency revisions instead of a row-level limit scan';
    END IF;

    IF position('ops.phase2_label_dependency_watermark()' IN v_base_definition)=0
       OR position('FROM feat.features_daily f' IN v_base_definition)>0 THEN
        RAISE EXCEPTION 'label base hash must use the feature revision watermark instead of serializing the feature panel';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_index i
         WHERE i.indexrelid='core.daily_price_limit_observations_symbol_date_source_idx'::regclass
           AND i.indisvalid AND i.indisready
    ) THEN
        RAISE EXCEPTION 'execution-weight refresh still requires the valid symbol/date/source index';
    END IF;
END;
$phase2_label_input_hash_window_assertions$;

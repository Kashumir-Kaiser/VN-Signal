DO $phase2_label_first_date_cache_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
    v_old_marker constant text := 'SELECT v_hash,symbol_id,min(trade_date)';
    v_new_marker constant text := 'SELECT v_hash,s.symbol_id,f.first_date';
BEGIN
    IF position('FROM core.symbols s' IN v_definition)=0
       OR position('CROSS JOIN LATERAL' IN v_definition)=0
       OR position('ORDER BY fd.trade_date' IN v_definition)=0
       OR position('LIMIT 1' IN v_definition)=0
       OR position('AND fd.feature_set_hash=v_hash' IN v_definition)=0 THEN
        RAISE EXCEPTION 'label first-date cache is missing its indexed lookup';
    END IF;

    IF position(v_old_marker IN v_definition)>0
       OR (length(v_definition)-length(replace(v_definition,v_new_marker,'')))<>2*length(v_new_marker) THEN
        RAISE EXCEPTION 'both label first-date cache seeds must use indexed per-symbol lookups';
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM pg_constraint c
         WHERE c.conrelid='feat.features_daily'::regclass
           AND c.confrelid='core.symbols'::regclass
           AND c.contype='f'
           AND c.convalidated
    ) THEN
        RAISE EXCEPTION 'label first-date lookup requires the validated symbol foreign key';
    END IF;
END;
$phase2_label_first_date_cache_assertions$;

-- Keep raw labels tied to the exact current V3 rows, and orient the derived
-- uniform target so larger returns map to larger training targets.
BEGIN;

DO $phase2_label_current_hash_guard$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure
    );
    v_old_anchor constant text := $old$
       AND f.feature_version = 'phase2-v3'
       AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids));$old$;
    v_new_anchor constant text := $new$
       AND f.feature_version = 'phase2-v3'
       AND f.feature_set_hash = v_feature_hash
       AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids));$new$;
BEGIN
    IF position(v_new_anchor IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_anchor,''))<>length(v_new_anchor)
           OR position(v_old_anchor IN v_definition)>0 THEN
            RAISE EXCEPTION 'current-hash raw-label filter is duplicated';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_anchor,''))<>length(v_old_anchor) THEN
            RAISE EXCEPTION 'expected exactly one shared raw-label feature-version filter';
        END IF;
        v_definition:=replace(v_definition,v_old_anchor,v_new_anchor);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_current_hash_guard$;

-- The label input manifest is independent of the feature manifest. Keep
-- features at v3 and invalidate all prior raw-label chunks under v4.
DO $phase2_label_manifest_version$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('ops.phase2_chunk_input_hash(text,date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_anchor constant text := $old$CASE WHEN p_stage IN ('features','labels') THEN '3' ELSE '2' END$old$;
    v_new_anchor constant text := $new$CASE WHEN p_stage='features' THEN '3' WHEN p_stage='labels' THEN '4' ELSE '2' END$new$;
BEGIN
    IF position(v_new_anchor IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_anchor,''))<>length(v_new_anchor)
           OR position(v_old_anchor IN v_definition)>0 THEN
            RAISE EXCEPTION 'versioned feature/label manifest expression is duplicated';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_anchor,''))<>length(v_old_anchor) THEN
            RAISE EXCEPTION 'expected exactly one v3 feature/label manifest expression';
        END IF;
        v_definition:=replace(v_definition,v_old_anchor,v_new_anchor);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_manifest_version$;

COMMENT ON FUNCTION ops.phase2_chunk_input_hash(text,date,date) IS
    'Deterministic Phase 2 input manifest. Feature hashes cover the V3 calendar-year anchor plus its preceding 1,000 effective sessions; V2 feature context begins at the year anchor. Feature manifest domain is v3 and label manifest domain is v4.';

DO $phase2_label_target_orientation$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
    v_old_anchor constant text := 'ORDER BY volatility_scaled_score DESC,symbol_id';
    v_new_anchor constant text := 'ORDER BY volatility_scaled_score ASC,symbol_id';
BEGIN
    IF position(v_new_anchor IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_anchor,''))<>length(v_new_anchor)
           OR position(v_old_anchor IN v_definition)>0 THEN
            RAISE EXCEPTION 'ascending target score rank is duplicated';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_anchor,''))<>length(v_old_anchor) THEN
            RAISE EXCEPTION 'expected exactly one descending target score rank';
        END IF;
        v_definition:=replace(v_definition,v_old_anchor,v_new_anchor);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_target_orientation$;

COMMENT ON COLUMN feat.phase2_label_targets_v3.target_uniform_rank IS
    'Uniform training target within signal_date, horizon_sessions, and liquidity_tier. Scores rank ascending so larger volatility_scaled_score maps to a larger uniform rank and positive Gaussian target; ties break by symbol_id.';

DO $phase2_label_contract_assertions$
DECLARE
    v_label_definition text := pg_get_functiondef(
        'feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure
    );
    v_target_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
    v_manifest_definition text := pg_get_functiondef(
        'ops.phase2_chunk_input_hash(text,date,date)'::regprocedure
    );
    v_manifest_comment text := obj_description(
        'ops.phase2_chunk_input_hash(text,date,date)'::regprocedure,'pg_proc'
    );
BEGIN
    IF position('f.feature_set_hash = v_feature_hash' IN v_label_definition)=0
       OR position($stale$
       AND f.feature_version = 'phase2-v3'
       AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids));$stale$ IN v_label_definition)>0 THEN
        RAISE EXCEPTION 'raw-label builder does not require the current V3 feature hash';
    END IF;
    IF position('ORDER BY volatility_scaled_score ASC,symbol_id' IN v_target_definition)=0
       OR position('ORDER BY volatility_scaled_score DESC,symbol_id' IN v_target_definition)>0 THEN
        RAISE EXCEPTION 'derived label target rank is not oriented with higher score as higher target';
    END IF;
    IF position('CASE WHEN p_stage=''features'' THEN ''3'' WHEN p_stage=''labels'' THEN ''4'' ELSE ''2'' END' IN v_manifest_definition)=0 THEN
        RAISE EXCEPTION 'label input manifest did not advance independently to v4';
    END IF;
    IF position('Feature manifest domain is v3 and label manifest domain is v4.' IN v_manifest_comment)=0 THEN
        RAISE EXCEPTION 'input manifest function comment does not document the independent v3/v4 domains';
    END IF;
END;
$phase2_label_contract_assertions$;

COMMIT;

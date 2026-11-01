BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- The label builder can call this refresh more than once in one transaction.
-- ON COMMIT DROP only clears stages at transaction end, so each invocation
-- must explicitly remove stages left by its preceding invocation.
DO $phase2_execution_weight_reentrant$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_cleanup constant text := $cleanup$
    DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_counts_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_counts_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_sessions_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_windows_102;

$cleanup$;
    v_anchor constant text := '    CREATE TEMP TABLE phase2_weight_windows_102 ON COMMIT DROP AS';
    v_cleanup_marker constant text := 'DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;';
BEGIN
    IF position(v_cleanup_marker IN v_definition)>0 THEN
        -- Replays are safe only when every owned stage is cleared exactly once.
        IF length(v_definition)-length(replace(v_definition,v_cleanup_marker,''))<>length(v_cleanup_marker) THEN
            RAISE EXCEPTION 'execution-weight cleanup block is duplicated';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_anchor,''))<>length(v_anchor) THEN
            RAISE EXCEPTION 'execution-weight stage anchor is missing or duplicated';
        END IF;
        v_definition:=replace(v_definition,v_anchor,v_cleanup||v_anchor);
        EXECUTE v_definition;
    END IF;
END;
$phase2_execution_weight_reentrant$;

DO $phase2_execution_weight_reentrant_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date)'::regprocedure
    );
BEGIN
    IF position('DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_counts_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_counts_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_sessions_102;' IN v_definition)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_windows_102;' IN v_definition)=0 THEN
        RAISE EXCEPTION 'execution-weight stages must be cleared before each invocation';
    END IF;
END;
$phase2_execution_weight_reentrant_assertions$;

COMMIT;

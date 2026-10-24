-- Explicit SQL defaults support offline SQL callers. The runner supplies the
-- validated TOML profile as session overrides captured once per build.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.phase2_execution_weight_defaults (
    policy_version integer PRIMARY KEY CHECK(policy_version=1),
    entry_ceiling_weight double precision NOT NULL CHECK(entry_ceiling_weight>=0 AND entry_ceiling_weight<=1),
    multiple_locked_weight double precision NOT NULL CHECK(multiple_locked_weight>=0 AND multiple_locked_weight<=1)
);
INSERT INTO ops.phase2_execution_weight_defaults VALUES(1,0,0.5)
ON CONFLICT(policy_version) DO NOTHING;

CREATE OR REPLACE FUNCTION ops.phase2_execution_weight_policy()
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_entry double precision;
    v_locked double precision;
BEGIN
    SELECT coalesce(nullif(current_setting('vnpipe.phase2_entry_ceiling_weight',true),'')::double precision,entry_ceiling_weight),
           coalesce(nullif(current_setting('vnpipe.phase2_multiple_locked_weight',true),'')::double precision,multiple_locked_weight)
      INTO STRICT v_entry,v_locked
      FROM ops.phase2_execution_weight_defaults WHERE policy_version=1;
    IF NOT (v_entry>=0 AND v_entry<=1 AND v_locked>=0 AND v_locked<=1) THEN
        RAISE EXCEPTION 'execution weights must be finite values in [0,1]';
    END IF;
    RETURN jsonb_build_object('policy_version',1,'entry_ceiling_weight',v_entry,
                             'multiple_locked_weight',v_locked);
END;
$$;

CREATE OR REPLACE FUNCTION feat.phase2_execution_weight_decision(
    p_complete boolean,p_entry_open numeric,p_entry_limit_up numeric,p_limit_locked_sessions integer
)
RETURNS double precision LANGUAGE sql STABLE AS $$
    SELECT CASE WHEN NOT coalesce(p_complete,false) OR p_entry_open IS NULL
                      OR p_entry_limit_up IS NULL OR p_limit_locked_sessions IS NULL THEN NULL
                WHEN p_entry_open=p_entry_limit_up
                    THEN (ops.phase2_execution_weight_policy()->>'entry_ceiling_weight')::double precision
                WHEN p_limit_locked_sessions>=2
                    THEN (ops.phase2_execution_weight_policy()->>'multiple_locked_weight')::double precision
                ELSE 1::double precision END
$$;

ALTER TABLE feat.phase2_label_targets_v3
    DROP CONSTRAINT IF EXISTS phase2_label_targets_v3_execution_weight_check;
ALTER TABLE feat.phase2_label_targets_v3
    ADD CONSTRAINT phase2_label_targets_v3_execution_weight_check
    CHECK(execution_weight IS NULL OR (execution_weight>=0 AND execution_weight<=1));
ALTER TABLE ops.feature_chunks ADD COLUMN IF NOT EXISTS execution_weight_policy jsonb;
ALTER TABLE ops.step_runs ADD COLUMN IF NOT EXISTS execution_weight_policy jsonb;

DO $policy_hash$
DECLARE
    v_definition text:=pg_get_functiondef('ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure);
    v_anchor text:='||''|exact_limits=''||';
BEGIN
    IF position('ops.phase2_execution_weight_policy()' IN v_definition)>0 THEN RETURN; END IF;
    IF position(v_anchor IN v_definition)=0 THEN
        RAISE EXCEPTION 'execution-policy input-hash anchor missing';
    END IF;
    EXECUTE replace(v_definition,v_anchor,
        '||''|execution_policy=''||ops.phase2_execution_weight_policy()::text||''|exact_limits=''||');
END;
$policy_hash$;
COMMIT;

BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- The runner and the durable label builder call the same exact input-hash
-- function twice in one monthly transaction. Keep the first result only until
-- COMMIT so the second call reuses it without changing the hash contract.
CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_input_hash(
    p_date_from date,
    p_date_to date
)
RETURNS text
LANGUAGE plpgsql VOLATILE AS $phase2_label_input_hash_tx_cache$
DECLARE
    v_feature_hash text;
    v_execution_policy jsonb;
    v_input_hash text;
BEGIN
    v_feature_hash:=feat.phase2_feature_set_hash_v3();
    v_execution_policy:=ops.phase2_execution_weight_policy();

    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RETURN ops.phase2_hash_text(
            ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)
            ||'|execution_policy='||v_execution_policy::text||'|exact_limits='
        );
    END IF;

    IF current_setting('transaction_read_only')<>'on' THEN
        CREATE TEMP TABLE IF NOT EXISTS phase2_label_input_hash_tx_cache_098 (
            date_from date NOT NULL,
            date_to date NOT NULL,
            feature_set_hash text NOT NULL,
            execution_policy jsonb NOT NULL,
            input_hash text NOT NULL,
            PRIMARY KEY(date_from,date_to,feature_set_hash,execution_policy)
        ) ON COMMIT DELETE ROWS;

        SELECT c.input_hash INTO v_input_hash
          FROM pg_temp.phase2_label_input_hash_tx_cache_098 c
         WHERE c.date_from=p_date_from
           AND c.date_to=p_date_to
           AND c.feature_set_hash=v_feature_hash
           AND c.execution_policy=v_execution_policy;
        IF FOUND THEN
            RETURN v_input_hash;
        END IF;
    END IF;

    WITH relevant_windows AS MATERIALIZED (
        SELECT DISTINCT l.symbol_id,l.entry_date,l.exit_date
          FROM feat.labels_daily l
         WHERE l.signal_date BETWEEN p_date_from AND p_date_to
           AND l.label_status='READY'
           AND l.entry_date IS NOT NULL
           AND l.exit_date IS NOT NULL
    ), used_limits AS MATERIALIZED (
        SELECT DISTINCT p.observation_id,p.symbol_id,p.source,p.trade_date,
               p.limit_up,p.limit_down,p.available_at,p.fetched_at,
               p.raw_landing_id,p.source_row,p.row_payload,rl.payload_sha256
          FROM relevant_windows w
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=w.symbol_id AND p.source='vndirect'
           AND p.trade_date BETWEEN w.entry_date AND w.exit_date
          JOIN raw.landings rl ON rl.landing_id=p.raw_landing_id
    )
    SELECT ops.phase2_hash_text(
        ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)
        ||'|execution_policy='||v_execution_policy::text||'|exact_limits='
        ||coalesce((
            SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(p)),''
                             ORDER BY p.trade_date,p.symbol_id,p.observation_id)
              FROM used_limits p
        ),'')
    ) INTO v_input_hash;

    IF current_setting('transaction_read_only')<>'on' THEN
        INSERT INTO pg_temp.phase2_label_input_hash_tx_cache_098(
            date_from,date_to,feature_set_hash,execution_policy,input_hash
        ) VALUES (
            p_date_from,p_date_to,v_feature_hash,v_execution_policy,v_input_hash
        )
        ON CONFLICT(date_from,date_to,feature_set_hash,execution_policy)
        DO UPDATE SET input_hash=EXCLUDED.input_hash;
    END IF;

    RETURN v_input_hash;
END;
$phase2_label_input_hash_tx_cache$;

COMMENT ON FUNCTION ops.phase2_label_target_chunk_input_hash(date,date) IS
    'Exact label input manifest including base features, execution-weight policy, and all linked entry-to-exit price-limit observations. Caches identical calls only within one transaction; output/hash semantics are unchanged.';

DO $phase2_label_input_hash_tx_cache_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure
    );
BEGIN
    IF position('phase2_label_input_hash_tx_cache_098' IN v_definition)=0
       OR position('ON COMMIT DELETE ROWS' IN v_definition)=0
       OR position('c.execution_policy=v_execution_policy' IN v_definition)=0
       OR position('daily_price_limit_observations' IN v_definition)=0
       OR position('ops.phase2_execution_weight_policy()' IN v_definition)=0
       OR position('ops.phase2_label_target_chunk_base_input_hash' IN v_definition)=0 THEN
        RAISE EXCEPTION 'transaction cache must preserve current label input-hash dependencies';
    END IF;
END;
$phase2_label_input_hash_tx_cache_assertions$;

COMMIT;

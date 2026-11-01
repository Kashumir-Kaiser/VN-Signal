-- Execution weights use only exact, source-row-linked VNDIRECT raw bars and
-- archived exact ceiling/floor observations created by migration 062.
BEGIN;

ALTER TABLE feat.phase2_label_targets_v3
    ADD COLUMN IF NOT EXISTS execution_weight double precision
        CHECK(execution_weight IS NULL OR execution_weight IN (0,0.5,1));

CREATE OR REPLACE FUNCTION feat.phase2_execution_weight_decision(
    p_complete boolean,
    p_entry_open numeric,
    p_entry_limit_up numeric,
    p_limit_locked_sessions integer
)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN NOT coalesce(p_complete,false) OR p_entry_open IS NULL OR p_entry_limit_up IS NULL
                      OR p_limit_locked_sessions IS NULL THEN NULL
                WHEN p_entry_open=p_entry_limit_up THEN 0::double precision
                WHEN p_limit_locked_sessions>=2 THEN 0.5::double precision
                ELSE 1::double precision END
$$;

CREATE OR REPLACE FUNCTION feat.phase2_exact_execution_weight(
    p_symbol_id bigint,
    p_entry_date date,
    p_exit_date date
)
RETURNS double precision
LANGUAGE sql STABLE AS $$
    WITH expected AS MATERIALIZED (
        SELECT trade_date
          FROM core.effective_trading_sessions
         WHERE is_session AND trade_date BETWEEN p_entry_date AND p_exit_date
    ), evidence AS MATERIALIZED (
        SELECT s.trade_date,b.landing_id,b.source_row,b.o AS bar_open,b.h AS bar_high,
               b.l AS bar_low,b.c AS bar_close,
               l.limit_up,l.limit_down,
               CASE WHEN jsonb_typeof(l.row_payload->'open')='number'
                    THEN (l.row_payload->>'open')::numeric END AS raw_open,
               CASE WHEN jsonb_typeof(l.row_payload->'high')='number'
                    THEN (l.row_payload->>'high')::numeric END AS raw_high,
               CASE WHEN jsonb_typeof(l.row_payload->'low')='number'
                    THEN (l.row_payload->>'low')::numeric END AS raw_low,
               CASE WHEN jsonb_typeof(l.row_payload->'close')='number'
                    THEN (l.row_payload->>'close')::numeric END AS raw_close,
               rl.payload_sha256
          FROM expected s
          JOIN core.bars_daily_sources_ml_eligible b
            ON b.symbol_id=p_symbol_id AND b.trade_date=s.trade_date AND b.source='vndirect'
           AND b.adj_basis='unadjusted'
          JOIN core.daily_price_limit_observations l
            ON l.symbol_id=b.symbol_id AND l.trade_date=b.trade_date AND l.source='vndirect'
           AND l.raw_landing_id=b.landing_id AND l.source_row=b.source_row
          JOIN raw.landings rl ON rl.landing_id=b.landing_id
           AND rl.source='vndirect' AND rl.route='equity_ohlcv'
           AND rl.payload_sha256 ~ '^[0-9a-f]{64}$'
         WHERE l.available_at=l.fetched_at AND l.fetched_at=rl.fetched_at
           AND jsonb_typeof(l.row_payload)='object'
    ), counts AS (
        SELECT (SELECT count(*) FROM expected) AS expected_count,
               count(*) AS evidenced_count,
               count(*) FILTER (
                   WHERE raw_open=limit_up AND raw_high=limit_up
                     AND raw_low=limit_up AND raw_close=limit_up
                      OR raw_open=limit_down AND raw_high=limit_down
                     AND raw_low=limit_down AND raw_close=limit_down
               ) AS locked_count,
               max(raw_open) FILTER (WHERE trade_date=p_entry_date) AS entry_open,
               max(limit_up) FILTER (WHERE trade_date=p_entry_date) AS entry_limit_up
          FROM evidence
         WHERE raw_open IS NOT NULL AND raw_high IS NOT NULL
           AND raw_low IS NOT NULL AND raw_close IS NOT NULL
           AND limit_up IS NOT NULL AND limit_down IS NOT NULL
           AND bar_open=raw_open AND bar_high=raw_high
           AND bar_low=raw_low AND bar_close=raw_close
    )
    SELECT feat.phase2_execution_weight_decision(
               expected_count>0 AND evidenced_count=expected_count,
               entry_open,entry_limit_up,locked_count::integer
           )
      FROM counts
$$;

CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE v_rows bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF (SELECT count(*) FROM core.effective_trading_sessions
         WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to)>300 THEN
        RAISE EXCEPTION 'execution-weight chunks are limited to 300 sessions';
    END IF;
    UPDATE feat.phase2_label_targets_v3 t
       SET execution_weight=feat.phase2_exact_execution_weight(t.symbol_id,l.entry_date,l.exit_date)
      FROM feat.labels_daily l
     WHERE t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
       AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
       AND t.feature_set_hash=l.feature_set_hash
       AND t.signal_date BETWEEN p_date_from AND p_date_to
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    RETURN v_rows;
END;
$$;

-- Hash every exact limit observation used by labels whose signal dates are in
-- this chunk, including observations after the signal date through exit_date.
CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_input_hash(p_date_from date,p_date_to date)
RETURNS text LANGUAGE sql STABLE AS $$
    WITH relevant_windows AS MATERIALIZED (
        SELECT DISTINCT l.symbol_id,l.entry_date,l.exit_date
          FROM feat.labels_daily l
         WHERE l.signal_date BETWEEN p_date_from AND p_date_to
           AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL
    ), used_limits AS MATERIALIZED (
        SELECT DISTINCT p.observation_id,p.symbol_id,p.source,p.trade_date,p.limit_up,p.limit_down,
               p.available_at,p.fetched_at,p.raw_landing_id,p.source_row,p.row_payload,rl.payload_sha256
          FROM relevant_windows w
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=w.symbol_id AND p.source='vndirect'
           AND p.trade_date BETWEEN w.entry_date AND w.exit_date
          JOIN raw.landings rl ON rl.landing_id=p.raw_landing_id
    )
    SELECT ops.phase2_hash_text(
        ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)||'|exact_limits='||
        coalesce((SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(p)),''
                         ORDER BY p.trade_date,p.symbol_id,p.observation_id) FROM used_limits p),'')
    )
$$;

-- Patch the durable chunk builder so each completed output hash includes the
-- exact execution weight.
DO $phase2_execution_weight_builder_hook$
DECLARE
    v_def text := pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
    v_output_anchor constant text := '    v_output_hash:=ops.phase2_label_targets_chunk_hash(p_date_from,p_date_to);';
    v_output_replacement constant text :=
        '    PERFORM feat.refresh_phase2_execution_weights(p_date_from,p_date_to);'||E'\n'||
        '    v_output_hash:=ops.phase2_label_targets_chunk_hash(p_date_from,p_date_to);';
BEGIN
    IF position(v_output_replacement IN v_def)=0 THEN
        IF length(v_def)-length(replace(v_def,v_output_anchor,''))<>length(v_output_anchor) THEN
            RAISE EXCEPTION 'unexpected derived-target output-hash hook in builder';
        END IF;
        v_def:=replace(v_def,v_output_anchor,v_output_replacement);
    END IF;
    EXECUTE v_def;
END;
$phase2_execution_weight_builder_hook$;

COMMENT ON COLUMN feat.phase2_label_targets_v3.execution_weight IS
    'NULL when any exact raw VNDIRECT bar or archived exact limit evidence is missing; otherwise 0 for entry open at ceiling, 0.5 for at least two fully limit-locked sessions, and 1 otherwise.';
COMMENT ON FUNCTION feat.phase2_exact_execution_weight(bigint,date,date) IS
    'Computes execution weight from complete same-row unadjusted VNDIRECT OHLC and exact archived ceiling/floor observations; never infers a percentage limit.';

COMMIT;

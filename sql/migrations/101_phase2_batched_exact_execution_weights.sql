BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Preserve feat.phase2_exact_execution_weight as the scalar reference, but
-- compute each distinct label window in one set-based pass rather than
-- invoking that multi-join function once for every target row.
CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $phase2_batched_execution_weights$
DECLARE
    v_rows bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF (SELECT count(*) FROM core.effective_trading_sessions
         WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to)>300 THEN
        RAISE EXCEPTION 'execution-weight chunks are limited to 300 sessions';
    END IF;

    WITH target_windows AS MATERIALIZED (
        SELECT DISTINCT t.symbol_id,l.entry_date,l.exit_date
          FROM feat.phase2_label_targets_v3 t
          JOIN feat.labels_daily l
            ON l.symbol_id=t.symbol_id AND l.signal_date=t.signal_date
           AND l.horizon_sessions=t.horizon_sessions AND l.label_version=t.label_version
           AND l.feature_set_hash=t.feature_set_hash
         WHERE t.signal_date BETWEEN p_date_from AND p_date_to
           AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL
    ), expected AS MATERIALIZED (
        SELECT w.symbol_id,w.entry_date,w.exit_date,s.trade_date
          FROM target_windows w
          JOIN core.effective_trading_sessions s
            ON s.is_session AND s.trade_date BETWEEN w.entry_date AND w.exit_date
    ), expected_counts AS MATERIALIZED (
        SELECT e.symbol_id,e.entry_date,e.exit_date,count(*)::bigint AS expected_count
          FROM expected e
         GROUP BY e.symbol_id,e.entry_date,e.exit_date
    ), evidence AS MATERIALIZED (
        SELECT e.symbol_id,e.entry_date,e.exit_date,e.trade_date,
               b.o AS bar_open,b.h AS bar_high,b.l AS bar_low,b.c AS bar_close,
               l.limit_up,l.limit_down,
               CASE WHEN jsonb_typeof(l.row_payload->'open')='number'
                    THEN (l.row_payload->>'open')::numeric END AS raw_open,
               CASE WHEN jsonb_typeof(l.row_payload->'high')='number'
                    THEN (l.row_payload->>'high')::numeric END AS raw_high,
               CASE WHEN jsonb_typeof(l.row_payload->'low')='number'
                    THEN (l.row_payload->>'low')::numeric END AS raw_low,
               CASE WHEN jsonb_typeof(l.row_payload->'close')='number'
                    THEN (l.row_payload->>'close')::numeric END AS raw_close
          FROM expected e
          JOIN core.bars_daily_sources_ml_eligible b
            ON b.symbol_id=e.symbol_id AND b.trade_date=e.trade_date AND b.source='vndirect'
           AND b.adj_basis='unadjusted'
          JOIN core.daily_price_limit_observations l
            ON l.symbol_id=b.symbol_id AND l.trade_date=b.trade_date AND l.source='vndirect'
           AND l.raw_landing_id=b.landing_id AND l.source_row=b.source_row
          JOIN raw.landings rl ON rl.landing_id=b.landing_id
           AND rl.source='vndirect' AND rl.route='equity_ohlcv'
           AND rl.payload_sha256 ~ '^[0-9a-f]{64}$'
         WHERE l.available_at=l.fetched_at AND l.fetched_at=rl.fetched_at
           AND jsonb_typeof(l.row_payload)='object'
    ), valid_evidence AS MATERIALIZED (
        SELECT e.*
          FROM evidence e
         WHERE e.raw_open IS NOT NULL AND e.raw_high IS NOT NULL
           AND e.raw_low IS NOT NULL AND e.raw_close IS NOT NULL
           AND e.limit_up IS NOT NULL AND e.limit_down IS NOT NULL
           AND e.bar_open=e.raw_open AND e.bar_high=e.raw_high
           AND e.bar_low=e.raw_low AND e.bar_close=e.raw_close
    ), aggregated AS MATERIALIZED (
        SELECT w.symbol_id,w.entry_date,w.exit_date,
               coalesce(ec.expected_count,0)::bigint AS expected_count,
               count(e.trade_date)::bigint AS evidenced_count,
               count(*) FILTER (
                   WHERE e.trade_date IS NOT NULL AND (
                       e.raw_open=e.limit_up AND e.raw_high=e.limit_up
                       AND e.raw_low=e.limit_up AND e.raw_close=e.limit_up
                       OR e.raw_open=e.limit_down AND e.raw_high=e.limit_down
                       AND e.raw_low=e.limit_down AND e.raw_close=e.limit_down
                   )
               )::bigint AS locked_count,
               max(e.raw_open) FILTER (WHERE e.trade_date=w.entry_date) AS entry_open,
               max(e.limit_up) FILTER (WHERE e.trade_date=w.entry_date) AS entry_limit_up
          FROM target_windows w
          LEFT JOIN expected_counts ec
            ON ec.symbol_id=w.symbol_id AND ec.entry_date=w.entry_date AND ec.exit_date=w.exit_date
          LEFT JOIN valid_evidence e
            ON e.symbol_id=w.symbol_id AND e.entry_date=w.entry_date AND e.exit_date=w.exit_date
         GROUP BY w.symbol_id,w.entry_date,w.exit_date,ec.expected_count
    ), weights AS MATERIALIZED (
        SELECT a.symbol_id,a.entry_date,a.exit_date,
               feat.phase2_execution_weight_decision(
                   a.expected_count>0 AND a.evidenced_count=a.expected_count,
                   a.entry_open,a.entry_limit_up,a.locked_count::integer
               ) AS execution_weight
          FROM aggregated a
    )
    UPDATE feat.phase2_label_targets_v3 t
       SET execution_weight=w.execution_weight
      FROM feat.labels_daily l
      JOIN weights w ON w.symbol_id=l.symbol_id
                    AND w.entry_date=l.entry_date AND w.exit_date=l.exit_date
     WHERE t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
       AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
       AND t.feature_set_hash=l.feature_set_hash
       AND t.signal_date BETWEEN p_date_from AND p_date_to
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;

    GET DIAGNOSTICS v_rows=ROW_COUNT;
    RETURN v_rows;
END;
$phase2_batched_execution_weights$;

DO $phase2_batched_execution_weights_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date)'::regprocedure
    );
BEGIN
    IF position('target_windows AS MATERIALIZED' IN v_definition)=0
       OR position('valid_evidence AS MATERIALIZED' IN v_definition)=0
       OR position('feat.phase2_exact_execution_weight' IN v_definition)>0
       OR position('phase2_execution_weight_decision' IN v_definition)=0
       OR position('bars_daily_sources_ml_eligible' IN v_definition)=0
       OR position('daily_price_limit_observations' IN v_definition)=0
       OR position('rl.payload_sha256 ~' IN v_definition)=0 THEN
        RAISE EXCEPTION 'execution-weight refresh must preserve exact evidence while batching distinct label windows';
    END IF;
END;
$phase2_batched_execution_weights_assertions$;

COMMIT;

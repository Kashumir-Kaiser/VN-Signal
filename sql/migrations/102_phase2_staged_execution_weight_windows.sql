BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Stage and analyze each set before joining it. PostgreSQL's clone statistics
-- estimate one target row for a full month, so the compact CTE implementation
-- selected a nested-loop comparison of every window with every evidence row.
CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $phase2_staged_execution_weight_windows$
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

    CREATE TEMP TABLE phase2_weight_windows_102 ON COMMIT DROP AS
    SELECT DISTINCT t.symbol_id,l.entry_date,l.exit_date
      FROM feat.phase2_label_targets_v3 t
      JOIN feat.labels_daily l
        ON l.symbol_id=t.symbol_id AND l.signal_date=t.signal_date
       AND l.horizon_sessions=t.horizon_sessions AND l.label_version=t.label_version
       AND l.feature_set_hash=t.feature_set_hash
     WHERE t.signal_date BETWEEN p_date_from AND p_date_to
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;
    CREATE UNIQUE INDEX phase2_weight_windows_102_pk
        ON pg_temp.phase2_weight_windows_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_windows_102;

    CREATE TEMP TABLE phase2_weight_sessions_102 ON COMMIT DROP AS
    SELECT trade_date FROM core.effective_trading_sessions WHERE is_session;
    CREATE UNIQUE INDEX phase2_weight_sessions_102_pk
        ON pg_temp.phase2_weight_sessions_102(trade_date);
    ANALYZE pg_temp.phase2_weight_sessions_102;

    CREATE TEMP TABLE phase2_weight_expected_102 ON COMMIT DROP AS
    SELECT w.symbol_id,w.entry_date,w.exit_date,s.trade_date
      FROM pg_temp.phase2_weight_windows_102 w
      CROSS JOIN LATERAL (
          SELECT s.trade_date
            FROM pg_temp.phase2_weight_sessions_102 s
           WHERE s.trade_date BETWEEN w.entry_date AND w.exit_date
           OFFSET 0
      ) s;
    CREATE UNIQUE INDEX phase2_weight_expected_102_pk
        ON pg_temp.phase2_weight_expected_102(symbol_id,entry_date,exit_date,trade_date);
    CREATE INDEX phase2_weight_expected_102_bar_lookup_idx
        ON pg_temp.phase2_weight_expected_102(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_weight_expected_102;

    CREATE TEMP TABLE phase2_weight_expected_counts_102 ON COMMIT DROP AS
    SELECT symbol_id,entry_date,exit_date,count(*)::bigint AS expected_count
      FROM pg_temp.phase2_weight_expected_102
     GROUP BY symbol_id,entry_date,exit_date;
    CREATE UNIQUE INDEX phase2_weight_expected_counts_102_pk
        ON pg_temp.phase2_weight_expected_counts_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_expected_counts_102;

    CREATE TEMP TABLE phase2_weight_evidence_102 ON COMMIT DROP AS
    SELECT q.symbol_id,q.entry_date,q.exit_date,q.trade_date,
           q.limit_up,q.limit_down,q.raw_open,q.raw_high,q.raw_low,q.raw_close
      FROM (
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
            FROM pg_temp.phase2_weight_expected_102 e
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
      ) q
     WHERE q.raw_open IS NOT NULL AND q.raw_high IS NOT NULL
       AND q.raw_low IS NOT NULL AND q.raw_close IS NOT NULL
       AND q.limit_up IS NOT NULL AND q.limit_down IS NOT NULL
       AND q.bar_open=q.raw_open AND q.bar_high=q.raw_high
       AND q.bar_low=q.raw_low AND q.bar_close=q.raw_close;
    CREATE INDEX phase2_weight_evidence_102_window_idx
        ON pg_temp.phase2_weight_evidence_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_evidence_102;

    CREATE TEMP TABLE phase2_weight_evidence_counts_102 ON COMMIT DROP AS
    SELECT symbol_id,entry_date,exit_date,
           count(*)::bigint AS evidenced_count,
           count(*) FILTER (
               WHERE raw_open=limit_up AND raw_high=limit_up
                 AND raw_low=limit_up AND raw_close=limit_up
                  OR raw_open=limit_down AND raw_high=limit_down
                 AND raw_low=limit_down AND raw_close=limit_down
           )::bigint AS locked_count,
           max(raw_open) FILTER (WHERE trade_date=entry_date) AS entry_open,
           max(limit_up) FILTER (WHERE trade_date=entry_date) AS entry_limit_up
      FROM pg_temp.phase2_weight_evidence_102
     GROUP BY symbol_id,entry_date,exit_date;
    CREATE UNIQUE INDEX phase2_weight_evidence_counts_102_pk
        ON pg_temp.phase2_weight_evidence_counts_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_evidence_counts_102;

    CREATE TEMP TABLE phase2_weight_values_102 ON COMMIT DROP AS
    SELECT w.symbol_id,w.entry_date,w.exit_date,
           feat.phase2_execution_weight_decision(
               coalesce(ec.expected_count,0)>0
                   AND coalesce(vc.evidenced_count,0)=coalesce(ec.expected_count,0),
               vc.entry_open,vc.entry_limit_up,coalesce(vc.locked_count,0)::integer
           ) AS execution_weight
      FROM pg_temp.phase2_weight_windows_102 w
      LEFT JOIN pg_temp.phase2_weight_expected_counts_102 ec
        ON ec.symbol_id=w.symbol_id AND ec.entry_date=w.entry_date AND ec.exit_date=w.exit_date
      LEFT JOIN pg_temp.phase2_weight_evidence_counts_102 vc
        ON vc.symbol_id=w.symbol_id AND vc.entry_date=w.entry_date AND vc.exit_date=w.exit_date;
    CREATE UNIQUE INDEX phase2_weight_values_102_pk
        ON pg_temp.phase2_weight_values_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_values_102;

    UPDATE feat.phase2_label_targets_v3 t
       SET execution_weight=w.execution_weight
      FROM feat.labels_daily l
      JOIN pg_temp.phase2_weight_values_102 w
        ON w.symbol_id=l.symbol_id AND w.entry_date=l.entry_date AND w.exit_date=l.exit_date
     WHERE t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
       AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
       AND t.feature_set_hash=l.feature_set_hash
       AND t.signal_date BETWEEN p_date_from AND p_date_to
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;

    GET DIAGNOSTICS v_rows=ROW_COUNT;
    RETURN v_rows;
END;
$phase2_staged_execution_weight_windows$;

DO $phase2_staged_execution_weight_windows_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date)'::regprocedure
    );
BEGIN
    IF position('CREATE TEMP TABLE phase2_weight_windows_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_expected_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_evidence_102' IN v_definition)=0
       OR position('CREATE TEMP TABLE phase2_weight_values_102' IN v_definition)=0
       OR position('ANALYZE pg_temp.phase2_weight_windows_102' IN v_definition)=0
       OR position('ANALYZE pg_temp.phase2_weight_evidence_102' IN v_definition)=0
       OR position('feat.phase2_exact_execution_weight' IN v_definition)>0
       OR position('phase2_execution_weight_decision' IN v_definition)=0
       OR position('rl.payload_sha256 ~' IN v_definition)=0 THEN
        RAISE EXCEPTION 'execution-weight refresh must stage analyzed windows while preserving exact evidence';
    END IF;
END;
$phase2_staged_execution_weight_windows_assertions$;

COMMIT;

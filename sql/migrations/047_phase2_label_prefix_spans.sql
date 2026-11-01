BEGIN;

-- Build adjustment-factor prefixes only for the current chunk's endpoint
-- window. The previous label builder joined every target to every adjustment
-- row in the same symbol/episode, then applied the date range as a join filter.
CREATE OR REPLACE FUNCTION feat.build_labels_set_based(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    affected bigint;
    v_step_started timestamptz;
    v_step_rows bigint;
    v_label constant text := 'close-next-open-v1';
    v_feature_hash constant text := feat.phase2_feature_set_hash_v3();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;

    PERFORM feat.prepare_phase2_adjustment_rows(false);
    DELETE FROM feat.labels_daily
     WHERE signal_date BETWEEN p_date_from AND p_date_to
       AND label_version = v_label;

    v_step_started := clock_timestamp();
    DROP TABLE IF EXISTS pg_temp.phase2_label_targets;
    CREATE TEMP TABLE phase2_label_targets ON COMMIT DROP AS
    WITH calendar_axis AS MATERIALIZED (
        SELECT trade_date,
               lead(trade_date, 1) OVER (ORDER BY trade_date) AS entry_date,
               lead(trade_date, 6) OVER (ORDER BY trade_date) AS exit_5_date,
               lead(trade_date, 21) OVER (ORDER BY trade_date) AS exit_20_date
          FROM core.effective_trading_sessions
         WHERE is_session
    ), signals AS MATERIALIZED (
        SELECT c.trade_date AS signal_date,
               c.entry_date,
               CASE h.horizon_sessions
                   WHEN 5 THEN c.exit_5_date
                   ELSE c.exit_20_date
               END AS exit_date,
               h.horizon_sessions
          FROM calendar_axis c
          CROSS JOIN (VALUES (5::smallint), (20::smallint)) h(horizon_sessions)
         WHERE c.trade_date BETWEEN p_date_from AND p_date_to
    )
    SELECT f.symbol_id, s.signal_date, s.entry_date, s.exit_date, s.horizon_sessions
      FROM signals s
      JOIN feat.features_daily f
        ON f.trade_date = s.signal_date
       AND f.feature_version = 'phase2-v3';
    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    ALTER TABLE pg_temp.phase2_label_targets
        ADD PRIMARY KEY (symbol_id, signal_date, horizon_sessions);
    CREATE INDEX phase2_label_targets_exit_idx
        ON pg_temp.phase2_label_targets (symbol_id, exit_date);
    ANALYZE pg_temp.phase2_label_targets;
    RAISE NOTICE 'Phase 2 label targets rows %, elapsed %', v_step_rows,
        clock_timestamp() - v_step_started;

    DROP TABLE IF EXISTS pg_temp.phase2_label_latest_exit;
    CREATE TEMP TABLE phase2_label_latest_exit ON COMMIT DROP AS
    SELECT symbol_id, max(exit_date) AS latest_exit_date
      FROM pg_temp.phase2_label_targets
     WHERE exit_date IS NOT NULL
     GROUP BY symbol_id;
    ALTER TABLE pg_temp.phase2_label_latest_exit
        ADD PRIMARY KEY (symbol_id);
    ANALYZE pg_temp.phase2_label_latest_exit;

    v_step_started := clock_timestamp();
    DROP TABLE IF EXISTS pg_temp.phase2_label_endpoint_days;
    CREATE TEMP TABLE phase2_label_endpoint_days ON COMMIT DROP AS
    SELECT symbol_id, entry_date AS trade_date
      FROM pg_temp.phase2_label_targets
     WHERE entry_date IS NOT NULL
    UNION
    SELECT symbol_id, exit_date
      FROM pg_temp.phase2_label_targets
     WHERE exit_date IS NOT NULL;
    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    ALTER TABLE pg_temp.phase2_label_endpoint_days
        ADD PRIMARY KEY (symbol_id, trade_date);
    ANALYZE pg_temp.phase2_label_endpoint_days;
    RAISE NOTICE 'Phase 2 label endpoint days rows %, elapsed %', v_step_rows,
        clock_timestamp() - v_step_started;

    DROP TABLE IF EXISTS pg_temp.phase2_label_endpoint_bounds;
    CREATE TEMP TABLE phase2_label_endpoint_bounds ON COMMIT DROP AS
    SELECT min(trade_date) AS first_endpoint_date,
           max(trade_date) AS last_endpoint_date
      FROM pg_temp.phase2_label_endpoint_days;
    ANALYZE pg_temp.phase2_label_endpoint_bounds;

    v_step_started := clock_timestamp();
    DROP TABLE IF EXISTS pg_temp.phase2_label_adjustment_prefix;
    CREATE TEMP TABLE phase2_label_adjustment_prefix ON COMMIT DROP AS
    SELECT r.symbol_id,
           r.trade_date,
           r.episode_start_date,
           sum(CASE
                   WHEN r.reference_adjustment_ratio > 0
                    AND r.reference_adjustment_ratio < 'Infinity'::double precision
                   THEN ln(r.reference_adjustment_ratio)
                   ELSE 0::double precision
               END) OVER w AS factor_log_prefix,
           count(*) OVER w AS factor_row_prefix,
           count(*) FILTER (
               WHERE r.reference_adjustment_ratio > 0
                 AND r.reference_adjustment_ratio < 'Infinity'::double precision
           ) OVER w AS valid_factor_prefix,
           count(*) FILTER (
               WHERE r.reference_adjustment_ratio IS NULL
                  OR r.reference_adjustment_ratio <= 0
                  OR r.reference_adjustment_ratio >= 'Infinity'::double precision
           ) OVER w AS bad_factor_prefix
      FROM pg_temp.phase2_adjustment_rows r
      CROSS JOIN pg_temp.phase2_label_endpoint_bounds b
     WHERE r.source = 'vndirect'
       AND r.trade_date BETWEEN b.first_endpoint_date AND b.last_endpoint_date
    WINDOW w AS (
        PARTITION BY r.symbol_id, r.episode_start_date
        ORDER BY r.trade_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    );
    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    ALTER TABLE pg_temp.phase2_label_adjustment_prefix
        ADD PRIMARY KEY (symbol_id, trade_date);
    CREATE INDEX phase2_label_adjustment_prefix_episode_idx
        ON pg_temp.phase2_label_adjustment_prefix
           (symbol_id, episode_start_date, trade_date);
    ANALYZE pg_temp.phase2_label_adjustment_prefix;
    RAISE NOTICE 'Phase 2 label adjustment prefix rows %, elapsed %', v_step_rows,
        clock_timestamp() - v_step_started;

    v_step_started := clock_timestamp();
    DROP TABLE IF EXISTS pg_temp.phase2_label_endpoint_bars;
    CREATE TEMP TABLE phase2_label_endpoint_bars ON COMMIT DROP AS
    SELECT r.symbol_id,
           r.trade_date,
           r.model_o,
           r.model_c,
           r.v AS volume,
           r.is_traded,
           r.episode_start_date,
           r.adjustment_vintage_at,
           r.landing_id
      FROM pg_temp.phase2_adjustment_rows r
      JOIN pg_temp.phase2_label_endpoint_days d USING (symbol_id, trade_date)
      CROSS JOIN pg_temp.phase2_label_endpoint_bounds b
     WHERE r.source = 'vndirect'
       AND r.trade_date BETWEEN b.first_endpoint_date AND b.last_endpoint_date;
    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    ALTER TABLE pg_temp.phase2_label_endpoint_bars
        ADD PRIMARY KEY (symbol_id, trade_date);
    ANALYZE pg_temp.phase2_label_endpoint_bars;
    RAISE NOTICE 'Phase 2 label endpoint bars rows %, elapsed %', v_step_rows,
        clock_timestamp() - v_step_started;

    v_step_started := clock_timestamp();
    DROP TABLE IF EXISTS pg_temp.phase2_label_first_bad_factor;
    CREATE TEMP TABLE phase2_label_first_bad_factor ON COMMIT DROP AS
    SELECT r.symbol_id, min(r.trade_date) AS first_bad_date
      FROM pg_temp.phase2_adjustment_rows r
      JOIN pg_temp.phase2_label_latest_exit k
        ON k.symbol_id = r.symbol_id
       AND r.trade_date <= k.latest_exit_date
     WHERE r.source = 'vndirect'
       AND (r.reference_adjustment_ratio IS NULL
            OR r.reference_adjustment_ratio <= 0
            OR r.reference_adjustment_ratio >= 'Infinity'::double precision)
       AND NOT EXISTS (
           SELECT 1
             FROM ops.ml_symbol_scope x
            WHERE x.symbol_id = r.symbol_id
              AND x.scope_status = 'EXCLUDED'
       )
     GROUP BY r.symbol_id;
    GET DIAGNOSTICS v_step_rows = ROW_COUNT;
    ALTER TABLE pg_temp.phase2_label_first_bad_factor
        ADD PRIMARY KEY (symbol_id);
    ANALYZE pg_temp.phase2_label_first_bad_factor;
    RAISE NOTICE 'Phase 2 label first bad factor rows %, elapsed %', v_step_rows,
        clock_timestamp() - v_step_started;

    DROP TABLE IF EXISTS pg_temp.phase2_label_endpoint_targets;
    CREATE TEMP TABLE phase2_label_endpoint_targets ON COMMIT DROP AS
    SELECT t.*,
           en.model_o AS entry_model_open,
           ex.model_c AS exit_model_close,
           en.volume AS entry_volume,
           ex.volume AS exit_volume,
           en.is_traded AS entry_traded,
           ex.is_traded AS exit_traded,
           en.episode_start_date AS entry_episode,
           ex.episode_start_date AS exit_episode,
           en.adjustment_vintage_at AS entry_vintage,
           ex.adjustment_vintage_at AS exit_vintage,
           en.landing_id AS entry_landing_id,
           ex.landing_id AS exit_landing_id,
           en.trade_date AS entry_bar_date,
           ex.trade_date AS exit_bar_date
      FROM pg_temp.phase2_label_targets t
      LEFT JOIN pg_temp.phase2_label_endpoint_bars en
        ON en.symbol_id = t.symbol_id AND en.trade_date = t.entry_date
      LEFT JOIN pg_temp.phase2_label_endpoint_bars ex
        ON ex.symbol_id = t.symbol_id AND ex.trade_date = t.exit_date;
    ALTER TABLE pg_temp.phase2_label_endpoint_targets
        ADD PRIMARY KEY (symbol_id, signal_date, horizon_sessions);
    ANALYZE pg_temp.phase2_label_endpoint_targets;

    DROP TABLE IF EXISTS pg_temp.phase2_label_spans;
    CREATE TEMP TABLE phase2_label_spans ON COMMIT DROP AS
    WITH same_episode AS (
        SELECT t.symbol_id, t.signal_date, t.horizon_sessions,
               CASE
                   WHEN px_exit.valid_factor_prefix - px_entry.valid_factor_prefix > 0
                   THEN px_exit.factor_log_prefix - px_entry.factor_log_prefix
               END AS factor_log_span,
               coalesce(px_exit.factor_row_prefix - px_entry.factor_row_prefix, 0)::bigint AS factor_rows,
               coalesce(px_exit.bad_factor_prefix - px_entry.bad_factor_prefix, 0)::bigint AS bad_factor_rows,
               CASE
                   WHEN px_exit.factor_row_prefix - px_entry.factor_row_prefix > 0
                   THEN true
               END AS one_episode_span
          FROM pg_temp.phase2_label_endpoint_targets t
          LEFT JOIN pg_temp.phase2_label_adjustment_prefix px_entry
            ON px_entry.symbol_id = t.symbol_id
           AND px_entry.trade_date = t.entry_date
           AND px_entry.episode_start_date = t.entry_episode
          LEFT JOIN pg_temp.phase2_label_adjustment_prefix px_exit
            ON px_exit.symbol_id = t.symbol_id
           AND px_exit.trade_date = t.exit_date
           AND px_exit.episode_start_date = t.entry_episode
         WHERE t.entry_bar_date IS NULL
            OR t.exit_date IS NULL
            OR (t.exit_bar_date IS NOT NULL
                AND t.entry_episode IS NOT DISTINCT FROM t.exit_episode)
    ), changed_or_missing_exit AS (
        SELECT t.symbol_id, t.signal_date, t.horizon_sessions,
               CASE
                   WHEN px_exit.valid_factor_prefix - px_entry.valid_factor_prefix > 0
                   THEN px_exit.factor_log_prefix - px_entry.factor_log_prefix
               END AS factor_log_span,
               coalesce(px_exit.factor_row_prefix - px_entry.factor_row_prefix, 0)::bigint AS factor_rows,
               coalesce(px_exit.bad_factor_prefix - px_entry.bad_factor_prefix, 0)::bigint AS bad_factor_rows,
               CASE
                   WHEN px_exit.factor_row_prefix - px_entry.factor_row_prefix > 0
                   THEN true
               END AS one_episode_span
          FROM pg_temp.phase2_label_endpoint_targets t
          LEFT JOIN pg_temp.phase2_label_adjustment_prefix px_entry
            ON px_entry.symbol_id = t.symbol_id
           AND px_entry.trade_date = t.entry_date
           AND px_entry.episode_start_date = t.entry_episode
          LEFT JOIN LATERAL (
              SELECT p.factor_log_prefix, p.factor_row_prefix,
                     p.valid_factor_prefix, p.bad_factor_prefix
                FROM pg_temp.phase2_label_adjustment_prefix p
               WHERE p.symbol_id = t.symbol_id
                 AND p.episode_start_date = t.entry_episode
                 AND p.trade_date > t.entry_date
                 AND p.trade_date <= t.exit_date
               ORDER BY p.trade_date DESC
               LIMIT 1
          ) px_exit ON true
         WHERE t.entry_bar_date IS NOT NULL
           AND t.exit_date IS NOT NULL
           AND (t.exit_bar_date IS NULL
                OR t.entry_episode IS DISTINCT FROM t.exit_episode)
    )
    SELECT * FROM same_episode
    UNION ALL
    SELECT * FROM changed_or_missing_exit;
    ALTER TABLE pg_temp.phase2_label_spans
        ADD PRIMARY KEY (symbol_id, signal_date, horizon_sessions);
    ANALYZE pg_temp.phase2_label_spans;

    WITH index_points AS MATERIALIZED (
        SELECT DISTINCT t.signal_date, t.horizon_sessions, t.entry_date, t.exit_date,
               ie.trade_date AS index_entry_date,
               ix.trade_date AS index_exit_date,
               ie.o AS index_entry_open,
               ix.c AS index_exit_close
          FROM pg_temp.phase2_label_targets t
          LEFT JOIN core.index_bars ie
            ON ie.index_symbol = 'VNINDEX'
           AND ie.source = 'vci'
           AND ie.trade_date = t.entry_date
          LEFT JOIN core.index_bars ix
            ON ix.index_symbol = 'VNINDEX'
           AND ix.source = 'vci'
           AND ix.trade_date = t.exit_date
    ), assembled AS (
        SELECT t.*,
               sp.factor_log_span, sp.factor_rows, sp.bad_factor_rows, sp.one_episode_span,
               fb.first_bad_date,
               ip.index_entry_date, ip.index_exit_date,
               ip.index_entry_open, ip.index_exit_close,
               CASE
                   WHEN t.entry_date IS NULL OR t.exit_date IS NULL THEN 'INSUFFICIENT_SESSIONS'
                   WHEN t.entry_bar_date IS NULL THEN 'MISSING_ENTRY'
                   WHEN t.exit_bar_date IS NULL THEN 'MISSING_EXIT'
                   WHEN fb.first_bad_date IS NOT NULL AND fb.first_bad_date <= t.exit_date
                       THEN 'UNRESOLVED_ADJUSTMENT'
                   WHEN sp.bad_factor_rows > 0 OR sp.factor_log_span IS NULL
                        OR NOT coalesce(sp.one_episode_span, true)
                       THEN 'UNRESOLVED_ADJUSTMENT'
                   WHEN t.entry_episode IS DISTINCT FROM t.exit_episode THEN 'EPISODE_CHANGED'
                   WHEN NOT t.entry_traded OR t.entry_volume <= 0 THEN 'SUSPENDED_ENTRY'
                   WHEN NOT t.exit_traded OR t.exit_volume <= 0 THEN 'SUSPENDED_EXIT'
                   WHEN ip.index_entry_date IS NULL OR ip.index_exit_date IS NULL
                        OR ip.index_entry_open <= 0 OR ip.index_exit_close <= 0
                       THEN 'MISSING_BENCHMARK'
                   ELSE 'READY'
               END AS label_status
          FROM pg_temp.phase2_label_endpoint_targets t
          LEFT JOIN pg_temp.phase2_label_spans sp
            USING (symbol_id, signal_date, horizon_sessions)
          LEFT JOIN pg_temp.phase2_label_first_bad_factor fb
            ON fb.symbol_id = t.symbol_id
          LEFT JOIN index_points ip
            ON ip.signal_date = t.signal_date
           AND ip.horizon_sessions = t.horizon_sessions
    )
    INSERT INTO feat.labels_daily (
        symbol_id, signal_date, horizon_sessions, label_version, feature_set_hash,
        entry_date, exit_date, label_status, stock_return, vnindex_return, excess_return,
        stock_entry_open, stock_exit_close, vnindex_entry_open, vnindex_exit_close,
        price_basis, adjustment_vintage_at, entry_adjustment_vintage_at,
        exit_adjustment_vintage_at, factor_log_span, entry_landing_id, exit_landing_id
    )
    SELECT a.symbol_id, a.signal_date, a.horizon_sessions, v_label, v_feature_hash,
           a.entry_date, a.exit_date, a.label_status,
           CASE WHEN a.label_status = 'READY'
                THEN a.exit_model_close / (a.entry_model_open * exp(a.factor_log_span)) - 1 END,
           CASE WHEN a.label_status = 'READY'
                THEN a.index_exit_close / a.index_entry_open - 1 END,
           CASE WHEN a.label_status = 'READY'
                THEN a.exit_model_close / (a.entry_model_open * exp(a.factor_log_span)) - 1
                     - (a.index_exit_close / a.index_entry_open - 1) END,
           CASE WHEN a.label_status = 'READY'
                THEN a.entry_model_open * exp(a.factor_log_span) END,
           CASE WHEN a.label_status = 'READY' THEN a.exit_model_close END,
           a.index_entry_open, a.index_exit_close, 'adjusted_as_of_exit', a.exit_vintage,
           a.entry_vintage, a.exit_vintage, a.factor_log_span,
           a.entry_landing_id, a.exit_landing_id
      FROM assembled a
    ON CONFLICT (symbol_id, signal_date, horizon_sessions, label_version) DO UPDATE SET
        feature_set_hash = EXCLUDED.feature_set_hash,
        entry_date = EXCLUDED.entry_date,
        exit_date = EXCLUDED.exit_date,
        label_status = EXCLUDED.label_status,
        stock_return = EXCLUDED.stock_return,
        vnindex_return = EXCLUDED.vnindex_return,
        excess_return = EXCLUDED.excess_return,
        stock_entry_open = EXCLUDED.stock_entry_open,
        stock_exit_close = EXCLUDED.stock_exit_close,
        vnindex_entry_open = EXCLUDED.vnindex_entry_open,
        vnindex_exit_close = EXCLUDED.vnindex_exit_close,
        price_basis = EXCLUDED.price_basis,
        adjustment_vintage_at = EXCLUDED.adjustment_vintage_at,
        entry_adjustment_vintage_at = EXCLUDED.entry_adjustment_vintage_at,
        exit_adjustment_vintage_at = EXCLUDED.exit_adjustment_vintage_at,
        factor_log_span = EXCLUDED.factor_log_span,
        entry_landing_id = EXCLUDED.entry_landing_id,
        exit_landing_id = EXCLUDED.exit_landing_id,
        computed_at = now();

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$;

CREATE OR REPLACE FUNCTION feat.build_labels_internal(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $$
BEGIN
    RETURN feat.build_labels_set_based(p_date_from, p_date_to);
END;
$$;

DO $$
DECLARE
    v_def text := pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure);
BEGIN
    IF position('phase2_label_adjustment_prefix' IN v_def) = 0
       OR position('factor_log_prefix' IN v_def) = 0
       OR position('LEFT JOIN adjustment_rows r' IN v_def) > 0 THEN
        RAISE EXCEPTION 'Phase 2 label builder must use cumulative adjustment-factor prefixes';
    END IF;
END;
$$;

COMMIT;

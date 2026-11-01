\set ON_ERROR_STOP on
\pset pager off
WITH ranked_labels AS MATERIALIZED (
    SELECT l.symbol_id, l.signal_date, l.horizon_sessions, l.entry_date, l.exit_date,
           l.label_status, l.factor_log_span, l.stock_return,
           row_number() OVER (
               PARTITION BY l.symbol_id
               ORDER BY abs(l.factor_log_span) DESC, l.signal_date, l.horizon_sessions
           ) AS symbol_rank
      FROM feat.labels_daily l
     WHERE l.label_version = 'close-next-open-v1'
       AND l.feature_set_hash = feat.phase2_feature_set_hash_v3()
       AND l.label_status = 'READY'
       AND l.signal_date BETWEEN DATE '2018-10-01' AND DATE '2019-12-31'
       AND l.factor_log_span IS NOT NULL
       AND l.factor_log_span <> 0
), sample AS MATERIALIZED (
    SELECT symbol_id, signal_date, horizon_sessions, entry_date, exit_date,
           factor_log_span, stock_return
      FROM ranked_labels
     WHERE symbol_rank = 1
     ORDER BY abs(factor_log_span) DESC, symbol_id
     LIMIT 30
), symbol_ids AS MATERIALIZED (
    SELECT array_agg(DISTINCT symbol_id ORDER BY symbol_id) AS ids
      FROM sample
), price_rows AS MATERIALIZED (
    SELECT p.*
      FROM symbol_ids i
      CROSS JOIN LATERAL feat.phase2_vndirect_adjustment_details_for_symbols(i.ids) p
), endpoints AS MATERIALIZED (
    SELECT s.*, en.episode_start_date AS entry_episode,
           en.model_o AS entry_model_open,
           ex.episode_start_date AS exit_episode,
           ex.model_c AS exit_model_close
      FROM sample s
      JOIN price_rows en
        ON en.symbol_id = s.symbol_id
       AND en.trade_date = s.entry_date
       AND en.source = 'vndirect'
      JOIN price_rows ex
        ON ex.symbol_id = s.symbol_id
       AND ex.trade_date = s.exit_date
       AND ex.source = 'vndirect'
), legacy_spans AS (
    SELECT e.symbol_id, e.signal_date, e.horizon_sessions,
           sum(CASE
                   WHEN r.reference_adjustment_ratio > 0
                    AND r.reference_adjustment_ratio < 'Infinity'::double precision
                   THEN ln(r.reference_adjustment_ratio)
               END) AS direct_factor_log_span,
           count(r.trade_date) AS factor_rows,
           count(*) FILTER (
               WHERE r.trade_date IS NOT NULL
                 AND (r.reference_adjustment_ratio IS NULL
                      OR r.reference_adjustment_ratio <= 0
                      OR r.reference_adjustment_ratio >= 'Infinity'::double precision)
           ) AS bad_factor_rows,
           bool_and(r.episode_start_date = e.entry_episode) AS one_episode_span,
           max(e.factor_log_span) AS prefix_factor_log_span,
           max(e.stock_return) AS prefix_stock_return,
           max(e.entry_model_open) AS entry_model_open,
           max(e.exit_model_close) AS exit_model_close
      FROM endpoints e
      LEFT JOIN price_rows r
        ON r.symbol_id = e.symbol_id
       AND r.trade_date > e.entry_date
       AND r.trade_date <= e.exit_date
       AND r.episode_start_date = e.entry_episode
       AND r.source = 'vndirect'
     GROUP BY e.symbol_id, e.signal_date, e.horizon_sessions
), checked_spans AS (
    SELECT *,
           exit_model_close / (entry_model_open * exp(direct_factor_log_span)) - 1
               AS direct_stock_return
      FROM legacy_spans
)
SELECT count(*) AS sampled_labels,
       count(*) FILTER (
           WHERE prefix_factor_log_span IS DISTINCT FROM direct_factor_log_span
       ) AS exact_factor_mismatches,
       max(abs(prefix_factor_log_span - direct_factor_log_span)) AS max_abs_factor_delta,
       count(*) FILTER (
           WHERE prefix_stock_return IS DISTINCT FROM direct_stock_return
       ) AS exact_return_mismatches,
       max(abs(prefix_stock_return - direct_stock_return)) AS max_abs_return_delta,
       count(*) FILTER (WHERE bad_factor_rows > 0 OR NOT one_episode_span) AS invalid_spans
  FROM checked_spans;

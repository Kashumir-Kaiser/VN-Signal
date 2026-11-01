\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET LOCAL statement_timeout = '10min';
SET LOCAL work_mem = '128MB';

CREATE TEMP TABLE phase2_label_parity_symbols ON COMMIT DROP AS
SELECT symbol_id
  FROM core.symbols
 WHERE symbol IN ('HPX', 'DSN', 'AAM', 'GMC', 'TMS');
ALTER TABLE pg_temp.phase2_label_parity_symbols ADD PRIMARY KEY (symbol_id);

CREATE TEMP TABLE phase2_label_parity_prices ON COMMIT DROP AS
SELECT p.*
  FROM feat.phase2_vndirect_adjustment_details_for_symbols(
      (SELECT array_agg(symbol_id ORDER BY symbol_id)
         FROM pg_temp.phase2_label_parity_symbols)
  ) p;
ALTER TABLE pg_temp.phase2_label_parity_prices ADD PRIMARY KEY (symbol_id, trade_date);
CREATE INDEX phase2_label_parity_prices_episode_date_idx
    ON pg_temp.phase2_label_parity_prices (symbol_id, episode_start_date, trade_date);
ANALYZE pg_temp.phase2_label_parity_prices;

WITH sample AS MATERIALIZED (
    SELECT l.symbol_id, l.signal_date, l.horizon_sessions, l.entry_date, l.exit_date,
           l.factor_log_span AS prefix_factor_log_span,
           l.stock_return AS prefix_stock_return
      FROM feat.labels_daily l
      JOIN pg_temp.phase2_label_parity_symbols s USING (symbol_id)
     WHERE l.label_version = 'close-next-open-v1'
       AND l.feature_set_hash = feat.phase2_feature_set_hash_v3()
       AND l.label_status = 'READY'
       AND l.signal_date BETWEEN DATE '2018-10-01' AND DATE '2019-12-31'
), endpoints AS MATERIALIZED (
    SELECT s.*, en.episode_start_date AS entry_episode,
           en.model_o AS entry_model_open,
           ex.model_c AS exit_model_close
      FROM sample s
      JOIN pg_temp.phase2_label_parity_prices en
        ON en.symbol_id = s.symbol_id
       AND en.trade_date = s.entry_date
      JOIN pg_temp.phase2_label_parity_prices ex
        ON ex.symbol_id = s.symbol_id
       AND ex.trade_date = s.exit_date
), direct_spans AS (
    SELECT e.*,
           d.direct_factor_log_span,
           d.factor_rows,
           d.bad_factor_rows,
           d.one_episode_span
      FROM endpoints e
      LEFT JOIN LATERAL (
          SELECT sum(CASE
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
                 bool_and(r.episode_start_date = e.entry_episode) AS one_episode_span
            FROM pg_temp.phase2_label_parity_prices r
           WHERE r.symbol_id = e.symbol_id
             AND r.trade_date > e.entry_date
             AND r.trade_date <= e.exit_date
             AND r.episode_start_date = e.entry_episode
      ) d ON true
), checked AS (
    SELECT *,
           exit_model_close / (entry_model_open * exp(direct_factor_log_span)) - 1
               AS direct_stock_return
      FROM direct_spans
)
SELECT extract(year FROM signal_date)::integer AS year,
       count(*) AS sampled_labels,
       count(*) FILTER (WHERE prefix_factor_log_span <> 0) AS nonzero_factor_labels,
       count(*) FILTER (
           WHERE prefix_factor_log_span IS DISTINCT FROM direct_factor_log_span
       ) AS exact_factor_mismatches,
       max(abs(prefix_factor_log_span - direct_factor_log_span)) AS max_abs_factor_delta,
       count(*) FILTER (
           WHERE prefix_stock_return IS DISTINCT FROM direct_stock_return
       ) AS exact_return_mismatches,
       max(abs(prefix_stock_return - direct_stock_return)) AS max_abs_return_delta,
       count(*) FILTER (WHERE bad_factor_rows > 0 OR NOT one_episode_span) AS invalid_spans
  FROM checked
 GROUP BY extract(year FROM signal_date)::integer
 ORDER BY year;
ROLLBACK;

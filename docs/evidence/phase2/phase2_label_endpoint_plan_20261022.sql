\set ON_ERROR_STOP on
\pset pager off
BEGIN;
SET LOCAL statement_timeout = '3min';
SET LOCAL work_mem = '128MB';
SET LOCAL jit = off;
SET LOCAL random_page_cost = 1.1;

-- Use the bounded 60-symbol cache probe to compare endpoint lookup plans
-- without loading the full market cache or changing durable data.
SELECT * FROM feat.probe_phase2_adjustment_cache(60);

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
           CASE h.horizon_sessions WHEN 5 THEN c.exit_5_date ELSE c.exit_20_date END AS exit_date,
           h.horizon_sessions
      FROM calendar_axis c
      CROSS JOIN (VALUES (5::smallint), (20::smallint)) h(horizon_sessions)
     WHERE c.trade_date BETWEEN DATE '2018-10-01' AND DATE '2018-12-31'
)
SELECT f.symbol_id, s.signal_date, s.entry_date, s.exit_date, s.horizon_sessions
  FROM signals s
  JOIN feat.features_daily f
    ON f.trade_date = s.signal_date
   AND f.feature_version = 'phase2-v3'
  JOIN pg_temp.phase2_adjustment_symbol_batches b USING (symbol_id)
 WHERE b.batch_no = 0;

CREATE TEMP TABLE phase2_label_endpoint_days ON COMMIT DROP AS
SELECT symbol_id, entry_date AS trade_date
  FROM pg_temp.phase2_label_targets
 WHERE entry_date IS NOT NULL
UNION
SELECT symbol_id, exit_date
  FROM pg_temp.phase2_label_targets
 WHERE exit_date IS NOT NULL;
ALTER TABLE pg_temp.phase2_label_endpoint_days ADD PRIMARY KEY (symbol_id, trade_date);
ANALYZE pg_temp.phase2_label_endpoint_days;
CREATE TEMP TABLE phase2_label_latest_exit ON COMMIT DROP AS
SELECT symbol_id, max(exit_date) AS latest_exit_date
  FROM pg_temp.phase2_label_targets
 WHERE exit_date IS NOT NULL
 GROUP BY symbol_id;
ALTER TABLE pg_temp.phase2_label_latest_exit ADD PRIMARY KEY (symbol_id);
ANALYZE pg_temp.phase2_label_latest_exit;

\echo === current endpoint join ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT r.symbol_id, r.trade_date, r.model_o, r.model_c, r.v,
       r.is_traded, r.episode_start_date, r.adjustment_vintage_at, r.landing_id
  FROM pg_temp.phase2_adjustment_rows r
  JOIN pg_temp.phase2_label_endpoint_days d USING (symbol_id, trade_date)
 WHERE r.source = 'vndirect';

\echo === date-bounded endpoint join ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT r.symbol_id, r.trade_date, r.model_o, r.model_c, r.v,
       r.is_traded, r.episode_start_date, r.adjustment_vintage_at, r.landing_id
  FROM pg_temp.phase2_adjustment_rows r
  JOIN pg_temp.phase2_label_endpoint_days d USING (symbol_id, trade_date)
 WHERE r.source = 'vndirect'
   AND r.trade_date BETWEEN
       (SELECT min(trade_date) FROM pg_temp.phase2_label_endpoint_days)
       AND (SELECT max(trade_date) FROM pg_temp.phase2_label_endpoint_days);

\echo === indexed lateral endpoint lookup ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT d.symbol_id, d.trade_date, r.model_o, r.model_c, r.v,
       r.is_traded, r.episode_start_date, r.adjustment_vintage_at, r.landing_id
  FROM pg_temp.phase2_label_endpoint_days d
  JOIN LATERAL (
      SELECT r.model_o, r.model_c, r.v, r.is_traded,
             r.episode_start_date, r.adjustment_vintage_at, r.landing_id
        FROM pg_temp.phase2_adjustment_rows r
       WHERE r.symbol_id = d.symbol_id
         AND r.trade_date = d.trade_date
         AND r.source = 'vndirect'
       LIMIT 1
  ) r ON true;

\echo === full-history adjustment prefixes ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT r.symbol_id, r.trade_date, r.episode_start_date,
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
 WHERE r.source = 'vndirect'
WINDOW w AS (
    PARTITION BY r.symbol_id, r.episode_start_date
    ORDER BY r.trade_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
);

\echo === chunk-window adjustment prefixes ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
SELECT r.symbol_id, r.trade_date, r.episode_start_date,
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
 WHERE r.source = 'vndirect'
   AND r.trade_date BETWEEN
       (SELECT min(trade_date) FROM pg_temp.phase2_label_endpoint_days)
       AND (SELECT max(trade_date) FROM pg_temp.phase2_label_endpoint_days)
WINDOW w AS (
    PARTITION BY r.symbol_id, r.episode_start_date
    ORDER BY r.trade_date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
);

\echo === first invalid factor by symbol ===
EXPLAIN (ANALYZE, BUFFERS, SETTINGS, SUMMARY)
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
       SELECT 1 FROM ops.ml_symbol_scope x
        WHERE x.symbol_id = r.symbol_id AND x.scope_status = 'EXCLUDED'
   )
 GROUP BY r.symbol_id;
ROLLBACK;

\set ON_ERROR_STOP on
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout='30min';
SET LOCAL temp_file_limit='90GB';
SET LOCAL work_mem='128MB';
SET LOCAL jit=off;
SET LOCAL synchronous_commit=off;
SET LOCAL random_page_cost=1.1;
SET LOCAL vnpipe.phase2_symbol_batch_size='60';
SET LOCAL vnpipe.phase2_cache_time_budget_minutes='40';
SET LOCAL application_name='phase2_label_factor_probe_2023';
SELECT * FROM feat.probe_phase2_adjustment_cache(15);
SELECT * FROM feat.probe_phase2_adjustment_cache(30);
SELECT * FROM feat.probe_phase2_adjustment_cache(60);
-- Repeat after the first pass warms local PostgreSQL data pages; the cache probe
-- assertion consumes the most recent duration for each size.
SELECT * FROM feat.probe_phase2_adjustment_cache(15);
SELECT * FROM feat.probe_phase2_adjustment_cache(30);
SELECT * FROM feat.probe_phase2_adjustment_cache(60);
SELECT feat.assert_phase2_adjustment_cache_scaling();
SELECT feat.begin_phase2_adjustment_rows(60);
SELECT format('SELECT feat.populate_phase2_adjustment_rows(%s);',batch_no)
FROM (SELECT DISTINCT batch_no FROM pg_temp.phase2_adjustment_symbol_batches ORDER BY batch_no) batches
\gexec
SELECT feat.finish_phase2_adjustment_rows();
SELECT count(*) AS cached_adjustment_rows FROM pg_temp.phase2_adjustment_rows;

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
     WHERE c.trade_date BETWEEN DATE '2023-01-01' AND DATE '2023-12-31'
)
SELECT f.symbol_id, s.signal_date, s.entry_date, s.exit_date, s.horizon_sessions
  FROM signals s
  JOIN feat.features_daily f
    ON f.trade_date=s.signal_date
   AND f.feature_version='phase2-v3';
ALTER TABLE pg_temp.phase2_label_targets
    ADD PRIMARY KEY (symbol_id,signal_date,horizon_sessions);
CREATE INDEX phase2_label_targets_exit_idx
    ON pg_temp.phase2_label_targets(symbol_id,exit_date);
ANALYZE pg_temp.phase2_label_targets;

DROP TABLE IF EXISTS pg_temp.phase2_label_latest_exit;
CREATE TEMP TABLE phase2_label_latest_exit ON COMMIT DROP AS
SELECT symbol_id,max(exit_date) AS latest_exit_date
  FROM pg_temp.phase2_label_targets
 WHERE exit_date IS NOT NULL
 GROUP BY symbol_id;
ALTER TABLE pg_temp.phase2_label_latest_exit ADD PRIMARY KEY(symbol_id);
ANALYZE pg_temp.phase2_label_latest_exit;

SET LOCAL application_name='phase2_label_factor_probe_scan';
SET LOCAL enable_nestloop=off;
EXPLAIN (ANALYZE,BUFFERS,VERBOSE,TIMING OFF,SUMMARY ON)
SELECT r.symbol_id,min(r.trade_date) AS first_bad_date
  FROM pg_temp.phase2_adjustment_rows r
  JOIN pg_temp.phase2_label_latest_exit k
    ON k.symbol_id=r.symbol_id AND r.trade_date<=k.latest_exit_date
 WHERE r.source='vndirect'
   AND (r.reference_adjustment_ratio IS NULL
        OR r.reference_adjustment_ratio<=0
        OR r.reference_adjustment_ratio>='Infinity'::double precision)
   AND NOT EXISTS (
       SELECT 1 FROM ops.ml_symbol_scope x
        WHERE x.symbol_id=r.symbol_id AND x.scope_status='EXCLUDED')
 GROUP BY r.symbol_id;
SELECT s.symbol, r.symbol_id, r.trade_date, r.reference_adjustment_ratio,
       r.landing_id, r.source_row, r.fetched_at
  FROM pg_temp.phase2_adjustment_rows r
  JOIN pg_temp.phase2_label_latest_exit k
    ON k.symbol_id=r.symbol_id AND r.trade_date<=k.latest_exit_date
  JOIN core.symbols s ON s.symbol_id=r.symbol_id
 WHERE r.source='vndirect'
   AND (r.reference_adjustment_ratio IS NULL
        OR r.reference_adjustment_ratio<=0
        OR r.reference_adjustment_ratio>='Infinity'::double precision)
   AND NOT EXISTS (
       SELECT 1 FROM ops.ml_symbol_scope x
        WHERE x.symbol_id=r.symbol_id AND x.scope_status='EXCLUDED')
 ORDER BY r.symbol_id,r.trade_date
 LIMIT 20;
ROLLBACK;

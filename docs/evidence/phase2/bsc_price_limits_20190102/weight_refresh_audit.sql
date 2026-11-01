\set ON_ERROR_STOP on

-- Post-import audit for the exact Jan 2, 2019 BSC fallback observation.
-- BSC limits are accepted only where the source row and archived VNDIRECT bar
-- match exactly; this report does not impute missing evidence or weights.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '2min';
SET LOCAL work_mem = '8MB';
DO $$ BEGIN
  IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
    RAISE EXCEPTION 'audit is restricted to vnsignal_phase2_report_20261019';
  END IF;
END $$;

WITH bsc AS (
  SELECT DISTINCT symbol_id
    FROM core.daily_price_limit_observations
   WHERE source='bsc' AND trade_date=DATE '2019-01-02'
), windows AS (
  SELECT l.symbol_id,l.signal_date,l.horizon_sessions,l.entry_date,l.exit_date,
         t.execution_weight,(b.symbol_id IS NOT NULL) AS has_bsc_limit
    FROM feat.labels_daily l
    JOIN feat.phase2_label_targets_v3 t
      ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
     AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
     AND t.feature_set_hash=l.feature_set_hash
    LEFT JOIN bsc b ON b.symbol_id=l.symbol_id
   WHERE l.label_status='READY'
     AND l.feature_set_hash=feat.phase2_feature_set_hash_v3()
     AND l.signal_date BETWEEN DATE '2018-11-30' AND DATE '2018-12-28'
     AND l.entry_date<=DATE '2019-01-02' AND l.exit_date>=DATE '2019-01-02'
)
SELECT 'bsc_observations' AS metric,
       count(*)::text AS value
  FROM core.daily_price_limit_observations
 WHERE source='bsc' AND trade_date=DATE '2019-01-02'
UNION ALL
SELECT 'bsc_symbols',count(DISTINCT symbol_id)::text FROM bsc
UNION ALL
SELECT 'affected_current_hash_windows',count(*)::text FROM windows
UNION ALL
SELECT 'windows_with_exact_bsc_observation',count(*) FILTER (WHERE has_bsc_limit)::text FROM windows
UNION ALL
SELECT 'windows_without_exact_bsc_observation',count(*) FILTER (WHERE NOT has_bsc_limit)::text FROM windows
UNION ALL
SELECT 'windows_with_non_null_execution_weight',count(*) FILTER (WHERE execution_weight IS NOT NULL)::text FROM windows
UNION ALL
SELECT 'windows_with_null_execution_weight',count(*) FILTER (WHERE execution_weight IS NULL)::text FROM windows
UNION ALL
SELECT 'bsc_observation_but_null_weight',count(*) FILTER (WHERE has_bsc_limit AND execution_weight IS NULL)::text FROM windows
UNION ALL
SELECT 'no_bsc_observation_but_non_null_weight',count(*) FILTER (WHERE NOT has_bsc_limit AND execution_weight IS NOT NULL)::text FROM windows;

WITH bsc AS (
  SELECT DISTINCT symbol_id
    FROM core.daily_price_limit_observations
   WHERE source='bsc' AND trade_date=DATE '2019-01-02'
)
SELECT l.signal_date,l.horizon_sessions,count(*) AS affected_targets,
       count(*) FILTER (WHERE t.execution_weight IS NULL) AS null_weight_after_refresh,
       count(*) FILTER (WHERE t.execution_weight IS NOT NULL) AS nonnull_weight_after_refresh
  FROM feat.labels_daily l
  JOIN feat.phase2_label_targets_v3 t
    ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
   AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
   AND t.feature_set_hash=l.feature_set_hash
 WHERE l.label_status='READY' AND l.feature_set_hash=feat.phase2_feature_set_hash_v3()
   AND l.signal_date BETWEEN DATE '2018-11-30' AND DATE '2018-12-28'
   AND l.entry_date<=DATE '2019-01-02' AND l.exit_date>=DATE '2019-01-02'
 GROUP BY l.signal_date,l.horizon_sessions
 ORDER BY l.signal_date,l.horizon_sessions;

WITH bsc AS (
  SELECT DISTINCT symbol_id
    FROM core.daily_price_limit_observations
   WHERE source='bsc' AND trade_date=DATE '2019-01-02'
)
SELECT s.symbol,count(*) AS unresolved_windows
  FROM feat.labels_daily l
  JOIN feat.phase2_label_targets_v3 t
    ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
   AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
   AND t.feature_set_hash=l.feature_set_hash
  JOIN core.symbols s ON s.symbol_id=l.symbol_id
  LEFT JOIN bsc b ON b.symbol_id=l.symbol_id
 WHERE l.label_status='READY' AND l.feature_set_hash=feat.phase2_feature_set_hash_v3()
   AND l.signal_date BETWEEN DATE '2018-11-30' AND DATE '2018-12-28'
   AND l.entry_date<=DATE '2019-01-02' AND l.exit_date>=DATE '2019-01-02'
   AND b.symbol_id IS NULL AND t.execution_weight IS NULL
 GROUP BY s.symbol
 ORDER BY s.symbol;

COMMIT;

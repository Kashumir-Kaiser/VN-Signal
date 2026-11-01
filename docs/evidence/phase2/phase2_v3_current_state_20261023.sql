\set ON_ERROR_STOP on
\pset pager off

-- Read-only current execution and V3 state check. The guard restricts this
-- snapshot to the disposable report clone named in the Phase 2 evidence.
DO $$
BEGIN
    IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'refusing current-state audit outside the disposable report clone';
    END IF;
END;
$$;

SELECT now() AS observed_at,
       current_database() AS database_name,
       pid,
       state,
       wait_event_type,
       wait_event,
       now() - xact_start AS transaction_age,
       left(query, 160) AS query
  FROM pg_stat_activity
 WHERE datname = current_database()
   AND pid <> pg_backend_pid()
   AND state <> 'idle'
 ORDER BY pid;

SELECT feature_version,
       count(*) AS rows,
       min(trade_date) AS first_date,
       max(trade_date) AS last_date,
       count(DISTINCT feature_set_hash) AS distinct_feature_hashes
  FROM feat.features_daily
 GROUP BY feature_version
 ORDER BY feature_version;

SELECT feature_set_hash,
       count(*) AS rows,
       min(trade_date) AS first_date,
       max(trade_date) AS last_date
  FROM feat.features_daily
 WHERE feature_version = 'phase2-v3'
 GROUP BY feature_set_hash
 ORDER BY rows DESC, feature_set_hash;

SELECT relation_name,
       pg_size_pretty(pg_relation_size(relation_oid)) AS relation_size,
       reltuples::bigint AS estimated_rows
  FROM (
      SELECT c.oid AS relation_oid,
             c.relname AS relation_name,
             c.reltuples
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'feat'
         AND c.relname IN ('features_daily', 'labels_daily',
                           'phase2_label_targets_v3', 'phase2_liquidity_tiers_v3')
  ) relations
 ORDER BY relation_name;

SELECT to_regclass('feat.phase2_label_targets_v3') AS derived_label_targets,
       to_regclass('feat.phase2_liquidity_tiers_v3') AS liquidity_tiers,
       to_regprocedure('feat.build_phase2_label_targets_v3(date,date)') AS derived_label_builder;

SELECT temp_files,
       temp_bytes,
       stats_reset
  FROM pg_stat_database
 WHERE datname = current_database();

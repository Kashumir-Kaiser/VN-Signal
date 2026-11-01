-- Read-only post-backfill PIT fundamentals census.
-- Restricted to the disposable report clone; no rows are written.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '2min';
DO $$ BEGIN
    IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'census is restricted to vnsignal_phase2_report_20261019';
    END IF;
END $$;

SELECT 'archive_managed_rows' AS metric, count(*) AS value
  FROM core.fundamentals_pit WHERE archive_managed
UNION ALL SELECT 'symbols',count(DISTINCT symbol_id)
  FROM core.fundamentals_pit WHERE archive_managed
UNION ALL SELECT 'observations',count(*)
  FROM core.fundamentals_pit_observations
UNION ALL SELECT 'raw_fundamental_landings',count(*)
  FROM raw.landings WHERE route LIKE 'fundamental.equity.%'
UNION ALL SELECT 'daily_overlay_rows',count(*)
  FROM feat.fundamental_features_daily
UNION ALL SELECT 'line_item_mappings',count(*)
  FROM feat.fundamental_line_item_map
UNION ALL SELECT 'active_line_item_mappings',count(*)
  FROM feat.fundamental_line_item_map WHERE active
UNION ALL SELECT 'industry_mappings',count(*)
  FROM feat.fundamental_industry_class_map
ORDER BY metric;

SELECT statement_type,period_type,count(*) AS row_versions,
       count(DISTINCT symbol_id) AS symbols,
       count(DISTINCT (symbol_id,period_end)) AS symbol_periods,
       min(period_end) AS first_period_end,max(period_end) AS last_period_end
  FROM core.fundamentals_pit
 WHERE archive_managed
 GROUP BY statement_type,period_type
 ORDER BY statement_type,period_type;

SELECT count(*) AS availability_contract_violations
  FROM core.fundamentals_pit f
 WHERE f.archive_managed AND (
       f.statement_type NOT IN ('income_statement','balance_sheet','cash_flow')
    OR f.line_level IS DISTINCT FROM 1
    OR f.first_seen_at IS DISTINCT FROM f.fetched_at
    OR f.last_seen_at IS NULL OR f.last_seen_at < f.first_seen_at
    OR (f.availability_basis='assumed_backfill_lag' AND
        (f.availability_is_assumed IS DISTINCT FROM true OR
         f.available_at IS DISTINCT FROM
           ((f.period_end + CASE f.period_type WHEN 'quarter' THEN 45 ELSE 100 END)::timestamp
             AT TIME ZONE 'Asia/Ho_Chi_Minh')))
    OR (f.availability_basis='observed_ingestion' AND
        (f.availability_is_assumed IS DISTINCT FROM false OR
         f.available_at IS DISTINCT FROM f.fetched_at))
    OR f.availability_basis IS NULL
    OR f.availability_basis NOT IN ('assumed_backfill_lag','observed_ingestion')
 );

SELECT count(*) AS same_availability_duplicate_groups
  FROM (
    SELECT symbol_id,source,statement_type,period_type,period_end,row_id,available_at
      FROM core.fundamentals_pit
     WHERE archive_managed
     GROUP BY symbol_id,source,statement_type,period_type,period_end,row_id,available_at
    HAVING count(*) > 1
  ) duplicates;

SELECT count(*) AS snapshots_with_missing_or_invalid_observation_lineage
  FROM core.fundamentals_pit f
 WHERE f.archive_managed AND (
       NOT EXISTS (
           SELECT 1 FROM core.fundamentals_pit_observations o
            WHERE o.snapshot_id=f.snapshot_id
       )
       OR EXISTS (
           SELECT 1
             FROM core.fundamentals_pit_observations o
             LEFT JOIN raw.landings l ON l.landing_id=o.raw_landing_id
            WHERE o.snapshot_id=f.snapshot_id AND (
                   l.landing_id IS NULL
                OR o.source IS DISTINCT FROM l.source
                OR o.ingest_id IS DISTINCT FROM l.ingest_id
                OR o.fetched_at IS DISTINCT FROM l.fetched_at
                OR CASE WHEN jsonb_typeof(l.payload->'rows')='array' THEN
                     o.source_row < 0
                     OR o.source_row >= jsonb_array_length(l.payload->'rows')
                     OR o.row_payload IS DISTINCT FROM l.payload->'rows'->o.source_row
                   ELSE true END
            )
       )
 );

SELECT route,state,count(*) AS jobs,sum(attempts) AS attempts
  FROM ops.ingest_jobs
 WHERE idempotency_key LIKE 'fundamental:%'
 GROUP BY route,state
 ORDER BY route,state;

COMMIT;

-- Current-hash PIT coverage by symbol and observation-to-landing integrity.
-- Read-only: run against the disposable report clone after the final V3 build.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5min';
SET LOCAL work_mem = '8MB';

DO $$ BEGIN
  IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
    RAISE EXCEPTION 'diagnostic is restricted to vnsignal_phase2_report_20261019';
  END IF;
END $$;

SELECT feat.phase2_feature_set_hash_v3() AS feature_set_hash,
       count(*) AS current_hash_symbol_dates,
       count(DISTINCT f.symbol_id) AS symbols,
       min(f.trade_date) AS first_trade_date,
       max(f.trade_date) AS last_trade_date
FROM feat.features_daily f
WHERE f.feature_version='phase2-v3'
  AND f.feature_set_hash=feat.phase2_feature_set_hash_v3();

-- Per-symbol PIT coverage. Statement availability is evaluated at the local
-- signal cutoff. This counts distinct statement families; it does not map line
-- items into financial metrics or prove historical public timestamps.
WITH scope AS MATERIALIZED (
  SELECT f.symbol_id,f.trade_date,
         (f.trade_date::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh' AS cutoff
  FROM feat.features_daily f
  WHERE f.feature_version='phase2-v3'
    AND f.feature_set_hash=feat.phase2_feature_set_hash_v3()
), available AS (
  SELECT sc.symbol_id,sc.trade_date,
         count(DISTINCT p.statement_type) AS statement_types,
         count(DISTINCT (p.statement_type,p.period_type,p.period_end)) AS statement_periods,
         bool_and(p.availability_is_assumed) AS all_availability_assumed
  FROM scope sc
  JOIN core.fundamentals_pit p
    ON p.symbol_id=sc.symbol_id AND p.archive_managed
   AND p.period_end<=sc.trade_date AND p.available_at<=sc.cutoff
  GROUP BY sc.symbol_id,sc.trade_date
)
SELECT sym.symbol,
       count(*) AS current_hash_symbol_dates,
       count(*) FILTER (WHERE a.statement_types=3) AS dates_with_all_three_statement_types,
       count(*) FILTER (WHERE a.symbol_id IS NOT NULL) AS dates_with_any_pit_statement,
       max(a.statement_types) AS max_statement_types_available,
       max(a.statement_periods) AS max_statement_periods_available,
       count(*) FILTER (WHERE a.symbol_id IS NOT NULL AND a.all_availability_assumed) AS dates_using_only_assumed_availability
FROM scope sc
JOIN core.symbols sym USING(symbol_id)
LEFT JOIN available a USING(symbol_id,trade_date)
GROUP BY sym.symbol
HAVING count(*) FILTER (WHERE a.symbol_id IS NOT NULL)>0
ORDER BY sym.symbol;

-- Archive footprint by symbol/source and each observation's owning capture.
SELECT sym.symbol,p.source,
       count(DISTINCT p.snapshot_id) AS line_versions,
       count(DISTINCT (p.statement_type,p.period_type,p.period_end)) AS statement_periods,
       min(p.period_end) AS first_period_end,
       max(p.period_end) AS last_period_end,
       count(DISTINCT o.observation_id) AS observations,
       count(DISTINCT p.snapshot_id) FILTER (WHERE p.availability_is_assumed) AS versions_with_assumed_availability,
       count(DISTINCT p.snapshot_id) FILTER (WHERE p.restated) AS restated_versions
FROM core.fundamentals_pit p
JOIN core.symbols sym USING(symbol_id)
LEFT JOIN core.fundamentals_pit_observations o USING(snapshot_id)
WHERE p.archive_managed
GROUP BY sym.symbol,p.source
ORDER BY sym.symbol,p.source;

-- A repeat observation may use a newer landing than the immutable snapshot's
-- original landing. Validate each observation against its own landing and
-- source-row ordinal instead of requiring it to equal snapshot.raw_landing_id.
WITH observation_checks AS (
  SELECT o.observation_id,o.snapshot_id,o.raw_landing_id,o.source,o.ingest_id,
         o.fetched_at,o.source_row,o.row_payload,
         l.landing_id AS matched_landing_id,l.source AS landing_source,
         l.ingest_id AS landing_ingest_id,l.fetched_at AS landing_fetched_at,
         CASE WHEN jsonb_typeof(l.payload->'rows')='array' THEN
                o.source_row>=0
                AND o.source_row<jsonb_array_length(l.payload->'rows')
                AND o.row_payload=l.payload->'rows'->o.source_row
              ELSE false END AS exact_source_row_match
  FROM core.fundamentals_pit_observations o
  JOIN core.fundamentals_pit p USING(snapshot_id)
  LEFT JOIN raw.landings l ON l.landing_id=o.raw_landing_id
  WHERE p.archive_managed
), version_checks AS (
  SELECT p.snapshot_id
  FROM core.fundamentals_pit p
  WHERE p.archive_managed
    AND NOT EXISTS (
      SELECT 1 FROM core.fundamentals_pit_observations o
      WHERE o.snapshot_id=p.snapshot_id
    )
)
SELECT (SELECT count(*) FROM core.fundamentals_pit WHERE archive_managed) AS archive_versions,
       (SELECT count(*) FROM core.fundamentals_pit_observations o
         JOIN core.fundamentals_pit p USING(snapshot_id) WHERE p.archive_managed) AS observations,
       (SELECT count(*) FROM version_checks) AS versions_without_observation,
       count(*) FILTER (WHERE matched_landing_id IS NULL) AS observations_without_landing,
       count(*) FILTER (WHERE source IS DISTINCT FROM landing_source) AS source_mismatches,
       count(*) FILTER (WHERE ingest_id IS DISTINCT FROM landing_ingest_id) AS ingest_id_mismatches,
       count(*) FILTER (WHERE fetched_at IS DISTINCT FROM landing_fetched_at) AS fetch_time_mismatches,
       count(*) FILTER (WHERE NOT exact_source_row_match) AS exact_source_row_mismatches
FROM observation_checks;

SELECT count(*) AS overlay_rows,
       count(DISTINCT symbol_id) AS overlay_symbols,
       count(*) FILTER (WHERE mapping_hash IS NOT NULL) AS rows_with_mapping_hash
FROM feat.fundamental_features_daily
WHERE feature_version='fundamental-overlay-v1';

COMMIT;

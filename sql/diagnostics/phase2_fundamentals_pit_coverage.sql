-- Read-only Phase 2 PIT archive coverage and chunk-state report.
-- Run against the disposable report clone only, after E4's chunk driver exits.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '5min';

-- Archive totals, symbol/period coverage, and observation-time spans.
SELECT
    CASE WHEN f.archive_managed THEN 'archive_managed' ELSE 'legacy_unmanaged' END AS archive_class,
    f.source,
    f.statement_type,
    f.period_type,
    count(*) AS row_versions,
    count(DISTINCT f.symbol_id) AS symbols,
    count(DISTINCT (f.symbol_id, f.period_end)) AS symbol_periods,
    count(DISTINCT f.period_end) AS distinct_period_ends,
    min(f.period_end) AS first_period_end,
    max(f.period_end) AS last_period_end,
    min(f.first_seen_at) AS first_observed_at,
    max(f.last_seen_at) AS last_observed_at,
    min(f.available_at) AS first_available_at,
    max(f.available_at) AS last_available_at,
    count(*) FILTER (WHERE f.restated) AS restated_versions,
    count(*) FILTER (WHERE f.availability_is_assumed) AS assumed_availability_rows
FROM core.fundamentals_pit f
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4;

-- Per-source and statement type: explicit coverage by period, with archive rows only.
SELECT
    f.source, f.statement_type, f.period_type,
    count(DISTINCT f.symbol_id) AS symbols,
    count(DISTINCT f.period_end) AS distinct_period_ends,
    min(f.period_end) AS first_period_end,
    max(f.period_end) AS last_period_end,
    count(DISTINCT (f.symbol_id, f.period_end)) AS symbol_periods,
    count(DISTINCT (f.symbol_id, f.period_end, f.row_id)) AS logical_lines,
    count(*) AS row_versions
FROM core.fundamentals_pit f
WHERE f.archive_managed
GROUP BY f.source, f.statement_type, f.period_type
ORDER BY f.source, f.statement_type, f.period_type;

-- Check archive rows against the PIT availability contract; zero rows is clean.
SELECT f.snapshot_id, s.symbol, f.source, f.statement_type, f.period_type,
       f.period_end, f.row_id, f.availability_basis, f.available_at,
       f.first_seen_at, f.fetched_at, f.line_level
FROM core.fundamentals_pit f
JOIN core.symbols s USING (symbol_id)
WHERE f.archive_managed AND (
       f.statement_type NOT IN ('income_statement','balance_sheet','cash_flow')
    OR f.line_level IS DISTINCT FROM 1
    OR f.first_seen_at IS DISTINCT FROM f.fetched_at
    OR f.last_seen_at IS NULL OR f.last_seen_at < f.first_seen_at
    OR (f.availability_basis = 'assumed_backfill_lag' AND
        (f.availability_is_assumed IS DISTINCT FROM true OR
         f.available_at IS DISTINCT FROM
           ((f.period_end + CASE f.period_type WHEN 'quarter' THEN 45 ELSE 100 END)::timestamp
             AT TIME ZONE 'Asia/Ho_Chi_Minh')))
    OR (f.availability_basis = 'observed_ingestion' AND
        (f.availability_is_assumed IS DISTINCT FROM false OR
         f.available_at IS DISTINCT FROM f.fetched_at))
    OR f.availability_basis IS NULL
    OR f.availability_basis NOT IN ('assumed_backfill_lag','observed_ingestion')
)
ORDER BY f.snapshot_id
LIMIT 200;

-- Logical keys with multiple versions are expected when restated; this lists
-- same-availability collisions, which deserve review because as-of tie-breaking
-- otherwise falls through to snapshot_id.
SELECT f.source, f.symbol_id, f.statement_type, f.period_type,
       f.period_end, f.row_id, f.available_at,
       count(*) AS versions_at_same_availability,
       array_agg(f.snapshot_id ORDER BY f.snapshot_id) AS snapshot_ids
FROM core.fundamentals_pit f
WHERE f.archive_managed
GROUP BY f.source, f.symbol_id, f.statement_type, f.period_type,
         f.period_end, f.row_id, f.available_at
HAVING count(*) > 1
ORDER BY f.available_at, f.symbol_id, f.statement_type, f.period_end, f.row_id
LIMIT 200;

-- Version depth by logical source/statement/symbol/period/line key.
SELECT f.source, f.symbol_id, f.statement_type, f.period_type,
       f.period_end, f.row_id,
       count(*) AS versions,
       min(f.available_at) AS earliest_available_at,
       max(f.available_at) AS latest_available_at,
       count(*) FILTER (WHERE f.restated) AS restated_versions
FROM core.fundamentals_pit f
WHERE f.archive_managed
GROUP BY f.source, f.symbol_id, f.statement_type, f.period_type,
         f.period_end, f.row_id
HAVING count(*) > 1
ORDER BY versions DESC, f.symbol_id, f.statement_type, f.period_end, f.row_id
LIMIT 200;

-- Observation lineage: every archived version should have at least one
-- observation, and observations should point to the same raw landing/source.
SELECT f.snapshot_id, f.raw_landing_id, f.source, f.symbol_id,
       f.statement_type, f.period_type, f.period_end, f.row_id,
       count(o.observation_id) AS observations,
       count(*) FILTER (WHERE o.raw_landing_id IS DISTINCT FROM f.raw_landing_id
                         OR o.source IS DISTINCT FROM f.source) AS mismatched_observations
FROM core.fundamentals_pit f
LEFT JOIN core.fundamentals_pit_observations o USING (snapshot_id)
WHERE f.archive_managed
GROUP BY f.snapshot_id, f.raw_landing_id, f.source, f.symbol_id,
         f.statement_type, f.period_type, f.period_end, f.row_id
HAVING count(o.observation_id) = 0
    OR count(*) FILTER (WHERE o.raw_landing_id IS DISTINCT FROM f.raw_landing_id
                         OR o.source IS DISTINCT FROM f.source) > 0
ORDER BY f.snapshot_id
LIMIT 200;

-- Fundamental overlay materialization chunks, across every build. A missing
-- row here means no chunk was registered; it does not prove archive completion.
SELECT c.build_id, c.status, count(*) AS chunks,
       sum(c.rows) AS recorded_rows,
       min(c.date_from) AS first_chunk_date,
       max(c.date_to) AS last_chunk_date
FROM ops.feature_chunks c
WHERE c.stage = 'fundamentals'
GROUP BY c.build_id, c.status
ORDER BY c.build_id, c.status;

SELECT c.build_id, c.chunk_key, c.date_from, c.date_to, c.status,
       c.rows, c.started_at, c.finished_at, c.error
FROM ops.feature_chunks c
WHERE c.stage = 'fundamentals'
  AND c.status IN ('pending','running','failed')
ORDER BY c.build_id, c.date_from, c.chunk_key;

-- Include attempt-level records so interrupted/running states remain visible.
SELECT r.build_id, r.chunk_key, r.status, r.rows,
       r.started_at, r.finished_at, r.duration_ms, r.error
FROM ops.step_runs r
WHERE r.stage = 'fundamentals'
  AND r.status IN ('running','failed')
ORDER BY r.build_id, r.step_run_id;

COMMIT;

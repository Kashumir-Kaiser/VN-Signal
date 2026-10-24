\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Bounded E4 integrity report for the disposable Phase 2 report clone.
-- Run once per non-overlapping [chunk_start, chunk_end) date range. A quarterly
-- range is the intended default; smaller ranges are safe if a statement nears
-- the 180 second cap. Sum count metrics across chunks; do not sum hash lists.
-- Example:
--   psql -X -w -v ON_ERROR_STOP=1 -v chunk_start=2018-10-01 \
--     -v chunk_end=2019-01-01 -v build_id=... -f this_file
-- The caller must connect only to vnsignal_phase2_report_20261019.

BEGIN READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

WITH bounds AS (
    SELECT :'chunk_start'::date AS chunk_start,
           :'chunk_end'::date AS chunk_end
),
v2 AS MATERIALIZED (
    SELECT f.symbol_id, f.trade_date
    FROM feat.features_daily f CROSS JOIN bounds b
    WHERE f.feature_version = 'phase2-v2'
      AND f.trade_date >= b.chunk_start AND f.trade_date < b.chunk_end
),
v3 AS MATERIALIZED (
    SELECT f.symbol_id, f.trade_date, f.feature_set_hash,
           f.momentum_20s, f.turnover_proxy_vnd, f.realized_vol20,
           f.return_20s, f.rank_momentum_20s, f.rank_turnover_proxy,
           f.rank_realized_vol20, f.rank_gaussian_return20,
           f.rank_gaussian_turnover_proxy, f.rank_gaussian_realized_vol20,
           f.rank_gaussian_momentum20_industry
    FROM feat.features_daily f CROSS JOIN bounds b
    WHERE f.feature_version = 'phase2-v3'
      AND f.trade_date >= b.chunk_start AND f.trade_date < b.chunk_end
),
symbols AS (
    SELECT DISTINCT symbol_id FROM v3 WHERE symbol_id IS NOT NULL
),
predecessor AS MATERIALIZED (
    SELECT p.symbol_id, p.trade_date
    FROM symbols x CROSS JOIN bounds b
    CROSS JOIN LATERAL (
        SELECT f.symbol_id, f.trade_date
        FROM feat.features_daily f
        WHERE f.feature_version = 'phase2-v3'
          AND f.symbol_id = x.symbol_id
          AND f.trade_date < b.chunk_start
        ORDER BY f.trade_date DESC
        LIMIT 1
    ) p
),
sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
),
session_sequence AS (
    SELECT q.symbol_id, q.trade_date, s.session_no,
           lag(s.session_no) OVER (
               PARTITION BY q.symbol_id ORDER BY s.session_no
           ) AS prior_session_no
    FROM (
        SELECT symbol_id, trade_date FROM predecessor
        UNION ALL
        SELECT symbol_id, trade_date FROM v3
        WHERE symbol_id IS NOT NULL AND trade_date IS NOT NULL
    ) q
    JOIN sessions s USING (trade_date)
),
rank_values AS (
    SELECT f.symbol_id, f.trade_date, r.feature, r.rank_value,
           r.input_value, r.uniform_rank
    FROM v3 f
    CROSS JOIN LATERAL (VALUES
        ('rank_momentum_20s'::text, f.rank_momentum_20s, f.momentum_20s, true),
        ('rank_turnover_proxy', f.rank_turnover_proxy, f.turnover_proxy_vnd, true),
        ('rank_realized_vol20', f.rank_realized_vol20, f.realized_vol20, true),
        ('rank_gaussian_return20', f.rank_gaussian_return20, f.return_20s, false),
        ('rank_gaussian_turnover_proxy', f.rank_gaussian_turnover_proxy, f.turnover_proxy_vnd, false),
        ('rank_gaussian_realized_vol20', f.rank_gaussian_realized_vol20, f.realized_vol20, false)
    ) r(feature, rank_value, input_value, uniform_rank)
),
rank_issue_counts AS (
    SELECT feature,
           count(*) FILTER (WHERE uniform_rank AND rank_value IS NOT NULL AND rank_value < 0
                              AND rank_value NOT IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)) AS below_zero,
           count(*) FILTER (WHERE uniform_rank AND rank_value IS NOT NULL
                              AND rank_value > 1
                              AND rank_value NOT IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)) AS above_one,
           count(*) FILTER (WHERE rank_value = 'NaN'::double precision) AS nan_values,
           count(*) FILTER (WHERE rank_value = 'Infinity'::double precision) AS positive_infinity,
           count(*) FILTER (WHERE rank_value = '-Infinity'::double precision) AS negative_infinity,
           count(*) FILTER (WHERE rank_value IS NOT NULL AND input_value IS NULL) AS null_input,
           count(*) FILTER (WHERE rank_value IS NULL AND input_value IS NOT NULL) AS null_rank
    FROM rank_values
    GROUP BY feature
),
metrics AS (
    SELECT 'coverage'::text AS section, 'v2_rows'::text AS metric,
           count(*)::text AS value, 'V2 rows in this date chunk'::text AS details FROM v2
    UNION ALL
    SELECT 'coverage', 'v3_rows', count(*)::text, 'V3 rows in this date chunk' FROM v3
    UNION ALL
    SELECT 'coverage', 'v3_missing_v2_keys', count(*)::text,
           'V2 symbol-date keys with no V3 row in this chunk'
    FROM v2 a LEFT JOIN v3 b USING (symbol_id, trade_date)
    WHERE b.symbol_id IS NULL
    UNION ALL
    SELECT 'coverage', 'v3_extra_keys', count(*)::text,
           'V3 symbol-date keys with no V2 row in this chunk'
    FROM v3 a LEFT JOIN v2 b USING (symbol_id, trade_date)
    WHERE b.symbol_id IS NULL
    UNION ALL
    SELECT 'keys', 'null_key_rows', count(*)::text,
           'V3 rows with a NULL symbol or date' FROM v3
    WHERE symbol_id IS NULL OR trade_date IS NULL
    UNION ALL
    SELECT 'keys', 'duplicate_key_groups', count(*)::text,
           'V3 symbol-date groups with more than one row'
    FROM (
        SELECT symbol_id, trade_date FROM v3
        GROUP BY symbol_id, trade_date HAVING count(*) > 1
    ) duplicate_keys
    UNION ALL
    SELECT 'contract', 'distinct_feature_hashes', count(DISTINCT feature_set_hash)::text,
           coalesce(string_agg(DISTINCT feature_set_hash, ',' ORDER BY feature_set_hash), 'none')
    FROM v3
    UNION ALL
    SELECT 'contract', 'rows_with_current_feature_hash', count(*)::text,
           'Expected hash=' || feat.phase2_feature_set_hash_v3()
    FROM v3 WHERE feature_set_hash = feat.phase2_feature_set_hash_v3()
    UNION ALL
    SELECT 'calendar', 'rows_without_effective_session', count(*)::text,
           'V3 rows whose date is absent from the effective-session calendar'
    FROM v3 f LEFT JOIN sessions s USING (trade_date)
    WHERE s.trade_date IS NULL
    UNION ALL
    SELECT 'calendar', 'noncontiguous_symbol_session_pairs', count(*)::text,
           'Adjacent observed V3 rows separated by more than one effective session; includes chunk boundary predecessor'
    FROM session_sequence
    WHERE prior_session_no IS NOT NULL AND session_no - prior_session_no > 1
    UNION ALL
    SELECT 'ranks', 'uniform_rank_values_outside_0_1_or_nonfinite', count(*)::text,
           'Non-NULL uniform ranks outside [0,1] or NaN/Infinity'
    FROM rank_values
    WHERE uniform_rank AND rank_value IS NOT NULL
      AND (rank_value < 0 OR rank_value > 1 OR rank_value = 'NaN'::double precision)
    UNION ALL
    SELECT 'ranks', 'gaussian_rank_nonfinite_values', count(*)::text,
           'Non-NULL Gaussian scores that are NaN or positive/negative Infinity; finite Gaussian scores are unbounded'
    FROM rank_values
    WHERE NOT uniform_rank AND rank_value IS NOT NULL
      AND rank_value IN ('NaN'::double precision, 'Infinity'::double precision, '-Infinity'::double precision)
    UNION ALL
    SELECT 'ranks', 'non_null_rank_with_null_input', count(*)::text,
           'Non-NULL rank values whose mapped input is NULL'
    FROM rank_values
    WHERE rank_value IS NOT NULL AND input_value IS NULL
    UNION ALL
    SELECT 'ranks', 'null_rank_with_non_null_input', count(*)::text,
           'NULL rank values whose mapped input is available; singleton ranks must remain defined'
    FROM rank_values
    WHERE rank_value IS NULL AND input_value IS NOT NULL
    UNION ALL
    SELECT 'ranks', 'per_column:' || feature,
           'below_zero=' || below_zero || '; above_one=' || above_one ||
           '; NaN=' || nan_values || '; +Infinity=' || positive_infinity ||
           '; -Infinity=' || negative_infinity || '; nonnull_with_null_input=' || null_input ||
           '; null_with_nonnull_input=' || null_rank,
           'Gaussian scores are unbounded; [0,1] checks apply only to the three uniform rank columns'
    FROM rank_issue_counts
    UNION ALL
    SELECT 'ranks', 'source_unverified_industry_rank_non_null', count(*)::text,
           'Expected zero until point-in-time industry inputs are verified'
    FROM v3 WHERE rank_gaussian_momentum20_industry IS NOT NULL
    UNION ALL
    SELECT 'timing', r.stage || ':' || r.chunk_key,
           coalesce(r.status, 'unknown') || '; rows=' || coalesce(r.rows::text, 'NULL') ||
             '; duration_ms=' || coalesce(r.duration_ms::text, 'NULL'),
           'build_id=' || r.build_id || '; input_sha256=' || coalesce(r.input_sha256, 'NULL') ||
             '; output_sha256=' || coalesce(r.output_sha256, 'NULL')
    FROM ops.step_runs r
    WHERE r.build_id = :'build_id'
      AND :'report_ops'::boolean
)
SELECT :'chunk_start'::text || '/' || :'chunk_end'::text AS chunk,
       section, metric, value, details
FROM metrics
ORDER BY section, metric;

COMMIT;

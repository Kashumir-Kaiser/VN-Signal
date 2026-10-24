\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Run with: psql ... -v build_id=phase2-vci-full-rebuild-YYYYMMDD -f this_file
WITH v2 AS MATERIALIZED (
    SELECT symbol_id,trade_date
    FROM feat.features_daily
    WHERE feature_version='phase2-v2'
), v3 AS MATERIALIZED (
    SELECT symbol_id,trade_date,feature_set_hash,
           momentum_20s,turnover_proxy_vnd,realized_vol20,return_20s,
           rank_momentum_20s,rank_turnover_proxy,rank_realized_vol20,
           rank_gaussian_return20,rank_gaussian_turnover_proxy,
           rank_gaussian_realized_vol20,rank_gaussian_momentum20_industry
    FROM feat.features_daily
    WHERE feature_version='phase2-v3'
), sessions AS MATERIALIZED (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), session_sequence AS (
    SELECT f.symbol_id,f.trade_date,s.session_no,
           lag(s.session_no) OVER(PARTITION BY f.symbol_id ORDER BY s.session_no) AS prior_session_no
    FROM v3 f
    JOIN sessions s USING(trade_date)
), rank_values AS (
    SELECT f.symbol_id,f.trade_date,r.feature,r.rank_value,r.input_value
    FROM v3 f
    CROSS JOIN LATERAL (VALUES
        ('rank_momentum_20s'::text,f.rank_momentum_20s,f.momentum_20s),
        ('rank_turnover_proxy',f.rank_turnover_proxy,f.turnover_proxy_vnd),
        ('rank_realized_vol20',f.rank_realized_vol20,f.realized_vol20),
        ('rank_gaussian_return20',f.rank_gaussian_return20,f.return_20s),
        ('rank_gaussian_turnover_proxy',f.rank_gaussian_turnover_proxy,f.turnover_proxy_vnd),
        ('rank_gaussian_realized_vol20',f.rank_gaussian_realized_vol20,f.realized_vol20)
    ) r(feature,rank_value,input_value)
), metrics AS (
    SELECT 'coverage'::text AS section,'v2_rows'::text AS metric,
           count(*)::text AS value,'Expected V3 key count'::text AS details FROM v2
    UNION ALL
    SELECT 'coverage','v3_rows',count(*)::text,'Built V3 rows' FROM v3
    UNION ALL
    SELECT 'coverage','v3_missing_v2_keys',count(*)::text,'V2 symbol-date keys without a V3 row'
    FROM v2 a LEFT JOIN v3 b USING(symbol_id,trade_date) WHERE b.symbol_id IS NULL
    UNION ALL
    SELECT 'coverage','v3_extra_keys',count(*)::text,'V3 symbol-date keys without a V2 row'
    FROM v3 a LEFT JOIN v2 b USING(symbol_id,trade_date) WHERE b.symbol_id IS NULL
    UNION ALL
    SELECT 'keys','null_key_rows',count(*)::text,'V3 rows with a NULL symbol or date' FROM v3
    WHERE symbol_id IS NULL OR trade_date IS NULL
    UNION ALL
    SELECT 'keys','duplicate_key_groups',count(*)::text,'V3 symbol-date groups with more than one row'
    FROM (
        SELECT symbol_id,trade_date
        FROM v3 GROUP BY symbol_id,trade_date HAVING count(*)<>1
    ) duplicate_keys
    UNION ALL
    SELECT 'contract','distinct_feature_hashes',count(DISTINCT feature_set_hash)::text,
           coalesce(string_agg(DISTINCT feature_set_hash,',' ORDER BY feature_set_hash),'none')
    FROM v3
    UNION ALL
    SELECT 'contract','rows_with_current_feature_hash',count(*)::text,
           'Expected hash='||feat.phase2_feature_set_hash_v3()
    FROM v3 WHERE feature_set_hash=feat.phase2_feature_set_hash_v3()
    UNION ALL
    SELECT 'calendar','rows_without_effective_session',count(*)::text,
           'Rows whose date is absent from the effective session calendar'
    FROM v3 f LEFT JOIN sessions s USING(trade_date) WHERE s.trade_date IS NULL
    UNION ALL
    SELECT 'calendar','noncontiguous_symbol_session_pairs',count(*)::text,
           'Adjacent V3 rows separated by more than one effective session; investigate against source/suspension evidence'
    FROM session_sequence WHERE prior_session_no IS NOT NULL AND session_no-prior_session_no>1
    UNION ALL
    SELECT 'ranks','rank_values_outside_0_1',count(*)::text,
           'Non-NULL rank values outside [0,1] or non-finite'
    FROM rank_values WHERE rank_value IS NOT NULL
      AND (rank_value<0 OR rank_value>1 OR rank_value='NaN'::double precision)
    UNION ALL
    SELECT 'ranks','non_null_rank_with_null_input',count(*)::text,
           'Non-NULL rank values whose mapped input is NULL'
    FROM rank_values WHERE rank_value IS NOT NULL AND input_value IS NULL
    UNION ALL
    SELECT 'ranks','source_unverified_industry_rank_non_null',count(*)::text,
           'Expected zero until point-in-time industry inputs are verified'
    FROM v3 WHERE rank_gaussian_momentum20_industry IS NOT NULL
    UNION ALL
    SELECT 'timing',r.stage||':'||r.chunk_key,
           coalesce(r.status,'unknown')||'; rows='||coalesce(r.rows::text,'NULL')||
             '; duration_ms='||coalesce(r.duration_ms::text,'NULL'),
           'input_sha256='||coalesce(r.input_sha256,'NULL')||'; output_sha256='||coalesce(r.output_sha256,'NULL')
    FROM ops.step_runs r
    WHERE r.build_id=:'build_id'
    UNION ALL
    SELECT 'timing','cache_scaling_probe',
           'Read the runner log for the 15/30/60 symbol timings and measured exponent',
           'Probe measurements are session-local in migration 042; ops.step_runs records durable feature/label chunk timings.'
)
SELECT section,metric,value,details
FROM metrics
ORDER BY section,metric;

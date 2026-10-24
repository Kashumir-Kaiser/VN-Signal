SET statement_timeout='5min';
SET temp_file_limit='5GB';
SET work_mem='128MB';
SET jit=off;
SET application_name='phase2_label_plan_probe';
SELECT * FROM feat.probe_phase2_adjustment_cache(60);
EXPLAIN (VERBOSE, SETTINGS)
WITH calendar_axis AS MATERIALIZED (
    SELECT trade_date,
           lead(trade_date,1) OVER(ORDER BY trade_date) AS entry_date,
           lead(trade_date,6) OVER(ORDER BY trade_date) AS exit_5_date,
           lead(trade_date,21) OVER(ORDER BY trade_date) AS exit_20_date
    FROM core.effective_trading_sessions
    WHERE is_session
), signals AS MATERIALIZED (
    SELECT c.trade_date AS signal_date,c.entry_date,h.horizon_sessions,
           CASE h.horizon_sessions WHEN 5 THEN c.exit_5_date ELSE c.exit_20_date END AS exit_date
    FROM calendar_axis c
    CROSS JOIN (VALUES (5::smallint),(20::smallint)) h(horizon_sessions)
    WHERE c.trade_date BETWEEN DATE '2021-01-01' AND DATE '2021-12-31'
), targets AS MATERIALIZED (
    SELECT s.signal_date,s.entry_date,s.exit_date,s.horizon_sessions,f.symbol_id
    FROM signals s
    JOIN feat.features_daily f ON f.trade_date=s.signal_date AND f.feature_version='phase2-v3'
    JOIN pg_temp.phase2_adjustment_symbol_batches sb USING(symbol_id)
), target_symbols AS MATERIALIZED (
    SELECT DISTINCT symbol_id FROM targets
), adjustment_rows AS MATERIALIZED (
    SELECT r.symbol_id,r.trade_date,r.model_o,r.model_c,r.v,r.is_traded,
           r.episode_start_date,r.adjustment_vintage_at,r.landing_id,
           r.reference_adjustment_ratio
    FROM pg_temp.phase2_adjustment_rows r
    JOIN target_symbols s USING(symbol_id)
    WHERE r.source='vndirect'
), endpoint_days AS MATERIALIZED (
    SELECT DISTINCT symbol_id,entry_date AS trade_date FROM targets
    UNION
    SELECT DISTINCT symbol_id,exit_date FROM targets WHERE exit_date IS NOT NULL
), endpoint_bars AS MATERIALIZED (
    SELECT r.symbol_id,r.trade_date,r.model_o,r.model_c,r.v AS volume,r.is_traded,
           r.episode_start_date,r.adjustment_vintage_at,r.landing_id
    FROM adjustment_rows r
    JOIN endpoint_days d USING(symbol_id,trade_date)
), latest_exit_by_symbol AS MATERIALIZED (
    SELECT symbol_id,max(exit_date) AS latest_exit_date
    FROM targets WHERE exit_date IS NOT NULL GROUP BY symbol_id
), first_bad_factor AS MATERIALIZED (
    SELECT r.symbol_id,min(r.trade_date) AS first_bad_date
    FROM adjustment_rows r
    JOIN latest_exit_by_symbol k ON k.symbol_id=r.symbol_id AND r.trade_date<=k.latest_exit_date
    WHERE (r.reference_adjustment_ratio IS NULL OR r.reference_adjustment_ratio<=0
           OR r.reference_adjustment_ratio>='Infinity'::double precision)
      AND NOT EXISTS (SELECT 1 FROM ops.ml_symbol_scope x
                      WHERE x.symbol_id=r.symbol_id AND x.scope_status='EXCLUDED')
    GROUP BY r.symbol_id
), spans AS MATERIALIZED (
    SELECT t.symbol_id,t.signal_date,t.horizon_sessions,
           sum(CASE WHEN r.reference_adjustment_ratio>0 AND
                              r.reference_adjustment_ratio<'Infinity'::double precision
                    THEN ln(r.reference_adjustment_ratio) END) AS factor_log_span,
           count(r.trade_date) AS factor_rows,
           count(*) FILTER(WHERE r.trade_date IS NOT NULL AND
               (r.reference_adjustment_ratio IS NULL OR r.reference_adjustment_ratio<=0 OR
                r.reference_adjustment_ratio>='Infinity'::double precision)) AS bad_factor_rows,
           bool_and(r.episode_start_date=t_entry.episode_start_date) AS one_episode_span
    FROM targets t
    LEFT JOIN endpoint_bars t_entry ON t_entry.symbol_id=t.symbol_id AND t_entry.trade_date=t.entry_date
    LEFT JOIN adjustment_rows r
      ON r.symbol_id=t.symbol_id
     AND r.trade_date>t.entry_date AND r.trade_date<=t.exit_date
     AND r.episode_start_date=t_entry.episode_start_date
    GROUP BY t.symbol_id,t.signal_date,t.horizon_sessions
)
SELECT count(*) FROM spans;
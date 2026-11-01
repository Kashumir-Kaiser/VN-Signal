\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Audit the meaning of adjacent feature-row dates without calling every row
-- a traded bar. All derived data is connection-local temporary state.
BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout = '900s';
SET LOCAL lock_timeout = '5s';
SET LOCAL work_mem = '8MB';
SET LOCAL temp_file_limit = '20GB';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing endpoint-semantics audit outside disposable report clone'
  \quit 2
\endif

DO $assert$
BEGIN
  IF feat.phase2_feature_set_hash_v3() <> '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b' THEN
    RAISE EXCEPTION 'current feature hash differs from E4 endpoint audit candidate';
  END IF;
END
$assert$;

DROP TABLE IF EXISTS pg_temp.e4_feature_endpoint_semantics;
CREATE TEMP TABLE e4_feature_endpoint_semantics ON COMMIT PRESERVE ROWS AS
WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), feature_rows AS MATERIALIZED (
    SELECT f.symbol_id,f.trade_date,f.is_traded,s.session_no
    FROM feat.features_daily f
    JOIN sessions s USING (trade_date)
    WHERE f.feature_version='phase2-v3'
      AND f.feature_set_hash=feat.phase2_feature_set_hash_v3()
      AND f.trade_date>=DATE '2018-10-01'
      AND f.trade_date<DATE '2026-10-17'
), adjacent AS (
    SELECT f.symbol_id,f.trade_date AS next_feature_date,
           f.is_traded AS next_feature_is_traded,
           lag(f.trade_date) OVER w AS prior_feature_date,
           lag(f.is_traded) OVER w AS prior_feature_is_traded,
           f.session_no-lag(f.session_no) OVER w AS session_distance
    FROM feature_rows f
    WINDOW w AS (PARTITION BY f.symbol_id ORDER BY f.session_no)
), gaps AS (
    SELECT a.*,(a.session_distance-1)::integer AS missing_effective_sessions
    FROM adjacent a
    WHERE a.session_distance>1
)
SELECT s.symbol,g.symbol_id,g.prior_feature_date,g.prior_feature_is_traded,
       g.next_feature_date,g.next_feature_is_traded,
       g.missing_effective_sessions,
       (SELECT count(*)::integer FROM core.bars_daily b
        WHERE b.symbol_id=g.symbol_id
          AND b.trade_date>g.prior_feature_date AND b.trade_date<g.next_feature_date) AS bar_rows_between,
       (SELECT count(*)::integer FROM core.bars_daily_sources bs
        WHERE bs.symbol_id=g.symbol_id
          AND bs.trade_date>g.prior_feature_date AND bs.trade_date<g.next_feature_date) AS source_rows_between,
       (SELECT max(b.trade_date) FROM core.bars_daily b
        WHERE b.symbol_id=g.symbol_id AND b.is_traded
          AND b.trade_date<=g.prior_feature_date) AS last_positive_bar_on_or_before_prior_feature,
       (SELECT max(b.trade_date) FROM core.bars_daily b
        WHERE b.symbol_id=g.symbol_id AND b.is_traded
          AND b.trade_date<g.next_feature_date) AS last_positive_bar_before_next_feature,
       EXISTS (
           SELECT 1 FROM ops.phase2_verified_security_transfers t
           WHERE t.symbol_id=g.symbol_id
             AND t.effective_date=g.next_feature_date
             AND t.prior_ceased_from>g.prior_feature_date
             AND t.prior_ceased_from<g.next_feature_date
       ) AS strict_transfer_matches_feature_interval
FROM gaps g
JOIN core.symbols s ON s.symbol_id=g.symbol_id;

COMMIT;

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='60s';
SELECT count(*) AS gap_intervals,
       count(*) FILTER (WHERE NOT prior_feature_is_traded) AS prior_feature_rows_not_traded,
       count(*) FILTER (WHERE NOT next_feature_is_traded) AS next_feature_rows_not_traded,
       count(*) FILTER (WHERE last_positive_bar_on_or_before_prior_feature IS DISTINCT FROM prior_feature_date) AS prior_feature_after_last_positive_bar,
       count(*) FILTER (WHERE strict_transfer_matches_feature_interval) AS strict_transfer_matches
FROM e4_feature_endpoint_semantics;

\copy (SELECT symbol,symbol_id,prior_feature_date,prior_feature_is_traded,next_feature_date,next_feature_is_traded,missing_effective_sessions,bar_rows_between,source_rows_between,last_positive_bar_on_or_before_prior_feature,last_positive_bar_before_next_feature,strict_transfer_matches_feature_interval FROM e4_feature_endpoint_semantics ORDER BY next_feature_date,symbol) TO 'docs/evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_posttielcm1.csv' WITH (FORMAT csv,HEADER true)

COMMIT;


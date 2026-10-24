\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Read-only source/feature cross-check for the TSB interval whose lifecycle
-- row references a CTR landing. This does not validate the lifecycle claim.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

SELECT m.symbol,
       s.trade_date,
       b.source AS curated_bar_source,
       b.is_traded,
       b.o, b.h, b.l, b.c, b.v,
       coalesce(src.source_rows, 0) AS source_archive_rows,
       EXISTS (
           SELECT 1 FROM feat.features_daily f
       WHERE f.symbol_id = m.symbol_id AND f.trade_date = s.trade_date
             AND f.feature_version = 'phase2-v2'
       ) AS has_v2_feature,
       EXISTS (
           SELECT 1 FROM feat.features_daily f
       WHERE f.symbol_id = m.symbol_id AND f.trade_date = s.trade_date
             AND f.feature_version = 'phase2-v3'
       ) AS has_v3_feature
FROM core.security_master m
CROSS JOIN core.effective_trading_sessions s
LEFT JOIN core.bars_daily b
       ON b.symbol_id = m.security_id AND b.trade_date = s.trade_date
LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS source_rows
    FROM core.bars_daily_sources d
    WHERE d.symbol_id = m.symbol_id AND d.trade_date = s.trade_date
) src ON true
WHERE m.symbol = 'TSB'
  AND s.is_session
  AND s.trade_date BETWEEN DATE '2022-02-15' AND DATE '2022-02-22'
ORDER BY s.trade_date;

COMMIT;

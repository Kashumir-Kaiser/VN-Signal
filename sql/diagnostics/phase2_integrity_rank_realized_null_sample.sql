\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Read-only lineage sample for 2018-10 rank_realized_vol20 values with a NULL
-- realized_vol20 input. Run only on vnsignal_phase2_report_20261019.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '180s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

-- There are no stored observation/window-count columns in feat.features_daily;
-- this inventory checks available candidate fields before the row sample.
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'feat'
  AND table_name = 'features_daily'
  AND (column_name ILIKE '%count%'
       OR column_name ILIKE '%window%'
       OR column_name ILIKE '%observ%')
ORDER BY ordinal_position;

SELECT v3.symbol_id, v3.trade_date,
       v2.realized_vol20 AS v2_realized_vol20_input,
       v2.rank_realized_vol20 AS v2_rank_realized_vol20,
       v3.realized_vol20 AS v3_realized_vol20_input,
       v3.rank_realized_vol20 AS v3_rank_realized_vol20,
       v2.return_20s AS v2_return_20s,
       v3.return_20s AS v3_return_20s,
       v3.momentum_20s, v3.turnover_proxy_vnd,
       v2.feature_set_hash AS v2_feature_set_hash,
       v3.feature_set_hash AS v3_feature_set_hash
FROM feat.features_daily v3
JOIN feat.features_daily v2
  ON v2.symbol_id = v3.symbol_id AND v2.trade_date = v3.trade_date
 AND v2.feature_version = 'phase2-v2'
WHERE v3.feature_version = 'phase2-v3'
  AND v3.trade_date >= DATE '2018-10-01'
  AND v3.trade_date < DATE '2018-11-01'
  AND v3.rank_realized_vol20 IS NOT NULL
  AND v3.realized_vol20 IS NULL
ORDER BY v3.trade_date, v3.symbol_id
LIMIT 12;

COMMIT;

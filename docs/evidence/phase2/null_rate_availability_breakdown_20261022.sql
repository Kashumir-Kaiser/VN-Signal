\set ON_ERROR_STOP on
\pset format unaligned
\pset fieldsep '|'
\pset footer off
\pset tuples_only off

BEGIN READ ONLY;
SET LOCAL statement_timeout = '60s';

SELECT coalesce(is_traded::text, 'NULL') AS is_traded,
       count(*)::bigint AS row_count,
       count(*) FILTER(WHERE bar_landing_id IS NULL)::bigint AS null_bar_landing_id,
       count(*) FILTER(WHERE ret_1 IS NULL)::bigint AS null_ret_1,
       count(*) FILTER(WHERE close_sma200_ratio IS NULL)::bigint AS null_close_sma200_ratio
FROM feat.features_daily
WHERE feature_version='phase2-v3'
GROUP BY is_traded
ORDER BY is_traded DESC NULLS LAST;

ROLLBACK;

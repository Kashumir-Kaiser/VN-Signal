\set ON_ERROR_STOP on
BEGIN;

-- This column classifies OHLC price fields. It does not imply adjusted volume
-- or capture when a provider first restated a historical row.
UPDATE core.bars_daily
SET adj_basis = 'adjusted'
WHERE source = 'vci' AND adj_basis = 'unknown';

UPDATE core.bars_daily_sources
SET adj_basis = 'adjusted'
WHERE source = 'dnse' AND adj_basis = 'unknown';

COMMIT;

SELECT source, adj_basis, count(*)
FROM (
    SELECT source, adj_basis FROM core.bars_daily
    UNION ALL
    SELECT source, adj_basis FROM core.bars_daily_sources
) AS all_bars
GROUP BY source, adj_basis
ORDER BY source, adj_basis;

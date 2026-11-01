-- Read-only scope for the 2026-11-01 Phase 2 PIT archive continuation.
-- Select current V3 investable members with no archive-managed fundamentals.
BEGIN READ ONLY;
WITH latest AS (
    SELECT max(trade_date) AS trade_date
    FROM feat.phase2_liquidity_tiers_v3
    WHERE feature_set_hash =
        '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b'
), investable AS (
    SELECT DISTINCT s.symbol_id, s.symbol, t.liquidity_tier, t.tier_rank
    FROM feat.phase2_liquidity_tiers_v3 t
    JOIN latest l ON l.trade_date = t.trade_date
    JOIN core.symbols s USING (symbol_id)
    WHERE t.feature_set_hash =
        '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b'
      AND t.is_investable_member
)
SELECT i.symbol, i.liquidity_tier, i.tier_rank
FROM investable i
WHERE NOT EXISTS (
    SELECT 1
    FROM core.fundamentals_pit f
    WHERE f.symbol_id = i.symbol_id
      AND f.archive_managed
)
ORDER BY CASE i.liquidity_tier WHEN 'L1' THEN 1 WHEN 'L2' THEN 2 ELSE 3 END,
         i.tier_rank,
         i.symbol;
ROLLBACK;

BEGIN;

-- The rank stage reads only these V2 inputs. This narrow partial covering
-- index avoids fetching every wide feature row for date-scoped rank windows.
SET LOCAL maintenance_work_mem='16MB';
SET LOCAL max_parallel_maintenance_workers=0;
CREATE INDEX IF NOT EXISTS features_daily_v2_rank_inputs_cover_idx
    ON feat.features_daily (trade_date,symbol_id)
    INCLUDE (return_20s,turnover_proxy_vnd,realized_vol20)
    WHERE feature_version='phase2-v2';
COMMENT ON INDEX feat.features_daily_v2_rank_inputs_cover_idx IS
    'Covers the V2 return, turnover and volatility inputs consumed by the Phase 2 cross-sectional rank stage.';
ANALYZE feat.features_daily;

COMMIT;

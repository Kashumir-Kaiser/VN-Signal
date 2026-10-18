-- Phase 1: retain VNDIRECT's independent unadjusted daily market series.
-- Existing DNSE/SSI sources remain isolated and raw landing bytes stay immutable.
BEGIN;

ALTER TABLE ops.external_market_calls
    DROP CONSTRAINT IF EXISTS external_market_calls_source_check;
ALTER TABLE ops.external_market_calls
    ADD CONSTRAINT external_market_calls_source_check
    CHECK (source IN ('dnse','ssi','vndirect'));

ALTER TABLE core.bars_daily_sources
    DROP CONSTRAINT IF EXISTS bars_daily_sources_source_check;
ALTER TABLE core.bars_daily_sources
    ADD CONSTRAINT bars_daily_sources_source_check
    CHECK (source IN ('dnse','ssi','vndirect'));

COMMIT;

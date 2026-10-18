-- Opening/closing auction prices may fall outside continuous-session extrema.
BEGIN;

ALTER TABLE core.bars_daily DROP CONSTRAINT IF EXISTS bars_daily_check;
ALTER TABLE core.bars_daily DROP CONSTRAINT IF EXISTS bars_daily_high_low_order;
ALTER TABLE core.bars_daily ADD CONSTRAINT bars_daily_high_low_order
    CHECK (h >= l);

COMMIT;

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='5min';
SELECT feat.begin_phase2_adjustment_rows(2,4);
SELECT feat.populate_phase2_adjustment_rows(0);
SELECT feat.populate_phase2_adjustment_rows(1);
SELECT feat.finish_phase2_adjustment_rows();
SELECT ops.phase2_prepare_price_day_hashes(min(trade_date),max(trade_date)) FROM pg_temp.phase2_adjustment_rows;
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hash_coverage) THEN
  RAISE EXCEPTION 'fixture did not prepare any date hashes';
 END IF;
END $$;
CREATE TEMP TABLE reset_original_hashes ON COMMIT DROP AS SELECT * FROM pg_temp.phase2_price_day_hashes;
DO $$
BEGIN
 BEGIN
  COMMENT ON TABLE pg_temp.phase2_price_day_hash_coverage IS 'unowned test relation';
  PERFORM feat.invalidate_phase2_price_cache_hashes();
  RAISE EXCEPTION 'unowned hash coverage was accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'temporary relation phase2_price_day_hash_coverage is reserved%' THEN RAISE; END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hashes) THEN
  RAISE EXCEPTION 'failed invalidation did not roll back atomically';
 END IF;
END $$;
SELECT feat.populate_phase2_adjustment_rows(0);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hashes)
    OR EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hash_coverage) THEN
  RAISE EXCEPTION 'batch refill retained stale price-day hash evidence';
 END IF;
END $$;
SELECT feat.finish_phase2_adjustment_rows();
SELECT ops.phase2_prepare_price_day_hashes(min(trade_date),max(trade_date)) FROM pg_temp.phase2_adjustment_rows;
DO $$
BEGIN
 IF EXISTS (
  (SELECT * FROM reset_original_hashes EXCEPT SELECT * FROM pg_temp.phase2_price_day_hashes)
  UNION ALL
  (SELECT * FROM pg_temp.phase2_price_day_hashes EXCEPT SELECT * FROM reset_original_hashes)
 ) THEN RAISE EXCEPTION 'identical retry changed deterministic day hashes'; END IF;
END $$;
SELECT feat.begin_phase2_adjustment_rows(1,1);
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hashes)
    OR EXISTS(SELECT 1 FROM pg_temp.phase2_price_day_hash_coverage)
    OR EXISTS(SELECT 1 FROM pg_temp.phase2_adjustment_batch_dates) THEN
  RAISE EXCEPTION 'cache reinitialization retained old date/hash manifests';
 END IF;
END $$;
SELECT feat.populate_phase2_adjustment_rows(0);
SELECT feat.finish_phase2_adjustment_rows();
SELECT ops.phase2_prepare_price_day_hashes(min(trade_date),max(trade_date)) FROM pg_temp.phase2_adjustment_rows;
DO $$
BEGIN
 IF EXISTS (
  SELECT trade_date FROM pg_temp.phase2_adjustment_batch_dates
  EXCEPT SELECT trade_date FROM pg_temp.phase2_adjustment_rows
 ) THEN RAISE EXCEPTION 'reset manifest contains dates from the previous cache'; END IF;
END $$;
ROLLBACK;

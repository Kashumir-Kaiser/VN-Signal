\set ON_ERROR_STOP on
-- Synthetic timing fixtures test validation only, never market performance.
BEGIN;
SET LOCAL vnpipe.phase2_symbol_batch_size='15';
SET LOCAL work_mem='8MB';
SET LOCAL maintenance_work_mem='16MB';
CREATE TEMP TABLE phase2_cache_samples(
 sample_no integer PRIMARY KEY,symbol_count integer,row_count bigint,duration_ms bigint,
 configured_batch_size integer,work_memory text,maintenance_memory text
);
COMMENT ON TABLE pg_temp.phase2_cache_samples IS 'VN-Signal fixed 90-sample cache benchmark';
CREATE TEMP TABLE phase2_adjustment_cache_probe_results(
 symbol_count integer PRIMARY KEY,row_count bigint,duration_ms bigint,
 configured_batch_size integer,work_memory text,maintenance_memory text
);
INSERT INTO pg_temp.phase2_cache_samples
SELECT n,15*(1<<((n-1)%3)),100,1000*(1<<((n-1)%3)),15,current_setting('work_mem'),current_setting('maintenance_work_mem')
FROM generate_series(1,90) n;
INSERT INTO pg_temp.phase2_adjustment_cache_probe_results
SELECT symbol_count,100,1,15,current_setting('work_mem'),current_setting('maintenance_work_mem')
FROM pg_temp.phase2_cache_samples GROUP BY symbol_count;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_temp.phase2_adjustment_cache_probe_results WHERE duration_ms<>1000*symbol_count/15) THEN
  RAISE EXCEPTION 'validator did not aggregate all timing samples';
 END IF;
 BEGIN
  DELETE FROM pg_temp.phase2_cache_samples WHERE sample_no=90;
  PERFORM feat.validate_phase2_cache_samples();
  RAISE EXCEPTION 'missing sample accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE pg_temp.phase2_cache_samples SET duration_ms=100000 WHERE sample_no>60;
  PERFORM feat.validate_phase2_cache_samples();
  RAISE EXCEPTION 'unstable blocks accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cache benchmark block means vary%' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE pg_temp.phase2_cache_samples SET configured_batch_size=60 WHERE sample_no=1;
  PERFORM feat.validate_phase2_cache_samples();
  RAISE EXCEPTION 'configuration mismatch accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
 END;
 BEGIN
  UPDATE pg_temp.phase2_cache_samples SET row_count=101 WHERE sample_no=1;
  PERFORM feat.validate_phase2_cache_samples();
  RAISE EXCEPTION 'row-count mismatch accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
 END;
END $$;
ROLLBACK;

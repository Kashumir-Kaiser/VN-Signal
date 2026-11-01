\set ON_ERROR_STOP on
-- Synthetic timing fixtures test cache scaling logic, never market performance.
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
WITH sizes AS (
 SELECT n,15*(1<<((n-1)%3)) AS symbol_count FROM generate_series(1,90) n
)
INSERT INTO pg_temp.phase2_cache_samples
SELECT n,symbol_count,symbol_count*10,1000*symbol_count/15,15,
       current_setting('work_mem'),current_setting('maintenance_work_mem')
FROM sizes;
INSERT INTO pg_temp.phase2_adjustment_cache_probe_results
SELECT symbol_count,min(row_count),1,15,current_setting('work_mem'),current_setting('maintenance_work_mem')
FROM pg_temp.phase2_cache_samples GROUP BY symbol_count;

SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_temp.phase2_adjustment_cache_probe_results
            WHERE duration_ms<>1000*symbol_count/15)
    OR (SELECT count(*) FROM pg_temp.phase2_cache_scaling_blocks)<>3
    OR EXISTS (SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
               WHERE b_15_30<>1 OR b_30_60<>1) THEN
  RAISE EXCEPTION 'baseline row-weighted exponents or all-sample timing aggregation are wrong';
 END IF;
 BEGIN
  DELETE FROM pg_temp.phase2_cache_samples WHERE sample_no=90;
  PERFORM feat.validate_phase2_cache_samples();
  RAISE EXCEPTION 'missing sample accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
 END;
END $$;

-- Reproduce the rejected 15-to-30 timing comparison with the actual unequal
-- source-row counts. Row normalization moves the exponent below the same 1.3 cap.
UPDATE pg_temp.phase2_cache_samples
   SET row_count=CASE symbol_count WHEN 15 THEN 23765 WHEN 30 THEN 53205 WHEN 60 THEN 108331 END;
UPDATE pg_temp.phase2_adjustment_cache_probe_results
   SET row_count=CASE symbol_count WHEN 15 THEN 23765 WHEN 30 THEN 53205 WHEN 60 THEN 108331 END;
UPDATE pg_temp.phase2_cache_samples
   SET duration_ms=CASE symbol_count WHEN 15 THEN 1472 WHEN 30 THEN 3822 WHEN 60 THEN 5352 END;
SELECT feat.validate_phase2_cache_samples();
DO $$
DECLARE v_exponent double precision;
BEGIN
 SELECT b_15_30 INTO v_exponent FROM pg_temp.phase2_cache_scaling_blocks WHERE block_no=1;
 IF v_exponent NOT BETWEEN 1.17 AND 1.20 THEN
  RAISE EXCEPTION 'unequal source-row cohorts produced exponent %, expected about 1.18',v_exponent;
 END IF;
 IF (SELECT max(greatest(b_15_30,b_30_60)) FROM pg_temp.phase2_cache_scaling_blocks)>1.3 THEN
  RAISE EXCEPTION 'row-normalized observed cache workload incorrectly exceeds 1.3';
 END IF;
END $$;

-- Return to equal-work fixtures for the independent boundary and guard checks.
UPDATE pg_temp.phase2_cache_samples
   SET row_count=symbol_count*10,duration_ms=1000*symbol_count/15;
UPDATE pg_temp.phase2_adjustment_cache_probe_results
   SET row_count=symbol_count*10;
SELECT feat.validate_phase2_cache_samples();

-- A small uniform timing drift across one block remains within the 20% sample
-- stability allowance; the slowest complete block drives projection.
UPDATE pg_temp.phase2_cache_samples
   SET duration_ms=round(duration_ms*1.1)::bigint WHERE sample_no>60;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_temp.phase2_adjustment_cache_probe_results
            WHERE duration_ms<>1100*symbol_count/15)
    OR EXISTS (SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
               WHERE b_15_30<>1 OR b_30_60<>1) THEN
  RAISE EXCEPTION 'slowest-block timing projection or row exponent changed under a small uniform drift';
 END IF;
 IF (SELECT count(*) FROM pg_temp.phase2_cache_samples)<>90 THEN
  RAISE EXCEPTION 'validation removed raw timing observations';
 END IF;
END $$;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=1000*symbol_count/15;
SELECT feat.validate_phase2_cache_samples();

-- Exact 20% within-block inversions remain allowed by the existing guard.
UPDATE pg_temp.phase2_cache_samples SET duration_ms=800 WHERE symbol_count=30;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
            WHERE mean_30_ms<>mean_15_ms*0.8) THEN
  RAISE EXCEPTION '15-to-30 exact 20 percent inversion boundary was not retained';
 END IF;
END $$;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=2000 WHERE symbol_count=30;
SELECT feat.validate_phase2_cache_samples();
UPDATE pg_temp.phase2_cache_samples SET duration_ms=1600 WHERE symbol_count=60;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
            WHERE mean_60_ms<>mean_30_ms*0.8) THEN
  RAISE EXCEPTION '30-to-60 exact 20 percent inversion boundary was not retained';
 END IF;
END $$;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=4000 WHERE symbol_count=60;
SELECT feat.validate_phase2_cache_samples();

-- A superlinear block must remain visible; it cannot be averaged away.
UPDATE pg_temp.phase2_cache_samples SET duration_ms=5000 WHERE symbol_count=30;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF (SELECT max(b_15_30) FROM pg_temp.phase2_cache_scaling_blocks)<=1.3 THEN
  RAISE EXCEPTION 'superlinear 15-to-30 row growth was hidden';
 END IF;
END $$;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=2000 WHERE symbol_count=30;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=6000 WHERE symbol_count=60;
SELECT feat.validate_phase2_cache_samples();
DO $$
BEGIN
 IF (SELECT max(b_30_60) FROM pg_temp.phase2_cache_scaling_blocks)<=1.3 THEN
  RAISE EXCEPTION 'superlinear 30-to-60 row growth was hidden';
 END IF;
END $$;
UPDATE pg_temp.phase2_cache_samples SET duration_ms=4000 WHERE symbol_count=60;
SELECT feat.validate_phase2_cache_samples();

DO $$
BEGIN
BEGIN
 UPDATE pg_temp.phase2_cache_samples SET duration_ms=799 WHERE symbol_count=30;
 PERFORM feat.validate_phase2_cache_samples();
 RAISE EXCEPTION 'material within-block 15-to-30 timing inversion accepted';
EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'cache benchmark sample-size timings invert%' THEN RAISE; END IF;
END;
BEGIN
 UPDATE pg_temp.phase2_cache_samples SET duration_ms=1599 WHERE symbol_count=60;
 PERFORM feat.validate_phase2_cache_samples();
 RAISE EXCEPTION 'material within-block 30-to-60 timing inversion accepted';
EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'cache benchmark sample-size timings invert%' THEN RAISE; END IF;
END;
BEGIN
 UPDATE pg_temp.phase2_cache_samples SET configured_batch_size=60 WHERE sample_no=1;
 PERFORM feat.validate_phase2_cache_samples();
 RAISE EXCEPTION 'configuration mismatch accepted';
EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
END;
BEGIN
 UPDATE pg_temp.phase2_cache_samples SET row_count=151 WHERE sample_no=1;
 PERFORM feat.validate_phase2_cache_samples();
 RAISE EXCEPTION 'row-count mismatch accepted';
EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN RAISE; END IF;
END;
BEGIN
 UPDATE pg_temp.phase2_cache_samples SET row_count=100 WHERE symbol_count=30;
 PERFORM feat.validate_phase2_cache_samples();
 RAISE EXCEPTION 'non-monotonic cohort row volume accepted';
EXCEPTION WHEN raise_exception THEN
 IF SQLERRM NOT LIKE 'cache benchmark samples are incomplete%' THEN
  IF SQLERRM NOT LIKE 'cache benchmark row volume must increase%' THEN RAISE; END IF;
 END IF;
END;
END $$;
ROLLBACK;

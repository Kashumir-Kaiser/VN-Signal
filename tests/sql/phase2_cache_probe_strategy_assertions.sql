\set ON_ERROR_STOP on
BEGIN;
SET LOCAL vnpipe.phase2_symbol_batch_size='15';
SET LOCAL work_mem='8MB';
SET LOCAL maintenance_work_mem='16MB';
SELECT * FROM feat.probe_phase2_adjustment_cache(30);
DO $$
BEGIN
    IF (SELECT count(*) FROM pg_temp.phase2_adjustment_symbol_batches)<>30
       OR (SELECT count(DISTINCT batch_no) FROM pg_temp.phase2_adjustment_symbol_batches)<>2
       OR EXISTS(SELECT 1 FROM pg_temp.phase2_adjustment_symbol_batches WHERE NOT loaded)
       OR NOT EXISTS (
           SELECT 1 FROM pg_temp.phase2_adjustment_cache_probe_results
           WHERE symbol_count=30 AND configured_batch_size=15
             AND work_memory=current_setting('work_mem')
             AND maintenance_memory=current_setting('maintenance_work_mem')
       ) THEN
        RAISE EXCEPTION 'probe did not measure and record the configured bounded strategy';
    END IF;
END
$$;
ROLLBACK;

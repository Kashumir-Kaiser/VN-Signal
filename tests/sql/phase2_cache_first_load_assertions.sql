\set ON_ERROR_STOP on
BEGIN;
SELECT feat.begin_phase2_adjustment_rows(2,4);
SELECT feat.populate_phase2_adjustment_rows(0);
SELECT feat.populate_phase2_adjustment_rows(1);
DO $$
BEGIN
    IF pg_stat_get_xact_numscans('pg_temp.phase2_adjustment_rows'::regclass)<>0 THEN
        RAISE EXCEPTION 'first-load batches scanned the growing adjustment cache';
    END IF;
END $$;
SELECT feat.populate_phase2_adjustment_rows(0);
DO $$
BEGIN
    IF pg_stat_get_xact_numscans('pg_temp.phase2_adjustment_rows'::regclass)<1 THEN
        RAISE EXCEPTION 'retry failed to scan/delete its previous batch rows';
    END IF;
END $$;
SELECT feat.finish_phase2_adjustment_rows();
DO $$
BEGIN
    IF EXISTS (SELECT symbol_id,trade_date FROM pg_temp.phase2_adjustment_rows
               GROUP BY symbol_id,trade_date HAVING count(*)<>1) THEN
        RAISE EXCEPTION 'retry duplicated cache rows';
    END IF;
END $$;
ROLLBACK;

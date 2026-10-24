-- Bounded current-hash refresh for the three deterministic E3 real-data dates.
-- Run only against vnsignal_phase2_report_20261019. It uses the production
-- cache lifecycle and builder, and rewrites only V3 rows on these three dates.
\set ON_ERROR_STOP on
\timing on
BEGIN;
SET LOCAL statement_timeout='20min';
SET LOCAL work_mem='128MB';
SET LOCAL jit=off;
SELECT feat.begin_phase2_adjustment_rows(60);
DO $fill_cache$
DECLARE
    batch_no integer;
BEGIN
    FOR batch_no IN
        SELECT DISTINCT b.batch_no
        FROM pg_temp.phase2_adjustment_symbol_batches b
        ORDER BY b.batch_no
    LOOP
        PERFORM feat.populate_phase2_adjustment_rows(batch_no);
    END LOOP;
END;
$fill_cache$;
SELECT feat.finish_phase2_adjustment_rows();
COMMIT;

BEGIN;
SET LOCAL statement_timeout='20min';
SET LOCAL work_mem='128MB';
SET LOCAL jit=off;
SELECT feat.phase2_builder_set_context('core','feat','ops') AS previous_path \gset
SELECT feat.build_price_features_v3_shared(DATE '2022-10-10',DATE '2022-10-10',NULL);
SELECT feat.phase2_builder_restore_context(:'previous_path');
COMMIT;

BEGIN;
SET LOCAL statement_timeout='20min';
SET LOCAL work_mem='128MB';
SET LOCAL jit=off;
SELECT feat.phase2_builder_set_context('core','feat','ops') AS previous_path \gset
SELECT feat.build_price_features_v3_shared(DATE '2023-04-04',DATE '2023-04-04',NULL);
SELECT feat.phase2_builder_restore_context(:'previous_path');
COMMIT;

BEGIN;
SET LOCAL statement_timeout='20min';
SET LOCAL work_mem='128MB';
SET LOCAL jit=off;
SELECT feat.phase2_builder_set_context('core','feat','ops') AS previous_path \gset
SELECT feat.build_price_features_v3_shared(DATE '2024-09-04',DATE '2024-09-04',NULL);
SELECT feat.phase2_builder_restore_context(:'previous_path');
COMMIT;

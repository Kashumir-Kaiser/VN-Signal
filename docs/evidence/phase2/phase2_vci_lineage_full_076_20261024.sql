\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database()<>'vnsignal_phase2_report_20261019' THEN
  RAISE EXCEPTION 'this evidence run requires the isolated report clone';
 END IF;
END $$;
SET application_name='phase2_vci_lineage_archive';
SET work_mem='8MB';
SET statement_timeout='120s';
-- Each generated statement commits its bounded batch independently. Re-running
-- compares deterministic observations and inserts only changed input versions.
WITH symbols AS (
 SELECT symbol_id,(row_number() OVER(ORDER BY symbol_id)-1)/15 AS batch
 FROM core.symbols s WHERE EXISTS(
  SELECT 1 FROM core.bars_daily b WHERE b.symbol_id=s.symbol_id AND b.source='vci')
)
SELECT format('SELECT %s AS batch, clock_timestamp() AS started_at, ops.materialize_phase2_vci_lineage(ARRAY[%s]::bigint[]) AS inserted;',
 batch,string_agg(symbol_id::text,',' ORDER BY symbol_id))
FROM symbols GROUP BY batch ORDER BY batch
\gexec
WITH latest AS (
 SELECT DISTINCT ON(symbol_id,trade_date) * FROM ops.phase2_vci_bar_lineage
 WHERE algorithm_version='vci-exact-row-v1'
 ORDER BY symbol_id,trade_date,observation_id DESC
)
SELECT status,count(*) FROM latest GROUP BY status ORDER BY status;
SELECT count(*) AS canonical_vci_rows FROM core.bars_daily WHERE source='vci';
SELECT count(*) AS observed_symbol_days FROM (
 SELECT DISTINCT symbol_id,trade_date FROM ops.phase2_vci_bar_lineage
 WHERE algorithm_version='vci-exact-row-v1'
) x;

\set ON_ERROR_STOP on
DO $$ BEGIN
 IF current_database()<>'vnsignal_phase2_report_20261019' THEN
  RAISE EXCEPTION 'this evidence run requires the isolated report clone';
 END IF;
END $$;
SET application_name='phase2_public_execution_archive';
SET work_mem='8MB';
SET statement_timeout='120s';
-- Independent bounded commits; exact unchanged canonical versions insert zero.
WITH symbols AS (
 SELECT symbol_id,(row_number() OVER(ORDER BY symbol_id)-1)/15 AS batch
 FROM core.symbols s WHERE EXISTS(SELECT 1 FROM core.bars_daily_sources b
  WHERE b.symbol_id=s.symbol_id AND b.source='vndirect')
)
SELECT format('SELECT %s AS batch, clock_timestamp() AS started_at, ops.archive_phase2_public_execution_proof(ARRAY[%s]::bigint[]) AS inserted;',
 batch,string_agg(symbol_id::text,',' ORDER BY symbol_id))
FROM symbols GROUP BY batch ORDER BY batch
\gexec
SELECT status,count(*) FROM ops.phase2_public_execution_proof GROUP BY status ORDER BY status;
SELECT count(*) AS current_verified_executions FROM ops.phase2_current_public_execution_proof;

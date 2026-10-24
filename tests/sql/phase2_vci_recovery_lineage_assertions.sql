\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TimeZone='UTC';
DO $$
DECLARE sid bigint; lid bigint; jid bigint; iid uuid:=gen_random_uuid(); frame jsonb; bytes bytea;
 proof jsonb; n bigint; scope bigint[];
BEGIN
 INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
 VALUES('LINRECOV','HOSE','2097-01-01+00','2097-01-01+00') RETURNING symbol_id INTO sid;
 scope:=ARRAY[sid];
 frame:='{"attributes":{"source":"vci","route":"market.equity.ohlcv"},"rows":[{"time":"2097-01-02","open":100,"high":101,"low":99,"close":100,"volume":10}]}'::jsonb;
 bytes:=convert_to(frame::text,'UTF8');
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(iid,'vci','equity_ohlcv_quarantine','2097-01-03+00','LINRECOV',frame,encode(sha256(bytes),'hex'),bytes)
 RETURNING landing_id INTO lid;
 INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at)
 VALUES(sid,'2097-01-02',100,101,99,100,10,'unadjusted','vci',iid,'2097-01-03+00');
 IF ops.phase2_vci_recovery_evidence(lid) IS NOT NULL THEN RAISE EXCEPTION 'unowned quarantine accepted'; END IF;
 PERFORM ops.materialize_phase2_vci_lineage(scope);
 INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to,state,landed_id)
 VALUES('lineage-recovery-fixture','equity_ohlcv','LINRECOV','vci','2097-01-01','2097-01-03','COMPLETED',lid)
 RETURNING job_id INTO jid;
 IF ops.phase2_vci_recovery_evidence(lid) IS NOT NULL THEN RAISE EXCEPTION 'unaudited quarantine accepted'; END IF;
 INSERT INTO ops.bar_quality_reprocess_audit(job_id,landing_id,previous_state,resulting_state,
 previous_issue_count,resulting_issue_count,validator_version,reprocessed_at)
 VALUES(jid,lid,'PARTIAL','COMPLETED',1,0,'vn-equity-auction-extrema-v1','2097-01-04+00');
 proof:=ops.phase2_vci_recovery_evidence(lid);
 IF proof IS NULL OR proof->>'job_id'<>jid::text THEN RAISE EXCEPTION 'verified recovery omitted'; END IF;
 n:=ops.materialize_phase2_vci_lineage(scope);
 IF n<>1 OR NOT EXISTS(SELECT 1 FROM ops.phase2_vci_bar_lineage WHERE symbol_id=sid
  AND algorithm_version='vci-exact-row-v2' AND status='EXACT' AND landing_id=lid
  AND source_ordinal_1based=1 AND source_evidence->>'route'='equity_ohlcv_quarantine'
  AND source_evidence->'recovery'=proof) THEN RAISE EXCEPTION 'exact recovered source not retained'; END IF;
 PERFORM set_config('TimeZone','Asia/Ho_Chi_Minh',true);
 IF ops.materialize_phase2_vci_lineage(scope)<>0 THEN RAISE EXCEPTION 'recovery changed under timezone/retry'; END IF;
 -- A later row-quality finding invalidates this exact source candidate and hash.
 INSERT INTO ops.bar_quality_issues(job_id,landing_id,source_row,trade_date,category,reason)
 VALUES(jid,lid,0,'2097-01-02','INVALID_OHLC','fixture rejection');
 n:=ops.materialize_phase2_vci_lineage(scope);
 IF n<>1 OR NOT EXISTS(
  SELECT 1 FROM ops.phase2_vci_bar_lineage WHERE symbol_id=sid AND status='UNMATCHED'
  AND algorithm_version='vci-exact-row-v2') THEN RAISE EXCEPTION 'recovered rejected row accepted or hash stale: inserted %, results %',n,
  (SELECT jsonb_agg(to_jsonb(r)) FROM pg_temp.phase2_vci_lineage_results_work r); END IF;
 -- Unknown newer validators do not inherit older approval.
 INSERT INTO ops.bar_quality_reprocess_audit(job_id,landing_id,previous_state,resulting_state,
 previous_issue_count,resulting_issue_count,validator_version,reprocessed_at)
 VALUES(jid,lid,'PARTIAL','COMPLETED',1,0,'unreviewed-validator','2097-01-05+00');
 IF ops.phase2_vci_recovery_evidence(lid) IS NOT NULL THEN RAISE EXCEPTION 'unknown newer validator accepted'; END IF;
 DELETE FROM ops.bar_quality_reprocess_audit WHERE job_id=jid AND validator_version='unreviewed-validator';
 UPDATE ops.ingest_jobs SET symbol='OTHER' WHERE job_id=jid;
 IF ops.phase2_vci_recovery_evidence(lid) IS NOT NULL THEN RAISE EXCEPTION 'mismatched recovery job accepted'; END IF;
 UPDATE ops.ingest_jobs SET symbol='LINRECOV',date_from='2097-01-03' WHERE job_id=jid;
 DELETE FROM ops.bar_quality_issues WHERE landing_id=lid;
 PERFORM ops.materialize_phase2_vci_lineage(scope);
 IF EXISTS(SELECT 1 FROM pg_temp.phase2_vci_lineage_results_work WHERE status='EXACT') THEN
  RAISE EXCEPTION 'recovered date outside original job accepted';
 END IF;
 UPDATE ops.ingest_jobs SET date_from='2097-01-01' WHERE job_id=jid;
 INSERT INTO ops.ingest_jobs(idempotency_key,route,symbol,source,date_from,date_to,state,landed_id)
 VALUES('lineage-recovery-collision','equity_ohlcv','LINRECOV','vci','2097-01-01','2097-01-03','COMPLETED',lid);
 IF ops.phase2_vci_recovery_evidence(lid) IS NOT NULL THEN RAISE EXCEPTION 'ambiguous recovery owner accepted'; END IF;
END $$;
ROLLBACK;

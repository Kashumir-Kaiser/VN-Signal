\set ON_ERROR_STOP on
-- Synthetic provenance fixtures only; these are not market observations.
BEGIN;
SET LOCAL TimeZone='UTC';
SET LOCAL work_mem='8MB';
CREATE TEMP TABLE lineage_expected(symbol_id bigint,symbol text,expected text) ON COMMIT DROP;
DO $$
DECLARE expected text; ticker text; sid bigint; ingest uuid; frame jsonb; stored jsonb; bytes bytea; digest text;
BEGIN
 FOREACH expected IN ARRAY ARRAY['EXACT','UNMATCHED','AMBIGUOUS','MISSING_LANDING','CHECKSUM_INVALID','PAYLOAD_MISMATCH','MALFORMED','RELATIVE_TIME','BAD_SUFFIX'] LOOP
  ticker:='LIN'||(SELECT count(*)+1 FROM lineage_expected)::text;
  INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
   VALUES(ticker,'HOSE','2097-01-01+00','2097-01-01+00') RETURNING symbol_id INTO sid;
  ingest:=gen_random_uuid();
  INSERT INTO core.bars_daily(symbol_id,trade_date,o,h,l,c,v,adj_basis,source,ingest_id,fetched_at,is_traded)
   VALUES(sid,'2097-01-02',100,101,99,100,10,'unadjusted','vci',ingest,'2097-01-03+00',true);
  INSERT INTO lineage_expected VALUES(sid,ticker,CASE WHEN expected IN ('RELATIVE_TIME','BAD_SUFFIX') THEN 'MALFORMED' ELSE expected END);
  IF expected='MISSING_LANDING' THEN CONTINUE; END IF;
  frame:='{"rows":[{"time":"2097-01-01","open":100,"high":101,"low":99,"close":100,"volume":10},{"time":"2097-01-02","open":100,"high":101,"low":99,"close":100,"volume":10}]}'::jsonb;
  IF expected='UNMATCHED' THEN frame:=jsonb_set(frame,'{rows,1,volume}','11'); END IF;
  IF expected='AMBIGUOUS' THEN frame:=jsonb_set(frame,'{rows}',(frame->'rows')||jsonb_build_array(frame->'rows'->1)); END IF;
  IF expected='MALFORMED' THEN frame:=jsonb_set(frame,'{rows,0,time}','"2097-02-31"'); END IF;
  IF expected='RELATIVE_TIME' THEN frame:=jsonb_set(frame,'{rows,0,time}','"tomorrow"'); END IF;
  IF expected='BAD_SUFFIX' THEN frame:=jsonb_set(frame,'{rows,0,time}','"2097-01-01garbage"'); END IF;
  bytes:=convert_to(frame::text,'UTF8'); stored:=frame;
  digest:=encode(sha256(bytes),'hex');
  IF expected='CHECKSUM_INVALID' THEN digest:=repeat('0',64); END IF;
  IF expected='PAYLOAD_MISMATCH' THEN stored:=jsonb_set(frame,'{rows,1,volume}','12'); END IF;
  INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
   VALUES(ingest,'vci','equity_ohlcv','2097-01-03+00',ticker,stored,digest,bytes);
 END LOOP;
END $$;
SELECT ops.materialize_phase2_vci_lineage(array_agg(symbol_id ORDER BY symbol_id)) FROM lineage_expected;
DO $$
DECLARE inserted bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM lineage_expected e LEFT JOIN ops.phase2_vci_bar_lineage o USING(symbol_id)
           WHERE o.status IS DISTINCT FROM e.expected) THEN RAISE EXCEPTION 'lineage status differs from fixture'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ops.phase2_vci_bar_lineage o JOIN lineage_expected e USING(symbol_id)
               WHERE e.expected='EXACT' AND o.source_ordinal_1based=2 AND o.exact_matches=1)
    OR EXISTS(SELECT 1 FROM ops.phase2_vci_bar_lineage o JOIN lineage_expected e USING(symbol_id)
               WHERE e.expected<>'EXACT' AND o.landing_id IS NOT NULL) THEN
  RAISE EXCEPTION 'lineage chose an arbitrary ambiguous/unverified source or changed ordinal convention';
 END IF;
 PERFORM set_config('TimeZone','Asia/Ho_Chi_Minh',true);
 inserted:=ops.materialize_phase2_vci_lineage((SELECT array_agg(symbol_id ORDER BY symbol_id) FROM lineage_expected));
 IF inserted<>0 THEN RAISE EXCEPTION 'repeat or timezone change altered lineage inputs'; END IF;
 BEGIN
  UPDATE ops.phase2_vci_bar_lineage SET status='UNMATCHED' WHERE symbol_id=(SELECT symbol_id FROM lineage_expected WHERE expected='EXACT');
  RAISE EXCEPTION 'lineage mutation accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'Phase 2 lineage observations are append-only' THEN RAISE; END IF;
 END;
 BEGIN
  TRUNCATE TABLE ops.phase2_vci_bar_lineage;
  RAISE EXCEPTION 'lineage truncate accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'Phase 2 lineage observations are append-only' THEN RAISE; END IF;
 END;
 BEGIN
  TRUNCATE TABLE ops.phase2_vci_lineage_batches;
  RAISE EXCEPTION 'lineage batch truncate accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'Phase 2 lineage observations are append-only' THEN RAISE; END IF;
 END;
 IF ops.phase2_vci_row_date('2097-01-02T12:00:01.123+07:00') IS DISTINCT FROM DATE '2097-01-02'
    OR ops.phase2_vci_row_date('2097-01-02 12:00:01') IS DISTINCT FROM DATE '2097-01-02'
    OR ops.phase2_vci_row_date('2097-01-02T29:00:00') IS NOT NULL THEN
  RAISE EXCEPTION 'ISO date/time validation differs from the source contract';
 END IF;
 IF ops.phase2_try_jsonb_bytes(decode('ff','hex')) IS NOT NULL
    OR ops.phase2_try_jsonb_bytes(convert_to('not json','UTF8')) IS NOT NULL THEN
  RAISE EXCEPTION 'malformed bytes accepted as JSON';
 END IF;
END $$;
-- A changed canonical input creates a new observation; it does not erase history.
UPDATE core.bars_daily SET v=11 WHERE symbol_id=(SELECT symbol_id FROM lineage_expected WHERE expected='EXACT');
SELECT ops.materialize_phase2_vci_lineage(ARRAY[(SELECT symbol_id FROM lineage_expected WHERE expected='EXACT')]);
DO $$
BEGIN
 IF (SELECT count(*) FROM ops.phase2_vci_bar_lineage WHERE symbol_id=(SELECT symbol_id FROM lineage_expected WHERE expected='EXACT'))<>2
    OR NOT EXISTS(SELECT 1 FROM ops.phase2_vci_bar_lineage WHERE symbol_id=(SELECT symbol_id FROM lineage_expected WHERE expected='EXACT') AND status='UNMATCHED') THEN
  RAISE EXCEPTION 'changed canonical input was silently overwritten or ignored';
 END IF;
 BEGIN
  PERFORM ops.materialize_phase2_vci_lineage(ARRAY[NULL::bigint]);
  RAISE EXCEPTION 'null scope accepted';
 EXCEPTION WHEN raise_exception THEN
  IF SQLERRM<>'provide 1 to 100 distinct known symbol IDs' THEN RAISE; END IF;
 END;
END $$;
-- Empty observations still identify the exact requested symbol scope.
DO $$
DECLARE first_id bigint; second_id bigint; first_hash text; second_hash text;
BEGIN
 INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
 VALUES('LINEMPTY1','HOSE','2097-01-01+00','2097-01-01+00') RETURNING symbol_id INTO first_id;
 INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
 VALUES('LINEMPTY2','HOSE','2097-01-01+00','2097-01-01+00') RETURNING symbol_id INTO second_id;
 PERFORM ops.materialize_phase2_vci_lineage(ARRAY[first_id]);
 SELECT input_sha256 INTO first_hash FROM ops.phase2_vci_lineage_batches
 WHERE symbol_ids=ARRAY[first_id] ORDER BY batch_id DESC LIMIT 1;
 PERFORM ops.materialize_phase2_vci_lineage(ARRAY[second_id]);
 SELECT input_sha256 INTO second_hash FROM ops.phase2_vci_lineage_batches
 WHERE symbol_ids=ARRAY[second_id] ORDER BY batch_id DESC LIMIT 1;
 IF first_hash IS NULL OR second_hash IS NULL OR first_hash=second_hash THEN
  RAISE EXCEPTION 'empty lineage batch fingerprint omitted scope';
 END IF;
 PERFORM ops.materialize_phase2_vci_lineage(ARRAY[first_id,second_id]);
 SELECT input_sha256 INTO first_hash FROM ops.phase2_vci_lineage_batches ORDER BY batch_id DESC LIMIT 1;
 PERFORM ops.materialize_phase2_vci_lineage(ARRAY[second_id,first_id]);
 SELECT input_sha256 INTO second_hash FROM ops.phase2_vci_lineage_batches ORDER BY batch_id DESC LIMIT 1;
 IF first_hash IS DISTINCT FROM second_hash THEN
  RAISE EXCEPTION 'lineage scope ordering changed fingerprint';
 END IF;
END $$;
ROLLBACK;

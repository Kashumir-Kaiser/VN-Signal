\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE pilot_input(payload jsonb);
\copy pilot_input FROM 'C:/Users/HP/VN-Signal/.phase2-runtime/execution_pilot.csv' WITH CSV
DO $$
DECLARE p jsonb; l raw.landings; sid bigint; lid bigint; n bigint;
BEGIN
 SELECT payload INTO STRICT p FROM pilot_input;
 l:=jsonb_populate_record(NULL::raw.landings,p->'landing');
 IF EXISTS(SELECT 1 FROM core.symbols WHERE symbol=p->>'symbol') THEN RAISE EXCEPTION 'pilot requires absent ACB security'; END IF;
 INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
 VALUES(p->>'symbol','HOSE',l.fetched_at,l.fetched_at) RETURNING symbol_id INTO sid;
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(l.ingest_id,l.source,l.route,l.fetched_at,l.symbol,l.payload,l.payload_sha256,l.payload_bytes) RETURNING landing_id INTO lid;
 INSERT INTO core.bars_daily_sources
 SELECT (jsonb_populate_record(NULL::core.bars_daily_sources,b||jsonb_build_object('symbol_id',sid,'landing_id',lid))).*
 FROM jsonb_array_elements(p->'bars') b;
 n:=ops.archive_phase2_public_execution_proof(ARRAY[sid]);
 RAISE NOTICE 'actual native source rows %, archived %, verified %',jsonb_array_length(p->'bars'),n,
  (SELECT count(*) FROM ops.phase2_current_public_execution_proof WHERE symbol_id=sid);
 IF n<>jsonb_array_length(p->'bars') OR n=0 THEN RAISE EXCEPTION 'pilot archive missing real rows'; END IF;
 IF EXISTS(SELECT 1 FROM ops.phase2_public_execution_proof WHERE symbol_id=sid AND status<>'VERIFIED_PUBLIC_EXECUTION') THEN
  RAISE EXCEPTION 'real native ACB source qualification failed'; END IF;
 IF ops.archive_phase2_public_execution_proof(ARRAY[sid])<>0 THEN RAISE EXCEPTION 'real archive repeat not zero'; END IF;
END $$;
SELECT status,venue,count(*),min(trade_date),max(trade_date),min(available_at),max(observed_at)
FROM ops.phase2_public_execution_proof WHERE symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='ACB') GROUP BY status,venue;
ROLLBACK;

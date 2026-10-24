\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.public_execution_fixture(sym text,variant text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE sid bigint; lid bigint; body jsonb; bytes bytea; ingest uuid:=gen_random_uuid();
BEGIN
 INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at) VALUES(sym,'HOSE','2098-01-01+07','2099-05-01+07') RETURNING symbol_id INTO sid;
 WITH dates AS (SELECT trade_date,row_number() OVER(ORDER BY trade_date)-1 AS n FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date LIMIT 270)
 SELECT jsonb_build_object('data',jsonb_agg(jsonb_build_object('code',CASE WHEN variant='bad_code' THEN 'WRONG' ELSE sym END,
  'date',to_char(trade_date,'YYYY-MM-DD'),'type',CASE WHEN variant='unknown_type' THEN NULL ELSE 'STOCK' END,
  'floor',CASE WHEN variant='otc' THEN 'OTC' WHEN n<135 THEN 'HNX' ELSE 'HOSE' END,
  'open',10,'high',11,'low',9,'close',10,'nmVolume',CASE WHEN variant='zero' THEN 0 ELSE 1000 END,
  'adOpen',10,'adHigh',11,'adLow',9,'adClose',10,'basicPrice',10,'average',10) ORDER BY trade_date)) INTO body FROM dates;
 bytes:=convert_to(body::text,'UTF8');
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(ingest,'vndirect','equity_ohlcv','2099-05-01+07',sym,body,
 CASE WHEN variant='bad_hash' THEN repeat('0',64) ELSE encode(sha256(bytes),'hex') END,bytes) RETURNING landing_id INTO lid;
 INSERT INTO core.bars_daily_sources(symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at,
 adjusted_o,adjusted_h,adjusted_l,adjusted_c,adjustment_vintage_at,basic_price,average_price,exchange_code)
 SELECT sid,(r.item->>'date')::date,'vndirect',10,11,9,10,CASE WHEN variant='zero' THEN 0 ELSE 1000 END,'unadjusted',variant<>'zero',lid,(r.ordinality-1)::integer,ingest,'2099-05-01+07',
 10,11,9,10,'2099-05-01+07',10,10,CASE WHEN r.ordinality<=135 THEN 'HNX' ELSE 'HOSE' END
 FROM jsonb_array_elements(body->'data') WITH ORDINALITY r(item,ordinality);
 RETURN sid;
END $$;
DO $$
DECLARE sid bigint; bad bigint; d date[]; n bigint; old_hash text; new_hash text; lid bigint; bytes bytea:=convert_to('{"synthetic_notice":true}','UTF8');
BEGIN
 SELECT array_agg(trade_date ORDER BY trade_date) INTO d FROM core.calendar WHERE source='phase2_test_fixture';
 sid:=pg_temp.public_execution_fixture('PXBOUND','valid');
 n:=ops.archive_phase2_public_execution_proof(ARRAY[sid]);
 IF n<>270 OR ops.archive_phase2_public_execution_proof(ARRAY[sid])<>0 THEN RAISE EXCEPTION 'public execution archive count/repeat wrong'; END IF;
 IF EXISTS(SELECT 1 FROM ops.phase2_public_execution_proof WHERE symbol_id=sid
  AND (available_at IS DISTINCT FROM ((trade_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
   OR availability_basis<>'PUBLIC_EXECUTION_EVENT_RECONSTRUCTION')) THEN RAISE EXCEPTION 'event reconstruction availability wrong'; END IF;
 IF core.verified_listing_tenure(sid,d[250]) IS NOT NULL OR core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 250 THEN
  RAISE EXCEPTION 'lower-bound 249 must stay unknown; 250 strictly prior must qualify';
 END IF;
 old_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 UPDATE core.bars_daily_sources SET c=10.125 WHERE symbol_id=sid AND trade_date=d[10];
 IF core.verified_listing_tenure(sid,d[251]) IS NOT NULL THEN RAISE EXCEPTION 'stale canonical proof remained eligible'; END IF;
 new_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 IF old_hash=new_hash THEN RAISE EXCEPTION 'old proof dependency missing from label hash'; END IF;
 IF ops.archive_phase2_public_execution_proof(ARRAY[sid])<>1 THEN RAISE EXCEPTION 'changed canonical source not reobserved'; END IF;
 IF NOT EXISTS(SELECT 1 FROM ops.phase2_public_execution_proof WHERE symbol_id=sid AND trade_date=d[10] AND status='ROW_MISMATCH') THEN RAISE EXCEPTION 'source mismatch accepted'; END IF;
 UPDATE core.bars_daily_sources SET c=10 WHERE symbol_id=sid AND trade_date=d[10];
 IF core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 250 THEN RAISE EXCEPTION 'exact restored source proof not reusable'; END IF;
 PERFORM feat.build_features(d[1],d[251]);
 UPDATE feat.features_daily SET turnover_proxy_vnd=6000000000 WHERE symbol_id=sid AND feature_version='phase2-v3';
 PERFORM feat.build_phase2_label_targets_v3(d[1],d[251]);
 IF NOT EXISTS(SELECT 1 FROM feat.phase2_liquidity_tiers_v3 WHERE symbol_id=sid AND trade_date=d[250] AND membership_gate_status='INDETERMINATE' AND membership_tenure_basis='UNKNOWN')
 OR NOT EXISTS(SELECT 1 FROM feat.phase2_liquidity_tiers_v3 WHERE symbol_id=sid AND trade_date=d[251] AND membership_gate_status='ELIGIBLE' AND membership_tenure_basis='PUBLIC_EXECUTION_LOWER_BOUND' AND is_investable_member) THEN
  RAISE EXCEPTION 'persisted qualified execution membership wrong: %', (SELECT jsonb_agg(to_jsonb(m)) FROM feat.phase2_liquidity_tiers_v3 m WHERE symbol_id=sid AND trade_date IN(d[250],d[251]));
 END IF;
 -- A known future cessation does not change the evidence basis for today.
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(gen_random_uuid(),'fixture','security_lifecycle_notice','2097-01-02+07','PXBOUND',
 jsonb_build_object('source_url','https://example.invalid/future','document_date','2097-01-01'),encode(sha256(bytes),'hex'),bytes) RETURNING landing_id INTO lid;
 INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,source_landing_id,
 document_date,available_at,availability_basis,source_url,reviewed_claim)
 VALUES(sid,gen_random_uuid(),'DELISTING','HOSE',d[280],lid,'2097-01-01','2097-01-02+07','ARCHIVE_FETCH',
 'https://example.invalid/future','Synthetic announced future cessation test');
 PERFORM feat.build_phase2_label_targets_v3(d[1],d[251]);
 IF NOT EXISTS(SELECT 1 FROM feat.phase2_liquidity_tiers_v3 WHERE symbol_id=sid AND trade_date=d[251]
  AND membership_tenure_basis='PUBLIC_EXECUTION_LOWER_BOUND' AND verified_listed_sessions=250) THEN
  RAISE EXCEPTION 'future cessation mislabeled historical lower-bound basis'; END IF;
 INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,source_landing_id,
 document_date,available_at,availability_basis,source_url,reviewed_claim)
 VALUES(sid,gen_random_uuid(),'ADMISSION','HOSE',d[281],lid,'2097-01-01','2097-01-02+07','ARCHIVE_FETCH',
 'https://example.invalid/future','Synthetic announced admission conflicts with older unidentified executions');
 IF core.verified_listing_tenure(sid,d[251]) IS NOT NULL THEN RAISE EXCEPTION 'announced future admission bypassed identity fence'; END IF;
 bad:=pg_temp.public_execution_fixture('PXOTC','otc');PERFORM ops.archive_phase2_public_execution_proof(ARRAY[bad]);
 IF core.verified_listing_tenure(bad,d[271]) IS NOT NULL OR EXISTS(SELECT 1 FROM ops.phase2_current_public_execution_proof WHERE symbol_id=bad) THEN RAISE EXCEPTION 'OTC source qualified'; END IF;
 bad:=pg_temp.public_execution_fixture('PXTYPE','unknown_type');PERFORM ops.archive_phase2_public_execution_proof(ARRAY[bad]);
 IF EXISTS(SELECT 1 FROM ops.phase2_current_public_execution_proof WHERE symbol_id=bad) THEN RAISE EXCEPTION 'missing stock type qualified'; END IF;
 bad:=pg_temp.public_execution_fixture('PXZERO','zero');PERFORM ops.archive_phase2_public_execution_proof(ARRAY[bad]);
 IF EXISTS(SELECT 1 FROM ops.phase2_current_public_execution_proof WHERE symbol_id=bad) THEN RAISE EXCEPTION 'zero volume qualified'; END IF;
 bad:=pg_temp.public_execution_fixture('PXCODE','bad_code');PERFORM ops.archive_phase2_public_execution_proof(ARRAY[bad]);
 IF EXISTS(SELECT 1 FROM ops.phase2_current_public_execution_proof WHERE symbol_id=bad) THEN RAISE EXCEPTION 'wrong security code qualified'; END IF;
 bad:=pg_temp.public_execution_fixture('PXHASH','bad_hash');PERFORM ops.archive_phase2_public_execution_proof(ARRAY[bad]);
 IF EXISTS(SELECT 1 FROM ops.phase2_current_public_execution_proof WHERE symbol_id=bad) THEN RAISE EXCEPTION 'bad byte hash qualified'; END IF;
 IF ops.phase2_json_float_matches('1e1000'::jsonb,1) OR ops.phase2_json_float_matches('"10"'::jsonb,10)
 OR NOT ops.phase2_json_float_matches('0.30000000000000004'::jsonb,0.30000000000000004::float8) THEN RAISE EXCEPTION 'numeric coercion/overflow/exactness guard failed'; END IF;
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(gen_random_uuid(),'fixture','security_lifecycle_notice','2097-01-01+07','PXBOUND',convert_from(bytes,'UTF8')::jsonb,encode(sha256(bytes),'hex'),bytes) RETURNING landing_id INTO lid;
 INSERT INTO core.security_lifecycle_evidence(symbol_id,exchange,evidence_type,date_from,source_landing_id,source_url,source_document_date)
 VALUES(sid,'HOSE','DELISTED',d[200],lid,'https://example.invalid/synthetic-closure','2097-01-01');
 IF core.verified_listing_tenure(sid,d[251]) IS NOT NULL THEN RAISE EXCEPTION 'execution proof bypassed known unreconciled closure'; END IF;
END $$;
ROLLBACK;

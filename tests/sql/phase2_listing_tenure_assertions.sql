\set ON_ERROR_STOP on
-- Synthetic-only legal notices. No vendor endpoint or real tenure is claimed.
BEGIN;
CREATE FUNCTION pg_temp.listing_event(sym text,ep integer,kind text,venue text,day date,
 prior text DEFAULT NULL,ceased date DEFAULT NULL,known timestamptz DEFAULT '2097-01-02+07')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE lid bigint; sid bigint; body jsonb:=jsonb_build_object('synthetic_legal_notice',sym,'kind',kind,'day',day,'source_url','https://example.invalid/synthetic-notice','document_date','2097-01-01');
BEGIN
 SELECT symbol_id INTO STRICT sid FROM core.symbols WHERE symbol=sym;
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(md5(sym||ep||kind||day||coalesce(prior,''))::uuid,'fixture','security_lifecycle_notice','2097-01-02+07',sym,body,
 encode(sha256(convert_to(body::text,'UTF8')),'hex'),convert_to(body::text,'UTF8')) RETURNING landing_id INTO lid;
 INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,prior_venue,prior_ceased_from,
 source_landing_id,continuity_landing_id,document_date,available_at,availability_basis,source_url,reviewed_claim)
 VALUES(sid,md5(sym||ep)::uuid,kind,venue,day,prior,ceased,lid,CASE WHEN kind='TRANSFER' THEN lid END,
 '2097-01-01',known,'ARCHIVE_FETCH','https://example.invalid/synthetic-notice',
 'Synthetic-only explicit admission, closure or same-identity transfer proof');
END $$;
DO $$
DECLARE d date[]; sid bigint; before_hash text; after_hash text; n integer;
BEGIN
 SELECT array_agg(trade_date ORDER BY trade_date) INTO d FROM core.calendar WHERE source='phase2_test_fixture';
 IF cardinality(d)<300 THEN RAISE EXCEPTION 'tenure test requires 300 synthetic sessions'; END IF;
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2READY';
 IF core.verified_listing_tenure(sid,d[251]) IS NOT NULL THEN RAISE EXCEPTION 'missing admission inferred from bars'; END IF;
 before_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 PERFORM pg_temp.listing_event('P2READY',1,'ADMISSION','HOSE',d[1]);
 IF core.verified_listing_tenure(sid,d[250]) IS DISTINCT FROM 249 OR core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 250 THEN
  RAISE EXCEPTION '250 boundary must count strictly prior actual sessions';
 END IF;
 after_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 IF before_hash=after_hash THEN RAISE EXCEPTION 'admission omitted from label dependency hash'; END IF;
 before_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 UPDATE core.calendar SET is_session=false WHERE trade_date=d[1];
 after_hash:=ops.phase2_label_target_chunk_base_input_hash(d[250],d[251]);
 UPDATE core.calendar SET is_session=true WHERE trade_date=d[1];
 IF before_hash=after_hash THEN RAISE EXCEPTION 'old calendar session omitted from tenure input hash'; END IF;
 BEGIN
  INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,source_landing_id,document_date,available_at,availability_basis,source_url,reviewed_claim,supersedes_event_id)
  SELECT symbol_id,episode_id,'WITHDRAWAL',venue,effective_date,source_landing_id,document_date,available_at,availability_basis,'https://example.invalid/wrong-url','Synthetic intentionally mismatched source URL claim',event_id
   FROM core.security_listing_events WHERE symbol_id=sid;
  RAISE EXCEPTION 'bad source URL accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='bad source URL accepted' THEN RAISE; END IF; END;
 BEGIN
  INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,source_landing_id,document_date,available_at,availability_basis,source_url,reviewed_claim)
  SELECT (SELECT symbol_id FROM core.symbols WHERE symbol='P2MISS'),episode_id,'ADMISSION',venue,effective_date,source_landing_id,document_date,available_at,availability_basis,source_url,'Synthetic intentionally mismatched security claim'
   FROM core.security_listing_events WHERE symbol_id=sid;
  RAISE EXCEPTION 'wrong-security notice accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='wrong-security notice accepted' THEN RAISE; END IF; END;
 -- A suspension is a trading restriction, not a legal cessation.
 INSERT INTO core.security_lifecycle_evidence(symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,source_document_date)
 SELECT sid,'HOSE','TRADING_SUSPENDED',d[201],d[220],source_landing_id,source_url,document_date FROM core.security_listing_events WHERE symbol_id=sid;
 IF core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 250 THEN RAISE EXCEPTION 'suspension reduced legal tenure'; END IF;
 PERFORM pg_temp.listing_event('P2ENTRY',1,'ADMISSION','HNX',d[1]);
 PERFORM pg_temp.listing_event('P2ENTRY',1,'TRANSFER','HOSE',d[111],'HNX',d[101]);
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2ENTRY';
 IF core.verified_listing_tenure(sid,d[105]) IS DISTINCT FROM 0 OR core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 240 THEN
  RAISE EXCEPTION 'transfer gap or preserved identity count wrong';
 END IF;
 -- Future-effective transfer whose cessation is already in the chunk must hash.
 before_hash:=ops.phase2_label_target_chunk_base_input_hash(d[100],d[105]);
 PERFORM pg_temp.listing_event('P2EXIT',1,'ADMISSION','HNX',d[1]);
 PERFORM pg_temp.listing_event('P2EXIT',1,'TRANSFER','HOSE',d[111],'HNX',d[101]);
 after_hash:=ops.phase2_label_target_chunk_base_input_hash(d[100],d[105]);
 IF before_hash=after_hash THEN RAISE EXCEPTION 'announced transfer gap omitted from hash'; END IF;
 PERFORM pg_temp.listing_event('P2EXIT',1,'DELISTING','HOSE',d[261]);
 PERFORM pg_temp.listing_event('P2EXIT',2,'ADMISSION','HOSE',d[271]);
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2EXIT';
 IF core.verified_listing_tenure(sid,d[265]) IS DISTINCT FROM 0 OR core.verified_listing_tenure(sid,d[281]) IS DISTINCT FROM 10 THEN
  RAISE EXCEPTION 'delisting/relisting did not close/reset episode';
 END IF;
 PERFORM pg_temp.listing_event('P2ZERO',1,'ADMISSION','HOSE',d[1],NULL,NULL,(d[251]::timestamp+time '16:00') AT TIME ZONE 'Asia/Ho_Chi_Minh');
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2ZERO';
 IF core.verified_listing_tenure(sid,d[251]) IS NOT NULL OR core.verified_listing_tenure(sid,d[252]) IS DISTINCT FROM 251 THEN
  RAISE EXCEPTION 'after-close legal notice leaked or missed next session';
 END IF;
 PERFORM pg_temp.listing_event('P2ZERO',2,'ADMISSION','HNX',d[253]);
 IF core.verified_listing_tenure(sid,d[254]) IS NOT NULL THEN RAISE EXCEPTION 'conflicting open admissions accepted'; END IF;
 -- Correct an erroneous review append-only; historical conflict remains
 -- visible until the correction was actually available.
 INSERT INTO core.security_listing_events(symbol_id,episode_id,event_type,venue,effective_date,source_landing_id,
 document_date,available_at,availability_basis,source_url,reviewed_claim,supersedes_event_id)
 SELECT symbol_id,episode_id,'WITHDRAWAL',venue,effective_date,source_landing_id,document_date,
 (d[254]::timestamp+time '16:00') AT TIME ZONE 'Asia/Ho_Chi_Minh','ARCHIVE_FETCH',source_url,
 'Synthetic correction withdraws erroneous duplicate open admission',event_id
 FROM core.security_listing_events WHERE symbol_id=sid AND event_type='ADMISSION' AND effective_date=d[253];
 IF core.verified_listing_tenure(sid,d[254]) IS NOT NULL OR core.verified_listing_tenure(sid,d[255]) IS DISTINCT FROM 254 THEN
  RAISE EXCEPTION 'append-only correction leaked backward or failed to restore valid history';
 END IF;
 PERFORM pg_temp.listing_event('P2MISS',1,'ADMISSION','HOSE',d[1]);
 PERFORM pg_temp.listing_event('P2MISS',1,'DELISTING','HOSE',d[201]);
 PERFORM pg_temp.listing_event('P2MISS',2,'ADMISSION','HOSE',d[201]);
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2MISS';
 IF core.verified_listing_tenure(sid,d[201]) IS DISTINCT FROM 0 OR core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 50 THEN
  RAISE EXCEPTION 'same-day cessation/readmission did not reset tenure';
 END IF;
 -- Exercise the persisted consumer using explicit synthetic liquidity.
 PERFORM feat.build_price_features_v3(d[1],d[251]);
 UPDATE feat.features_daily SET turnover_proxy_vnd=6000000000
  WHERE feature_version='phase2-v3' AND symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='P2READY') AND trade_date BETWEEN d[1] AND d[251];
 PERFORM feat.build_phase2_label_targets_v3(d[1],d[251]);
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2READY';
 IF NOT EXISTS(SELECT 1 FROM feat.phase2_liquidity_tiers_v3 WHERE symbol_id=sid AND trade_date=d[250] AND verified_listed_sessions=249 AND membership_gate_status='INELIGIBLE' AND NOT is_investable_member)
 OR NOT EXISTS(SELECT 1 FROM feat.phase2_liquidity_tiers_v3 WHERE symbol_id=sid AND trade_date=d[251] AND verified_listed_sessions=250 AND membership_gate_status='ELIGIBLE' AND is_investable_member) THEN
  RAISE EXCEPTION 'persisted membership missed verified tenure boundary';
 END IF;
 DROP TABLE IF EXISTS pg_temp.phase2_listing_session_prefix;
 -- The production prefix strategy must agree with standalone range counting.
 CREATE TEMP TABLE phase2_listing_session_prefix ON COMMIT DROP AS
 SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS session_no FROM core.effective_trading_sessions WHERE is_session;
 ALTER TABLE pg_temp.phase2_listing_session_prefix ADD PRIMARY KEY(trade_date);
 SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='P2ENTRY';
 IF ops.phase2_verified_listing_tenure(sid,d[251],true) IS DISTINCT FROM 240 THEN RAISE EXCEPTION 'prefix tenure differs from direct calendar'; END IF;
 UPDATE core.calendar SET is_session=false WHERE trade_date=d[1];
 IF core.verified_listing_tenure(sid,d[251]) IS DISTINCT FROM 239 THEN RAISE EXCEPTION 'public tenure read stale temporary prefix'; END IF;
 UPDATE core.calendar SET is_session=true WHERE trade_date=d[1];
 BEGIN
  UPDATE core.security_listing_events SET reviewed_claim='mutated synthetic source claim';
  RAISE EXCEPTION 'append-only update accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='append-only update accepted' THEN RAISE; END IF; END;
 BEGIN
  TRUNCATE core.security_listing_events;
  RAISE EXCEPTION 'append-only truncate accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM='append-only truncate accepted' THEN RAISE; END IF; END;
END $$;
ROLLBACK;

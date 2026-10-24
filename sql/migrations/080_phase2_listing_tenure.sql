BEGIN;
-- Reviewed legal events: PDF/HTML bytes are preserved; JSON metadata is a
-- separately reviewed claim, not an automatic interpretation of those bytes.
-- One notice may explicitly establish both transfer and identity continuity.
-- These events are distinct from price observations and zero-volume
-- classifications. Delisting dates are effective cessation dates (exclusive).
CREATE TABLE IF NOT EXISTS core.security_listing_events (
 event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
 episode_id uuid NOT NULL,
 event_type text NOT NULL CHECK(event_type IN ('ADMISSION','TRANSFER','DELISTING')),
 venue text NOT NULL CHECK(venue IN ('HOSE','HNX','UPCOM')),
 effective_date date NOT NULL,
 prior_venue text CHECK(prior_venue IN ('HOSE','HNX','UPCOM')),
 prior_ceased_from date,
 source_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
 continuity_landing_id bigint REFERENCES raw.landings(landing_id),
 document_date date NOT NULL,
 available_at timestamptz NOT NULL,
 availability_basis text NOT NULL CHECK(availability_basis IN ('ARCHIVE_FETCH','VERIFIED_PUBLICATION')),
 source_url text NOT NULL CHECK(source_url ~ '^https://[^[:space:]]+$'),
 reviewed_claim text NOT NULL CHECK(length(trim(reviewed_claim))>=20),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((event_type='TRANSFER')=(prior_venue IS NOT NULL AND prior_ceased_from IS NOT NULL AND continuity_landing_id IS NOT NULL)),
 CHECK(event_type='TRANSFER' OR (prior_venue IS NULL AND prior_ceased_from IS NULL AND continuity_landing_id IS NULL)),
 CHECK(prior_venue IS NULL OR prior_venue<>venue),
 CHECK(prior_ceased_from IS NULL OR prior_ceased_from<=effective_date),
 CHECK(isfinite(effective_date) AND isfinite(document_date) AND isfinite(available_at)),
 UNIQUE(symbol_id,episode_id,event_type,effective_date,source_landing_id)
);
ALTER TABLE core.security_listing_events ADD COLUMN IF NOT EXISTS supersedes_event_id bigint REFERENCES core.security_listing_events(event_id);
ALTER TABLE core.security_listing_events DROP CONSTRAINT IF EXISTS security_listing_events_event_type_check;
ALTER TABLE core.security_listing_events ADD CONSTRAINT security_listing_events_event_type_check CHECK(event_type IN ('ADMISSION','TRANSFER','DELISTING','WITHDRAWAL'));
ALTER TABLE core.security_listing_events DROP CONSTRAINT IF EXISTS security_listing_events_supersedes_check;
ALTER TABLE core.security_listing_events ADD CONSTRAINT security_listing_events_supersedes_check CHECK((supersedes_event_id IS NULL OR supersedes_event_id<event_id) AND (event_type<>'WITHDRAWAL' OR supersedes_event_id IS NOT NULL));
CREATE UNIQUE INDEX IF NOT EXISTS security_listing_event_one_successor ON core.security_listing_events(supersedes_event_id) WHERE supersedes_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS security_listing_event_lookup
 ON core.security_listing_events(symbol_id,effective_date,available_at);
CREATE OR REPLACE FUNCTION core.verify_listing_event_source() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE l record; expected_symbol text; lid bigint; prior_event record;
BEGIN
 SELECT symbol INTO STRICT expected_symbol FROM core.symbols WHERE symbol_id=NEW.symbol_id;
 IF NEW.supersedes_event_id IS NOT NULL THEN
  SELECT * INTO STRICT prior_event FROM core.security_listing_events WHERE event_id=NEW.supersedes_event_id;
  IF prior_event.symbol_id<>NEW.symbol_id OR prior_event.available_at>NEW.available_at THEN
   RAISE EXCEPTION 'listing correction must preserve security and cannot predate original knowledge';
  END IF;
 END IF;
 FOREACH lid IN ARRAY array_remove(ARRAY[NEW.source_landing_id,NEW.continuity_landing_id],NULL) LOOP
  SELECT * INTO STRICT l FROM raw.landings WHERE landing_id=lid;
  IF l.symbol IS DISTINCT FROM expected_symbol OR l.route<>'security_lifecycle_notice'
    OR l.payload_bytes IS NULL OR length(l.payload_bytes)<2
    OR encode(sha256(l.payload_bytes),'hex')<>lower(l.payload_sha256) THEN
   RAISE EXCEPTION 'listing event requires intact same-security lifecycle source';
  END IF;
  IF l.payload->>'source_url' IS NULL OR l.payload->>'source_url' !~ '^https://[^[:space:]]+$'
    OR coalesce(l.payload->>'document_date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    OR NOT isfinite((l.payload->>'document_date')::date)
    OR NEW.available_at<(((l.payload->>'document_date')::date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
    OR (lid=NEW.source_landing_id AND (l.payload->>'source_url' IS DISTINCT FROM NEW.source_url OR (l.payload->>'document_date')::date<>NEW.document_date)) THEN
   RAISE EXCEPTION 'listing claim URL/date/availability must match archived notice metadata';
  END IF;
  IF NEW.availability_basis='ARCHIVE_FETCH' AND NEW.available_at<l.fetched_at THEN
   RAISE EXCEPTION 'archive-fetch availability precedes source capture';
  END IF;
 END LOOP;
 -- A date-only publication claim never grants knowledge before that day's
 -- close. Verified publication requires explicit human-reviewed source proof.
 IF NEW.available_at < ((NEW.document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh') THEN
  RAISE EXCEPTION 'listing notice availability must follow its document date';
 END IF;
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS security_listing_event_source ON core.security_listing_events;
CREATE TRIGGER security_listing_event_source BEFORE INSERT ON core.security_listing_events
 FOR EACH ROW EXECUTE FUNCTION core.verify_listing_event_source();
DROP TRIGGER IF EXISTS security_listing_event_append_only ON core.security_listing_events;
CREATE TRIGGER security_listing_event_append_only BEFORE UPDATE OR DELETE ON core.security_listing_events
 FOR EACH ROW EXECUTE FUNCTION core.reject_lifecycle_evidence_mutation();
DROP TRIGGER IF EXISTS security_listing_event_no_truncate ON core.security_listing_events;
CREATE TRIGGER security_listing_event_no_truncate BEFORE TRUNCATE ON core.security_listing_events
 FOR EACH STATEMENT EXECUTE FUNCTION core.reject_lifecycle_evidence_mutation();

CREATE OR REPLACE FUNCTION ops.phase2_verified_listing_tenure(p_symbol bigint,p_signal date,p_use_prefix boolean)
RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE e record; admitted date; start_date date; current_venue text;
 episode uuid; ceased boolean:=false; covered daterange[]:='{}'; n integer;
 cutoff timestamptz:=(p_signal::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh';
 previous_date date; previous_kind text; seen_episodes uuid[]:='{}'; span daterange; hi integer; lo integer;
BEGIN
 IF p_symbol IS NULL OR p_signal IS NULL OR NOT isfinite(p_signal) THEN RETURN NULL; END IF;
 -- Duplicate independent agreeing evidence is harmless; contradictory events
 -- or mismatched identities fail closed. Future events never reset old tenure.
 FOR e IN SELECT * FROM (SELECT DISTINCT episode_id,event_type,venue,effective_date,prior_venue,prior_ceased_from
   FROM core.security_listing_events ev WHERE symbol_id=p_symbol AND available_at<=cutoff AND event_type<>'WITHDRAWAL'
    AND NOT EXISTS(SELECT 1 FROM core.security_listing_events correction WHERE correction.supersedes_event_id=ev.event_id AND correction.available_at<=cutoff)
    AND (effective_date<=p_signal OR (event_type='TRANSFER' AND prior_ceased_from<=p_signal))) known_events ORDER BY effective_date,CASE event_type WHEN 'DELISTING' THEN 0 WHEN 'ADMISSION' THEN 1 ELSE 2 END,episode_id,venue
 LOOP
  IF previous_date=e.effective_date AND NOT (previous_kind='DELISTING' AND e.event_type='ADMISSION') THEN RETURN NULL; END IF;
  previous_date:=e.effective_date;previous_kind:=e.event_type;
  IF e.event_type='ADMISSION' THEN
   IF admitted IS NOT NULL AND NOT ceased THEN RETURN NULL; END IF;
   IF e.episode_id=ANY(seen_episodes) THEN RETURN NULL; END IF;
   seen_episodes:=array_append(seen_episodes,e.episode_id);
   admitted:=e.effective_date;start_date:=admitted;episode:=e.episode_id;
   current_venue:=e.venue;ceased:=false;covered:='{}';
  ELSIF e.event_type='DELISTING' THEN
   IF admitted IS NULL OR ceased OR episode<>e.episode_id OR current_venue<>e.venue THEN RETURN NULL; END IF;
   ceased:=true;
  ELSE
   IF admitted IS NULL OR ceased OR episode<>e.episode_id OR current_venue<>e.prior_venue
     OR e.prior_ceased_from<start_date THEN RETURN NULL; END IF;
   covered:=array_append(covered,daterange(start_date,e.prior_ceased_from,'[)'));
   IF e.effective_date>p_signal THEN RETURN 0; END IF;
   start_date:=e.effective_date;current_venue:=e.venue;
  END IF;
 END LOOP;
 IF admitted IS NULL THEN RETURN NULL; END IF;
 IF ceased THEN RETURN 0; END IF;
 covered:=array_append(covered,daterange(start_date,p_signal,'[)'));
 IF p_use_prefix AND to_regclass('pg_temp.phase2_listing_session_prefix') IS NOT NULL THEN
  IF NOT EXISTS(SELECT 1 FROM pg_temp.phase2_listing_session_prefix WHERE trade_date>=p_signal) THEN
   SELECT count(*)::integer INTO n FROM core.effective_trading_sessions s WHERE s.is_session AND s.trade_date<p_signal AND s.trade_date>=admitted AND EXISTS(SELECT 1 FROM unnest(covered) r WHERE r @> s.trade_date);
   RETURN n;
  END IF;
  n:=0;
  FOREACH span IN ARRAY covered LOOP
   IF isempty(span) THEN CONTINUE; END IF;
   SELECT session_no INTO hi FROM pg_temp.phase2_listing_session_prefix WHERE trade_date<upper(span) ORDER BY trade_date DESC LIMIT 1;
   SELECT session_no INTO lo FROM pg_temp.phase2_listing_session_prefix WHERE trade_date<lower(span) ORDER BY trade_date DESC LIMIT 1;
   n:=n+coalesce(hi,0)-coalesce(lo,0);
  END LOOP;
 ELSE
  SELECT count(*)::integer INTO n FROM core.effective_trading_sessions s
   WHERE s.is_session AND s.trade_date<p_signal AND s.trade_date>=admitted
    AND EXISTS(SELECT 1 FROM unnest(covered) r WHERE r @> s.trade_date);
 END IF;
 RETURN n;
END $$;
CREATE OR REPLACE FUNCTION core.verified_listing_tenure(p_symbol bigint,p_signal date)
RETURNS integer LANGUAGE sql STABLE AS $$
 SELECT ops.phase2_verified_listing_tenure(p_symbol,p_signal,false)
$$;
COMMENT ON FUNCTION core.verified_listing_tenure(bigint,date) IS
 'Verified legal sessions strictly before local signal date in the current admission episode. Suspensions do not subtract legal tenure. Explicit documented transfers preserve identity but exclude no-venue gaps. Effective delisting closes tenure; relisting requires a new episode. Known closed episodes and no-venue transfer gaps return zero. Missing/conflicting or unavailable evidence returns NULL. No bar, current snapshot or incorporation-date inference.';

DO $listing_consumer$
DECLARE d text:=pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
 a text;
BEGIN
 IF position('core.verified_listing_tenure' IN d)>0 THEN
  EXECUTE replace(d,'core.verified_listing_tenure(symbol_id,trade_date)','ops.phase2_verified_listing_tenure(symbol_id,trade_date,true)');
  RETURN;
 END IF;
 IF position('ops.phase2_verified_listing_tenure' IN d)>0 THEN RETURN; END IF;
 a:='    DROP TABLE IF EXISTS pg_temp.phase2_label_liquidity_median;';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'listing prefix initialization anchor missing'; END IF;
 d:=replace(d,a,'    DROP TABLE IF EXISTS pg_temp.phase2_listing_session_prefix;
    CREATE TEMP TABLE phase2_listing_session_prefix ON COMMIT DROP AS
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS session_no
      FROM core.effective_trading_sessions WHERE is_session AND trade_date<=p_date_to;
    ALTER TABLE pg_temp.phase2_listing_session_prefix ADD PRIMARY KEY(trade_date);
    ANALYZE pg_temp.phase2_listing_session_prefix;
' || a);
 a:='NULL::integer AS verified_listed_sessions,';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'listing count consumer anchor missing'; END IF;
 d:=replace(d,a,'tenure.verified_listed_sessions AS verified_listed_sessions,');
 a:='CASE WHEN proxy_count20=20 AND average_turnover_proxy20<5000000000 THEN ''INELIGIBLE''';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'listing eligibility consumer anchor missing'; END IF;
 d:=replace(d,a,'CASE WHEN proxy_count20=20 AND average_turnover_proxy20<5000000000 THEN ''INELIGIBLE''
                WHEN tenure.verified_listed_sessions<250 THEN ''INELIGIBLE''
                WHEN proxy_count20=20 AND tenure.verified_listed_sessions>=250 THEN ''ELIGIBLE''
                ');
 a:='FROM windows WHERE trade_date BETWEEN v_first_signal AND p_date_to;';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'listing lookup materialization anchor missing'; END IF;
 d:=replace(d,a,'FROM windows CROSS JOIN LATERAL (SELECT ops.phase2_verified_listing_tenure(symbol_id,trade_date,true) AS verified_listed_sessions OFFSET 0) tenure WHERE trade_date BETWEEN v_first_signal AND p_date_to;');
 EXECUTE d;
END $listing_consumer$;
DO $listing_hash$
DECLARE d text:=pg_get_functiondef('ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure);
 a text:='RETURN ops.phase2_hash_text(v_hash||''|liquidity_context=''||v_context||''|prior_membership=''||v_prior_state);';
BEGIN
 IF position('|listing_tenure=v2|' IN d)>0 THEN RETURN; END IF;
 IF position('|listing_tenure=v1|' IN d)>0 THEN d:=regexp_replace(d,'RETURN ops[.]phase2_hash_text[(]v_hash[|][|].*?;',a,'s'); END IF;
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'listing input hash anchor missing'; END IF;
 d:=replace(d,a,'RETURN ops.phase2_hash_text(v_hash||''|liquidity_context=''||v_context||''|prior_membership=''||v_prior_state||''|listing_tenure=v2|''||
   coalesce((SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(e)-''recorded_at''),'''' ORDER BY e.event_id)
    FROM core.security_listing_events e WHERE e.available_at<=((p_date_to::timestamp+time ''15:00'') AT TIME ZONE ''Asia/Ho_Chi_Minh'')),'''')||''|listing_calendar=''||coalesce((SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(c)),'''' ORDER BY c.trade_date) FROM core.effective_trading_sessions c WHERE c.trade_date<=p_date_to),''''));');
 EXECUTE d;
END $listing_hash$;
COMMIT;

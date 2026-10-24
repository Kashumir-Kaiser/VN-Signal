BEGIN;
-- A positive, exact public-market execution is a sufficient lower-bound
-- observation under the canonical provider-security identity used for prices.
-- It is not an exact admission date, ISIN assertion, or continuity certificate.
CREATE OR REPLACE FUNCTION ops.phase2_execution_bar_hash(b core.bars_daily_sources)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
 SELECT ops.phase2_hash_jsonb(jsonb_build_array(b.symbol_id,to_char(b.trade_date,'YYYY-MM-DD'),b.source,
 b.ingest_id,b.landing_id,b.source_row,extract(epoch FROM b.fetched_at),b.is_traded,b.exchange_code,
 encode(float8send(b.o),'hex'),encode(float8send(b.h),'hex'),encode(float8send(b.l),'hex'),encode(float8send(b.c),'hex'),encode(float8send(b.v),'hex')))
$$;
CREATE OR REPLACE FUNCTION ops.phase2_json_float_matches(j jsonb,v double precision)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
 SELECT CASE WHEN jsonb_typeof(j)='number' AND pg_input_is_valid(j#>>'{}','double precision')
 THEN (j#>>'{}')::float8=v AND abs(v)<'Infinity'::float8 ELSE false END
$$;
CREATE TABLE IF NOT EXISTS ops.phase2_public_execution_proof (
 proof_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
 trade_date date NOT NULL,
 source text NOT NULL CHECK(source='vndirect'),
 algorithm_version text NOT NULL CHECK(algorithm_version='vndirect-public-execution-v1'),
 canonical_sha256 text NOT NULL CHECK(canonical_sha256 ~ '^[0-9a-f]{64}$'),
 landing_id bigint REFERENCES raw.landings(landing_id),
 source_row integer CHECK(source_row>=0),
 status text NOT NULL CHECK(status IN ('VERIFIED_PUBLIC_EXECUTION','NON_EXECUTION','INVALID_SOURCE','UNQUALIFIED_MARKET','ROW_MISMATCH')),
 venue text CHECK(venue IN ('HOSE','HNX','UPCOM')),
 observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(status<>'VERIFIED_PUBLIC_EXECUTION' OR (landing_id IS NOT NULL AND source_row IS NOT NULL AND venue IS NOT NULL)),
 UNIQUE(symbol_id,trade_date,source,algorithm_version,canonical_sha256)
);
CREATE INDEX IF NOT EXISTS phase2_public_execution_lookup ON ops.phase2_public_execution_proof(symbol_id,trade_date);
-- Event availability is reconstructed from a dated public execution. Keep
-- the later capture time in the landing; this is not an original vendor vintage.
ALTER TABLE ops.phase2_public_execution_proof ADD COLUMN IF NOT EXISTS available_at timestamptz
 GENERATED ALWAYS AS ((trade_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh') STORED;
ALTER TABLE ops.phase2_public_execution_proof ADD COLUMN IF NOT EXISTS availability_basis text
 GENERATED ALWAYS AS ('PUBLIC_EXECUTION_EVENT_RECONSTRUCTION'::text) STORED;
DROP TRIGGER IF EXISTS public_execution_no_mutation ON ops.phase2_public_execution_proof;
CREATE TRIGGER public_execution_no_mutation BEFORE UPDATE OR DELETE ON ops.phase2_public_execution_proof
 FOR EACH ROW EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();
DROP TRIGGER IF EXISTS public_execution_no_truncate ON ops.phase2_public_execution_proof;
CREATE TRIGGER public_execution_no_truncate BEFORE TRUNCATE ON ops.phase2_public_execution_proof
 FOR EACH STATEMENT EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();

CREATE OR REPLACE FUNCTION ops.archive_phase2_public_execution_proof(p_symbols bigint[])
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
 IF p_symbols IS NULL OR cardinality(p_symbols) NOT BETWEEN 1 AND 100 OR array_position(p_symbols,NULL) IS NOT NULL
 OR cardinality(p_symbols)<>(SELECT count(DISTINCT x) FROM unnest(p_symbols) x)
 OR EXISTS(SELECT 1 FROM unnest(p_symbols) x WHERE NOT EXISTS(SELECT 1 FROM core.symbols WHERE symbol_id=x)) THEN
  RAISE EXCEPTION 'provide 1 to 100 distinct known symbol IDs';
 END IF;
 WITH bars AS MATERIALIZED (
  SELECT b.*,s.symbol,ops.phase2_execution_bar_hash(b) AS canonical_hash
  FROM core.bars_daily_sources b JOIN core.symbols s USING(symbol_id)
  WHERE b.source='vndirect' AND b.symbol_id=ANY(p_symbols)
 ), landings AS MATERIALIZED (
  SELECT l.*,encode(sha256(l.payload_bytes),'hex')=lower(l.payload_sha256)
    AND ops.phase2_try_jsonb_bytes(l.payload_bytes)=l.payload AS intact
  FROM raw.landings l JOIN (SELECT DISTINCT landing_id FROM bars) b USING(landing_id)
 ), rows AS MATERIALIZED (
  SELECT l.landing_id,(r.ordinality-1)::integer AS source_row,r.item
  FROM landings l CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN l.intact AND jsonb_typeof(l.payload->'data')='array'
    THEN l.payload->'data' ELSE '[]'::jsonb END) WITH ORDINALITY r(item,ordinality)
 ), checked AS (
  SELECT b.*,CASE r.item->>'floor' WHEN 'HSX' THEN 'HOSE' ELSE r.item->>'floor' END AS venue,
   CASE WHEN NOT coalesce(l.intact,false) OR l.source<>'vndirect' OR l.route<>'equity_ohlcv'
      OR l.symbol IS DISTINCT FROM b.symbol OR l.ingest_id<>b.ingest_id OR l.fetched_at<>b.fetched_at THEN 'INVALID_SOURCE'
    WHEN r.item IS NULL OR r.item->>'code' IS DISTINCT FROM b.symbol OR r.item->>'date' IS DISTINCT FROM to_char(b.trade_date,'YYYY-MM-DD')
      OR jsonb_typeof(r.item->'open') IS DISTINCT FROM 'number' OR jsonb_typeof(r.item->'high') IS DISTINCT FROM 'number'
      OR jsonb_typeof(r.item->'low') IS DISTINCT FROM 'number' OR jsonb_typeof(r.item->'close') IS DISTINCT FROM 'number'
      OR jsonb_typeof(r.item->'nmVolume') IS DISTINCT FROM 'number' THEN 'ROW_MISMATCH'
    WHEN NOT ops.phase2_json_float_matches(r.item->'open',b.o) OR NOT ops.phase2_json_float_matches(r.item->'high',b.h)
      OR NOT ops.phase2_json_float_matches(r.item->'low',b.l) OR NOT ops.phase2_json_float_matches(r.item->'close',b.c)
      OR NOT ops.phase2_json_float_matches(r.item->'nmVolume',b.v) THEN 'ROW_MISMATCH'
    WHEN r.item->>'type' IS DISTINCT FROM 'STOCK' OR coalesce(r.item->>'floor','') NOT IN ('HOSE','HSX','HNX','UPCOM')
      OR (CASE r.item->>'floor' WHEN 'HSX' THEN 'HOSE' ELSE r.item->>'floor' END) IS DISTINCT FROM (CASE b.exchange_code WHEN 'HSX' THEN 'HOSE' ELSE b.exchange_code END) THEN 'UNQUALIFIED_MARKET'
    WHEN NOT b.is_traded OR NOT (b.v>0 AND b.v<'Infinity'::float8 AND b.o>0 AND b.o<'Infinity'::float8
      AND b.h>0 AND b.h<'Infinity'::float8 AND b.l>0 AND b.l<'Infinity'::float8 AND b.c>0 AND b.c<'Infinity'::float8) THEN 'NON_EXECUTION'
    ELSE 'VERIFIED_PUBLIC_EXECUTION' END AS proof_status
  FROM bars b LEFT JOIN landings l USING(landing_id) LEFT JOIN rows r ON r.landing_id=b.landing_id AND r.source_row=b.source_row
 )
 INSERT INTO ops.phase2_public_execution_proof(symbol_id,trade_date,source,algorithm_version,canonical_sha256,landing_id,source_row,status,venue)
 SELECT symbol_id,trade_date,source,'vndirect-public-execution-v1',canonical_hash,landing_id,CASE WHEN source_row>=0 THEN source_row END,proof_status,
  CASE WHEN venue IN ('HOSE','HNX','UPCOM') THEN venue END FROM checked
 ON CONFLICT(symbol_id,trade_date,source,algorithm_version,canonical_sha256) DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT;RETURN n;
END $$;
CREATE OR REPLACE VIEW ops.phase2_current_public_execution_proof AS
 SELECT p.* FROM ops.phase2_public_execution_proof p JOIN core.bars_daily_sources b
 ON b.symbol_id=p.symbol_id AND b.trade_date=p.trade_date AND b.source=p.source
 AND p.canonical_sha256=ops.phase2_execution_bar_hash(b)
 WHERE p.status='VERIFIED_PUBLIC_EXECUTION' AND p.algorithm_version='vndirect-public-execution-v1';

CREATE OR REPLACE FUNCTION ops.phase2_execution_tenure_lower_bound(p_symbol bigint,p_signal date,p_use_prefix boolean)
RETURNS integer LANGUAGE plpgsql STABLE AS $$
DECLARE n integer; cutoff timestamptz:=(p_signal::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh';
BEGIN
 IF EXISTS(SELECT 1 FROM core.security_listing_events e WHERE e.symbol_id=p_symbol
  AND e.event_type='ADMISSION' AND e.effective_date>p_signal AND e.available_at<=cutoff
  AND NOT EXISTS(SELECT 1 FROM core.security_listing_events correction
   WHERE correction.supersedes_event_id=e.event_id AND correction.available_at<=cutoff)) THEN RETURN NULL; END IF;
 -- A known legacy identity/cessation claim must be reconciled with080 first.
 -- Never use absence of a notice to override an explicit conflicting one.
 IF EXISTS(SELECT 1 FROM core.security_lifecycle_evidence e WHERE e.symbol_id=p_symbol
  AND (e.evidence_type='FIRST_EVER_PUBLIC_TRADE' OR (e.evidence_type='DELISTED' AND e.date_from<=p_signal))
  AND ((e.source_document_date+1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')<=cutoff) THEN RETURN NULL; END IF;
 IF p_use_prefix AND to_regclass('pg_temp.phase2_execution_session_prefix') IS NOT NULL THEN
  SELECT execution_count INTO n FROM pg_temp.phase2_execution_session_prefix WHERE symbol_id=p_symbol AND trade_date<p_signal ORDER BY trade_date DESC LIMIT 1;
 ELSE
  SELECT count(*)::integer INTO n FROM ops.phase2_current_public_execution_proof p
   JOIN core.effective_trading_sessions c USING(trade_date) WHERE c.is_session AND p.symbol_id=p_symbol AND p.trade_date<p_signal AND p.available_at<=cutoff;
 END IF;
 -- Asymmetric proof: fewer observed executions cannot establish young age.
 RETURN CASE WHEN n>=250 THEN n END;
END $$;

DO $execution_tenure$
DECLARE d text:=pg_get_functiondef('ops.phase2_verified_listing_tenure(bigint,date,boolean)'::regprocedure); a text;
BEGIN
 IF position('ops.phase2_execution_tenure_lower_bound' IN d)=0 THEN
  a:='IF admitted IS NULL THEN RETURN NULL; END IF;';
  IF position(a IN d)=0 THEN RAISE EXCEPTION 'execution lower-bound anchor missing'; END IF;
  EXECUTE replace(d,a,'IF admitted IS NULL THEN RETURN ops.phase2_execution_tenure_lower_bound(p_symbol,p_signal,p_use_prefix); END IF;');
 END IF;
 d:=pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
 IF position('phase2_execution_session_prefix' IN d)=0 THEN
  a:='    DROP TABLE IF EXISTS pg_temp.phase2_label_liquidity_median;';
  IF position(a IN d)=0 THEN RAISE EXCEPTION 'execution prefix anchor missing'; END IF;
  EXECUTE replace(d,a,'    DROP TABLE IF EXISTS pg_temp.phase2_execution_session_prefix;
    CREATE TEMP TABLE phase2_execution_session_prefix ON COMMIT DROP AS
    SELECT p.symbol_id,p.trade_date,row_number() OVER(PARTITION BY p.symbol_id ORDER BY p.trade_date)::integer AS execution_count
    FROM ops.phase2_current_public_execution_proof p JOIN core.effective_trading_sessions c USING(trade_date)
    WHERE c.is_session AND p.trade_date<=p_date_to;
    ALTER TABLE pg_temp.phase2_execution_session_prefix ADD PRIMARY KEY(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_execution_session_prefix;
'||a);
 END IF;
END $execution_tenure$;

-- Persist which proof was used, without relabeling a lower bound as exact age.
ALTER TABLE feat.phase2_liquidity_tiers_v3 ADD COLUMN IF NOT EXISTS membership_tenure_basis text;
ALTER TABLE feat.phase2_label_targets_v3 ADD COLUMN IF NOT EXISTS membership_tenure_basis text;
DO $proof_basis$
DECLARE d text:=pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
 a text:='    GET DIAGNOSTICS v_rows=ROW_COUNT;';
BEGIN
 IF position('membership_tenure_basis=' IN d)>0 THEN RETURN; END IF;
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'tenure basis persistence anchor missing'; END IF;
 EXECUTE replace(d,a,a||'
    UPDATE feat.phase2_liquidity_tiers_v3 m SET membership_tenure_basis=CASE
      WHEN m.verified_listed_sessions IS NULL THEN ''UNKNOWN''
      WHEN EXISTS(SELECT 1 FROM core.security_listing_events e WHERE e.symbol_id=m.symbol_id
        AND e.available_at<=((m.trade_date::timestamp+time ''15:00'') AT TIME ZONE ''Asia/Ho_Chi_Minh'')
        AND e.event_type<>''WITHDRAWAL''
        AND (e.effective_date<=m.trade_date OR (e.event_type=''TRANSFER'' AND e.prior_ceased_from<=m.trade_date))
        AND NOT EXISTS(SELECT 1 FROM core.security_listing_events correction WHERE correction.supersedes_event_id=e.event_id
         AND correction.available_at<=((m.trade_date::timestamp+time ''15:00'') AT TIME ZONE ''Asia/Ho_Chi_Minh''))) THEN ''LEGAL_EPISODE''
      ELSE ''PUBLIC_EXECUTION_LOWER_BOUND'' END
    WHERE m.trade_date BETWEEN p_date_from AND p_date_to;
    UPDATE feat.phase2_label_targets_v3 t SET membership_tenure_basis=m.membership_tenure_basis
    FROM feat.phase2_liquidity_tiers_v3 m WHERE m.symbol_id=t.symbol_id AND m.trade_date=t.signal_date
     AND t.signal_date BETWEEN p_date_from AND p_date_to;');
END $proof_basis$;
DO $execution_hash$
DECLARE d text:=pg_get_functiondef('ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure); a text:='v_hash||''|liquidity_context=''';
BEGIN
 IF position('|execution_proof=v' IN d)>0 THEN RETURN; END IF;
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'execution proof hash anchor missing'; END IF;
 EXECUTE replace(d,a,'v_hash||''|execution_proof=v1|''||coalesce((SELECT string_agg(ops.phase2_hash_jsonb((to_jsonb(p)-''observed_at''-''available_at'')||jsonb_build_object(''available_at_epoch'',extract(epoch FROM p.available_at))),'''' ORDER BY p.symbol_id,p.trade_date,p.proof_id)
 FROM ops.phase2_current_public_execution_proof p WHERE p.trade_date<p_date_to),'''')||
 coalesce((SELECT string_agg(ops.phase2_hash_jsonb(to_jsonb(e)),'''' ORDER BY e.evidence_id) FROM core.security_lifecycle_evidence e
 WHERE (e.evidence_type=''FIRST_EVER_PUBLIC_TRADE'' OR e.date_from<=p_date_to) AND ((e.source_document_date+1)::timestamp AT TIME ZONE ''Asia/Ho_Chi_Minh'')<=((p_date_to::timestamp+time ''15:00'') AT TIME ZONE ''Asia/Ho_Chi_Minh'')),'''')||''|liquidity_context=''');
END $execution_hash$;
COMMENT ON TABLE ops.phase2_public_execution_proof IS
 'Append-only exact VNDIRECT native-row qualification. STOCK, dated public-market venue, matched positive volume, original raw OHLC, code/date/pointer and intact bytes are required. Canonical provider-symbol identity is the existing price contract; this does not assert an unprovided ISIN. Known identity/lifecycle conflicts fence fallback. >=250 prior qualified sessions suffice; fewer remain unknown.';
COMMENT ON FUNCTION core.verified_listing_tenure(bigint,date) IS
 'Exact prior true sessions from a consistent legal episode; otherwise a sufficient >=250 lower bound from exact public executions under the canonical price identity, subject to known lifecycle fences. Below-threshold execution evidence remains unknown. Public execution event availability is reconstructed at next local midnight; raw capture and observed timestamps remain later vendor-vintage evidence.';
COMMIT;

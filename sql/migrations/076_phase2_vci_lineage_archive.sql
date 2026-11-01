-- Durable provenance observations only. This does not infer listing tenure.
BEGIN;
CREATE TABLE IF NOT EXISTS ops.phase2_vci_bar_lineage (
 observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 symbol_id bigint NOT NULL,
 trade_date date NOT NULL,
 algorithm_version text NOT NULL,
 canonical_sha256 text NOT NULL CHECK(canonical_sha256 ~ '^[0-9a-f]{64}$'),
 input_sha256 text NOT NULL CHECK(input_sha256 ~ '^[0-9a-f]{64}$'),
 canonical_snapshot jsonb NOT NULL,
 status text NOT NULL CHECK(status IN ('EXACT','UNMATCHED','AMBIGUOUS','MISSING_LANDING','CHECKSUM_INVALID','PAYLOAD_MISMATCH','MALFORMED')),
 exact_matches bigint NOT NULL CHECK(exact_matches>=0),
 landing_id bigint REFERENCES raw.landings(landing_id),
 source_ordinal_1based bigint,
 source_fetched_at timestamptz,
 observed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(symbol_id,trade_date) REFERENCES core.bars_daily(symbol_id,trade_date),
 UNIQUE(symbol_id,trade_date,algorithm_version,input_sha256),
 CHECK((status='EXACT' AND exact_matches=1 AND landing_id IS NOT NULL
        AND source_ordinal_1based IS NOT NULL AND source_ordinal_1based>=1 AND source_fetched_at IS NOT NULL)
    OR (status<>'EXACT' AND landing_id IS NULL AND source_ordinal_1based IS NULL AND source_fetched_at IS NULL)),
 CHECK(status<>'AMBIGUOUS' OR exact_matches>1),
 CHECK(status NOT IN ('UNMATCHED','MISSING_LANDING') OR exact_matches=0)
);
CREATE INDEX IF NOT EXISTS phase2_vci_lineage_lookup
 ON ops.phase2_vci_bar_lineage(symbol_id,trade_date,observed_at DESC,observation_id DESC);
CREATE TABLE IF NOT EXISTS ops.phase2_vci_lineage_batches (
 batch_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 symbol_ids bigint[] NOT NULL,
 algorithm_version text NOT NULL,
 input_sha256 text NOT NULL CHECK(input_sha256 ~ '^[0-9a-f]{64}$'),
 bar_count bigint NOT NULL CHECK(bar_count>=0),
 exact_count bigint NOT NULL CHECK(exact_count BETWEEN 0 AND bar_count),
 inserted_count bigint NOT NULL CHECK(inserted_count BETWEEN 0 AND bar_count),
 completed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE OR REPLACE FUNCTION ops.reject_phase2_lineage_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Phase 2 lineage observations are append-only'; END;
$$;
DROP TRIGGER IF EXISTS phase2_lineage_append_only ON ops.phase2_vci_bar_lineage;
CREATE TRIGGER phase2_lineage_append_only BEFORE UPDATE OR DELETE ON ops.phase2_vci_bar_lineage
 FOR EACH ROW EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();
DROP TRIGGER IF EXISTS phase2_lineage_no_truncate ON ops.phase2_vci_bar_lineage;
CREATE TRIGGER phase2_lineage_no_truncate BEFORE TRUNCATE ON ops.phase2_vci_bar_lineage
 FOR EACH STATEMENT EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();
DROP TRIGGER IF EXISTS phase2_lineage_batch_append_only ON ops.phase2_vci_lineage_batches;
CREATE TRIGGER phase2_lineage_batch_append_only BEFORE UPDATE OR DELETE ON ops.phase2_vci_lineage_batches
 FOR EACH ROW EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();
DROP TRIGGER IF EXISTS phase2_lineage_batch_no_truncate ON ops.phase2_vci_lineage_batches;
CREATE TRIGGER phase2_lineage_batch_no_truncate BEFORE TRUNCATE ON ops.phase2_vci_lineage_batches
 FOR EACH STATEMENT EXECUTE FUNCTION ops.reject_phase2_lineage_mutation();

CREATE OR REPLACE FUNCTION ops.phase2_try_jsonb_bytes(p_bytes bytea)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 RETURN convert_from(p_bytes,'UTF8')::jsonb;
EXCEPTION WHEN data_exception THEN RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION ops.phase2_vci_row_date(p_time text)
RETURNS date LANGUAGE sql STABLE AS $$
 SELECT CASE WHEN left(p_time,10) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
       AND pg_input_is_valid(left(p_time,10),'date')
       AND (p_time ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
         OR (p_time ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-2][0-9]:[0-5][0-9]:[0-5][0-9]([.][0-9]{1,9})?(Z|[+-][0-2][0-9]:[0-5][0-9])?$'
             AND pg_input_is_valid(p_time,'timestamp with time zone')))
      THEN left(p_time,10)::date END
$$;

CREATE OR REPLACE FUNCTION ops.materialize_phase2_vci_lineage(p_symbol_ids bigint[])
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
 v_algorithm constant text:='vci-exact-row-v1';
 v_inserted bigint;
 item text;
BEGIN
 IF p_symbol_ids IS NULL OR cardinality(p_symbol_ids) NOT BETWEEN 1 AND 100
    OR array_position(p_symbol_ids,NULL) IS NOT NULL
    OR cardinality(p_symbol_ids)<>(SELECT count(DISTINCT x) FROM unnest(p_symbol_ids) x)
    OR EXISTS(SELECT 1 FROM unnest(p_symbol_ids) x WHERE NOT EXISTS(SELECT 1 FROM core.symbols s WHERE s.symbol_id=x)) THEN
  RAISE EXCEPTION 'provide 1 to 100 distinct known symbol IDs';
 END IF;
 FOREACH item IN ARRAY ARRAY['phase2_vci_lineage_results_work','phase2_vci_lineage_rows_work','phase2_vci_lineage_landings_work','phase2_vci_lineage_bars_work'] LOOP
  IF to_regclass(format('pg_temp.%I',item)) IS NOT NULL THEN
   IF obj_description(to_regclass(format('pg_temp.%I',item)),'pg_class') IS DISTINCT FROM 'VN-Signal VCI lineage work relation' THEN
    RAISE EXCEPTION 'temporary relation % is reserved for VCI lineage',item;
   END IF;
   EXECUTE format('DROP TABLE pg_temp.%I',item);
  END IF;
 END LOOP;

 CREATE TEMP TABLE phase2_vci_lineage_bars_work ON COMMIT DROP AS
 SELECT b.symbol_id,b.trade_date,b.ingest_id,b.source,b.o,b.h,b.l,b.c,b.v,
        b.is_traded,b.adj_basis,b.fetched_at,s.symbol,
        jsonb_build_object('symbol_id',b.symbol_id,'symbol',s.symbol,
          'trade_date',to_char(b.trade_date,'YYYY-MM-DD'),'ingest_id',b.ingest_id,
          'source',b.source,'adj_basis',b.adj_basis,'is_traded',b.is_traded,
          'fetched_at_epoch',extract(epoch FROM b.fetched_at),
          'o_hex',encode(float8send(b.o),'hex'),'h_hex',encode(float8send(b.h),'hex'),
          'l_hex',encode(float8send(b.l),'hex'),'c_hex',encode(float8send(b.c),'hex'),
          'v_hex',encode(float8send(b.v),'hex')) AS snapshot
 FROM core.bars_daily b JOIN core.symbols s USING(symbol_id)
 WHERE b.source='vci' AND b.symbol_id=ANY(p_symbol_ids);
 COMMENT ON TABLE pg_temp.phase2_vci_lineage_bars_work IS 'VN-Signal VCI lineage work relation';
 CREATE INDEX ON pg_temp.phase2_vci_lineage_bars_work(ingest_id,symbol,trade_date);
 ANALYZE pg_temp.phase2_vci_lineage_bars_work;

 CREATE TEMP TABLE phase2_vci_lineage_landings_work ON COMMIT DROP AS
 WITH checked AS MATERIALIZED (
  SELECT l.landing_id,l.ingest_id,l.symbol,l.fetched_at,l.payload,l.payload_sha256,
         encode(sha256(l.payload_bytes),'hex') AS actual_sha256,
         ops.phase2_try_jsonb_bytes(l.payload_bytes) AS body
  FROM raw.landings l
  JOIN (SELECT DISTINCT ingest_id,symbol FROM pg_temp.phase2_vci_lineage_bars_work) b
    ON b.ingest_id=l.ingest_id AND b.symbol=l.symbol
  WHERE l.source='vci' AND l.route='equity_ohlcv'
 )
 SELECT c.*,
  CASE WHEN c.actual_sha256 IS DISTINCT FROM lower(c.payload_sha256) OR c.actual_sha256 IS NULL THEN 'CHECKSUM_INVALID'
       WHEN c.body IS NULL THEN 'MALFORMED'
       WHEN c.body IS DISTINCT FROM c.payload THEN 'PAYLOAD_MISMATCH'
       WHEN jsonb_typeof(c.payload->'rows') IS DISTINCT FROM 'array' THEN 'MALFORMED'
       ELSE 'VALID' END AS integrity_status,
  ops.phase2_hash_jsonb(jsonb_build_array(c.landing_id,c.ingest_id,c.symbol,
     extract(epoch FROM c.fetched_at),c.payload_sha256,c.actual_sha256,c.payload)) AS landing_sha256
 FROM checked c;
 COMMENT ON TABLE pg_temp.phase2_vci_lineage_landings_work IS 'VN-Signal VCI lineage work relation';

 CREATE TEMP TABLE phase2_vci_lineage_rows_work ON COMMIT DROP AS
 SELECT l.landing_id,l.ingest_id,l.symbol,l.fetched_at,r.ordinality AS source_ordinal_1based,
  CASE WHEN jsonb_typeof(r.value->'time')='string'
       THEN ops.phase2_vci_row_date(r.value->>'time') END AS trade_date,
  CASE WHEN jsonb_typeof(r.value->'open')='number' AND pg_input_is_valid(r.value->>'open','double precision') THEN (r.value->>'open')::float8 END AS o,
  CASE WHEN jsonb_typeof(r.value->'high')='number' AND pg_input_is_valid(r.value->>'high','double precision') THEN (r.value->>'high')::float8 END AS h,
  CASE WHEN jsonb_typeof(r.value->'low')='number' AND pg_input_is_valid(r.value->>'low','double precision') THEN (r.value->>'low')::float8 END AS low,
  CASE WHEN jsonb_typeof(r.value->'close')='number' AND pg_input_is_valid(r.value->>'close','double precision') THEN (r.value->>'close')::float8 END AS c,
  CASE WHEN jsonb_typeof(r.value->'volume')='number' AND pg_input_is_valid(r.value->>'volume','double precision') THEN (r.value->>'volume')::float8 END AS v
 FROM pg_temp.phase2_vci_lineage_landings_work l
 CROSS JOIN LATERAL jsonb_array_elements(CASE WHEN l.integrity_status='VALID' THEN l.payload->'rows' ELSE '[]'::jsonb END)
 WITH ORDINALITY r(value,ordinality);
 COMMENT ON TABLE pg_temp.phase2_vci_lineage_rows_work IS 'VN-Signal VCI lineage work relation';
 CREATE INDEX ON pg_temp.phase2_vci_lineage_rows_work(ingest_id,symbol,trade_date);
 ANALYZE pg_temp.phase2_vci_lineage_rows_work;

 CREATE TEMP TABLE phase2_vci_lineage_results_work ON COMMIT DROP AS
 WITH bad_rows AS (
  SELECT landing_id,bool_or(trade_date IS NULL OR o IS NULL OR h IS NULL OR low IS NULL OR c IS NULL OR v IS NULL
    OR NOT(abs(o)<'Infinity'::float8 AND abs(h)<'Infinity'::float8 AND abs(low)<'Infinity'::float8 AND abs(c)<'Infinity'::float8 AND abs(v)<'Infinity'::float8)) AS malformed
  FROM pg_temp.phase2_vci_lineage_rows_work GROUP BY landing_id
 ), landings AS MATERIALIZED (
  SELECT l.ingest_id,l.symbol,count(*) AS n,
   bool_or(l.integrity_status='CHECKSUM_INVALID') AS checksum_invalid,
   bool_or(l.integrity_status='PAYLOAD_MISMATCH') AS payload_mismatch,
   bool_or(l.integrity_status='MALFORMED' OR coalesce(b.malformed,false)) AS malformed,
   ops.phase2_hash_text(string_agg(l.landing_sha256,'|' ORDER BY l.landing_id)) AS digest
  FROM pg_temp.phase2_vci_lineage_landings_work l LEFT JOIN bad_rows b USING(landing_id)
  GROUP BY l.ingest_id,l.symbol
 ), matches AS MATERIALIZED (
  SELECT b.symbol_id,b.trade_date,b.snapshot,b.ingest_id,b.symbol,
   count(*) FILTER(WHERE r.o=b.o AND r.h=b.h AND r.low=b.l AND r.c=b.c AND r.v=b.v) AS exact_matches,
   min(r.landing_id) FILTER(WHERE r.o=b.o AND r.h=b.h AND r.low=b.l AND r.c=b.c AND r.v=b.v) AS landing_id,
   min(r.source_ordinal_1based) FILTER(WHERE r.o=b.o AND r.h=b.h AND r.low=b.l AND r.c=b.c AND r.v=b.v) AS ordinal,
   min(r.fetched_at) FILTER(WHERE r.o=b.o AND r.h=b.h AND r.low=b.l AND r.c=b.c AND r.v=b.v) AS source_fetched_at
  FROM pg_temp.phase2_vci_lineage_bars_work b LEFT JOIN pg_temp.phase2_vci_lineage_rows_work r
   ON r.ingest_id=b.ingest_id AND r.symbol=b.symbol AND r.trade_date=b.trade_date
  GROUP BY b.symbol_id,b.trade_date,b.snapshot,b.ingest_id,b.symbol
 ), classified AS (
  SELECT m.*,ops.phase2_hash_jsonb(m.snapshot) AS canonical_sha256,
   CASE WHEN l.n IS NULL THEN 'MISSING_LANDING' WHEN l.checksum_invalid THEN 'CHECKSUM_INVALID'
        WHEN l.payload_mismatch THEN 'PAYLOAD_MISMATCH' WHEN l.malformed THEN 'MALFORMED'
        WHEN m.exact_matches>1 THEN 'AMBIGUOUS' WHEN m.exact_matches=1 THEN 'EXACT' ELSE 'UNMATCHED' END AS status,
   coalesce(l.digest,'MISSING') AS landing_digest
  FROM matches m LEFT JOIN landings l USING(ingest_id,symbol)
 )
 SELECT c.symbol_id,c.trade_date,c.snapshot,c.canonical_sha256,c.status,c.exact_matches,
  CASE WHEN c.status='EXACT' THEN c.landing_id END AS landing_id,
  CASE WHEN c.status='EXACT' THEN c.ordinal END AS source_ordinal_1based,
  CASE WHEN c.status='EXACT' THEN c.source_fetched_at END AS source_fetched_at,
  ops.phase2_hash_jsonb(jsonb_build_array(v_algorithm,c.canonical_sha256,c.landing_digest)) AS input_sha256
 FROM classified c;
 COMMENT ON TABLE pg_temp.phase2_vci_lineage_results_work IS 'VN-Signal VCI lineage work relation';

 INSERT INTO ops.phase2_vci_bar_lineage(symbol_id,trade_date,algorithm_version,canonical_sha256,input_sha256,
   canonical_snapshot,status,exact_matches,landing_id,source_ordinal_1based,source_fetched_at)
 SELECT r.symbol_id,r.trade_date,v_algorithm,r.canonical_sha256,r.input_sha256,r.snapshot,r.status,
   r.exact_matches,r.landing_id,r.source_ordinal_1based,r.source_fetched_at
 FROM pg_temp.phase2_vci_lineage_results_work r
 ON CONFLICT(symbol_id,trade_date,algorithm_version,input_sha256) DO NOTHING;
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 IF EXISTS(SELECT 1 FROM pg_temp.phase2_vci_lineage_results_work r JOIN ops.phase2_vci_bar_lineage o
     ON o.symbol_id=r.symbol_id AND o.trade_date=r.trade_date AND o.algorithm_version=v_algorithm AND o.input_sha256=r.input_sha256
     WHERE ROW(o.canonical_sha256,o.canonical_snapshot,o.status,o.exact_matches,o.landing_id,o.source_ordinal_1based,o.source_fetched_at)
       IS DISTINCT FROM ROW(r.canonical_sha256,r.snapshot,r.status,r.exact_matches,r.landing_id,r.source_ordinal_1based,r.source_fetched_at)) THEN
  RAISE EXCEPTION 'existing lineage observation conflicts with deterministic result';
 END IF;
 INSERT INTO ops.phase2_vci_lineage_batches(symbol_ids,algorithm_version,input_sha256,bar_count,exact_count,inserted_count)
 SELECT ARRAY(SELECT x FROM unnest(p_symbol_ids) x ORDER BY x),v_algorithm,
   ops.phase2_hash_jsonb(jsonb_build_array(v_algorithm,
     ARRAY(SELECT x FROM unnest(p_symbol_ids) x ORDER BY x),
     coalesce(string_agg(r.input_sha256||'|'||r.status,';' ORDER BY r.symbol_id,r.trade_date),''))),
   count(*),count(*) FILTER(WHERE r.status='EXACT'),v_inserted
 FROM pg_temp.phase2_vci_lineage_results_work r;
 RETURN v_inserted;
END;
$$;
COMMENT ON TABLE ops.phase2_vci_bar_lineage IS
 'Append-only exact-row provenance snapshots, including unresolved outcomes. Ordinal is explicitly one-based. Observations do not establish continuous legal identity, listing tenure or historical availability.';
COMMIT;

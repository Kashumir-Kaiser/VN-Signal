-- An immutable quarantine route can have a later, explicitly audited recovery.
-- Preserve that distinction in versioned provenance; never rewrite raw data.
BEGIN;
ALTER TABLE ops.phase2_vci_bar_lineage ADD COLUMN IF NOT EXISTS source_evidence jsonb;
CREATE INDEX IF NOT EXISTS ingest_jobs_landed_id_lookup
 ON ops.ingest_jobs(landed_id) WHERE landed_id IS NOT NULL;
CREATE OR REPLACE FUNCTION ops.phase2_vci_recovery_evidence(p_landing_id bigint)
RETURNS jsonb LANGUAGE sql STABLE AS $$
 SELECT jsonb_build_object(
   'job_id',j.job_id,'landing_id',l.landing_id,'symbol',j.symbol,'source',j.source,
   'requested_route',j.route,'date_from',to_char(j.date_from,'YYYY-MM-DD'),
   'date_to',to_char(j.date_to,'YYYY-MM-DD'),'state',j.state,
   'audit_id',a.audit_id,'validator_version',a.validator_version,'previous_state',a.previous_state,
   'resulting_state',a.resulting_state,'reprocessed_at_epoch',extract(epoch FROM a.reprocessed_at),
   'issues',coalesce((SELECT jsonb_agg(jsonb_build_object(
       'source_row',q.source_row,'trade_date',to_char(q.trade_date,'YYYY-MM-DD'),
       'category',q.category,'reason',q.reason) ORDER BY q.source_row)
       FROM ops.bar_quality_issues q WHERE q.landing_id=l.landing_id AND q.job_id=j.job_id),'[]'::jsonb))
 FROM raw.landings l JOIN ops.ingest_jobs j ON j.landed_id=l.landing_id
 CROSS JOIN LATERAL (
   SELECT x.* FROM ops.bar_quality_reprocess_audit x
   WHERE x.landing_id=l.landing_id AND x.job_id=j.job_id
   ORDER BY x.reprocessed_at DESC,x.audit_id DESC LIMIT 1
 ) a
 WHERE l.landing_id=p_landing_id AND l.route='equity_ohlcv_quarantine'
   AND (SELECT count(*) FROM ops.ingest_jobs owner WHERE owner.landed_id=l.landing_id)=1
   AND l.source='vci' AND j.route='equity_ohlcv' AND j.source=l.source AND j.symbol=l.symbol
   AND j.date_from IS NOT NULL AND j.date_to IS NOT NULL
   AND j.state IN ('COMPLETED','PARTIAL') AND a.resulting_state=j.state
   AND a.validator_version IN ('vn-equity-auction-extrema-v1','vn-equity-auction-extrema-empty-response-v2')
   AND l.payload #>> '{attributes,source}'='vci'
   AND l.payload #>> '{attributes,route}'='market.equity.ohlcv'
$$;
COMMENT ON COLUMN ops.phase2_vci_bar_lineage.source_evidence IS
 'Versioned source-route and audited recovery snapshot. Recovery proves source projection acceptance, not listing tenure or independent historical publication.';
CREATE OR REPLACE FUNCTION ops.materialize_phase2_vci_lineage(p_symbol_ids bigint[])
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
 v_algorithm constant text:='vci-exact-row-v2';
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
  SELECT l.landing_id,l.ingest_id,l.symbol,l.fetched_at,l.payload,l.payload_sha256,l.route,
         CASE WHEN l.route='equity_ohlcv_quarantine' THEN ops.phase2_vci_recovery_evidence(l.landing_id) END AS recovery,
         encode(sha256(l.payload_bytes),'hex') AS actual_sha256,
         ops.phase2_try_jsonb_bytes(l.payload_bytes) AS body
  FROM raw.landings l
  JOIN (SELECT DISTINCT ingest_id,symbol FROM pg_temp.phase2_vci_lineage_bars_work) b
    ON b.ingest_id=l.ingest_id AND b.symbol=l.symbol
  WHERE l.source='vci' AND l.route IN ('equity_ohlcv','equity_ohlcv_quarantine')
 )
 SELECT c.*,jsonb_build_object('route',c.route,'recovery',c.recovery) AS source_evidence,
  CASE WHEN c.actual_sha256 IS DISTINCT FROM lower(c.payload_sha256) OR c.actual_sha256 IS NULL THEN 'CHECKSUM_INVALID'
       WHEN c.body IS NULL THEN 'MALFORMED'
       WHEN c.body IS DISTINCT FROM c.payload THEN 'PAYLOAD_MISMATCH'
       WHEN jsonb_typeof(c.payload->'rows') IS DISTINCT FROM 'array' THEN 'MALFORMED'
       ELSE 'VALID' END AS integrity_status,
  ops.phase2_hash_jsonb(jsonb_build_array(c.landing_id,c.ingest_id,c.symbol,
     extract(epoch FROM c.fetched_at),c.payload_sha256,c.actual_sha256,c.payload,c.route,c.recovery)) AS landing_sha256
 FROM checked c WHERE c.route='equity_ohlcv' OR c.recovery IS NOT NULL;
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
   AND EXISTS(SELECT 1 FROM pg_temp.phase2_vci_lineage_landings_work accepted
     WHERE accepted.landing_id=r.landing_id AND (accepted.route='equity_ohlcv' OR
       (b.trade_date BETWEEN (accepted.recovery->>'date_from')::date AND (accepted.recovery->>'date_to')::date
        AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(accepted.recovery->'issues') q
                       WHERE q->>'trade_date'=to_char(b.trade_date,'YYYY-MM-DD')))))
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
  CASE WHEN c.status='EXACT' THEN (SELECT l.source_evidence FROM pg_temp.phase2_vci_lineage_landings_work l WHERE l.landing_id=c.landing_id) END AS source_evidence,
  ops.phase2_hash_jsonb(jsonb_build_array(v_algorithm,c.canonical_sha256,c.landing_digest)) AS input_sha256
 FROM classified c;
 COMMENT ON TABLE pg_temp.phase2_vci_lineage_results_work IS 'VN-Signal VCI lineage work relation';

 INSERT INTO ops.phase2_vci_bar_lineage(symbol_id,trade_date,algorithm_version,canonical_sha256,input_sha256,
   canonical_snapshot,status,exact_matches,landing_id,source_ordinal_1based,source_fetched_at,source_evidence)
 SELECT r.symbol_id,r.trade_date,v_algorithm,r.canonical_sha256,r.input_sha256,r.snapshot,r.status,
   r.exact_matches,r.landing_id,r.source_ordinal_1based,r.source_fetched_at,r.source_evidence
 FROM pg_temp.phase2_vci_lineage_results_work r
 ON CONFLICT(symbol_id,trade_date,algorithm_version,input_sha256) DO NOTHING;
 GET DIAGNOSTICS v_inserted=ROW_COUNT;
 IF EXISTS(SELECT 1 FROM pg_temp.phase2_vci_lineage_results_work r JOIN ops.phase2_vci_bar_lineage o
     ON o.symbol_id=r.symbol_id AND o.trade_date=r.trade_date AND o.algorithm_version=v_algorithm AND o.input_sha256=r.input_sha256
     WHERE ROW(o.canonical_sha256,o.canonical_snapshot,o.status,o.exact_matches,o.landing_id,o.source_ordinal_1based,o.source_fetched_at,o.source_evidence)
       IS DISTINCT FROM ROW(r.canonical_sha256,r.snapshot,r.status,r.exact_matches,r.landing_id,r.source_ordinal_1based,r.source_fetched_at,r.source_evidence)) THEN
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

COMMIT;

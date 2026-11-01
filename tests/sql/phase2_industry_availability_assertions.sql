\set ON_ERROR_STOP on
BEGIN;
\ir fundamental_industry_helpers.sql
SELECT feat.build_price_features_v3('2098-01-06','2098-01-07');
DO $$
DECLARE sid bigint; h6 text; h7 text; r record; f feat.fundamental_features_daily%ROWTYPE;
BEGIN
 SELECT symbol_id INTO STRICT sid FROM core.symbols WHERE symbol='P2READY';
 h6:=ops.phase2_chunk_input_hash('fundamentals','2098-01-06','2098-01-06');
 h7:=ops.phase2_chunk_input_hash('fundamentals','2098-01-07','2098-01-07');
 PERFORM pg_temp.synthetic_industry_observation('AfterClose','2098-01-06 16:00+07');
 SELECT * INTO STRICT r FROM core.industry_as_of(sid,'2098-01-06');
 IF r.industry IS DISTINCT FROM 'Synthetic Finance' OR r.available_at IS DISTINCT FROM '2098-01-02 12:00+07'::timestamptz THEN RAISE EXCEPTION 'after-close classification leaked'; END IF;
 SELECT * INTO STRICT r FROM core.industry_as_of(sid,'2098-01-07');
 IF r.industry IS DISTINCT FROM 'AfterClose' THEN RAISE EXCEPTION 'next-day classification missed'; END IF;
 IF h6<>ops.phase2_chunk_input_hash('fundamentals','2098-01-06','2098-01-06') OR h7=ops.phase2_chunk_input_hash('fundamentals','2098-01-07','2098-01-07') THEN
  RAISE EXCEPTION 'industry manifest cutoff/invalidation wrong';
 END IF;
 PERFORM pg_temp.synthetic_industry_observation('ConflictingSameInstant','2098-01-06 16:00+07');
 SELECT * INTO STRICT r FROM core.industry_as_of(sid,'2098-01-07');
 IF r.industry IS NOT NULL OR cardinality(r.observation_ids)<>2 OR cardinality(r.landing_ids)<>2 THEN RAISE EXCEPTION 'latest conflicting observations were arbitrarily selected or lost lineage'; END IF;
 PERFORM feat.build_fundamental_features('2098-01-06','2098-01-07');
 SELECT * INTO STRICT f FROM feat.fundamental_features_daily WHERE symbol_id=sid AND trade_date='2098-01-07';
 IF f.industry IS NOT NULL OR f.bank_ttm_net_profit IS NOT NULL OR cardinality(f.industry_observation_ids)<>2 OR f.industry_available_at IS DISTINCT FROM '2098-01-06 16:00+07'::timestamptz OR NOT (r.landing_ids<@f.raw_landing_ids) THEN
  RAISE EXCEPTION 'overlay industry/bank classification/lineage did not follow timestamped source';
 END IF;
 SELECT * INTO STRICT r FROM core.industry_as_of((SELECT symbol_id FROM core.symbols WHERE symbol='P2GAP'),'2098-01-07');
 IF r.industry IS NOT NULL OR cardinality(r.observation_ids)<>0 OR r.available_at IS NOT NULL THEN RAISE EXCEPTION 'missing industry observation inferred from snapshot/current symbol'; END IF;
 PERFORM pg_temp.synthetic_industry_observation(NULL,'2098-01-07 10:00+07');
 SELECT * INTO STRICT r FROM core.industry_as_of(sid,'2098-01-07');
 IF r.industry IS NOT NULL OR cardinality(r.observation_ids)<>1 THEN RAISE EXCEPTION 'unknown latest industry fell back to older classification'; END IF;
END $$;
ROLLBACK;

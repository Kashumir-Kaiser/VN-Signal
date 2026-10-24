BEGIN;
-- Ordered per-security aggregates bound each transition state to one security's
-- daily history instead of concatenating the entire market into one value.
DO $bounded_proof_hash$
DECLARE d text:=pg_get_functiondef('ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure);
 a text:=$old$coalesce((SELECT string_agg(ops.phase2_hash_jsonb((to_jsonb(p)-'observed_at'-'available_at')||jsonb_build_object('available_at_epoch',extract(epoch FROM p.available_at))),'' ORDER BY p.symbol_id,p.trade_date,p.proof_id)
 FROM ops.phase2_current_public_execution_proof p WHERE p.trade_date<p_date_to),'')$old$;
 b text:=$new$coalesce((SELECT string_agg(symbol_hash,'' ORDER BY symbol_id) FROM (
 SELECT p.symbol_id,ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(
 (to_jsonb(p)-'observed_at'-'available_at')||jsonb_build_object('available_at_epoch',extract(epoch FROM p.available_at))),''
 ORDER BY p.trade_date,p.proof_id)) AS symbol_hash
 FROM ops.phase2_current_public_execution_proof p WHERE p.trade_date<p_date_to
 GROUP BY p.symbol_id) bounded_symbols),'')$new$;
BEGIN
 IF position('bounded_symbols' IN d)>0 THEN RETURN; END IF;
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'bounded execution proof hash anchor missing'; END IF;
 EXECUTE replace(replace(d,a,b),'|execution_proof=v1|','|execution_proof=v2|');
END $bounded_proof_hash$;
COMMIT;

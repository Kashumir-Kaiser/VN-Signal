BEGIN;
-- A statement-level source revision and the append-only proof identity form a
-- cheap invalidation watermark. This avoids rescanning millions of raw proof
-- rows for every label chunk while still detecting source edits and new proofs.
CREATE SEQUENCE IF NOT EXISTS ops.phase2_public_execution_source_revision_seq
    AS bigint MINVALUE 0 START WITH 0;

CREATE OR REPLACE FUNCTION ops.bump_phase2_public_execution_source_revision()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM nextval('ops.phase2_public_execution_source_revision_seq'::regclass);
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS phase2_public_execution_source_revision ON core.bars_daily_sources;
CREATE TRIGGER phase2_public_execution_source_revision
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON core.bars_daily_sources
FOR EACH STATEMENT EXECUTE FUNCTION ops.bump_phase2_public_execution_source_revision();

CREATE OR REPLACE FUNCTION ops.phase2_public_execution_proof_watermark()
RETURNS text LANGUAGE sql STABLE AS $$
 SELECT s.last_value::text||':'||s.is_called::text||':'||coalesce((
     SELECT p.proof_id::text FROM ops.phase2_public_execution_proof p ORDER BY p.proof_id DESC LIMIT 1
 ),'0')
 FROM ops.phase2_public_execution_source_revision_seq s
$$;

COMMENT ON FUNCTION ops.phase2_public_execution_proof_watermark() IS
    'Append-only proof identity plus a statement-level source-bar revision. Used to invalidate label chunk hashes without serializing the full proof archive.';

DO $bounded_proof_hash$
DECLARE d text:=pg_get_functiondef('ops.phase2_label_target_chunk_base_input_hash(date,date)'::regprocedure);
 a text:=$old$coalesce((SELECT string_agg(ops.phase2_hash_jsonb((to_jsonb(p)-'observed_at'-'available_at')||jsonb_build_object('available_at_epoch',extract(epoch FROM p.available_at))),'' ORDER BY p.symbol_id,p.trade_date,p.proof_id)
 FROM ops.phase2_current_public_execution_proof p WHERE p.trade_date<p_date_to),'')$old$;
 b text:=$new$ops.phase2_public_execution_proof_watermark()||'|'$new$;
BEGIN
 IF position('ops.phase2_public_execution_proof_watermark()' IN d)>0 THEN RETURN; END IF;
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'bounded execution proof hash anchor missing'; END IF;
 EXECUTE replace(replace(d,a,b),'|execution_proof=v1|','|execution_proof=v2|');
END $bounded_proof_hash$;
COMMIT;

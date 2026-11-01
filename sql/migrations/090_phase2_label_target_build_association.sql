BEGIN;

-- Add a distinct association to the durable labels chunk build. The legacy
-- build_id column is a builder-version label, not the runner's build ID; leave
-- it and every pre-existing row unchanged. This new nullable column remains
-- NULL for history written before the runner started supplying the GUC.
ALTER TABLE ops.phase2_label_target_chunk_runs
    ADD COLUMN IF NOT EXISTS label_build_id text;
ALTER TABLE ops.phase2_label_target_chunk_runs
    ALTER COLUMN label_build_id DROP DEFAULT,
    ALTER COLUMN label_build_id DROP NOT NULL;

DO $label_build_id_constraint$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid='ops.phase2_label_target_chunk_runs'::regclass
           AND conname='phase2_label_target_chunk_runs_label_build_id_check'
    ) THEN
        ALTER TABLE ops.phase2_label_target_chunk_runs
            ADD CONSTRAINT phase2_label_target_chunk_runs_label_build_id_check
            CHECK (label_build_id IS NULL OR label_build_id ~ '^[A-Za-z0-9._-]{1,100}$');
    END IF;
END;
$label_build_id_constraint$;

CREATE INDEX IF NOT EXISTS phase2_label_target_chunk_runs_build_range_idx
    ON ops.phase2_label_target_chunk_runs(label_build_id,date_from,date_to,run_id)
    WHERE label_build_id IS NOT NULL;

COMMENT ON COLUMN ops.phase2_label_target_chunk_runs.label_build_id IS
    'Actual ops.feature_chunks build_id that invoked this derived-target attempt. Set only from transaction-local vnpipe.phase2_label_build_id; NULL means the source build association is unknown or predates migration 090.';

DO $label_build_id_builder_hook$
DECLARE
    v_def text := pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
    v_anchor constant text := $anchor$
    INSERT INTO ops.phase2_label_target_chunk_runs(
        chunk_key,date_from,date_to,status,input_hash
    ) VALUES (
        to_char(p_date_from,'YYYYMMDD')||'-'||to_char(p_date_to,'YYYYMMDD'),
        p_date_from,p_date_to,'running',v_input_hash
    ) RETURNING run_id INTO v_run_id;
$anchor$;
    v_replacement constant text := $replacement$
    INSERT INTO ops.phase2_label_target_chunk_runs(
        chunk_key,date_from,date_to,status,input_hash,label_build_id
    ) VALUES (
        to_char(p_date_from,'YYYYMMDD')||'-'||to_char(p_date_to,'YYYYMMDD'),
        p_date_from,p_date_to,'running',v_input_hash,
        NULLIF(current_setting('vnpipe.phase2_label_build_id',true),'')
    ) RETURNING run_id INTO v_run_id;
$replacement$;
BEGIN
    IF position(v_replacement IN v_def)=0 THEN
        IF length(v_def)-length(replace(v_def,v_anchor,''))<>length(v_anchor) THEN
            RAISE EXCEPTION 'unexpected derived-target run insertion hook in builder';
        END IF;
        v_def:=replace(v_def,v_anchor,v_replacement);
    ELSIF length(v_def)-length(replace(v_def,v_replacement,''))<>length(v_replacement) THEN
        RAISE EXCEPTION 'derived-target build association hook is duplicated';
    END IF;
    EXECUTE v_def;
END;
$label_build_id_builder_hook$;

DO $label_build_id_assertions$
DECLARE
    v_nullable text;
    v_default text;
    v_def text := pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
BEGIN
    SELECT is_nullable,column_default INTO v_nullable,v_default
      FROM information_schema.columns
     WHERE table_schema='ops' AND table_name='phase2_label_target_chunk_runs'
       AND column_name='label_build_id';
    IF v_nullable IS DISTINCT FROM 'YES' OR v_default IS NOT NULL THEN
        RAISE EXCEPTION 'label_build_id must be nullable and have no default so old/unassociated runs remain NULL';
    END IF;
    IF position('vnpipe.phase2_label_build_id' IN v_def)=0
       OR position('NULLIF' IN upper(v_def))=0
       OR position('label_build_id' IN v_def)=0 THEN
        RAISE EXCEPTION 'derived-target builder does not stamp the transaction-local label build association';
    END IF;
END;
$label_build_id_assertions$;

COMMIT;

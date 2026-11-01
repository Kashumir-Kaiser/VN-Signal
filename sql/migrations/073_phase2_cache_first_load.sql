-- Each symbol belongs to exactly one batch. A never-loaded batch cannot have
-- committed cache rows: its insert and loaded flag change are one statement.
BEGIN;
DO $first_load$
DECLARE
    v_definition text:=pg_get_functiondef('feat.populate_phase2_adjustment_rows(integer)'::regprocedure);
    v_old text:=$old$    DELETE FROM pg_temp.phase2_adjustment_rows r
    USING pg_temp.phase2_adjustment_symbol_batches s
    WHERE s.batch_no=p_batch_no AND r.symbol_id=s.symbol_id;$old$;
    v_new text:=$new$    IF EXISTS (
        SELECT 1 FROM pg_temp.phase2_adjustment_symbol_batches
        WHERE batch_no=p_batch_no AND loaded
    ) THEN
        DELETE FROM pg_temp.phase2_adjustment_rows r
        USING pg_temp.phase2_adjustment_symbol_batches s
        WHERE s.batch_no=p_batch_no AND r.symbol_id=s.symbol_id;
    END IF;$new$;
BEGIN
    IF position(v_new IN v_definition)>0 THEN RETURN; END IF;
    IF position(v_old IN v_definition)=0 THEN RAISE EXCEPTION 'cache first-load migration anchor missing'; END IF;
    EXECUTE replace(v_definition,v_old,v_new);
END;
$first_load$;
COMMIT;

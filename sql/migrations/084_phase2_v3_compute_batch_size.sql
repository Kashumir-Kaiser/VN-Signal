-- Allow the V3 working set to be reduced without changing the canonical
-- cache batch size or chunk input hash. V3 computes cross-sectional ranks and
-- market context before this symbol-only batching, so group size is operational.
BEGIN;

DO $phase2_v3_compute_batch$
DECLARE
    definition text:=replace(
        pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure),
        E'\r\n',E'\n'
    );
    anchor text;
    replacement text;
BEGIN
    IF position('phase2_v3_compute_batch_size' IN definition)>0 THEN
        RETURN;
    END IF;

    anchor:='v_batch_size integer:=COALESCE(NULLIF(current_setting(''vnpipe.phase2_symbol_batch_size'',true),''''),''50'')::integer;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'V3 compute batch declaration anchor must occur exactly once';
    END IF;
    replacement:='v_batch_size integer:=COALESCE(NULLIF(current_setting(''vnpipe.phase2_v3_compute_batch_size'',true),''''),NULLIF(current_setting(''vnpipe.phase2_symbol_batch_size'',true),''''),''50'')::integer;';
    definition:=replace(definition,anchor,replacement);

    anchor:='RAISE EXCEPTION ''vnpipe.phase2_symbol_batch_size must be between 1 and 250'';';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'V3 compute batch validation anchor must occur exactly once';
    END IF;
    replacement:='RAISE EXCEPTION ''V3 symbol compute batch size must be between 1 and 250'';';
    definition:=replace(definition,anchor,replacement);

    EXECUTE definition;
END
$phase2_v3_compute_batch$;

COMMENT ON FUNCTION feat.build_price_features_v3_shared(date,date,bigint[]) IS
    'Builds source-independent Phase 2 V3 features. The optional vnpipe.phase2_v3_compute_batch_size setting (1..250) limits only the symbol working set; it does not change cross-sectional ranks, market context, or feature values.';

COMMIT;

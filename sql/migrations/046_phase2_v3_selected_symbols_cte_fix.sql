-- Migration 045 can upgrade an older V3 function body whose selected_symbols
-- CTE still refers to the pre-patch `symbols` name. Repair that reference
-- without changing the already-applied migration.
BEGIN;

DO $phase2_v3_selected_symbols_cte_fix$
DECLARE
    definition text;
    old_reference constant text:='SELECT symbol_id FROM symbols ORDER BY symbol_id';
    new_reference constant text:='SELECT symbol_id FROM eligible_symbols ORDER BY symbol_id';
BEGIN
    definition:=pg_get_functiondef(
        'feat.build_price_features_v3_internal(date,date)'::regprocedure
    );

    IF position(new_reference IN definition)=0 THEN
        IF position(old_reference IN definition)=0 THEN
            RAISE EXCEPTION 'V3 selected-symbol CTE reference was not recognized';
        END IF;
        definition:=replace(definition,old_reference,new_reference);
        EXECUTE definition;
    END IF;

    definition:=pg_get_functiondef(
        'feat.build_price_features_v3_internal(date,date)'::regprocedure
    );
    IF position(new_reference IN definition)=0 OR
       position(old_reference IN definition)>0 THEN
        RAISE EXCEPTION 'V3 selected-symbol CTE still references an undefined relation';
    END IF;
END;
$phase2_v3_selected_symbols_cte_fix$;

COMMENT ON FUNCTION feat.build_price_features_v3_internal(date,date) IS
    'Build Phase 2 V3 features with set-based VNDIRECT adjustment eligibility; selected_symbols reads the eligible_symbols CTE.';

COMMIT;

-- Replace per-symbol adjustment-cache probes with one session-date-driven join.
BEGIN;

DO $phase2_v3_symbol_eligibility$
DECLARE
    definition text;
    old_text text;
    new_text text;
BEGIN
    definition:=pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);

    old_text:=$old$    ), symbols AS MATERIALIZED (
        -- Preserve the old eligibility rule: a symbol must have at least one
        -- finite positive VNDIRECT adjustment row on the effective-session
        -- spine. The cache's (symbol_id, trade_date) index bounds each probe.
        SELECT c.symbol_id
        FROM requested_symbols c
        WHERE EXISTS (
            SELECT 1
            FROM pg_temp.phase2_adjustment_rows r
            WHERE r.symbol_id=c.symbol_id
              AND r.source='vndirect'
              AND r.reference_adjustment_ratio>0
              AND r.reference_adjustment_ratio<'Infinity'::double precision
              AND EXISTS (
                  SELECT 1 FROM pg_temp.phase2_v3_sessions s
                  WHERE s.trade_date=r.trade_date
              )
        )
    ), selected_symbols AS MATERIALIZED ($old$;
    new_text:=$new$    ), eligible_symbols AS MATERIALIZED (
        -- Walk the selected session dates once through the cache's date-first
        -- index, then retain requested symbols with any finite positive factor.
        SELECT DISTINCT c.symbol_id
        FROM pg_temp.phase2_v3_sessions s
        JOIN pg_temp.phase2_adjustment_rows r ON r.trade_date=s.trade_date
        JOIN requested_symbols c ON c.symbol_id=r.symbol_id
        WHERE r.source='vndirect'
          AND r.reference_adjustment_ratio>0
          AND r.reference_adjustment_ratio<'Infinity'::double precision
    ), selected_symbols AS MATERIALIZED ($new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 per-symbol adjustment eligibility block was not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    IF position('JOIN pg_temp.phase2_adjustment_rows r ON r.trade_date=s.trade_date' IN definition)=0 THEN
        RAISE EXCEPTION 'V3 set-based session-date eligibility patch was not installed';
    END IF;
    EXECUTE definition;
END;
$phase2_v3_symbol_eligibility$;

COMMENT ON FUNCTION feat.build_price_features_v3_internal(date,date) IS
    'Build Phase 2 V3 features with symbol eligibility joined once from effective session dates into the date-first temporary adjustment cache index.';

COMMIT;

-- Drive V3 cache eligibility from requested symbols so the symbol/date index
-- can stop after the first eligible in-scope session for each symbol.
BEGIN;

DO $symbol_first_v3_eligibility$
DECLARE
    definition text;
    anchor text := $old$
    ), eligible_symbols AS MATERIALIZED (
        -- Walk the selected session dates once through the cache's date-first
        -- index, then retain requested symbols with any finite positive factor.
        SELECT DISTINCT c.symbol_id
        FROM pg_temp.phase2_v3_sessions s
        JOIN pg_temp.phase2_adjustment_rows r ON r.trade_date=s.trade_date
        JOIN requested_symbols c ON c.symbol_id=r.symbol_id
        WHERE r.source='vndirect'
          AND r.reference_adjustment_ratio>0
          AND r.reference_adjustment_ratio<'Infinity'::double precision
    ), selected_symbols AS MATERIALIZED (
$old$;
    replacement text := $new$
    ), eligible_symbols AS MATERIALIZED (
        -- symbol_first_v3_eligibility_v1: use the symbol/date index and stop
        -- after the first valid row inside the exact selected session range.
        SELECT c.symbol_id
        FROM requested_symbols c
        CROSS JOIN LATERAL (
            SELECT r.symbol_id
            FROM pg_temp.phase2_adjustment_rows r
            JOIN pg_temp.phase2_v3_sessions s ON s.trade_date=r.trade_date
            WHERE r.symbol_id=c.symbol_id
              AND r.trade_date BETWEEN
                  (SELECT min(trade_date) FROM pg_temp.phase2_v3_sessions)
                  AND (SELECT max(trade_date) FROM pg_temp.phase2_v3_sessions)
              AND r.source='vndirect'
              AND r.reference_adjustment_ratio>0
              AND r.reference_adjustment_ratio<'Infinity'::double precision
            LIMIT 1
        ) eligible
    ), selected_symbols AS MATERIALIZED (
$new$;
BEGIN
    definition:=pg_get_functiondef(
        'feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure
    );
    IF strpos(definition,'symbol_first_v3_eligibility_v1')=0 THEN
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 symbol eligibility query anchor';
        END IF;
        definition:=replace(definition,anchor,replacement);
        EXECUTE definition;
    END IF;

    definition:=pg_get_functiondef(
        'feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure
    );
    IF strpos(definition,'symbol_first_v3_eligibility_v1')=0
       OR strpos(definition,'CROSS JOIN LATERAL')=0
       OR strpos(definition,'r.symbol_id=c.symbol_id')=0
       OR strpos(definition,'r.trade_date BETWEEN')=0
       OR strpos(definition,'JOIN pg_temp.phase2_v3_sessions s ON s.trade_date=r.trade_date')=0
       OR strpos(definition,'JOIN pg_temp.phase2_adjustment_rows r ON r.trade_date=s.trade_date')>0 THEN
        RAISE EXCEPTION 'V3 symbol-first eligibility rewrite is incomplete';
    END IF;
END;
$symbol_first_v3_eligibility$;

COMMIT;

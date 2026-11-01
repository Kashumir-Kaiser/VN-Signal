BEGIN;

-- Keep the byte-verified evidence path exact while staging only source rows
-- needed by eligible bars that have price-limit observations. Older archived
-- VNDIRECT payloads can contain years of rows even when a label chunk uses
-- only one month; expanding and indexing every row made small chunks slow.
DO $phase2_selective_execution_payload_rows_109$
DECLARE
    v_signature constant regprocedure :=
        'feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure;
    v_definition text := pg_get_functiondef(v_signature);
    v_old constant text := $old$
    ANALYZE pg_temp.phase2_weight_verified_vndirect_landings_106;

    CREATE TEMP TABLE phase2_weight_vndirect_payload_rows_108 ON COMMIT DROP AS
    SELECT verified.landing_id,
           (raw_row.row_ordinality-1)::integer AS source_row,
           raw_row.row_payload
      FROM pg_temp.phase2_weight_verified_vndirect_landings_106 verified
      JOIN raw.landings land USING (landing_id)
      CROSS JOIN LATERAL jsonb_array_elements(
          CASE WHEN jsonb_typeof(land.payload->'data')='array'
               THEN land.payload->'data' ELSE '[]'::jsonb END
      ) WITH ORDINALITY AS raw_row(row_payload,row_ordinality);
    CREATE UNIQUE INDEX phase2_weight_vndirect_payload_rows_108_pk
        ON pg_temp.phase2_weight_vndirect_payload_rows_108(landing_id,source_row);
    ANALYZE pg_temp.phase2_weight_vndirect_payload_rows_108;

    CREATE TEMP TABLE phase2_weight_evidence_days_106 ON COMMIT DROP AS
    $old$;
    v_new constant text := $new$
    -- phase2_weight_payload_rows_selected_109
    CREATE TEMP TABLE phase2_weight_vndirect_payload_rows_108 ON COMMIT DROP AS
    WITH needed AS MATERIALIZED (
        SELECT DISTINCT b.landing_id,b.source_row
          FROM pg_temp.phase2_weight_eligible_bars_106 b
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=b.symbol_id AND p.trade_date=b.trade_date
           AND p.source IN ('vndirect','bsc')
         WHERE b.landing_id IS NOT NULL AND b.source_row IS NOT NULL
    ), needed_by_landing AS MATERIALIZED (
        SELECT landing_id,array_agg(source_row ORDER BY source_row) AS source_rows
          FROM needed
         GROUP BY landing_id
    )
    SELECT verified.landing_id,
           (raw_row.row_ordinality-1)::integer AS source_row,
           raw_row.row_payload
      FROM needed_by_landing needed
      JOIN pg_temp.phase2_weight_verified_vndirect_landings_106 verified USING (landing_id)
      JOIN raw.landings land USING (landing_id)
      CROSS JOIN LATERAL jsonb_array_elements(
          CASE WHEN jsonb_typeof(land.payload->'data')='array'
               THEN land.payload->'data' ELSE '[]'::jsonb END
      ) WITH ORDINALITY AS raw_row(row_payload,row_ordinality)
     WHERE (raw_row.row_ordinality-1)::integer=ANY(needed.source_rows);
    CREATE UNIQUE INDEX phase2_weight_vndirect_payload_rows_108_pk
        ON pg_temp.phase2_weight_vndirect_payload_rows_108(landing_id,source_row);
    ANALYZE pg_temp.phase2_weight_vndirect_payload_rows_108;

    CREATE TEMP TABLE phase2_weight_evidence_days_106 ON COMMIT DROP AS
    $new$;
BEGIN
    IF position('phase2_weight_payload_rows_selected_109' IN v_definition)>0 THEN
        IF position('=ANY(needed.source_rows)' IN v_definition)=0
           OR position('p.source IN (''vndirect'',''bsc'')' IN v_definition)=0 THEN
            RAISE EXCEPTION 'selective execution-payload staging is partially installed';
        END IF;
        RETURN;
    END IF;

    IF length(v_definition)-length(replace(v_definition,v_old,''))<>length(v_old) THEN
        RAISE EXCEPTION 'unexpected execution-payload staging implementation';
    END IF;

    v_definition:=replace(v_definition,v_old,v_new);
    EXECUTE v_definition;
END;
$phase2_selective_execution_payload_rows_109$;

COMMENT ON FUNCTION feat.refresh_phase2_execution_weights(date,date,date,bigint[]) IS
    'Computes exact execution weights from verified archived VNDIRECT and BSC payloads. It stages only source rows referenced by eligible bars with price-limit observations, expanding each needed landing once while preserving exact raw-row and limit-evidence checks.';

DO $phase2_selective_execution_payload_rows_assertions_109$
DECLARE
    v_definition text:=pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure
    );
BEGIN
    IF position('phase2_weight_payload_rows_selected_109' IN v_definition)=0
       OR position('array_agg(source_row ORDER BY source_row)' IN v_definition)=0
       OR position('=ANY(needed.source_rows)' IN v_definition)=0
       OR position('p.source IN (''vndirect'',''bsc'')' IN v_definition)=0
       OR position('p.row_payload=raw_bar.bar_row' IN v_definition)=0
       OR position('bar_l.payload->''data''->b.source_row' IN v_definition)>0
       OR position('limits_l.payload->''data''->p.source_row' IN v_definition)>0 THEN
        RAISE EXCEPTION 'selective execution-payload staging check failed';
    END IF;
END;
$phase2_selective_execution_payload_rows_assertions_109$;

COMMIT;

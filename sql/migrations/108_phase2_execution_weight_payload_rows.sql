BEGIN;

-- Raw labels are outputs of this same build step. The runner already checks
-- their exact chunk output hash, so changing them must not invalidate the
-- transaction-local source-input hash cache between the raw and derived steps.
DROP TRIGGER IF EXISTS phase2_label_dependency_labels_daily ON feat.labels_daily;

COMMENT ON FUNCTION ops.phase2_label_dependency_watermark() IS
    'Statement-level source revision watermark for feature rows, exact price-limit observations, and mutable raw landing payloads. Raw label outputs are checked through the runner exact output hash and do not invalidate source-input hashes within the same build transaction.';

-- Avoid repeatedly detoasting a full archived VNDIRECT landing for every
-- symbol/date row. Expand each verified landing's data array once, then join
-- its exact source_row to the staged canonical bar.
DO $phase2_execution_weight_payload_rows_108$
DECLARE
    v_signature constant regprocedure :=
        'feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure;
    v_definition text := pg_get_functiondef(v_signature);
    v_drop_anchor constant text :=
        '    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_days_106;';
    v_drop_replacement constant text :=
        '    DROP TABLE IF EXISTS pg_temp.phase2_weight_vndirect_payload_rows_108;'||E'\n'||
        v_drop_anchor;
    v_verified_anchor constant text :=
        '    ANALYZE pg_temp.phase2_weight_verified_vndirect_landings_106;'||E'\n'||E'\n'||
        '    CREATE TEMP TABLE phase2_weight_evidence_days_106 ON COMMIT DROP AS';
    v_verified_replacement constant text :=
        '    ANALYZE pg_temp.phase2_weight_verified_vndirect_landings_106;'||E'\n'||E'\n'||
        '    CREATE TEMP TABLE phase2_weight_vndirect_payload_rows_108 ON COMMIT DROP AS'||E'\n'||
        '    SELECT verified.landing_id,'||E'\n'||
        '           (raw_row.row_ordinality-1)::integer AS source_row,'||E'\n'||
        '           raw_row.row_payload'||E'\n'||
        '      FROM pg_temp.phase2_weight_verified_vndirect_landings_106 verified'||E'\n'||
        '      JOIN raw.landings land USING (landing_id)'||E'\n'||
        '      CROSS JOIN LATERAL jsonb_array_elements('||E'\n'||
        '          CASE WHEN jsonb_typeof(land.payload->''data'')=''array'''||E'\n'||
        '               THEN land.payload->''data'' ELSE ''[]''::jsonb END'||E'\n'||
        '      ) WITH ORDINALITY AS raw_row(row_payload,row_ordinality);'||E'\n'||
        '    CREATE UNIQUE INDEX phase2_weight_vndirect_payload_rows_108_pk'||E'\n'||
        '        ON pg_temp.phase2_weight_vndirect_payload_rows_108(landing_id,source_row);'||E'\n'||
        '    ANALYZE pg_temp.phase2_weight_vndirect_payload_rows_108;'||E'\n'||E'\n'||
        '    CREATE TEMP TABLE phase2_weight_evidence_days_106 ON COMMIT DROP AS';
    v_bar_extract_anchor constant text :=
        '          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id'||E'\n'||
        '          CROSS JOIN LATERAL ('||E'\n'||
        '              SELECT bar_l.payload->''data''->b.source_row AS bar_row'||E'\n'||
        '          ) raw_bar';
    v_bar_extract_replacement constant text :=
        '          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id'||E'\n'||
        '          JOIN pg_temp.phase2_weight_vndirect_payload_rows_108 raw_rows'||E'\n'||
        '            ON raw_rows.landing_id=b.landing_id AND raw_rows.source_row=b.source_row'||E'\n'||
        '          CROSS JOIN LATERAL ('||E'\n'||
        '              SELECT raw_rows.row_payload AS bar_row'||E'\n'||
        '          ) raw_bar';
    v_limit_row_anchor constant text :=
        '           AND p.row_payload=limits_l.payload->''data''->p.source_row';
    v_limit_row_replacement constant text :=
        '           AND p.row_payload=raw_bar.bar_row';
    v_type_anchor constant text :=
        '           AND jsonb_typeof(bar_l.payload->''data''->b.source_row)=''object''';
    v_type_replacement constant text :=
        '           AND jsonb_typeof(raw_bar.bar_row)=''object''';
BEGIN
    IF position('CREATE TEMP TABLE phase2_weight_vndirect_payload_rows_108' IN v_definition)>0 THEN
        IF position('p.row_payload=raw_bar.bar_row' IN v_definition)=0
           OR position('bar_l.payload->''data''->b.source_row' IN v_definition)>0
           OR position('jsonb_typeof(bar_l.payload->''data''->b.source_row)' IN v_definition)>0
           OR position('limits_l.payload->''data''->p.source_row' IN v_definition)>0 THEN
            RAISE EXCEPTION 'execution-weight payload-row optimization is partially installed';
        END IF;
        RETURN;
    END IF;

    IF length(v_definition)-length(replace(v_definition,v_drop_anchor,''))
       <>length(v_drop_anchor)
       OR length(v_definition)-length(replace(v_definition,v_verified_anchor,''))
       <>length(v_verified_anchor)
       OR length(v_definition)-length(replace(v_definition,v_bar_extract_anchor,''))
       <>2*length(v_bar_extract_anchor)
       OR length(v_definition)-length(replace(v_definition,v_limit_row_anchor,''))
       <>length(v_limit_row_anchor)
       OR length(v_definition)-length(replace(v_definition,v_type_anchor,''))
       <>length(v_type_anchor) THEN
        RAISE EXCEPTION 'unexpected execution-weight payload-row implementation';
    END IF;

    v_definition:=replace(v_definition,v_drop_anchor,v_drop_replacement);
    v_definition:=replace(v_definition,v_verified_anchor,v_verified_replacement);
    v_definition:=replace(v_definition,v_bar_extract_anchor,v_bar_extract_replacement);
    v_definition:=replace(v_definition,v_limit_row_anchor,v_limit_row_replacement);
    v_definition:=replace(v_definition,v_type_anchor,v_type_replacement);
    EXECUTE v_definition;
END;
$phase2_execution_weight_payload_rows_108$;

COMMENT ON FUNCTION feat.refresh_phase2_execution_weights(date,date,date,bigint[]) IS
    'Computes exact execution weights from verified archived VNDIRECT and BSC payloads. It expands each verified VNDIRECT landing into indexed source rows once per refresh, avoiding repeated full-payload detoasting for each symbol/date while preserving exact raw-row and limit-evidence checks.';

DO $phase2_execution_weight_payload_rows_assertions_108$
DECLARE
    v_definition text:=pg_get_functiondef(
        'feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure
    );
BEGIN
    IF position('phase2_weight_vndirect_payload_rows_108' IN v_definition)=0
       OR position('jsonb_array_elements' IN v_definition)=0
       OR position('p.row_payload=raw_bar.bar_row' IN v_definition)=0
       OR position('bar_l.payload->''data''->b.source_row' IN v_definition)>0
       OR position('limits_l.payload->''data''->p.source_row' IN v_definition)>0 THEN
        RAISE EXCEPTION 'execution-weight payload-row check failed: compare %, old bar extract %, old limit extract %, marker %',
            position('p.row_payload=raw_bar.bar_row' IN v_definition),
            position('bar_l.payload->''data''->b.source_row' IN v_definition),
            position('limits_l.payload->''data''->p.source_row' IN v_definition),
            position('phase2_weight_vndirect_payload_rows_108' IN v_definition);
    END IF;
END;
$phase2_execution_weight_payload_rows_assertions_108$;

COMMIT;

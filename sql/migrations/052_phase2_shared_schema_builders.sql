-- Phase 2 E2 support: route the existing feature and label implementations
-- through a validated search path, while retaining the public production API.
-- The shared implementations are generated from the already-installed final
-- builders so the math is not copied into a test-only implementation.
BEGIN;

CREATE OR REPLACE FUNCTION feat.phase2_builder_set_context(
    p_input_schema text,
    p_output_schema text,
    p_ops_schema text
)
RETURNS text
LANGUAGE plpgsql
AS $phase2_builder_set_context$
DECLARE
    schema_name text;
    schema_oid oid;
    schema_owner oid;
    previous_search_path text;
BEGIN
    FOREACH schema_name IN ARRAY ARRAY[p_input_schema,p_output_schema,p_ops_schema] LOOP
        IF schema_name IS NULL OR schema_name !~ '^[a-z_][a-z0-9_]{0,62}$'
           OR schema_name IN ('pg_catalog','information_schema','public')
           OR schema_name LIKE 'pg\_%' ESCAPE '\' THEN
            RAISE EXCEPTION 'invalid Phase 2 schema identifier';
        END IF;
        schema_oid := to_regnamespace(schema_name);
        IF schema_oid IS NULL OR NOT has_schema_privilege(current_user,schema_oid,'USAGE') THEN
            RAISE EXCEPTION 'Phase 2 schema % is unavailable',schema_name;
        END IF;
        SELECT n.nspowner INTO schema_owner
          FROM pg_namespace n WHERE n.oid=schema_oid;
        IF schema_name NOT IN ('core','feat','ops')
           AND schema_owner<>(SELECT r.oid FROM pg_roles r WHERE r.rolname=current_user) THEN
            RAISE EXCEPTION 'non-canonical Phase 2 schema % must be owned by the calling role',schema_name;
        END IF;
    END LOOP;

    IF p_input_schema=p_output_schema OR p_input_schema=p_ops_schema
       OR p_output_schema=p_ops_schema THEN
        RAISE EXCEPTION 'Phase 2 input, output, and ops schemas must be distinct';
    END IF;
    previous_search_path := current_setting('search_path');
    -- Schema names are restricted above and still identifier-quoted here.
    PERFORM set_config(
        'search_path',
        format('pg_catalog,%I,pg_temp,%I,%I,feat',
               p_output_schema,p_input_schema,p_ops_schema),
        true
    );
    RETURN previous_search_path;
END;
$phase2_builder_set_context$;

CREATE OR REPLACE FUNCTION feat.phase2_builder_restore_context(p_search_path text)
RETURNS void
LANGUAGE plpgsql
AS $phase2_builder_restore_context$
BEGIN
    PERFORM set_config('search_path',p_search_path,true);
END;
$phase2_builder_restore_context$;

-- The V3 market return dispersion, breadth, and turnover context always use
-- the complete V2 market panel. Scoped builds replace the selected symbols
-- from their isolated output while retaining the untouched universe from this
-- narrow input view/table.
CREATE OR REPLACE VIEW feat.phase2_market_features_daily AS
SELECT symbol_id,trade_date,feature_version,ret_1,
       distance_52w_high,distance_52w_low,turnover_proxy_vnd
  FROM feat.features_daily
 WHERE feature_version='phase2-v2';
COMMENT ON VIEW feat.phase2_market_features_daily IS
    'Full-universe V2 inputs for V3 market context; scoped rebuilds replace cohort rows from their isolated output.';

-- pg_get_functiondef formats argument lists differently across releases.
-- Add the typed cohort parameter by locating the declaration bounds, not by
-- substituting a caller-controlled identifier or assuming line breaks.
CREATE OR REPLACE FUNCTION feat.phase2_add_symbol_scope_argument(p_definition text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT
AS $phase2_add_symbol_scope_argument$
DECLARE
    open_pos integer:=strpos(p_definition,'(');
    close_pos integer;
    arguments text;
BEGIN
    IF open_pos=0 THEN RAISE EXCEPTION 'function definition has no argument list'; END IF;
    close_pos:=strpos(substr(p_definition,open_pos+1),')')+open_pos;
    IF close_pos<=open_pos THEN RAISE EXCEPTION 'function definition has an invalid argument list'; END IF;
    arguments:=substr(p_definition,open_pos+1,close_pos-open_pos-1);
    IF regexp_replace(arguments,'[[:space:]]+','','g')<>'p_date_fromdate,p_date_todate' THEN
        RAISE EXCEPTION 'unexpected Phase 2 builder signature: %',arguments;
    END IF;
    RETURN overlay(p_definition PLACING arguments||',p_symbol_ids bigint[]'
                   FROM open_pos+1 FOR close_pos-open_pos-1);
END;
$phase2_add_symbol_scope_argument$;

-- Generate shared V2 SQL from the exact final production function. Only
-- relation routing, write scoping, and the session-local symbol predicate are
-- changed; feature expressions remain byte-for-byte sourced from production.
DO $phase2_shared_v2$
DECLARE
    definition text;
    anchor text;
BEGIN
    IF to_regprocedure('feat.build_features_v2_shared(date,date,bigint[])') IS NULL THEN
    definition := pg_get_functiondef('feat.build_features_v2(date,date)'::regprocedure);
    definition := replace(definition,
        'FUNCTION feat.build_features_v2(',
        'FUNCTION feat.build_features_v2_shared(');
    definition := feat.phase2_add_symbol_scope_argument(definition);
    definition := replace(definition,'core.','');
    definition := replace(definition,'feat.features_daily','features_daily');

    -- The production CTE named `symbols` shadows the routed core.symbols
    -- relation after schema qualification is removed. Give that CTE a unique
    -- name so the exchange lookup resolves through the input-schema search path.
    anchor := '    ), symbols AS ('
        || E'\n        SELECT DISTINCT symbol_id FROM neutral_bars'
        || E'\n    ), spine0 AS (';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V2 symbol-spine CTE anchor';
    END IF;
    definition := replace(definition,anchor,
        '    ), phase2_v2_spine_symbols AS ('
        || E'\n        SELECT DISTINCT symbol_id FROM neutral_bars'
        || E'\n    ), spine0 AS (');
    anchor := '        FROM symbols y';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V2 symbol-spine source anchor';
    END IF;
    definition := replace(definition,anchor,'        FROM phase2_v2_spine_symbols y');

    anchor := '    WHERE trade_date BETWEEN p_date_from AND p_date_to AND feature_version=v_version;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V2 delete scope anchor';
    END IF;
    definition := replace(definition,anchor,
        '    WHERE trade_date BETWEEN p_date_from AND p_date_to AND feature_version=v_version'
        || E'\n      AND (p_symbol_ids IS NULL OR symbol_id=ANY(p_symbol_ids));');

    anchor := '        WHERE r.source=''vndirect'' AND r.trade_date<=p_date_to';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V2 adjustment input anchor';
    END IF;
    definition := replace(definition,anchor,
        anchor || E'\n          AND (p_symbol_ids IS NULL OR r.symbol_id=ANY(p_symbol_ids))');

    -- The generated declaration is kept identical to the production signature.
    IF position('feat.features_daily' IN definition)>0 OR position('core.' IN definition)>0
       OR position('build_features_v2_shared' IN definition)=0 THEN
        RAISE EXCEPTION 'V2 shared-builder routing transformation incomplete';
    END IF;
    EXECUTE definition;
    END IF;
END;
$phase2_shared_v2$;

-- Generate shared V3 SQL from the final 051-installed implementation. The
-- complete input cohort is scoped before its rank windows are computed.
DO $phase2_shared_v3$
DECLARE
    definition text;
    anchor text;
BEGIN
    IF to_regprocedure('feat.build_price_features_v3_shared(date,date,bigint[])') IS NULL THEN
    definition := pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);
    definition := replace(definition,
        'FUNCTION feat.build_price_features_v3_internal(',
        'FUNCTION feat.build_price_features_v3_shared(');
    definition := feat.phase2_add_symbol_scope_argument(definition);
    definition := replace(definition,'core.','');
    definition := replace(definition,'feat.features_daily','features_daily');
    definition := replace(definition,'feat.phase2_vci_index_features','phase2_vci_index_features');

    -- Preserve full-universe V3 market context during a selected-symbol build.
    -- The replacement view/table supplies untouched V2 rows, while freshly
    -- rebuilt cohort rows come from this invocation's output schema.
    anchor := '        FROM features_daily f'
        || E'\n        JOIN sessions s USING(trade_date)'
        || E'\n        WHERE f.feature_version=''phase2-v2'''
        || E'\n        GROUP BY f.trade_date,s.session_no';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 full-market context anchor';
    END IF;
    definition := replace(definition,anchor,
        '        FROM ('
        || E'\n            SELECT f.symbol_id,f.trade_date,f.feature_version,f.ret_1,'
        || E'\n                   f.distance_52w_high,f.distance_52w_low,f.turnover_proxy_vnd'
        || E'\n              FROM phase2_market_features_daily f'
        || E'\n             WHERE f.feature_version=''phase2-v2'''
        || E'\n               AND (p_symbol_ids IS NULL OR f.symbol_id<>ALL(p_symbol_ids))'
        || E'\n            UNION ALL'
        || E'\n            SELECT f.symbol_id,f.trade_date,f.feature_version,f.ret_1,'
        || E'\n                   f.distance_52w_high,f.distance_52w_low,f.turnover_proxy_vnd'
        || E'\n              FROM features_daily f'
        || E'\n             WHERE f.feature_version=''phase2-v2'''
        || E'\n               AND p_symbol_ids IS NOT NULL AND f.symbol_id=ANY(p_symbol_ids)'
        || E'\n        ) f'
        || E'\n        JOIN sessions s USING(trade_date)'
        || E'\n        GROUP BY f.trade_date,s.session_no');

    anchor := '    DELETE FROM features_daily'
        || E'\n     WHERE feature_version=''phase2-v3'' AND trade_date BETWEEN p_date_from AND p_date_to;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 delete scope anchor';
    END IF;
    definition := replace(definition,anchor,
        '    DELETE FROM features_daily'
        || E'\n     WHERE feature_version=''phase2-v3'' AND trade_date BETWEEN p_date_from AND p_date_to'
        || E'\n       AND (p_symbol_ids IS NULL OR symbol_id=ANY(p_symbol_ids));');

    anchor := 'WHERE f.feature_version=''phase2-v2'' AND f.trade_date BETWEEN p_date_from AND p_date_to';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 rank population anchor';
    END IF;
    definition := replace(definition,anchor,
        anchor || E'\n          AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids))');

    anchor := 'WHERE f.feature_version=''phase2-v2''' || E'\n          AND f.trade_date BETWEEN p_date_from AND p_date_to';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 selected-symbol anchor';
    END IF;
    definition := replace(definition,anchor,
        anchor || E'\n          AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids))');

    IF position('feat.features_daily' IN definition)>0 OR position('core.' IN definition)>0
       OR position('feat.phase2_vci_index_features' IN definition)>0
       OR position('build_price_features_v3_shared' IN definition)=0 THEN
        RAISE EXCEPTION 'V3 shared-builder routing transformation incomplete';
    END IF;
    EXECUTE definition;
    END IF;
END;
$phase2_shared_v3$;

-- Generate shared label SQL from the final 051-installed implementation.
DO $phase2_shared_labels$
DECLARE
    definition text;
    anchor text;
BEGIN
    IF to_regprocedure('feat.build_labels_set_based_shared(date,date,bigint[])') IS NULL THEN
    definition := pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure);
    definition := replace(definition,
        'FUNCTION feat.build_labels_set_based(',
        'FUNCTION feat.build_labels_set_based_shared(');
    definition := feat.phase2_add_symbol_scope_argument(definition);
    definition := replace(definition,'core.','');
    definition := replace(definition,'feat.features_daily','features_daily');
    definition := replace(definition,'feat.labels_daily','labels_daily');
    definition := replace(definition,'ops.ml_symbol_scope','ml_symbol_scope');

    anchor := '     WHERE signal_date BETWEEN p_date_from AND p_date_to'
        || E'\n       AND label_version = v_label;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected label delete scope anchor';
    END IF;
    definition := replace(definition,anchor,
        '     WHERE signal_date BETWEEN p_date_from AND p_date_to'
        || E'\n       AND label_version = v_label'
        || E'\n       AND (p_symbol_ids IS NULL OR symbol_id=ANY(p_symbol_ids));');

    anchor := '       AND f.feature_version = ''phase2-v3'';';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected label target scope anchor';
    END IF;
    definition := replace(definition,anchor,
        '       AND f.feature_version = ''phase2-v3'''
        || E'\n       AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids));');

    IF position('core.' IN definition)>0 OR position('feat.features_daily' IN definition)>0
       OR position('feat.labels_daily' IN definition)>0 OR position('ops.ml_symbol_scope' IN definition)>0
       OR position('build_labels_set_based_shared' IN definition)=0 THEN
        RAISE EXCEPTION 'label shared-builder routing transformation incomplete';
    END IF;
    EXECUTE definition;
    END IF;
END;
$phase2_shared_labels$;

DROP FUNCTION feat.phase2_add_symbol_scope_argument(text);

-- Legacy internal entry points continue to work against production schemas.
-- They now invoke the same shared SQL functions used by the scoped E2 entry.
CREATE OR REPLACE FUNCTION feat.build_features_v2(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; result bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    result:=feat.build_features_v2_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN result;
END $$;

CREATE OR REPLACE FUNCTION feat.build_price_features_v3_internal(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; result bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    result:=feat.build_price_features_v3_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN result;
END $$;

CREATE OR REPLACE FUNCTION feat.build_labels_set_based(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; result bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    result:=feat.build_labels_set_based_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN result;
END $$;

CREATE OR REPLACE FUNCTION feat.build_features(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; built bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    PERFORM feat.build_features_v2_shared(p_date_from,p_date_to,NULL);
    built:=feat.build_price_features_v3_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN built;
END $$;

CREATE OR REPLACE FUNCTION feat.build_price_features_v3(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; built bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    built:=feat.build_price_features_v3_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN built;
END $$;

CREATE OR REPLACE FUNCTION feat.build_labels(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE previous_path text; built bigint;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    built:=feat.build_labels_set_based_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN built;
END $$;

CREATE OR REPLACE FUNCTION feat.build_features_and_labels(p_date_from date,p_date_to date)
RETURNS TABLE(feature_rows bigint,label_rows bigint)
LANGUAGE plpgsql AS $$
DECLARE previous_path text;
BEGIN
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    feature_rows:=feat.build_features_v2_shared(p_date_from,p_date_to,NULL);
    feature_rows:=feat.build_price_features_v3_shared(p_date_from,p_date_to,NULL);
    label_rows:=feat.build_labels_set_based_shared(p_date_from,p_date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN NEXT;
END $$;

-- Scoped entry used by real-data E2. Its input schema must contain a copied
-- `phase2_adjustment_rows` table holding the canonical cache columns; the
-- other inputs are effective_trading_sessions, symbols, index_bars, and
-- phase2_vci_index_features. A temporary or input-schema
-- phase2_market_features_daily relation must hold the complete V2 market
-- context panel. Output tables are features_daily/labels_daily.
CREATE OR REPLACE FUNCTION feat.build_features_and_labels_scoped(
    p_date_from date,
    p_date_to date,
    p_input_schema text,
    p_output_schema text,
    p_ops_schema text,
    p_symbol_ids bigint[]
)
RETURNS TABLE(feature_rows bigint,label_rows bigint)
LANGUAGE plpgsql AS $$
DECLARE
    previous_path text;
    cache_relation oid;
    symbol_relation oid;
    state_relation oid;
    v_scope_symbols bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF p_output_schema IN ('core','feat','ops') OR p_ops_schema IN ('core','feat','ops') THEN
        RAISE EXCEPTION 'scoped Phase 2 builders require isolated output and ops schemas';
    END IF;
    IF p_symbol_ids IS NULL OR cardinality(p_symbol_ids)<1 OR cardinality(p_symbol_ids)>250
       OR array_position(p_symbol_ids,NULL) IS NOT NULL
       OR (SELECT count(DISTINCT x) FROM unnest(p_symbol_ids) x)<>cardinality(p_symbol_ids) THEN
        RAISE EXCEPTION 'Phase 2 symbol scope must contain 1..250 unique non-null IDs';
    END IF;
    previous_path:=feat.phase2_builder_set_context(
        p_input_schema,p_output_schema,p_ops_schema
    );

    IF to_regclass(format('%I.phase2_adjustment_rows',p_input_schema)) IS NULL
       OR to_regclass(format('%I.effective_trading_sessions',p_input_schema)) IS NULL
       OR to_regclass(format('%I.symbols',p_input_schema)) IS NULL
       OR to_regclass(format('%I.index_bars',p_input_schema)) IS NULL
       OR to_regclass(format('%I.phase2_vci_index_features',p_input_schema)) IS NULL
       OR (to_regclass('pg_temp.phase2_market_features_daily') IS NULL
           AND to_regclass(format('%I.phase2_market_features_daily',p_input_schema)) IS NULL)
       OR to_regclass(format('%I.ml_symbol_scope',p_ops_schema)) IS NULL
       OR to_regclass(format('%I.features_daily',p_output_schema)) IS NULL
       OR to_regclass(format('%I.labels_daily',p_output_schema)) IS NULL THEN
        RAISE EXCEPTION 'scoped Phase 2 schemas do not contain the required input/output relations';
    END IF;

    EXECUTE format('SELECT count(*) FROM %I.symbols WHERE symbol_id=ANY($1)',p_input_schema)
       INTO v_scope_symbols USING p_symbol_ids;
    IF v_scope_symbols<>cardinality(p_symbol_ids) THEN
        RAISE EXCEPTION 'input schema does not contain every requested symbol';
    END IF;

    cache_relation:=to_regclass('pg_temp.phase2_adjustment_rows');
    IF cache_relation IS NOT NULL THEN
        IF obj_description(cache_relation,'pg_class') IS DISTINCT FROM
            'VN-Signal Phase 2 session-local point-in-time price input cache' THEN
            RAISE EXCEPTION 'temporary relation phase2_adjustment_rows is reserved by the Phase 2 builder';
        END IF;
        DROP TABLE pg_temp.phase2_adjustment_rows;
    END IF;
    symbol_relation:=to_regclass('pg_temp.phase2_adjustment_symbol_batches');
    IF symbol_relation IS NOT NULL THEN
        IF obj_description(symbol_relation,'pg_class') IS DISTINCT FROM
            'VN-Signal Phase 2 session-local cache symbol-batch manifest' THEN
            RAISE EXCEPTION 'temporary relation phase2_adjustment_symbol_batches is reserved by the Phase 2 builder';
        END IF;
        DROP TABLE pg_temp.phase2_adjustment_symbol_batches;
    END IF;
    state_relation:=to_regclass('pg_temp.phase2_adjustment_cache_state');
    IF state_relation IS NOT NULL THEN
        IF obj_description(state_relation,'pg_class') IS DISTINCT FROM
            'VN-Signal Phase 2 session-local cache readiness state' THEN
            RAISE EXCEPTION 'temporary relation phase2_adjustment_cache_state is reserved by the Phase 2 builder';
        END IF;
        DROP TABLE pg_temp.phase2_adjustment_cache_state;
    END IF;
    EXECUTE format(
        'CREATE TEMP TABLE pg_temp.phase2_adjustment_rows ON COMMIT DROP AS '
        || 'SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,'
        || 'r.reference_adjustment_ratio,r.episode_start_date,r.model_o,r.model_h,r.model_l,r.model_c,'
        || 'r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at '
        || 'FROM %I.phase2_adjustment_rows r '
        || 'WHERE r.source=''vndirect'' AND r.symbol_id=ANY($1)',
        p_input_schema
    ) USING p_symbol_ids;
    SELECT count(DISTINCT symbol_id) INTO v_scope_symbols
      FROM pg_temp.phase2_adjustment_rows;
    IF v_scope_symbols<>cardinality(p_symbol_ids) THEN
        RAISE EXCEPTION 'copied adjustment inputs do not cover every requested symbol';
    END IF;
    COMMENT ON TABLE pg_temp.phase2_adjustment_rows IS
        'VN-Signal Phase 2 session-local point-in-time price input cache';
    CREATE INDEX phase2_adjustment_rows_date_symbol_idx
        ON pg_temp.phase2_adjustment_rows(trade_date,symbol_id);
    CREATE INDEX phase2_adjustment_rows_symbol_date_idx
        ON pg_temp.phase2_adjustment_rows(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_adjustment_rows;

    CREATE TEMP TABLE phase2_adjustment_symbol_batches ON COMMIT DROP AS
    SELECT symbol_id,0::integer AS batch_no,true AS loaded
      FROM pg_temp.phase2_adjustment_rows GROUP BY symbol_id;
    COMMENT ON TABLE pg_temp.phase2_adjustment_symbol_batches IS
        'VN-Signal Phase 2 session-local cache symbol-batch manifest';
    ALTER TABLE pg_temp.phase2_adjustment_symbol_batches ADD PRIMARY KEY(symbol_id);
    CREATE INDEX phase2_adjustment_symbol_batches_batch_idx
        ON pg_temp.phase2_adjustment_symbol_batches(batch_no,symbol_id);
    ANALYZE pg_temp.phase2_adjustment_symbol_batches;
    SELECT count(*) INTO v_scope_symbols
      FROM pg_temp.phase2_adjustment_symbol_batches
     WHERE NOT (symbol_id=ANY(p_symbol_ids));
    IF v_scope_symbols<>0 OR
       (SELECT count(*) FROM pg_temp.phase2_adjustment_symbol_batches)<>cardinality(p_symbol_ids) THEN
        RAISE EXCEPTION 'Phase 2 adjustment-cache manifest does not exactly match the requested symbol scope';
    END IF;

    CREATE TEMP TABLE phase2_adjustment_cache_state(
        cache_id integer PRIMARY KEY DEFAULT 1 CHECK(cache_id=1),
        ready boolean NOT NULL DEFAULT false,
        finalized_at timestamptz
    ) ON COMMIT DROP;
    COMMENT ON TABLE pg_temp.phase2_adjustment_cache_state IS
        'VN-Signal Phase 2 session-local cache readiness state';
    INSERT INTO pg_temp.phase2_adjustment_cache_state(ready,finalized_at)
    VALUES(true,clock_timestamp());

    PERFORM feat.prepare_phase2_adjustment_rows(false);
    feature_rows:=feat.build_features_v2_shared(p_date_from,p_date_to,p_symbol_ids);
    feature_rows:=feat.build_price_features_v3_shared(p_date_from,p_date_to,p_symbol_ids);
    label_rows:=feat.build_labels_set_based_shared(p_date_from,p_date_to,p_symbol_ids);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    RETURN NEXT;
END $$;

COMMENT ON FUNCTION feat.build_features_and_labels_scoped(date,date,text,text,text,bigint[]) IS
    'Runs the production V2, V3, and label SQL bodies against owner-controlled isolated schemas and a selected symbol cohort. Schema names are identifier-validated and quoted; input data is never fetched from vnstock.';

COMMIT;

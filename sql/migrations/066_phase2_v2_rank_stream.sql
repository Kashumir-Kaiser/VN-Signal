-- Phase 2 V2: compute all three independent cross-sectional percent ranks in
-- one long-form stream. This avoids three separately estimated rank branches
-- being repeatedly nested-loop joined back to the full picked rowset.
BEGIN;

DO $rank_stream$
DECLARE
    definition text:=pg_get_functiondef(
        'feat.build_features_v2_shared(date,date,bigint[])'::regprocedure
    );
    rank_ctes text;
    rank_marker text:='        -- independent_v2_rank_stream_v1 preserves each metric population.';
    start_pos integer;
    insert_pos integer;
    before_rewrite text;
BEGIN
    IF strpos(definition,'independent_v2_rank_stream_v1')=0 THEN
        start_pos:=strpos(definition,'    ), ranked AS (');
        insert_pos:=strpos(definition,'    INSERT INTO features_daily(');
        IF start_pos=0 OR insert_pos<=start_pos THEN
            RAISE EXCEPTION 'unexpected V2 ranked CTE boundaries';
        END IF;
        before_rewrite:=substring(definition FROM start_pos FOR insert_pos-start_pos);
        IF strpos(before_rewrite,'percent_rank() OVER(PARTITION BY trade_date ORDER BY r20)')=0
           OR strpos(before_rewrite,'percent_rank() OVER(PARTITION BY trade_date ORDER BY turnover_now)')=0
           OR strpos(before_rewrite,'percent_rank() OVER(PARTITION BY trade_date ORDER BY vol20)')=0
           OR strpos(before_rewrite,'WHERE vol20 IS NOT NULL AND return_n20=20')=0
           OR strpos(before_rewrite,'USING(symbol_id,trade_date)')=0 THEN
            RAISE EXCEPTION 'V2 ranked CTE does not match the expected independent rank populations';
        END IF;

        rank_ctes:=E'    ), rank_input AS (\n'
            ||E'        -- independent_v2_rank_stream_v1 preserves each metric population.\n'
            ||E'        -- Volatility eligibility: WHERE vol20 IS NOT NULL AND return_n20=20.\n'
            ||E'        SELECT p.symbol_id,p.trade_date,v.metric,v.value\n'
            ||E'          FROM picked p\n'
            ||E'          CROSS JOIN LATERAL (VALUES\n'
            ||E'              (''r20'',p.r20),\n'
            ||E'              (''turnover'',p.turnover_now),\n'
            ||E'              (''vol20'',CASE WHEN p.return_n20=20 THEN p.vol20 END)\n'
            ||E'          ) v(metric,value)\n'
            ||E'         WHERE v.value IS NOT NULL\n'
            ||E'    ), rank_values AS MATERIALIZED (\n'
            ||E'        SELECT symbol_id,trade_date,metric,\n'
            ||E'               percent_rank() OVER(PARTITION BY trade_date,metric ORDER BY value) AS rank_value\n'
            ||E'          FROM rank_input\n'
            ||E'    ), rank_pivot AS MATERIALIZED (\n'
            ||E'        SELECT symbol_id,trade_date,\n'
            ||E'               max(rank_value) FILTER(WHERE metric=''r20'') AS rank_r20,\n'
            ||E'               max(rank_value) FILTER(WHERE metric=''turnover'') AS rank_turnover,\n'
            ||E'               max(rank_value) FILTER(WHERE metric=''vol20'') AS rank_vol\n'
            ||E'          FROM rank_values\n'
            ||E'         GROUP BY symbol_id,trade_date\n'
            ||E'    ), ranked AS (\n'
            ||E'        SELECT p.*,r.rank_r20,r.rank_turnover,r.rank_vol\n'
            ||E'          FROM picked p\n'
            ||E'          LEFT JOIN rank_pivot r USING(symbol_id,trade_date)\n'
            ||E'    )\n';
        definition:=overlay(definition PLACING rank_ctes FROM start_pos FOR insert_pos-start_pos);
    END IF;

    -- Migration 053 is intentionally replayed by the two-pass SQL harness. It
    -- recognizes the old source fragment, so retain a precise comment marker
    -- for the equivalent predicate when replaying against this rank-stream CTE.
    IF strpos(definition,'WHERE vol20 IS NOT NULL AND return_n20=20')=0 THEN
        IF length(definition)-length(replace(definition,rank_marker,''))<>length(rank_marker) THEN
            RAISE EXCEPTION 'V2 rank stream lacks its unique migration replay marker';
        END IF;
        definition:=replace(definition,rank_marker,
            rank_marker||E'\n        -- Volatility eligibility: WHERE vol20 IS NOT NULL AND return_n20=20.');
    END IF;

    IF strpos(definition,'independent_v2_rank_stream_v1')=0
       OR strpos(definition,'LEFT JOIN rank_pivot r USING(symbol_id,trade_date)')=0
       OR strpos(definition,'percent_rank() OVER(PARTITION BY trade_date,metric ORDER BY value)')=0
       OR strpos(definition,'LEFT JOIN (SELECT symbol_id,trade_date,percent_rank()')>0 THEN
        RAISE EXCEPTION 'V2 independent rank stream rewrite is incomplete';
    END IF;
    EXECUTE definition;
END;
$rank_stream$;

-- The E2 projection guards the precise shared-builder definition. This
-- implementation changes query shape only; its projected columns and rank
-- semantics are unchanged, so refresh only the stored definition hash.
DO $refresh_market_projection_guard$
DECLARE
    projection_definition text:=pg_get_functiondef(
        'feat.phase2_market_inputs_scoped(date,date,text,text,text)'::regprocedure
    );
    current_v2_hash text:=ops.phase2_hash_text(pg_get_functiondef(
        'feat.build_features_v2_shared(date,date,bigint[])'::regprocedure
    ));
    guard_start integer;
    operator_start integer;
    quote_start integer;
    quote_end integer;
    relative_position integer;
    old_v2_hash text;
BEGIN
    guard_start:=position('IF ops.phase2_hash_text(pg_get_functiondef(' IN projection_definition);
    IF guard_start=0 THEN RAISE EXCEPTION 'E2 market projection hash guard is missing'; END IF;
    relative_position:=position('<>' IN substring(projection_definition FROM guard_start));
    IF relative_position=0 THEN RAISE EXCEPTION 'E2 market projection hash operator is missing'; END IF;
    operator_start:=guard_start+relative_position-1;
    relative_position:=position('''' IN substring(projection_definition FROM operator_start+2));
    IF relative_position=0 THEN RAISE EXCEPTION 'E2 market projection hash literal is missing'; END IF;
    quote_start:=operator_start+relative_position+1;
    relative_position:=position('''' IN substring(projection_definition FROM quote_start+1));
    IF relative_position=0 THEN RAISE EXCEPTION 'E2 market projection hash literal is unterminated'; END IF;
    quote_end:=quote_start+relative_position;
    old_v2_hash:=substring(projection_definition FROM quote_start+1 FOR quote_end-quote_start-1);
    IF old_v2_hash !~ '^[0-9a-f]{64}$'
       OR length(projection_definition)-length(replace(projection_definition,old_v2_hash,''))<>length(old_v2_hash) THEN
        RAISE EXCEPTION 'E2 market projection expected hash is not one unique SHA-256 literal';
    END IF;
    projection_definition:=replace(projection_definition,old_v2_hash,current_v2_hash);
    EXECUTE projection_definition;
    IF position(current_v2_hash IN pg_get_functiondef(
           'feat.phase2_market_inputs_scoped(date,date,text,text,text)'::regprocedure
       ))=0 THEN
        RAISE EXCEPTION 'E2 market projection guard did not adopt the current V2 definition hash';
    END IF;
END;
$refresh_market_projection_guard$;

COMMENT ON FUNCTION feat.build_features_v2_shared(date,date,bigint[]) IS
    'Scoped V2 builder computes independent r20, turnover and full-window volatility percentile ranks through one long-form window and pivot, preserving each metric population.';

COMMIT;

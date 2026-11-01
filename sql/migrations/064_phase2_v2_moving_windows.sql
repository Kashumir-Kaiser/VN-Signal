-- Phase 2 V2 exact trailing 250-session extrema without a frame-rescan
-- WindowAgg. Native avg/stddev aggregates remain unchanged for strict parity.
BEGIN;

DO $rewrite_v2$
DECLARE
    definition text:=pg_get_functiondef(
        'feat.build_features_v2_shared(date,date,bigint[])'::regprocedure
    );
    extrema_ctes text;
    anchor text:='    ), prior_daily AS (';
    before_rewrite text;
    extrema_start integer;
    prior_daily_start integer;
    start_at integer;
    source_at integer;
    prior_source text;
BEGIN
    -- Upgrade a disposable clone that has an earlier draft installed. These
    -- replacements are deliberately full-prefix-first to avoid nesting names.
    definition:=replace(definition,'feat.p2_moving_feat.p2_moving_avg(','avg(');
    definition:=replace(definition,'feat.p2_moving_avg(','avg(');
    definition:=replace(definition,'feat.p2_moving_feat.p2_shifted_stddev_samp(','stddev_samp(');
    definition:=replace(definition,'feat.p2_shifted_stddev_samp(','stddev_samp(');
    definition:=replace(definition,'feat.p2_moving_feat.p2_moving_stddev_samp(','stddev_samp(');
    definition:=replace(definition,'feat.p2_moving_stddev_samp(','stddev_samp(');

    extrema_ctes:=E'    ), extrema_rows AS (\n'
        ||E'        SELECT s.*,row_number() OVER(PARTITION BY s.symbol_id,s.episode_key ORDER BY s.session_no)-1 AS episode_row,\n'
        ||E'               CASE WHEN s.is_traded THEN s.h END AS high_value,\n'
        ||E'               CASE WHEN s.is_traded THEN s.l END AS low_value\n'
        ||E'        FROM spine s\n'
        ||E'    ), extrema_blocks AS (\n'
        ||E'        SELECT e.*,(e.episode_row/250)::bigint AS block_no,\n'
        ||E'               max(e.high_value) OVER(PARTITION BY e.symbol_id,e.episode_key,(e.episode_row/250) ORDER BY e.episode_row ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS high_prefix,\n'
        ||E'               max(e.high_value) OVER(PARTITION BY e.symbol_id,e.episode_key,(e.episode_row/250) ORDER BY e.episode_row ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS high_suffix,\n'
        ||E'               min(e.low_value) OVER(PARTITION BY e.symbol_id,e.episode_key,(e.episode_row/250) ORDER BY e.episode_row ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS low_prefix,\n'
        ||E'               min(e.low_value) OVER(PARTITION BY e.symbol_id,e.episode_key,(e.episode_row/250) ORDER BY e.episode_row ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS low_suffix\n'
        ||E'        FROM extrema_rows e\n'
        ||E'    ), extrema_lags AS (\n'
        ||E'        SELECT e.*,lag(e.high_suffix,249) OVER(PARTITION BY e.symbol_id,e.episode_key ORDER BY e.episode_row) AS high_suffix_start,\n'
        ||E'               lag(e.low_suffix,249) OVER(PARTITION BY e.symbol_id,e.episode_key ORDER BY e.episode_row) AS low_suffix_start\n'
        ||E'        FROM extrema_blocks e\n'
        ||E'    ), extrema250 AS (\n'
        ||E'        SELECT e.symbol_id,e.trade_date,e.session_no,e.o,e.h,e.l,e.c,e.model_c,e.v,e.is_traded,\n'
        ||E'               e.adjustment_vintage_at,e.landing_id,e.source_row,e.fetched_at,e.bar_episode,e.exchange,e.episode_key,\n'
        ||E'               CASE WHEN e.episode_row<249 OR e.block_no=((e.episode_row-249)/250) THEN e.high_prefix\n'
        ||E'                    ELSE greatest(e.high_prefix,e.high_suffix_start) END AS extrema_high250,\n'
        ||E'               CASE WHEN e.episode_row<249 OR e.block_no=((e.episode_row-249)/250) THEN e.low_prefix\n'
        ||E'                    ELSE least(e.low_prefix,e.low_suffix_start) END AS extrema_low250\n'
        ||E'        FROM extrema_lags e\n'
        ||E'    ), prior_daily AS (';

    -- Remove the earlier separate-join variant if it is present, then install
    -- the row-stream variant. The regex is bounded to the generated CTE names.
    IF position('), extrema_rows AS MATERIALIZED (' IN definition)>0 THEN
        before_rewrite:=definition;
        definition:=regexp_replace(definition,
            E'\\), extrema_rows AS MATERIALIZED \\(.*?\\), prior_daily AS \\(',extrema_ctes,'s');
        IF definition=before_rewrite THEN
            RAISE EXCEPTION 'materialized V2 extrema rewrite did not match its CTE block';
        END IF;
    ELSIF position('), extrema_rows AS (' IN definition)>0 THEN
        before_rewrite:=definition;
        definition:=regexp_replace(definition,
            E'\\), extrema_rows AS \\(.*?\\), prior_daily AS \\(',extrema_ctes,'s');
        IF definition=before_rewrite THEN
            RAISE EXCEPTION 'V2 extrema rewrite did not match its CTE block';
        END IF;
    ELSE
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V2 prior_daily CTE anchor';
        END IF;
        definition:=replace(definition,anchor,extrema_ctes);
    END IF;

    definition:=replace(definition,'JOIN extrema250 ex USING(symbol_id,trade_date)','');
    definition:=replace(definition,'ex.high250 AS high250','x.extrema_high250 AS high250');
    definition:=replace(definition,'ex.low250 AS low250','x.extrema_low250 AS low250');
    definition:=replace(definition,'max(x.h) FILTER(WHERE x.is_traded) OVER w250 AS high250','x.extrema_high250 AS high250');
    definition:=replace(definition,'min(x.l) FILTER(WHERE x.is_traded) OVER w250 AS low250','x.extrema_low250 AS low250');

    -- Move only the prior_daily input from spine to the augmented row stream.
    start_at:=position(anchor IN definition);
    IF start_at=0 THEN RAISE EXCEPTION 'V2 prior_daily CTE missing after extrema rewrite'; END IF;
    source_at:=position('FROM spine x' IN substring(definition FROM start_at));
    IF source_at>0 THEN
        source_at:=start_at+source_at-1;
        prior_source:=substring(definition FROM start_at FOR source_at-start_at+length('FROM spine x'));
        definition:=replace(definition,prior_source,
            replace(prior_source,'FROM spine x','FROM extrema250 x'));
    ELSIF position('FROM extrema250 x' IN substring(definition FROM start_at))=0 THEN
        RAISE EXCEPTION 'V2 prior_daily source is neither pristine nor integrated';
    END IF;

    extrema_start:=position('), extrema250 AS (' IN definition);
    prior_daily_start:=position(anchor IN definition);
    IF extrema_start=0 OR prior_daily_start<=extrema_start
       OR position('e.session_no' IN substring(definition FROM extrema_start FOR prior_daily_start-extrema_start))=0
       OR position('e.is_traded' IN substring(definition FROM extrema_start FOR prior_daily_start-extrema_start))=0
       OR position('extrema_high250' IN substring(definition FROM extrema_start FOR prior_daily_start-extrema_start))=0
       OR position('extrema_low250' IN substring(definition FROM extrema_start FOR prior_daily_start-extrema_start))=0 THEN
        RAISE EXCEPTION 'V2 extrema rewrite omitted columns required by prior_daily';
    END IF;

    IF position('feat.p2_moving_' IN definition)>0
       OR position('feat.p2_shifted_stddev' IN definition)>0
       OR position('extrema250 ex USING(symbol_id,trade_date)' IN definition)>0
       OR position('ex.high250 AS high250' IN definition)>0
       OR position('ex.low250 AS low250' IN definition)>0
       OR position('FROM extrema250 x' IN definition)=0
       OR position('max(x.h) FILTER(WHERE x.is_traded) OVER w250 AS high250' IN definition)>0
       OR position('min(x.l) FILTER(WHERE x.is_traded) OVER w250 AS low250' IN definition)>0 THEN
        RAISE EXCEPTION 'V2 extrema rewrite is incomplete';
    END IF;
    EXECUTE definition;
END;
$rewrite_v2$;

-- Migration 055 generated the E2 market-input projection from the prior V2
-- definition and stored that definition's hash as a drift guard. The V2
-- equations remain unchanged here, but the exact-extrema implementation does
-- change the function text. Refresh only that expected hash; the projection
-- still has to pass the output-parity and future-perturbation fixture.
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

DROP AGGREGATE IF EXISTS feat.p2_moving_avg(double precision);
DROP AGGREGATE IF EXISTS feat.p2_moving_stddev_pop(double precision);
DROP AGGREGATE IF EXISTS feat.p2_moving_stddev_samp(double precision);
DROP AGGREGATE IF EXISTS feat.p2_shifted_stddev_pop(double precision);
DROP AGGREGATE IF EXISTS feat.p2_shifted_stddev_samp(double precision);
DROP FUNCTION IF EXISTS feat.phase2_moving_avg_final(double precision[]);
DROP FUNCTION IF EXISTS feat.phase2_moving_stddev_pop_final(double precision[]);
DROP FUNCTION IF EXISTS feat.phase2_moving_stddev_samp_final(double precision[]);
DROP FUNCTION IF EXISTS feat.phase2_moving_moments_inv(double precision[],double precision);
DROP FUNCTION IF EXISTS feat.phase2_moving_moments_combine(double precision[],double precision[]);
DROP FUNCTION IF EXISTS feat.phase2_moving_moments_trans(double precision[],double precision);

COMMENT ON FUNCTION feat.build_features_v2_shared(date,date,bigint[]) IS
    'Scoped V2 builder uses exact block prefix/suffix trailing 250-session extrema; all native averages, standard deviations, expressions, keys, filters and null rules remain unchanged.';

COMMIT;

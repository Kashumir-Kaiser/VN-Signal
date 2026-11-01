-- Make V3 recursive features independent of the requested build chunk.
-- EMA and MACD state must begin from the 1,000 effective sessions before the
-- calendar year containing each output date, as in the Rust parity reference.
BEGIN;

DO $phase2_v3_year_anchored_impl$
DECLARE
    definition text;
    anchor text;
    replacement text;
    shared_guard text:= $guard$
    -- phase2_v3_calendar_shared_guard: shared is only a safe direct entry for
    -- a single year whose output starts on January 1. Use the calendar wrapper
    -- for partial-year or multi-year requests.
    IF p_date_from<>date_trunc('year',p_date_from)::date
       OR p_date_to >= (date_trunc('year',p_date_from)+INTERVAL '1 year')::date THEN
        RAISE EXCEPTION 'V3 shared builder requires a January 1 year start and a single-year range; use feat.build_price_features_v3_calendar_chunked';
    END IF;
$guard$;
    history_guard text:= $guard$
    IF p_history_from IS NULL
       OR p_history_from<>date_trunc('year',p_date_from)::date
       OR p_date_from<p_history_from
       OR p_date_to >= (p_history_from+INTERVAL '1 year')::date THEN
        RAISE EXCEPTION 'V3 year implementation requires a January 1 history anchor and a single-year output range';
    END IF;
$guard$;
BEGIN
    definition:=replace(
        pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure),
        E'\r\n',E'\n'
    );
    IF strpos(definition,'phase2_v3_calendar_shared_guard')=0 THEN
        anchor:=$validation$
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
$validation$;
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 shared date-validation anchor';
        END IF;
        definition:=replace(definition,anchor,anchor||E'\n'||shared_guard);
        EXECUTE definition;
    END IF;

    -- Clone the full, migration-patched shared implementation so the SQL
    -- stages remain identical. Keep the original body intact for migrations
    -- 053-084, which deliberately patch and validate its full definition.
    definition:=replace(
        pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure),
        E'\r\n',E'\n'
    );
    anchor:='FUNCTION feat.build_price_features_v3_shared(p_date_from date, p_date_to date, p_symbol_ids bigint[])';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 shared function signature';
    END IF;
    definition:=replace(definition,anchor,
        'FUNCTION feat.build_price_features_v3_year_impl(p_date_from date, p_date_to date, p_symbol_ids bigint[], p_history_from date)');

    IF length(definition)-length(replace(definition,shared_guard,''))<>length(shared_guard) THEN
        RAISE EXCEPTION 'unexpected V3 shared-year guard while cloning implementation';
    END IF;
    definition:=replace(definition,shared_guard,'');

    anchor:=$validation$
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
$validation$;
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 year-implementation date-validation anchor';
    END IF;
    definition:=replace(definition,anchor,anchor||E'\n'||history_guard);

    anchor:='WHERE trade_date<p_date_from AND is_session';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 prior-session warmup anchor';
    END IF;
    definition:=replace(definition,anchor,'WHERE trade_date<p_history_from AND is_session');

    anchor:='WHERE trade_date BETWEEN p_date_from AND p_date_to AND is_session';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected V3 session-spine anchor';
    END IF;
    definition:=replace(definition,anchor,
        'WHERE trade_date BETWEEN p_history_from AND p_date_to AND is_session');

    IF strpos(definition,'p_history_from')=0
       OR strpos(definition,'phase2_v3_compute_batch_size')=0
       OR strpos(definition,'phase2_v3_calendar_shared_guard')>0 THEN
        RAISE EXCEPTION 'V3 year implementation transformation is incomplete';
    END IF;
    EXECUTE definition;
END
$phase2_v3_year_anchored_impl$;

CREATE OR REPLACE FUNCTION feat.build_price_features_v3_calendar_chunked(
    p_date_from date,p_date_to date,p_symbol_ids bigint[]
)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    year_cursor date;
    year_end date;
    output_from date;
    output_to date;
    affected bigint:=0;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    year_cursor:=date_trunc('year',p_date_from)::date;
    WHILE year_cursor<=p_date_to LOOP
        year_end:=(year_cursor+INTERVAL '1 year'-INTERVAL '1 day')::date;
        output_from:=greatest(p_date_from,year_cursor);
        output_to:=least(p_date_to,year_end);
        affected:=affected+feat.build_price_features_v3_year_impl(
            output_from,output_to,p_symbol_ids,year_cursor
        );
        year_cursor:=(year_cursor+INTERVAL '1 year')::date;
    END LOOP;
    RETURN affected;
END
$$;

COMMENT ON FUNCTION feat.build_price_features_v3_year_impl(date,date,bigint[],date) IS
    'Private V3 implementation. Its effective-session axis begins at January 1 plus the preceding 1,000 sessions, while output writes remain restricted to the requested date range.';
COMMENT ON FUNCTION feat.build_price_features_v3_calendar_chunked(date,date,bigint[]) IS
    'Builds V3 output in calendar-year segments so EMA and MACD warmup is stable across annual, quarterly, monthly, and multi-year requests.';

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3()
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT md5(definition||'|'||base_hash)
        ||md5('VN-Signal:'||definition||'|'||base_hash)
    FROM (VALUES (
        'phase2-v3|effective_sessions|episode_neutral_prices|12_1_231_return_sessions'
        ||'|market_model_beta_60_250_one_session_lag_stable_pair_moments'
        ||'|independent_nonnull_rank_populations_v1'
        ||'|ordered_window_ema_5_10_20_50_100_200_1000_session_warmup_year_anchored_jan1_v1'
        ||'|macd_12_26_9|adx_14_simple_average|stochastic_14_3_same_adjustment_episode'
        ||'|downside_vol_5_60|population_skew_kurtosis_60|amihud_turnover_proxy_20'
        ||'|gap_stats_20|rank_gaussian_tie_averaged_midrank|lagged_market_context'
        ||'|vnindex_sma50_200_drawdown252_vol60|vnindex_source_vci'
        ||'|vnindex_inherited_returns_vol20_vci|quarter_end_calendar_days'
        ||'|strict_full_window_cross_sectional_vol_rank|source_dependent_features_null_without_evidence'
    )) d(definition)
    CROSS JOIN LATERAL (SELECT feat.phase2_feature_set_hash() AS base_hash) h
$$;

DO $phase2_v3_route_calendar_builder$
DECLARE
    target regprocedure;
    definition text;
    old_null text:='feat.build_price_features_v3_shared(p_date_from,p_date_to,NULL)';
    new_null text:='feat.build_price_features_v3_calendar_chunked(p_date_from,p_date_to,NULL)';
    old_scope text:='feat.build_price_features_v3_shared(p_date_from,p_date_to,p_symbol_ids)';
    new_scope text:='feat.build_price_features_v3_calendar_chunked(p_date_from,p_date_to,p_symbol_ids)';
BEGIN
    FOREACH target IN ARRAY ARRAY[
        'feat.build_price_features_v3_internal(date,date)'::regprocedure,
        'feat.build_price_features_v3(date,date)'::regprocedure,
        'feat.build_features(date,date)'::regprocedure,
        'feat.build_features_and_labels(date,date)'::regprocedure,
        'feat.build_features_and_labels_scoped(date,date,text,text,text,bigint[])'::regprocedure
    ] LOOP
        definition:=replace(pg_get_functiondef(target::oid),E'\r\n',E'\n');
        IF strpos(definition,'build_price_features_v3_calendar_chunked(')=0 THEN
            IF strpos(definition,old_null)>0 THEN
                definition:=replace(definition,old_null,new_null);
            ELSIF strpos(definition,old_scope)>0 THEN
                definition:=replace(definition,old_scope,new_scope);
            ELSE
                RAISE EXCEPTION 'V3 production caller % does not contain the expected shared-builder call',target;
            END IF;
            EXECUTE definition;
        END IF;
    END LOOP;
END
$phase2_v3_route_calendar_builder$;

COMMIT;

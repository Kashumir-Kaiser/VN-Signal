-- Preserve the Phase 2 feature meaning while avoiding cancellation from
-- subtracting long cumulative float8 prefixes for market-model variance.
BEGIN;

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3()
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT md5(definition||'|'||base_hash)
        ||md5('VN-Signal:'||definition||'|'||base_hash)
    FROM (VALUES (
        'phase2-v3|effective_sessions|episode_neutral_prices|12_1_231_return_sessions'
        ||'|market_model_beta_60_250_one_session_lag_stable_pair_moments'
        ||'|independent_nonnull_rank_populations_v1'
        ||'|ordered_window_ema_5_10_20_50_100_200_1000_session_warmup'
        ||'|macd_12_26_9|adx_14_simple_average|stochastic_14_3_same_adjustment_episode'
        ||'|downside_vol_5_60|population_skew_kurtosis_60|amihud_turnover_proxy_20'
        ||'|gap_stats_20|rank_gaussian_tie_averaged_midrank|lagged_market_context'
        ||'|vnindex_sma50_200_drawdown252_vol60|vnindex_source_vci'
        ||'|vnindex_inherited_returns_vol20_vci|quarter_end_calendar_days'
        ||'|strict_full_window_cross_sectional_vol_rank|source_dependent_features_null_without_evidence'
    )) d(definition)
    CROSS JOIN LATERAL (SELECT feat.phase2_feature_set_hash() AS base_hash) h
$$;

-- Amend the shared builder in place. Keeping its body visible is necessary:
-- later idempotent migrations inspect and extend the same ranked SQL stages.
DO $phase2_patch_v3_market_moments$
DECLARE
    definition text;
    anchor text;
BEGIN
    definition:=pg_get_functiondef(
        'feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure
    );
    IF position('stable_pair_moments_v1' IN definition)=0 THEN
        anchor:=$old_prefix$
               sum(abs(x.stock_return)/nullif(x.turnover_proxy_vnd,0)) OVER w AS amihud_sum_prefix
        FROM symbol_market x
        WINDOW w AS (PARTITION BY x.symbol_id ORDER BY x.session_no
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
$old_prefix$;
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 market-prefix window anchor';
        END IF;
        definition:=replace(definition,anchor,$new_prefix$
               sum(abs(x.stock_return)/nullif(x.turnover_proxy_vnd,0)) OVER w AS amihud_sum_prefix,
               -- stable_pair_moments_v1: local Welford moments avoid subtracting
               -- long cumulative prefixes when the residual variance is small.
               count(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                          THEN 1 END) OVER w60 AS pair_count60_rolling,
               var_samp(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                             THEN x.stock_return END) OVER w60 AS stock_var60_rolling,
               var_samp(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                             THEN x.index_return_lagged END) OVER w60 AS market_var60_rolling,
               covar_samp(
                   CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.stock_return END,
                   CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.index_return_lagged END
               ) OVER w60 AS covar60_rolling,
               count(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                          THEN 1 END) OVER w250 AS pair_count250_rolling,
               var_samp(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                             THEN x.stock_return END) OVER w250 AS stock_var250_rolling,
               var_samp(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                             THEN x.index_return_lagged END) OVER w250 AS market_var250_rolling,
               covar_samp(
                   CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.stock_return END,
                   CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.index_return_lagged END
               ) OVER w250 AS covar250_rolling
        FROM symbol_market x
        WINDOW base_w AS (PARTITION BY x.symbol_id ORDER BY x.session_no),
              w AS (base_w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
              w60 AS (base_w ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),
              w250 AS (base_w ROWS BETWEEN 249 PRECEDING AND CURRENT ROW)
$new_prefix$);

        anchor:=$old_counts$
               p.pair_count_prefix-coalesce(p.pair_count_lag60,0) AS n60,
               p.pair_count_prefix-coalesce(p.pair_count_lag250,0) AS n250,
$old_counts$;
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 rolling pair-count anchor';
        END IF;
        definition:=replace(definition,anchor,$new_counts$
                p.pair_count60_rolling AS n60,
                p.pair_count250_rolling AS n250,
$new_counts$);

        anchor:=$old_beta$
    ), stock_market_beta AS MATERIALIZED (
        SELECT d.*,
               CASE WHEN d.n60>1 THEN
                    (d.cross_product60-d.stock_sum60*d.market_sum60/d.n60) /
                    nullif(d.market_square60-d.market_sum60*d.market_sum60/d.n60,0) END AS beta60,
               CASE WHEN d.n60>1 THEN greatest(0::double precision,
                    (d.stock_square60-d.stock_sum60*d.stock_sum60/d.n60)/(d.n60-1)) END AS stock_var60,
               CASE WHEN d.n60>1 THEN greatest(0::double precision,
                    (d.market_square60-d.market_sum60*d.market_sum60/d.n60)/(d.n60-1)) END AS market_var60,
               CASE WHEN d.n60>1 THEN
                    (d.cross_product60-d.stock_sum60*d.market_sum60/d.n60)/(d.n60-1) END AS covar60,
               CASE WHEN d.n250>1 THEN
                    (d.cross_product250-d.stock_sum250*d.market_sum250/d.n250) /
                    nullif(d.market_square250-d.market_sum250*d.market_sum250/d.n250,0) END AS beta250,
               CASE WHEN d.n250>1 THEN greatest(0::double precision,
                    (d.stock_square250-d.stock_sum250*d.stock_sum250/d.n250)/(d.n250-1)) END AS stock_var250,
               CASE WHEN d.n250>1 THEN greatest(0::double precision,
                    (d.market_square250-d.market_sum250*d.market_sum250/d.n250)/(d.n250-1)) END AS market_var250,
               CASE WHEN d.n250>1 THEN
                    (d.cross_product250-d.stock_sum250*d.market_sum250/d.n250)/(d.n250-1) END AS covar250
        FROM stock_market_differences d
    ), stock_market_windows AS MATERIALIZED (
$old_beta$;
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 market-regression formula anchor';
        END IF;
        definition:=replace(definition,anchor,$new_beta$
    ), stock_market_beta AS MATERIALIZED (
        SELECT d.*,
               CASE WHEN d.n60>1 THEN d.covar60_rolling/nullif(d.market_var60_rolling,0) END AS beta60,
               CASE WHEN d.n60>1 THEN greatest(0::double precision,d.stock_var60_rolling) END AS stock_var60,
               CASE WHEN d.n60>1 THEN greatest(0::double precision,d.market_var60_rolling) END AS market_var60,
               CASE WHEN d.n60>1 THEN d.covar60_rolling END AS covar60,
               CASE WHEN d.n250>1 THEN d.covar250_rolling/nullif(d.market_var250_rolling,0) END AS beta250,
               CASE WHEN d.n250>1 THEN greatest(0::double precision,d.stock_var250_rolling) END AS stock_var250,
               CASE WHEN d.n250>1 THEN greatest(0::double precision,d.market_var250_rolling) END AS market_var250,
               CASE WHEN d.n250>1 THEN d.covar250_rolling END AS covar250
        FROM stock_market_differences d
    ), stock_market_windows AS MATERIALIZED (
$new_beta$);
        EXECUTE definition;
    END IF;
END;
$phase2_patch_v3_market_moments$;

COMMIT;

\set ON_ERROR_STOP on
\set QUIET 1
\pset format unaligned
\pset fieldsep ','
\pset footer off
\pset tuples_only on
-- Rank/input NULL alignment is an independent row-level diagnostic. It does
-- not change the structural lookback expectation or the >1pp status rule.
WITH aggregate_features AS (
    SELECT feature_version,
           min(feature_set_hash) AS feature_set_hash,
           count(*)::bigint AS row_count,
           count(DISTINCT symbol_id)::bigint AS symbol_count,
           min(trade_date) AS date_from,
           max(trade_date) AS date_to,
           count(*) FILTER(WHERE is_traded IS NULL)::bigint AS n_is_traded,
           count(*) FILTER(WHERE volume IS NULL)::bigint AS n_volume,
           count(*) FILTER(WHERE ret_1 IS NULL)::bigint AS n_ret_1,
           count(*) FILTER(WHERE ret_5 IS NULL)::bigint AS n_ret_5,
           count(*) FILTER(WHERE return_1d IS NULL)::bigint AS n_return_1d,
           count(*) FILTER(WHERE return_5s IS NULL)::bigint AS n_return_5s,
           count(*) FILTER(WHERE return_20s IS NULL)::bigint AS n_return_20s,
           count(*) FILTER(WHERE return_60s IS NULL)::bigint AS n_return_60s,
           count(*) FILTER(WHERE return_2s IS NULL)::bigint AS n_return_2s,
           count(*) FILTER(WHERE return_3s IS NULL)::bigint AS n_return_3s,
           count(*) FILTER(WHERE return_10s IS NULL)::bigint AS n_return_10s,
           count(*) FILTER(WHERE return_120s IS NULL)::bigint AS n_return_120s,
           count(*) FILTER(WHERE return_250s IS NULL)::bigint AS n_return_250s,
           count(*) FILTER(WHERE momentum_20s IS NULL)::bigint AS n_momentum_20s,
           count(*) FILTER(WHERE momentum_60s IS NULL)::bigint AS n_momentum_60s,
           count(*) FILTER(WHERE close_sma5_ratio IS NULL)::bigint AS n_close_sma5_ratio,
           count(*) FILTER(WHERE sma_5_ratio IS NULL)::bigint AS n_sma_5_ratio,
           count(*) FILTER(WHERE close_sma20_ratio IS NULL)::bigint AS n_close_sma20_ratio,
           count(*) FILTER(WHERE close_sma50_ratio IS NULL)::bigint AS n_close_sma50_ratio,
           count(*) FILTER(WHERE close_sma60_ratio IS NULL)::bigint AS n_close_sma60_ratio,
           count(*) FILTER(WHERE close_sma100_ratio IS NULL)::bigint AS n_close_sma100_ratio,
           count(*) FILTER(WHERE close_sma200_ratio IS NULL)::bigint AS n_close_sma200_ratio,
           count(*) FILTER(WHERE distance_52w_high IS NULL)::bigint AS n_distance_52w_high,
           count(*) FILTER(WHERE distance_52w_low IS NULL)::bigint AS n_distance_52w_low,
           count(*) FILTER(WHERE rsi_14 IS NULL)::bigint AS n_rsi_14,
           count(*) FILTER(WHERE bollinger_pct_b_20 IS NULL)::bigint AS n_bollinger_pct_b_20,
           count(*) FILTER(WHERE bollinger_bandwidth_20 IS NULL)::bigint AS n_bollinger_bandwidth_20,
           count(*) FILTER(WHERE downside_vol20 IS NULL)::bigint AS n_downside_vol20,
           count(*) FILTER(WHERE atr_pct_14 IS NULL)::bigint AS n_atr_pct_14,
           count(*) FILTER(WHERE volume_zscore_20 IS NULL)::bigint AS n_volume_zscore_20,
           count(*) FILTER(WHERE obv_slope_20 IS NULL)::bigint AS n_obv_slope_20,
           count(*) FILTER(WHERE realized_vol20 IS NULL)::bigint AS n_realized_vol20,
           count(*) FILTER(WHERE realized_vol60 IS NULL)::bigint AS n_realized_vol60,
           count(*) FILTER(WHERE vol_5 IS NULL)::bigint AS n_vol_5,
           count(*) FILTER(WHERE turnover_proxy_vnd IS NULL)::bigint AS n_turnover_proxy_vnd,
           count(*) FILTER(WHERE log_turnover_proxy_vnd IS NULL)::bigint AS n_log_turnover_proxy_vnd,
           count(*) FILTER(WHERE turnover_sma20_vnd IS NULL)::bigint AS n_turnover_sma20_vnd,
           count(*) FILTER(WHERE volume_sma20 IS NULL)::bigint AS n_volume_sma20,
           count(*) FILTER(WHERE gap_open_1d IS NULL)::bigint AS n_gap_open_1d,
           count(*) FILTER(WHERE intraday_return IS NULL)::bigint AS n_intraday_return,
           count(*) FILTER(WHERE intraday_range_pct IS NULL)::bigint AS n_intraday_range_pct,
           count(*) FILTER(WHERE close_location IS NULL)::bigint AS n_close_location,
           count(*) FILTER(WHERE large_move_approx IS NULL)::bigint AS n_large_move_approx,
           count(*) FILTER(WHERE session_ordinal IS NULL)::bigint AS n_session_ordinal,
           count(*) FILTER(WHERE day_of_week IS NULL)::bigint AS n_day_of_week,
           count(*) FILTER(WHERE month_of_year IS NULL)::bigint AS n_month_of_year,
           count(*) FILTER(WHERE vnindex_return_20s IS NULL)::bigint AS n_vnindex_return_20s,
           count(*) FILTER(WHERE vnindex_return_60s IS NULL)::bigint AS n_vnindex_return_60s,
           count(*) FILTER(WHERE vnindex_realized_vol20 IS NULL)::bigint AS n_vnindex_realized_vol20,
           count(*) FILTER(WHERE market_breadth_above_sma50 IS NULL)::bigint AS n_market_breadth_above_sma50,
           count(*) FILTER(WHERE rank_momentum_20s IS NULL)::bigint AS n_rank_momentum_20s,
           count(*) FILTER(WHERE rank_turnover_proxy IS NULL)::bigint AS n_rank_turnover_proxy,
           count(*) FILTER(WHERE rank_realized_vol20 IS NULL)::bigint AS n_rank_realized_vol20,
            count(*) FILTER(WHERE (rank_momentum_20s IS NULL)<>(momentum_20s IS NULL))::bigint
                AS n_rank_momentum_20s_input_null_mismatch,
            count(*) FILTER(WHERE (rank_turnover_proxy IS NULL)<>(turnover_proxy_vnd IS NULL))::bigint
                AS n_rank_turnover_proxy_input_null_mismatch,
            count(*) FILTER(WHERE (rank_realized_vol20 IS NULL)<>(realized_vol20 IS NULL))::bigint
                AS n_rank_realized_vol20_input_null_mismatch,
           count(*) FILTER(WHERE momentum_12_1s IS NULL)::bigint AS n_momentum_12_1s,
           count(*) FILTER(WHERE residual_momentum_12_1s IS NULL)::bigint AS n_residual_momentum_12_1s,
           count(*) FILTER(WHERE ema_5_ratio IS NULL)::bigint AS n_ema_5_ratio,
           count(*) FILTER(WHERE ema_10_ratio IS NULL)::bigint AS n_ema_10_ratio,
           count(*) FILTER(WHERE ema_20_ratio IS NULL)::bigint AS n_ema_20_ratio,
           count(*) FILTER(WHERE ema_50_ratio IS NULL)::bigint AS n_ema_50_ratio,
           count(*) FILTER(WHERE ema_100_ratio IS NULL)::bigint AS n_ema_100_ratio,
           count(*) FILTER(WHERE ema_200_ratio IS NULL)::bigint AS n_ema_200_ratio,
           count(*) FILTER(WHERE macd_histogram_pct IS NULL)::bigint AS n_macd_histogram_pct,
           count(*) FILTER(WHERE adx_14_sma IS NULL)::bigint AS n_adx_14_sma,
           count(*) FILTER(WHERE stochastic_k_14 IS NULL)::bigint AS n_stochastic_k_14,
           count(*) FILTER(WHERE stochastic_d_3 IS NULL)::bigint AS n_stochastic_d_3,
           count(*) FILTER(WHERE downside_vol5 IS NULL)::bigint AS n_downside_vol5,
           count(*) FILTER(WHERE downside_vol60 IS NULL)::bigint AS n_downside_vol60,
           count(*) FILTER(WHERE return_skew_pop60 IS NULL)::bigint AS n_return_skew_pop60,
           count(*) FILTER(WHERE return_excess_kurtosis_pop60 IS NULL)::bigint AS n_return_excess_kurtosis_pop60,
           count(*) FILTER(WHERE beta_vnindex_60 IS NULL)::bigint AS n_beta_vnindex_60,
           count(*) FILTER(WHERE beta_vnindex_250 IS NULL)::bigint AS n_beta_vnindex_250,
           count(*) FILTER(WHERE idio_vol_vnindex_60 IS NULL)::bigint AS n_idio_vol_vnindex_60,
           count(*) FILTER(WHERE idio_vol_vnindex_250 IS NULL)::bigint AS n_idio_vol_vnindex_250,
           count(*) FILTER(WHERE correlation_vn30_60 IS NULL)::bigint AS n_correlation_vn30_60,
           count(*) FILTER(WHERE amihud_proxy_20 IS NULL)::bigint AS n_amihud_proxy_20,
           count(*) FILTER(WHERE gap_mean20 IS NULL)::bigint AS n_gap_mean20,
           count(*) FILTER(WHERE gap_std20 IS NULL)::bigint AS n_gap_std20,
           count(*) FILTER(WHERE rank_gaussian_return20 IS NULL)::bigint AS n_rank_gaussian_return20,
           count(*) FILTER(WHERE rank_gaussian_turnover_proxy IS NULL)::bigint AS n_rank_gaussian_turnover_proxy,
           count(*) FILTER(WHERE rank_gaussian_realized_vol20 IS NULL)::bigint AS n_rank_gaussian_realized_vol20,
            count(*) FILTER(WHERE (rank_gaussian_return20 IS NULL)<>(return_20s IS NULL))::bigint
                AS n_rank_gaussian_return20_input_null_mismatch,
            count(*) FILTER(WHERE (rank_gaussian_turnover_proxy IS NULL)<>(turnover_proxy_vnd IS NULL))::bigint
                AS n_rank_gaussian_turnover_proxy_input_null_mismatch,
            count(*) FILTER(WHERE (rank_gaussian_realized_vol20 IS NULL)<>(realized_vol20 IS NULL))::bigint
                AS n_rank_gaussian_realized_vol20_input_null_mismatch,
           count(*) FILTER(WHERE rank_gaussian_momentum20_industry IS NULL)::bigint AS n_rank_gaussian_momentum20_industry,
           count(*) FILTER(WHERE market_advance_minus_decline IS NULL)::bigint AS n_market_advance_minus_decline,
           count(*) FILTER(WHERE market_new_high_minus_low IS NULL)::bigint AS n_market_new_high_minus_low,
           count(*) FILTER(WHERE market_turnover_z20 IS NULL)::bigint AS n_market_turnover_z20,
           count(*) FILTER(WHERE market_return_dispersion IS NULL)::bigint AS n_market_return_dispersion,
           count(*) FILTER(WHERE vnindex_sma50_ratio IS NULL)::bigint AS n_vnindex_sma50_ratio,
           count(*) FILTER(WHERE vnindex_sma200_ratio IS NULL)::bigint AS n_vnindex_sma200_ratio,
           count(*) FILTER(WHERE vnindex_drawdown252 IS NULL)::bigint AS n_vnindex_drawdown252,
           count(*) FILTER(WHERE vnindex_realized_vol60 IS NULL)::bigint AS n_vnindex_realized_vol60,
           count(*) FILTER(WHERE quarter_end_proximity_days IS NULL)::bigint AS n_quarter_end_proximity_days,
           count(*) FILTER(WHERE turnover_listed_shares IS NULL)::bigint AS n_turnover_listed_shares,
           count(*) FILTER(WHERE limit_up_hit IS NULL)::bigint AS n_limit_up_hit,
           count(*) FILTER(WHERE limit_down_hit IS NULL)::bigint AS n_limit_down_hit,
           count(*) FILTER(WHERE limit_up_streak IS NULL)::bigint AS n_limit_up_streak,
           count(*) FILTER(WHERE limit_down_streak IS NULL)::bigint AS n_limit_down_streak,
           count(*) FILTER(WHERE distance_to_price_limit IS NULL)::bigint AS n_distance_to_price_limit,
           count(*) FILTER(WHERE sessions_to_tet IS NULL)::bigint AS n_sessions_to_tet,
           count(*) FILTER(WHERE sessions_from_tet IS NULL)::bigint AS n_sessions_from_tet,
           count(*) FILTER(WHERE intraday_realized_variance IS NULL)::bigint AS n_intraday_realized_variance,
           count(*) FILTER(WHERE intraday_vwap_gap IS NULL)::bigint AS n_intraday_vwap_gap,
           count(*) FILTER(WHERE intraday_closing_auction_share IS NULL)::bigint AS n_intraday_closing_auction_share
    FROM feat.features_daily
    WHERE feature_version='phase2-v3'
    GROUP BY feature_version
), symbol_population AS (
    SELECT symbol_id,count(*)::bigint AS session_rows
    FROM feat.features_daily
    WHERE feature_version='phase2-v3'
    GROUP BY symbol_id
), expected_by_lookback AS MATERIALIZED (
    -- The report uses structural lookbacks from 0 through 252 sessions. Sum
    -- each lookback once, instead of rescanning the symbol population for
    -- every feature row in the report.
    SELECT l.structural_l,sum(least(l.structural_l,p.session_rows))::bigint AS expected_null_count
    FROM generate_series(0,252) AS l(structural_l)
    CROSS JOIN symbol_population p
    GROUP BY l.structural_l
)
SELECT feature_version,feature_set_hash,row_count,symbol_count,date_from,date_to,feature,
       structural_l,source_status,null_count,null_rate,expected_null_count,
       expected_null_rate,deviation_pp,status,rank_input_feature,rank_input_null_mismatch_count
FROM (
    SELECT 0 AS row_order,
           'feature_version'::text AS feature_version,'feature_set_hash'::text AS feature_set_hash,
           'row_count'::text AS row_count,'symbol_count'::text AS symbol_count,
           'date_from'::text AS date_from,'date_to'::text AS date_to,
           'feature'::text AS feature,'structural_l'::text AS structural_l,
           'source_status'::text AS source_status,'null_count'::text AS null_count,
           'null_rate'::text AS null_rate,'expected_null_count'::text AS expected_null_count,
           'expected_null_rate'::text AS expected_null_rate,'deviation_pp'::text AS deviation_pp,
            'status'::text AS status,'rank_input_feature'::text AS rank_input_feature,
            'rank_input_null_mismatch_count'::text AS rank_input_null_mismatch_count
    UNION ALL
    SELECT 1,a.feature_version,a.feature_set_hash,a.row_count::text,a.symbol_count::text,
           a.date_from::text,a.date_to::text,v.feature,lookback.structural_l::text,
           lookback.source_status,v.null_count::text,
           round(v.null_count::numeric/nullif(a.row_count,0),6)::text,
           expected.expected_null_count::text,
           round(expected.expected_null_count::numeric/nullif(a.row_count,0),6)::text,
           round((v.null_count-expected.expected_null_count)::numeric*100/nullif(a.row_count,0),3)::text,
           CASE
             WHEN lookback.source_status='SOURCE_UNVERIFIED' THEN 'SOURCE_UNVERIFIED'
             WHEN abs(v.null_count::numeric/nullif(a.row_count,0)
                      -expected.expected_null_count::numeric/nullif(a.row_count,0))>0.01 THEN 'FLAG_GT_1PP'
             ELSE 'WITHIN_1PP'
            END::text,
            rank_input.rank_input_feature,
            rank_input.rank_input_null_mismatch_count::text
    FROM aggregate_features a
    CROSS JOIN LATERAL (VALUES
    ('is_traded',a.n_is_traded),
    ('volume',a.n_volume),
    ('ret_1',a.n_ret_1),
    ('ret_5',a.n_ret_5),
    ('return_1d',a.n_return_1d),
    ('return_5s',a.n_return_5s),
    ('return_20s',a.n_return_20s),
    ('return_60s',a.n_return_60s),
    ('return_2s',a.n_return_2s),
    ('return_3s',a.n_return_3s),
    ('return_10s',a.n_return_10s),
    ('return_120s',a.n_return_120s),
    ('return_250s',a.n_return_250s),
    ('momentum_20s',a.n_momentum_20s),
    ('momentum_60s',a.n_momentum_60s),
    ('close_sma5_ratio',a.n_close_sma5_ratio),
    ('sma_5_ratio',a.n_sma_5_ratio),
    ('close_sma20_ratio',a.n_close_sma20_ratio),
    ('close_sma50_ratio',a.n_close_sma50_ratio),
    ('close_sma60_ratio',a.n_close_sma60_ratio),
    ('close_sma100_ratio',a.n_close_sma100_ratio),
    ('close_sma200_ratio',a.n_close_sma200_ratio),
    ('distance_52w_high',a.n_distance_52w_high),
    ('distance_52w_low',a.n_distance_52w_low),
    ('rsi_14',a.n_rsi_14),
    ('bollinger_pct_b_20',a.n_bollinger_pct_b_20),
    ('bollinger_bandwidth_20',a.n_bollinger_bandwidth_20),
    ('downside_vol20',a.n_downside_vol20),
    ('atr_pct_14',a.n_atr_pct_14),
    ('volume_zscore_20',a.n_volume_zscore_20),
    ('obv_slope_20',a.n_obv_slope_20),
    ('realized_vol20',a.n_realized_vol20),
    ('realized_vol60',a.n_realized_vol60),
    ('vol_5',a.n_vol_5),
    ('turnover_proxy_vnd',a.n_turnover_proxy_vnd),
    ('log_turnover_proxy_vnd',a.n_log_turnover_proxy_vnd),
    ('turnover_sma20_vnd',a.n_turnover_sma20_vnd),
    ('volume_sma20',a.n_volume_sma20),
    ('gap_open_1d',a.n_gap_open_1d),
    ('intraday_return',a.n_intraday_return),
    ('intraday_range_pct',a.n_intraday_range_pct),
    ('close_location',a.n_close_location),
    ('large_move_approx',a.n_large_move_approx),
    ('session_ordinal',a.n_session_ordinal),
    ('day_of_week',a.n_day_of_week),
    ('month_of_year',a.n_month_of_year),
    ('vnindex_return_20s',a.n_vnindex_return_20s),
    ('vnindex_return_60s',a.n_vnindex_return_60s),
    ('vnindex_realized_vol20',a.n_vnindex_realized_vol20),
    ('market_breadth_above_sma50',a.n_market_breadth_above_sma50),
    ('rank_momentum_20s',a.n_rank_momentum_20s),
    ('rank_turnover_proxy',a.n_rank_turnover_proxy),
    ('rank_realized_vol20',a.n_rank_realized_vol20),
    ('momentum_12_1s',a.n_momentum_12_1s),
    ('residual_momentum_12_1s',a.n_residual_momentum_12_1s),
    ('ema_5_ratio',a.n_ema_5_ratio),
    ('ema_10_ratio',a.n_ema_10_ratio),
    ('ema_20_ratio',a.n_ema_20_ratio),
    ('ema_50_ratio',a.n_ema_50_ratio),
    ('ema_100_ratio',a.n_ema_100_ratio),
    ('ema_200_ratio',a.n_ema_200_ratio),
    ('macd_histogram_pct',a.n_macd_histogram_pct),
    ('adx_14_sma',a.n_adx_14_sma),
    ('stochastic_k_14',a.n_stochastic_k_14),
    ('stochastic_d_3',a.n_stochastic_d_3),
    ('downside_vol5',a.n_downside_vol5),
    ('downside_vol60',a.n_downside_vol60),
    ('return_skew_pop60',a.n_return_skew_pop60),
    ('return_excess_kurtosis_pop60',a.n_return_excess_kurtosis_pop60),
    ('beta_vnindex_60',a.n_beta_vnindex_60),
    ('beta_vnindex_250',a.n_beta_vnindex_250),
    ('idio_vol_vnindex_60',a.n_idio_vol_vnindex_60),
    ('idio_vol_vnindex_250',a.n_idio_vol_vnindex_250),
    ('correlation_vn30_60',a.n_correlation_vn30_60),
    ('amihud_proxy_20',a.n_amihud_proxy_20),
    ('gap_mean20',a.n_gap_mean20),
    ('gap_std20',a.n_gap_std20),
    ('rank_gaussian_return20',a.n_rank_gaussian_return20),
    ('rank_gaussian_turnover_proxy',a.n_rank_gaussian_turnover_proxy),
    ('rank_gaussian_realized_vol20',a.n_rank_gaussian_realized_vol20),
    ('rank_gaussian_momentum20_industry',a.n_rank_gaussian_momentum20_industry),
    ('market_advance_minus_decline',a.n_market_advance_minus_decline),
    ('market_new_high_minus_low',a.n_market_new_high_minus_low),
    ('market_turnover_z20',a.n_market_turnover_z20),
    ('market_return_dispersion',a.n_market_return_dispersion),
    ('vnindex_sma50_ratio',a.n_vnindex_sma50_ratio),
    ('vnindex_sma200_ratio',a.n_vnindex_sma200_ratio),
    ('vnindex_drawdown252',a.n_vnindex_drawdown252),
    ('vnindex_realized_vol60',a.n_vnindex_realized_vol60),
    ('quarter_end_proximity_days',a.n_quarter_end_proximity_days),
    ('turnover_listed_shares',a.n_turnover_listed_shares),
    ('limit_up_hit',a.n_limit_up_hit),
    ('limit_down_hit',a.n_limit_down_hit),
    ('limit_up_streak',a.n_limit_up_streak),
    ('limit_down_streak',a.n_limit_down_streak),
    ('distance_to_price_limit',a.n_distance_to_price_limit),
    ('sessions_to_tet',a.n_sessions_to_tet),
    ('sessions_from_tet',a.n_sessions_from_tet),
    ('intraday_realized_variance',a.n_intraday_realized_variance),
    ('intraday_vwap_gap',a.n_intraday_vwap_gap),
    ('intraday_closing_auction_share',a.n_intraday_closing_auction_share)
) AS v(feature,null_count)
    CROSS JOIN LATERAL (
        SELECT
          CASE
            WHEN v.feature IN (
                'correlation_vn30_60','turnover_listed_shares',
                'limit_up_hit','limit_down_hit','limit_up_streak','limit_down_streak',
                'distance_to_price_limit','sessions_to_tet','sessions_from_tet',
                'intraday_realized_variance','intraday_vwap_gap',
                'intraday_closing_auction_share','rank_gaussian_momentum20_industry'
            ) THEN NULL::integer
            WHEN v.feature IN ('is_traded','volume','turnover_proxy_vnd',
                               'log_turnover_proxy_vnd','intraday_return',
                               'intraday_range_pct','close_location','session_ordinal',
                               'day_of_week','month_of_year','quarter_end_proximity_days',
                               'rank_turnover_proxy','rank_gaussian_turnover_proxy') THEN 0
            WHEN v.feature='return_1d' THEN 1
            WHEN v.feature ~ '^ret_[0-9]+$' THEN substring(v.feature FROM '^ret_([0-9]+)$')::integer
            WHEN v.feature ~ '^return_[0-9]+s$' THEN substring(v.feature FROM '^return_([0-9]+)s$')::integer
            WHEN v.feature ~ '^(rank_)?momentum_[0-9]+s$' THEN substring(v.feature FROM 'momentum_([0-9]+)s$')::integer
            WHEN v.feature='sma_5_ratio' THEN 4
            WHEN v.feature ~ '^close_sma[0-9]+_ratio$' THEN substring(v.feature FROM '^close_sma([0-9]+)_ratio$')::integer-1
            WHEN v.feature IN ('distance_52w_high','distance_52w_low',
                               'market_new_high_minus_low','vnindex_drawdown252') THEN 251
            WHEN v.feature IN ('rsi_14','atr_pct_14') THEN 14
            WHEN v.feature IN ('bollinger_pct_b_20','bollinger_bandwidth_20',
                               'volume_zscore_20','turnover_sma20_vnd','volume_sma20') THEN 19
            WHEN v.feature='obv_slope_20' THEN 20
            WHEN v.feature ~ '^realized_vol[0-9]+$' THEN substring(v.feature FROM '^realized_vol([0-9]+)$')::integer
            WHEN v.feature='vol_5' THEN 5
            WHEN v.feature IN ('gap_open_1d','large_move_approx',
                               'market_advance_minus_decline','market_return_dispersion') THEN 1
            WHEN v.feature='market_breadth_above_sma50' THEN 49
            WHEN v.feature IN ('rank_momentum_20s','rank_realized_vol20',
                               'rank_gaussian_return20','rank_gaussian_realized_vol20') THEN 20
            WHEN v.feature IN ('momentum_12_1s','residual_momentum_12_1s') THEN 252
            WHEN v.feature ~ '^ema_[0-9]+_ratio$' THEN substring(v.feature FROM '^ema_([0-9]+)_ratio$')::integer-1
            WHEN v.feature='macd_histogram_pct' THEN 33
            WHEN v.feature='adx_14_sma' THEN 27
            WHEN v.feature='stochastic_k_14' THEN 13
            WHEN v.feature='stochastic_d_3' THEN 15
            WHEN v.feature ~ '^downside_vol[0-9]+$' THEN substring(v.feature FROM '^downside_vol([0-9]+)$')::integer
            WHEN v.feature IN ('return_skew_pop60','return_excess_kurtosis_pop60',
                               'vnindex_return_60s','beta_vnindex_60','idio_vol_vnindex_60',
                               'vnindex_realized_vol60') THEN 60
            WHEN v.feature IN ('vnindex_return_20s','vnindex_realized_vol20',
                               'amihud_proxy_20','gap_mean20','gap_std20',
                               'market_turnover_z20') THEN 20
            WHEN v.feature IN ('beta_vnindex_250','idio_vol_vnindex_250') THEN 250
            WHEN v.feature='vnindex_sma50_ratio' THEN 49
            WHEN v.feature='vnindex_sma200_ratio' THEN 199
            ELSE 0
          END AS structural_l,
          CASE WHEN v.feature IN (
                'correlation_vn30_60','turnover_listed_shares',
                'limit_up_hit','limit_down_hit','limit_up_streak','limit_down_streak',
                'distance_to_price_limit','sessions_to_tet','sessions_from_tet',
                'intraday_realized_variance','intraday_vwap_gap',
                'intraday_closing_auction_share','rank_gaussian_momentum20_industry'
            ) THEN 'SOURCE_UNVERIFIED'
            ELSE 'SOURCE_MEASURED'
          END::text AS source_status
    ) lookback
    CROSS JOIN LATERAL (
        SELECT CASE
                 WHEN lookback.source_status='SOURCE_UNVERIFIED' THEN a.row_count
                 ELSE COALESCE((
                     SELECT e.expected_null_count
                     FROM expected_by_lookback e
                     WHERE e.structural_l=lookback.structural_l
                 ),0::bigint)
               END AS expected_null_count
    ) expected
    CROSS JOIN LATERAL (
        SELECT CASE v.feature
                 WHEN 'rank_momentum_20s' THEN 'momentum_20s'
                 WHEN 'rank_turnover_proxy' THEN 'turnover_proxy_vnd'
                 WHEN 'rank_realized_vol20' THEN 'realized_vol20'
                 WHEN 'rank_gaussian_return20' THEN 'return_20s'
                 WHEN 'rank_gaussian_turnover_proxy' THEN 'turnover_proxy_vnd'
                 WHEN 'rank_gaussian_realized_vol20' THEN 'realized_vol20'
               END::text AS rank_input_feature,
               CASE v.feature
                 WHEN 'rank_momentum_20s' THEN a.n_rank_momentum_20s_input_null_mismatch
                 WHEN 'rank_turnover_proxy' THEN a.n_rank_turnover_proxy_input_null_mismatch
                 WHEN 'rank_realized_vol20' THEN a.n_rank_realized_vol20_input_null_mismatch
                 WHEN 'rank_gaussian_return20' THEN a.n_rank_gaussian_return20_input_null_mismatch
                 WHEN 'rank_gaussian_turnover_proxy' THEN a.n_rank_gaussian_turnover_proxy_input_null_mismatch
                 WHEN 'rank_gaussian_realized_vol20' THEN a.n_rank_gaussian_realized_vol20_input_null_mismatch
               END::bigint AS rank_input_null_mismatch_count
    ) rank_input
) report_rows
ORDER BY row_order,feature;

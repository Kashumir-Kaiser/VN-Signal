-- Phase 2 uses the registered, audited VCI VNINDEX history. Equity OHLCV
-- remains on the point-in-time VNDIRECT basis; index provenance is independent.
BEGIN;

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3()
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT md5(definition||'|'||base_hash)||md5('VN-Signal:'||definition||'|'||base_hash)
    FROM (VALUES ('phase2-v3|effective_sessions|episode_neutral_prices|12_1_231_return_sessions|market_model_beta_60_250_one_session_lag|ordered_window_ema_5_10_20_50_100_200_1000_session_warmup|macd_12_26_9|adx_14_simple_average|stochastic_14_3_same_adjustment_episode|downside_vol_5_60|population_skew_kurtosis_60|amihud_turnover_proxy_20|gap_stats_20|rank_gaussian_tie_averaged_midrank|lagged_market_context|vnindex_sma50_200_drawdown252_vol60|vnindex_source_vci|quarter_end_calendar_days|strict_full_window_cross_sectional_vol_rank|source_dependent_features_null_without_evidence')) d(definition)
    CROSS JOIN LATERAL (SELECT feat.phase2_feature_set_hash() AS base_hash) h
$$;

DO $$
DECLARE
    def text;
BEGIN
    def:=pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);
    IF position('i.index_symbol=''VNINDEX'' AND i.source=''vndirect''' in def)>0 THEN
        def:=replace(def,'i.index_symbol=''VNINDEX'' AND i.source=''vndirect''',
                         'i.index_symbol=''VNINDEX'' AND i.source=''vci''');
        EXECUTE def;
    END IF;
    def:=pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);
    IF position('i.index_symbol=''VNINDEX'' AND i.source=''vci''' in def)=0 THEN
        RAISE EXCEPTION 'V3 builder is not bound to the registered VCI VNINDEX history';
    END IF;

    def:=pg_get_functiondef('feat.build_labels(date,date)'::regprocedure);
    def:=replace(def,'ie.source=''vndirect''','ie.source=''vci''');
    def:=replace(def,'ix.source=''vndirect''','ix.source=''vci''');
    IF position('ie.source=''vci''' in def)=0 OR position('ix.source=''vci''' in def)=0 THEN
        RAISE EXCEPTION 'V3 public label builder is not bound to the registered VCI VNINDEX history';
    END IF;
    EXECUTE def;

    def:=pg_get_functiondef('feat.build_labels_internal(date,date)'::regprocedure);
    def:=replace(def,'ie.source=''vndirect''','ie.source=''vci''');
    def:=replace(def,'ix.source=''vndirect''','ix.source=''vci''');
    IF position('ie.source=''vci''' in def)=0 OR position('ix.source=''vci''' in def)=0 THEN
        RAISE EXCEPTION 'V3 internal label builder is not bound to the registered VCI VNINDEX history';
    END IF;
    EXECUTE def;
END;
$$;

COMMENT ON FUNCTION feat.phase2_feature_set_hash_v3() IS
    'Phase 2 V3 feature contract; VNINDEX context uses the registered VCI index history while equity OHLCV uses point-in-time VNDIRECT bars.';

COMMIT;

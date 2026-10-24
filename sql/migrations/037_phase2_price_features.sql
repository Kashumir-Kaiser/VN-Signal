-- Phase 2 v3: additional source-independent price/index features.
-- Source-dependent fields are present for stable schema discovery but remain
-- NULL until audited PIT inputs exist; this migration seeds no market data.
BEGIN;

ALTER TABLE feat.features_daily
    ADD COLUMN IF NOT EXISTS momentum_12_1s double precision,
    ADD COLUMN IF NOT EXISTS residual_momentum_12_1s double precision,
    ADD COLUMN IF NOT EXISTS ema_5_ratio double precision,
    ADD COLUMN IF NOT EXISTS ema_10_ratio double precision,
    ADD COLUMN IF NOT EXISTS ema_20_ratio double precision,
    ADD COLUMN IF NOT EXISTS ema_50_ratio double precision,
    ADD COLUMN IF NOT EXISTS ema_100_ratio double precision,
    ADD COLUMN IF NOT EXISTS ema_200_ratio double precision,
    ADD COLUMN IF NOT EXISTS macd_histogram_pct double precision,
    ADD COLUMN IF NOT EXISTS adx_14_sma double precision,
    ADD COLUMN IF NOT EXISTS stochastic_k_14 double precision,
    ADD COLUMN IF NOT EXISTS stochastic_d_3 double precision,
    ADD COLUMN IF NOT EXISTS downside_vol5 double precision,
    ADD COLUMN IF NOT EXISTS downside_vol60 double precision,
    ADD COLUMN IF NOT EXISTS return_skew_pop60 double precision,
    ADD COLUMN IF NOT EXISTS return_excess_kurtosis_pop60 double precision,
    ADD COLUMN IF NOT EXISTS beta_vnindex_60 double precision,
    ADD COLUMN IF NOT EXISTS beta_vnindex_250 double precision,
    ADD COLUMN IF NOT EXISTS idio_vol_vnindex_60 double precision,
    ADD COLUMN IF NOT EXISTS idio_vol_vnindex_250 double precision,
    ADD COLUMN IF NOT EXISTS correlation_vn30_60 double precision,
    ADD COLUMN IF NOT EXISTS amihud_proxy_20 double precision,
    ADD COLUMN IF NOT EXISTS gap_mean20 double precision,
    ADD COLUMN IF NOT EXISTS gap_std20 double precision,
    ADD COLUMN IF NOT EXISTS rank_gaussian_return20 double precision,
    ADD COLUMN IF NOT EXISTS rank_gaussian_turnover_proxy double precision,
    ADD COLUMN IF NOT EXISTS rank_gaussian_realized_vol20 double precision,
    ADD COLUMN IF NOT EXISTS rank_gaussian_momentum20_industry double precision,
    ADD COLUMN IF NOT EXISTS market_advance_minus_decline bigint,
    ADD COLUMN IF NOT EXISTS market_new_high_minus_low bigint,
    ADD COLUMN IF NOT EXISTS market_turnover_z20 double precision,
    ADD COLUMN IF NOT EXISTS market_return_dispersion double precision,
    ADD COLUMN IF NOT EXISTS vnindex_sma50_ratio double precision,
    ADD COLUMN IF NOT EXISTS vnindex_sma200_ratio double precision,
    ADD COLUMN IF NOT EXISTS vnindex_drawdown252 double precision,
    ADD COLUMN IF NOT EXISTS vnindex_realized_vol60 double precision,
    ADD COLUMN IF NOT EXISTS quarter_end_proximity_days smallint,
    ADD COLUMN IF NOT EXISTS turnover_listed_shares double precision,
    ADD COLUMN IF NOT EXISTS limit_up_hit boolean,
    ADD COLUMN IF NOT EXISTS limit_down_hit boolean,
    ADD COLUMN IF NOT EXISTS limit_up_streak smallint,
    ADD COLUMN IF NOT EXISTS limit_down_streak smallint,
    ADD COLUMN IF NOT EXISTS distance_to_price_limit double precision,
    ADD COLUMN IF NOT EXISTS sessions_to_tet smallint,
    ADD COLUMN IF NOT EXISTS sessions_from_tet smallint,
    ADD COLUMN IF NOT EXISTS intraday_realized_variance double precision,
    ADD COLUMN IF NOT EXISTS intraday_vwap_gap double precision,
    ADD COLUMN IF NOT EXISTS intraday_closing_auction_share double precision;

COMMENT ON COLUMN feat.features_daily.adx_14_sma IS
    '14-session simple-average directional index; it is explicitly not Wilder-smoothed ADX.';
COMMENT ON COLUMN feat.features_daily.amihud_proxy_20 IS
    'Mean absolute daily return divided by the adjusted-close × volume turnover proxy; not executed turnover.';
COMMENT ON COLUMN feat.features_daily.rank_gaussian_momentum20_industry IS
    'Reserved for an unambiguous point-in-time ICB classification; NULL until dated classification evidence is complete.';
COMMENT ON COLUMN feat.features_daily.correlation_vn30_60 IS
    'NULL until source-attributed VN30 daily index history is available.';
COMMENT ON COLUMN feat.features_daily.turnover_listed_shares IS
    'NULL until point-in-time listed-share observations are archived.';
COMMENT ON COLUMN feat.features_daily.limit_up_hit IS
    'NULL until source-reported daily price limits are archived; never inferred from rounded percentage bands.';
COMMENT ON COLUMN feat.features_daily.sessions_to_tet IS
    'NULL until a point-in-time official Tết event calendar is archived.';
COMMENT ON COLUMN feat.features_daily.intraday_realized_variance IS
    'NULL until audited one-minute bars are archived.';

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3()
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT md5(definition||'|'||base_hash)||md5('VN-Signal:'||definition||'|'||base_hash)
    FROM (VALUES ('phase2-v3|effective_sessions|episode_neutral_prices|12_1_231_return_sessions|market_model_beta_60_250_one_session_lag|ordered_window_ema_5_10_20_50_100_200_1000_session_warmup|macd_12_26_9|adx_14_simple_average|stochastic_14_3_same_adjustment_episode|downside_vol_5_60|population_skew_kurtosis_60|amihud_turnover_proxy_20|gap_stats_20|rank_gaussian_tie_averaged_midrank|lagged_market_context|vnindex_sma50_200_drawdown252_vol60|vnindex_source_vci|quarter_end_calendar_days|strict_full_window_cross_sectional_vol_rank|source_dependent_features_null_without_evidence')) d(definition)
    CROSS JOIN LATERAL (SELECT feat.phase2_feature_set_hash() AS base_hash) h
$$;

CREATE OR REPLACE FUNCTION feat.phase2_ema_sfunc(
    p_state double precision,p_value double precision,p_alpha double precision
)
RETURNS double precision LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN p_value IS NULL THEN p_state
                WHEN p_state IS NULL THEN p_value
                ELSE p_alpha*p_value+(1-p_alpha)*p_state END
$$;

DO $$
BEGIN
    IF to_regprocedure('feat.ema(double precision,double precision)') IS NULL THEN
        CREATE AGGREGATE feat.ema(double precision,double precision) (
            SFUNC=feat.phase2_ema_sfunc,
            STYPE=double precision
        );
    END IF;
END $$;

COMMENT ON FUNCTION feat.phase2_ema_sfunc(double precision,double precision,double precision) IS
    'Ordered, NULL-carrying EMA transition used by Phase 2; the aggregate preserves the existing first-value seed and update order.';

CREATE OR REPLACE FUNCTION feat.normal_quantile(p double precision)
RETURNS double precision LANGUAGE plpgsql IMMUTABLE STRICT PARALLEL SAFE AS $$
DECLARE
    q double precision;
    r double precision;
    x double precision;
BEGIN
    IF p <= 0 OR p >= 1 THEN RETURN NULL; END IF;
    IF p < 0.02425 THEN
        q := sqrt(-2*ln(p));
        x := ((((((-0.00778489400243029*q-0.322396458041136)*q-2.40075827716184)*q-2.54973253934373)*q+4.37466414146497)*q+2.93816398269878)
             / ((((0.00778469570904146*q+0.32246712907004)*q+2.445134137143)*q+3.75440866190742)*q+1));
        RETURN x;
    ELSIF p > 0.97575 THEN
        q := sqrt(-2*ln(1-p));
        x := ((((((-0.00778489400243029*q-0.322396458041136)*q-2.40075827716184)*q-2.54973253934373)*q+4.37466414146497)*q+2.93816398269878)
             / ((((0.00778469570904146*q+0.32246712907004)*q+2.445134137143)*q+3.75440866190742)*q+1));
        RETURN -x;
    END IF;
    q := p-0.5;
    r := q*q;
    x := ((((((-39.6968302866538*r+220.946098424521)*r-275.928510446969)*r+138.357751867269)*r-30.6647980661472)*r+2.50662827745924));
    RETURN x*q / ((((((-54.4760987982241*r+161.585836858041)*r-155.698979859887)*r+66.8013118877197)*r-13.2806815528857)*r+1));
END;
$$;

DROP FUNCTION IF EXISTS feat.prepare_phase2_adjustment_rows();
CREATE OR REPLACE FUNCTION feat.prepare_phase2_adjustment_rows(p_refresh boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    cache_relation oid;
    v_started_at timestamptz:=clock_timestamp();
BEGIN
    IF p_refresh IS NULL THEN
        RAISE EXCEPTION 'p_refresh must be true or false';
    END IF;
    cache_relation:=to_regclass('pg_temp.phase2_adjustment_rows');
    IF cache_relation IS NOT NULL THEN
        IF obj_description(cache_relation,'pg_class')='VN-Signal Phase 2 transaction-local point-in-time price input cache' THEN
            IF NOT p_refresh THEN
                RETURN;
            END IF;
            DROP TABLE pg_temp.phase2_adjustment_rows;
        ELSE
            RAISE EXCEPTION 'temporary relation phase2_adjustment_rows is reserved by the Phase 2 builder';
        END IF;
    END IF;

    -- The source view intentionally computes full-history reference and
    -- episode state. Materialize its exact result once for this transaction;
    -- v2, v3 and labels then use the same immutable rows and indexed slices.
    CREATE TEMP TABLE phase2_adjustment_rows ON COMMIT DROP AS
    SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
           r.reference_adjustment_ratio,r.episode_start_date,
           r.model_o,r.model_h,r.model_l,r.model_c,
           r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
    FROM core.vndirect_reference_adjustment_details r
    WHERE r.source='vndirect'
      AND NOT EXISTS (
          SELECT 1 FROM ops.ml_symbol_scope excluded
          WHERE excluded.symbol_id=r.symbol_id
            AND excluded.scope_status='EXCLUDED'
      );
    COMMENT ON TABLE pg_temp.phase2_adjustment_rows IS
        'VN-Signal Phase 2 transaction-local point-in-time price input cache';
    CREATE INDEX phase2_adjustment_rows_date_symbol_idx
        ON pg_temp.phase2_adjustment_rows(trade_date,symbol_id);
    CREATE INDEX phase2_adjustment_rows_symbol_date_idx
        ON pg_temp.phase2_adjustment_rows(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_adjustment_rows;
    RAISE NOTICE 'Phase 2 adjustment cache rows %, elapsed %',
        (SELECT count(*) FROM pg_temp.phase2_adjustment_rows),clock_timestamp()-v_started_at;
END;
$$;

-- Preserve the tested v2 builder and labels for reproducibility. Public builders
-- now also materialize v3 rows alongside v2 rows.
DO $$
BEGIN
    IF to_regprocedure('feat.build_features_v2(date,date)') IS NULL THEN
        ALTER FUNCTION feat.build_features(date,date) RENAME TO build_features_v2;
    END IF;
    IF to_regprocedure('feat.build_labels_v2(date,date)') IS NULL THEN
        ALTER FUNCTION feat.build_labels(date,date) RENAME TO build_labels_v2;
    END IF;
    IF to_regprocedure('feat.build_price_features_v3_internal(date,date)') IS NULL
       AND to_regprocedure('feat.build_price_features_v3(date,date)') IS NOT NULL THEN
        ALTER FUNCTION feat.build_price_features_v3(date,date) RENAME TO build_price_features_v3_internal;
    END IF;
END $$;

CREATE OR REPLACE FUNCTION feat.build_price_features_v3_internal(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $build_price_features_v3$
DECLARE
    affected bigint:=0;
    v_batch record;
    v_batch_affected bigint;
    v_base_rows bigint;
    v_computed_rows bigint;
    v_output_rows bigint;
    v_stage_started timestamptz:=clock_timestamp();
    v_batch_started timestamptz;
    v_batch_size integer:=COALESCE(NULLIF(current_setting('vnpipe.phase2_symbol_batch_size',true),''),'50')::integer;
    v_probe_symbol_limit integer:=NULLIF(current_setting('vnpipe.phase2_probe_symbol_limit',true),'')::integer;
    v_hash constant text:=feat.phase2_feature_set_hash_v3();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF v_batch_size<1 OR v_batch_size>250 THEN
        RAISE EXCEPTION 'vnpipe.phase2_symbol_batch_size must be between 1 and 250';
    END IF;
    IF v_probe_symbol_limit IS NOT NULL THEN
        IF current_setting('application_name') NOT LIKE 'phase2_probe%' THEN
            RAISE EXCEPTION 'vnpipe.phase2_probe_symbol_limit is only allowed for an explicitly named rollback probe';
        END IF;
        IF v_probe_symbol_limit<1 OR v_probe_symbol_limit>250 THEN
            RAISE EXCEPTION 'vnpipe.phase2_probe_symbol_limit must be between 1 and 250';
        END IF;
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(false);
    DELETE FROM feat.features_daily
     WHERE feature_version='phase2-v3' AND trade_date BETWEEN p_date_from AND p_date_to;

    -- Keep one effective-session spine and use deterministic symbol batches to
    -- bound the downstream window working set. EMA and MACD state use ordered
    -- transition aggregates, so each row is processed once without recursion.
    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_sessions ON COMMIT DROP AS
    SELECT trade_date,0::bigint AS session_no
    FROM core.effective_trading_sessions WHERE false;
    TRUNCATE pg_temp.phase2_v3_sessions;
    INSERT INTO pg_temp.phase2_v3_sessions(trade_date,session_no)
    WITH prior_sessions AS MATERIALIZED (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date DESC) AS prior_no
        FROM core.effective_trading_sessions
        WHERE trade_date<p_date_from AND is_session
    ), requested_sessions AS MATERIALIZED (
        SELECT trade_date FROM core.effective_trading_sessions
        WHERE trade_date BETWEEN p_date_from AND p_date_to AND is_session
    ), bounded AS MATERIALIZED (
        SELECT trade_date FROM requested_sessions
        UNION
        SELECT trade_date FROM prior_sessions WHERE prior_no<=1000
    )
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint
    FROM bounded;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_sessions_no_idx
        ON pg_temp.phase2_v3_sessions(session_no);
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_sessions_date_idx
        ON pg_temp.phase2_v3_sessions(trade_date);
    ANALYZE pg_temp.phase2_v3_sessions;
    RAISE NOTICE 'Phase 2 sessions %, elapsed %',
        (SELECT count(*) FROM pg_temp.phase2_v3_sessions),clock_timestamp()-v_stage_started;
    v_stage_started:=clock_timestamp();

    -- Shared date-only market context and cross-sectional ranks are computed
    -- once. The symbol pipelines below can then be batched without changing
    -- rank populations or the one-session market-context lag.
    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_index_raw ON COMMIT DROP AS
    SELECT trade_date,session_no,NULL::double precision AS index_close,
           NULL::double precision AS prior_index_close,NULL::double precision AS index_return
    FROM pg_temp.phase2_v3_sessions WHERE false;
    TRUNCATE pg_temp.phase2_v3_index_raw;
    INSERT INTO pg_temp.phase2_v3_index_raw
    SELECT s.trade_date,s.session_no,i.c AS index_close,
           lag(i.c) OVER(ORDER BY s.session_no) AS prior_index_close,
           CASE WHEN i.c>0 AND lag(i.c) OVER(ORDER BY s.session_no)>0
                THEN i.c/lag(i.c) OVER(ORDER BY s.session_no)-1 END AS index_return
    FROM pg_temp.phase2_v3_sessions s
    LEFT JOIN core.index_bars i ON i.trade_date=s.trade_date
      AND i.index_symbol='VNINDEX' AND i.source='vci';
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_index_raw_session_idx
        ON pg_temp.phase2_v3_index_raw(session_no);
    ANALYZE pg_temp.phase2_v3_index_raw;

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_market_lagged ON COMMIT DROP AS
    SELECT 0::bigint AS session_no,NULL::bigint AS advance_minus_decline,
           NULL::bigint AS new_high_minus_low,NULL::double precision AS turnover_z20,
           NULL::double precision AS return_dispersion,NULL::double precision AS index_sma50_ratio,
           NULL::double precision AS index_sma200_ratio,NULL::double precision AS index_drawdown252,
           NULL::double precision AS vol60
    WHERE false;
    TRUNCATE pg_temp.phase2_v3_market_lagged;
    INSERT INTO pg_temp.phase2_v3_market_lagged
    WITH sessions AS MATERIALIZED (
        SELECT trade_date,session_no FROM pg_temp.phase2_v3_sessions
    ), index_context0 AS MATERIALIZED (
        SELECT i.*,
               avg(i.index_close) FILTER(WHERE i.index_close>0) OVER w50 AS index_sma50,
               avg(i.index_close) FILTER(WHERE i.index_close>0) OVER w200 AS index_sma200,
               max(i.index_close) FILTER(WHERE i.index_close>0) OVER w252 AS high252,
               stddev_samp(i.index_return) OVER w60 AS vol60,
               count(i.index_return) OVER w60 AS return_count60,
               count(i.index_close) FILTER(WHERE i.index_close>0) OVER w50 AS close_count50,
               count(i.index_close) FILTER(WHERE i.index_close>0) OVER w200 AS close_count200,
               count(i.index_close) FILTER(WHERE i.index_close>0) OVER w252 AS close_count252
        FROM pg_temp.phase2_v3_index_raw i
        WINDOW w50 AS (ORDER BY i.session_no ROWS BETWEEN 49 PRECEDING AND CURRENT ROW),
               w60 AS (ORDER BY i.session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),
               w200 AS (ORDER BY i.session_no ROWS BETWEEN 199 PRECEDING AND CURRENT ROW),
               w252 AS (ORDER BY i.session_no ROWS BETWEEN 251 PRECEDING AND CURRENT ROW)
    ), market_grouped AS MATERIALIZED (
        SELECT f.trade_date,s.session_no,
               count(*) FILTER(WHERE f.ret_1>0)::bigint AS advances,
               count(*) FILTER(WHERE f.ret_1<0)::bigint AS declines,
               count(*) FILTER(WHERE f.distance_52w_high IS NOT NULL AND f.distance_52w_high>=-1e-12)::bigint AS new_highs,
               count(*) FILTER(WHERE f.distance_52w_low IS NOT NULL AND f.distance_52w_low<=1e-12)::bigint AS new_lows,
               sum(f.turnover_proxy_vnd ORDER BY f.symbol_id)
                   FILTER(WHERE f.turnover_proxy_vnd IS NOT NULL) AS turnover_total,
               stddev_samp(f.ret_1 ORDER BY f.symbol_id)
                   FILTER(WHERE f.ret_1 IS NOT NULL) AS return_dispersion,
               count(f.ret_1) AS return_count
        FROM feat.features_daily f
        JOIN sessions s USING(trade_date)
        WHERE f.feature_version='phase2-v2'
        GROUP BY f.trade_date,s.session_no
    ), market_daily AS MATERIALIZED (
        SELECT s.trade_date,s.session_no,g.advances,g.declines,g.new_highs,g.new_lows,
               g.turnover_total,g.return_dispersion,g.return_count
        FROM sessions s LEFT JOIN market_grouped g USING(trade_date,session_no)
    ), market_daily_stats AS MATERIALIZED (
        SELECT m.*,
               avg(m.turnover_total) OVER(ORDER BY m.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS turnover_mean20,
               stddev_samp(m.turnover_total) OVER(ORDER BY m.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS turnover_sd20,
               count(m.turnover_total) OVER(ORDER BY m.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS turnover_count20
        FROM market_daily m
    )
    SELECT s.session_no,
           m.advances-m.declines AS advance_minus_decline,
           m.new_highs-m.new_lows AS new_high_minus_low,
           CASE WHEN m.turnover_count20=20
                THEN (m.turnover_total-m.turnover_mean20)/nullif(m.turnover_sd20,0) END AS turnover_z20,
           m.return_dispersion,
           CASE WHEN i.close_count50=50 THEN i.index_close/i.index_sma50-1 END AS index_sma50_ratio,
           CASE WHEN i.close_count200=200 THEN i.index_close/i.index_sma200-1 END AS index_sma200_ratio,
           CASE WHEN i.close_count252=252 THEN i.index_close/i.high252-1 END AS index_drawdown252,
           CASE WHEN i.return_count60=60 THEN i.vol60 END AS vol60
    FROM sessions s
    LEFT JOIN market_daily_stats m ON m.session_no=s.session_no
    LEFT JOIN index_context0 i ON i.session_no=s.session_no;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_market_lagged_session_idx
        ON pg_temp.phase2_v3_market_lagged(session_no);
    ANALYZE pg_temp.phase2_v3_market_lagged;
    RAISE NOTICE 'Phase 2 market context rows %, elapsed %',
        (SELECT count(*) FROM pg_temp.phase2_v3_market_lagged),clock_timestamp()-v_stage_started;
    v_stage_started:=clock_timestamp();

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_ranks ON COMMIT DROP AS
    SELECT NULL::bigint AS symbol_id,NULL::date AS trade_date,
           NULL::double precision AS gauss_return20,NULL::double precision AS gauss_turnover,
           NULL::double precision AS gauss_vol20
    WHERE false;
    TRUNCATE pg_temp.phase2_v3_ranks;
    INSERT INTO pg_temp.phase2_v3_ranks
    SELECT f.symbol_id,f.trade_date,
           feat.normal_quantile((rank() OVER(PARTITION BY f.trade_date ORDER BY f.return_20s)
               +(count(*) OVER(PARTITION BY f.trade_date,f.return_20s)-1)/2.0-0.5)/
               nullif(count(*) OVER(PARTITION BY f.trade_date),0)) AS gauss_return20,
           feat.normal_quantile((rank() OVER(PARTITION BY f.trade_date ORDER BY f.turnover_proxy_vnd)
               +(count(*) OVER(PARTITION BY f.trade_date,f.turnover_proxy_vnd)-1)/2.0-0.5)/
               nullif(count(*) OVER(PARTITION BY f.trade_date),0)) AS gauss_turnover,
           feat.normal_quantile((rank() OVER(PARTITION BY f.trade_date ORDER BY f.realized_vol20)
               +(count(*) OVER(PARTITION BY f.trade_date,f.realized_vol20)-1)/2.0-0.5)/
               nullif(count(*) OVER(PARTITION BY f.trade_date),0)) AS gauss_vol20
    FROM feat.features_daily f
    WHERE f.feature_version='phase2-v2' AND f.trade_date BETWEEN p_date_from AND p_date_to
      AND f.return_20s IS NOT NULL AND f.turnover_proxy_vnd IS NOT NULL AND f.realized_vol20 IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_ranks_key_idx
        ON pg_temp.phase2_v3_ranks(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_v3_ranks;
    RAISE NOTICE 'Phase 2 rank rows %, elapsed %',
        (SELECT count(*) FROM pg_temp.phase2_v3_ranks),clock_timestamp()-v_stage_started;

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_symbol_batches ON COMMIT DROP AS
    SELECT 0::bigint AS symbol_id,0::integer AS batch_no WHERE false;
    TRUNCATE pg_temp.phase2_v3_symbol_batches;
    INSERT INTO pg_temp.phase2_v3_symbol_batches(symbol_id,batch_no)
    WITH requested_symbols AS MATERIALIZED (
        -- Only symbols with V2 output rows in this chunk can produce V3 rows.
        -- This uses the date/version index instead of deduplicating the entire
        -- point-in-time adjustment cache for every chunk.
        SELECT DISTINCT f.symbol_id
        FROM feat.features_daily f
        WHERE f.feature_version='phase2-v2'
          AND f.trade_date BETWEEN p_date_from AND p_date_to
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
        SELECT symbol_id FROM eligible_symbols ORDER BY symbol_id
        LIMIT COALESCE(v_probe_symbol_limit,2147483647)
    )
    SELECT symbol_id,((row_number() OVER(ORDER BY symbol_id)-1)/v_batch_size)::integer
    FROM selected_symbols;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_symbol_batches_symbol_idx
        ON pg_temp.phase2_v3_symbol_batches(symbol_id);
    CREATE INDEX IF NOT EXISTS phase2_v3_symbol_batches_batch_idx
        ON pg_temp.phase2_v3_symbol_batches(batch_no,symbol_id);
    ANALYZE pg_temp.phase2_v3_symbol_batches;

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_spine ON COMMIT DROP AS
    SELECT 0::bigint AS symbol_id,NULL::date AS trade_date,0::bigint AS session_no,
           NULL::double precision AS o,NULL::double precision AS h,
           NULL::double precision AS l,NULL::double precision AS c,
           NULL::double precision AS v,NULL::boolean AS is_traded,
           NULL::date AS bar_episode,NULL::date AS episode_key
    WHERE false;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_spine_symbol_session_idx
        ON pg_temp.phase2_v3_spine(symbol_id,session_no);

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_output ON COMMIT DROP AS
    SELECT f.* FROM feat.features_daily f WHERE false;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_output_key_idx
        ON pg_temp.phase2_v3_output(symbol_id,trade_date);

    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_computed ON COMMIT DROP AS
    SELECT NULL::bigint AS symbol_id,NULL::date AS trade_date,
           NULL::double precision AS momentum_12_1s,
           NULL::double precision AS residual_momentum_12_1s,
           NULL::double precision AS ema_5_ratio,
           NULL::double precision AS ema_10_ratio,
           NULL::double precision AS ema_20_ratio,
           NULL::double precision AS ema_50_ratio,
           NULL::double precision AS ema_100_ratio,
           NULL::double precision AS ema_200_ratio,
           NULL::double precision AS macd_histogram_pct,
           NULL::double precision AS adx_14_sma,
           NULL::double precision AS stochastic_k_14,
           NULL::double precision AS stochastic_d_3,
           NULL::double precision AS downside_vol5,
           NULL::double precision AS downside_vol60,
           NULL::double precision AS return_skew_pop60,
           NULL::double precision AS return_excess_kurtosis_pop60,
           NULL::double precision AS beta_vnindex_60,
           NULL::double precision AS beta_vnindex_250,
           NULL::double precision AS idio_vol_vnindex_60,
           NULL::double precision AS idio_vol_vnindex_250,
           NULL::double precision AS amihud_proxy_20,
           NULL::double precision AS gap_mean20,
           NULL::double precision AS gap_std20,
           NULL::double precision AS rank_gaussian_return20,
           NULL::double precision AS rank_gaussian_turnover_proxy,
           NULL::double precision AS rank_gaussian_realized_vol20,
           NULL::bigint AS market_advance_minus_decline,
           NULL::bigint AS market_new_high_minus_low,
           NULL::double precision AS market_turnover_z20,
           NULL::double precision AS market_return_dispersion,
           NULL::double precision AS vnindex_sma50_ratio,
           NULL::double precision AS vnindex_sma200_ratio,
           NULL::double precision AS vnindex_drawdown252,
           NULL::double precision AS vnindex_realized_vol60,
           NULL::smallint AS quarter_end_proximity_days
    WHERE false;
    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_computed_key_idx
        ON pg_temp.phase2_v3_computed(symbol_id,trade_date);

    FOR v_batch IN
        SELECT DISTINCT batch_no FROM pg_temp.phase2_v3_symbol_batches ORDER BY batch_no
    LOOP
    v_batch_started:=clock_timestamp();
    TRUNCATE pg_temp.phase2_v3_spine;
    INSERT INTO pg_temp.phase2_v3_spine
    WITH symbol_set AS MATERIALIZED (
        SELECT symbol_id FROM pg_temp.phase2_v3_symbol_batches
        WHERE batch_no=v_batch.batch_no
    ), source_bars AS MATERIALIZED (
        SELECT r.*,s.session_no,
               sum(CASE WHEN r.reference_adjustment_ratio>0 AND
                                  r.reference_adjustment_ratio<'Infinity'::double precision
                        THEN ln(r.reference_adjustment_ratio) END) OVER (
                   PARTITION BY r.symbol_id,r.episode_start_date
                   ORDER BY r.trade_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS cumulative_log_factor
        FROM symbol_set y
        CROSS JOIN LATERAL (
            SELECT p.*
            FROM pg_temp.phase2_adjustment_rows p
            WHERE p.symbol_id=y.symbol_id AND p.source='vndirect'
              AND p.trade_date >= (SELECT min(trade_date) FROM pg_temp.phase2_v3_sessions)
              AND p.trade_date <= (SELECT max(trade_date) FROM pg_temp.phase2_v3_sessions)
            OFFSET 0
        ) r
        JOIN pg_temp.phase2_v3_sessions s USING(trade_date)
    ), neutral AS MATERIALIZED (
        SELECT r.symbol_id,r.trade_date,r.session_no,r.episode_start_date,
               r.model_o*exp(-r.cumulative_log_factor) AS o,
               r.model_h*exp(-r.cumulative_log_factor) AS h,
               r.model_l*exp(-r.cumulative_log_factor) AS l,
               r.model_c*exp(-r.cumulative_log_factor) AS c,
               r.v,r.is_traded
        FROM source_bars r
        WHERE r.reference_adjustment_ratio>0
          AND r.reference_adjustment_ratio<'Infinity'::double precision
          AND r.cumulative_log_factor IS NOT NULL
    ), spine0 AS MATERIALIZED (
        SELECT y.symbol_id,s.trade_date,s.session_no,b.o,b.h,b.l,b.c,b.v,b.is_traded,
               b.episode_start_date AS bar_episode
        FROM symbol_set y CROSS JOIN pg_temp.phase2_v3_sessions s
        LEFT JOIN neutral b ON b.symbol_id=y.symbol_id AND b.trade_date=s.trade_date
    )
    SELECT x.symbol_id,x.trade_date,x.session_no,x.o,x.h,x.l,x.c,x.v,x.is_traded,
           x.bar_episode,
           max(x.bar_episode) OVER(PARTITION BY x.symbol_id ORDER BY x.session_no
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS episode_key
    FROM spine0 x;
    ANALYZE pg_temp.phase2_v3_spine;
    RAISE NOTICE 'Phase 2 batch % spine rows %, elapsed %',
        v_batch.batch_no,(SELECT count(*) FROM pg_temp.phase2_v3_spine),clock_timestamp()-v_batch_started;
    v_stage_started:=clock_timestamp();
    TRUNCATE pg_temp.phase2_v3_output,pg_temp.phase2_v3_computed;
    INSERT INTO pg_temp.phase2_v3_output
    SELECT f.*
    FROM feat.features_daily f
    JOIN pg_temp.phase2_v3_symbol_batches bs
      ON bs.symbol_id=f.symbol_id AND bs.batch_no=v_batch.batch_no
    WHERE f.feature_version='phase2-v2'
      AND f.trade_date BETWEEN p_date_from AND p_date_to;
    GET DIAGNOSTICS v_base_rows=ROW_COUNT;
    UPDATE pg_temp.phase2_v3_output
       SET feature_version='phase2-v3',feature_set_hash=v_hash,built_at=now();
    ANALYZE pg_temp.phase2_v3_output;
    RAISE NOTICE 'Phase 2 batch % base rows %, elapsed %',
        v_batch.batch_no,v_base_rows,clock_timestamp()-v_stage_started;
    v_batch_started:=clock_timestamp();

    WITH sessions AS MATERIALIZED (
        SELECT trade_date,session_no FROM pg_temp.phase2_v3_sessions
    ), spine AS NOT MATERIALIZED (
        SELECT * FROM pg_temp.phase2_v3_spine
    ), ema_episode_marks AS MATERIALIZED (
        SELECT p.*,
               CASE WHEN p.c IS NOT NULL AND p.episode_key IS DISTINCT FROM
                         lag(p.episode_key) OVER(PARTITION BY p.symbol_id ORDER BY p.session_no)
                    THEN 1::bigint ELSE 0::bigint END AS ema_episode_start
        FROM spine p
    ), ema_episode_groups AS MATERIALIZED (
        SELECT p.*,
               sum(p.ema_episode_start) OVER(PARTITION BY p.symbol_id ORDER BY p.session_no
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ema_episode
        FROM ema_episode_marks p
    ), ema_input_stats AS MATERIALIZED (
        SELECT p.*,
               min(p.session_no) FILTER(WHERE p.c IS NOT NULL)
                   OVER(PARTITION BY p.symbol_id,p.ema_episode) AS first_close_session,
               count(*) FILTER(WHERE p.is_traded AND p.c IS NOT NULL)
                   OVER(PARTITION BY p.symbol_id,p.ema_episode ORDER BY p.session_no
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ema_count
        FROM ema_episode_groups p
    ), ema_inputs AS MATERIALIZED (
        SELECT p.*,
               CASE WHEN p.session_no=p.first_close_session OR p.is_traded THEN p.c END AS ema_input
        FROM ema_input_stats p
    ), ema_state AS MATERIALIZED (
        SELECT p.symbol_id,p.trade_date,p.session_no,p.episode_key,p.ema_episode,p.c,p.is_traded,p.ema_count,
               feat.ema(p.ema_input,2.0/6) OVER w AS ema5,
               feat.ema(p.ema_input,2.0/11) OVER w AS ema10,
               feat.ema(p.ema_input,2.0/21) OVER w AS ema20,
               feat.ema(p.ema_input,2.0/51) OVER w AS ema50,
               feat.ema(p.ema_input,2.0/101) OVER w AS ema100,
               feat.ema(p.ema_input,2.0/201) OVER w AS ema200,
               feat.ema(p.ema_input,2.0/13) OVER w AS ema12,
               feat.ema(p.ema_input,2.0/27) OVER w AS ema26
        FROM ema_inputs p
        WINDOW w AS (PARTITION BY p.symbol_id,p.ema_episode ORDER BY p.session_no
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ), ema_macd AS MATERIALIZED (
        SELECT e.*,
               feat.ema(CASE WHEN e.is_traded AND e.ema_count>=26 THEN e.ema12-e.ema26 END,0.2)
                   OVER(PARTITION BY e.symbol_id,e.ema_episode ORDER BY e.session_no
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS macd_signal,
               count(*) FILTER(WHERE e.is_traded AND e.ema_count>=26)
                   OVER(PARTITION BY e.symbol_id,e.ema_episode ORDER BY e.session_no
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS macd_count
        FROM ema_state e
    ), ema_signal AS MATERIALIZED (
        SELECT e.*,
               CASE WHEN e.is_traded AND e.ema_count>=5 AND e.ema5>0 THEN e.c/e.ema5-1 END AS ema5_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=10 AND e.ema10>0 THEN e.c/e.ema10-1 END AS ema10_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=20 AND e.ema20>0 THEN e.c/e.ema20-1 END AS ema20_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=50 AND e.ema50>0 THEN e.c/e.ema50-1 END AS ema50_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=100 AND e.ema100>0 THEN e.c/e.ema100-1 END AS ema100_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=200 AND e.ema200>0 THEN e.c/e.ema200-1 END AS ema200_ratio,
               CASE WHEN e.is_traded AND e.ema_count>=26 AND e.macd_count>=9 AND e.c>0
                    THEN ((e.ema12-e.ema26)-e.macd_signal)/e.c END AS macd_histogram_pct
        FROM ema_macd e
    ), prior_price AS MATERIALIZED (
        SELECT x.*,
               lag(x.is_traded) OVER w AS prior_is_traded,
               lag(x.c) OVER w AS prior_c,
               lag(x.h) OVER w AS prior_h,
               lag(x.l) OVER w AS prior_l,
               lag(x.episode_key) OVER w AS prior_episode
        FROM spine x
        WINDOW w AS (PARTITION BY x.symbol_id ORDER BY x.session_no)
    ), price_lags AS MATERIALIZED (
        SELECT x.*,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.episode_key=x.prior_episode AND x.prior_c>0
                    THEN x.c/x.prior_c-1 END AS daily_return,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.episode_key=x.prior_episode AND x.prior_c>0
                    THEN x.o/x.prior_c-1 END AS open_gap,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.episode_key=x.prior_episode
                    THEN greatest(x.h-x.l,abs(x.h-x.prior_c),abs(x.l-x.prior_c)) END AS true_range,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.episode_key=x.prior_episode
                    THEN greatest(x.h-x.prior_h,0.0) END AS plus_dm,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.episode_key=x.prior_episode
                    THEN greatest(x.prior_l-x.l,0.0) END AS minus_dm
        FROM prior_price x
    ), technical AS MATERIALIZED (
        SELECT p.*,
               count(p.c) FILTER(WHERE p.is_traded) OVER w5 AS traded5,
               count(p.c) FILTER(WHERE p.is_traded) OVER w10 AS traded10,
               count(p.c) FILTER(WHERE p.is_traded) OVER w14_episode AS traded14,
               max(p.h) FILTER(WHERE p.is_traded) OVER w14_episode AS high14,
               min(p.l) FILTER(WHERE p.is_traded) OVER w14_episode AS low14,
               avg(p.true_range) OVER w14 AS tr14,
               avg(p.plus_dm) OVER w14 AS plus14,
               avg(p.minus_dm) OVER w14 AS minus14,
               count(p.true_range) OVER w14 AS tr_count14,
               count(p.daily_return) OVER w5 AS return_count5,
               sqrt(avg(power(least(p.daily_return,0.0),2)) OVER w5) AS downside5,
               sqrt(avg(power(least(p.daily_return,0.0),2)) OVER w60) AS downside60,
               count(p.daily_return) OVER w60 AS return_count60,
               avg(p.daily_return) OVER w60 AS mean60,
               stddev_pop(p.daily_return) OVER w60 AS sd60,
               avg(power(p.daily_return,2)) OVER w60 AS raw_second60,
               avg(power(p.daily_return,3)) OVER w60 AS raw_third60,
               avg(power(p.daily_return,4)) OVER w60 AS raw_fourth60,
               avg(p.open_gap) OVER w20 AS gap_mean20,
               stddev_samp(p.open_gap) OVER w20 AS gap_sd20,
               count(p.open_gap) OVER w20 AS gap_count20
        FROM price_lags p
        WINDOW w AS (PARTITION BY p.symbol_id ORDER BY p.session_no),
               w5 AS (w ROWS BETWEEN 4 PRECEDING AND CURRENT ROW),
               w10 AS (w ROWS BETWEEN 9 PRECEDING AND CURRENT ROW),
               w14 AS (w ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
               w14_episode AS (PARTITION BY p.symbol_id,p.episode_key ORDER BY p.session_no ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
               w20 AS (w ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
               w60 AS (w ROWS BETWEEN 59 PRECEDING AND CURRENT ROW)
    ), directional AS MATERIALIZED (
        SELECT t.*,
               CASE WHEN t.tr_count14=14 AND t.tr14>0
                    THEN 100*abs(t.plus14-t.minus14)/nullif(t.plus14+t.minus14,0) END AS dx14
        FROM technical t
    ), adx_calc AS MATERIALIZED (
        SELECT d.*,
               avg(d.dx14) OVER(PARTITION BY d.symbol_id ORDER BY d.session_no
                   ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) AS adx14_sma,
               count(d.dx14) OVER(PARTITION BY d.symbol_id ORDER BY d.session_no
                   ROWS BETWEEN 13 PRECEDING AND CURRENT ROW) AS adx_count14,
               -- Convert the raw moments using this row's 60-return mean. A
               -- second rolling window over row-specific means would center
               -- each historical return on a different mean.
               d.raw_third60-3*d.mean60*d.raw_second60+2*power(d.mean60,3) AS third_moment60,
               d.raw_fourth60-4*d.mean60*d.raw_third60+6*power(d.mean60,2)*d.raw_second60
                   -3*power(d.mean60,4) AS fourth_moment60
        FROM directional d
    ), index_raw AS MATERIALIZED (
        SELECT * FROM pg_temp.phase2_v3_index_raw
    ), market_lagged AS MATERIALIZED (
        SELECT * FROM pg_temp.phase2_v3_market_lagged
    ), symbol_market AS MATERIALIZED (
        SELECT f.symbol_id,f.trade_date,s.session_no,f.ret_1 AS stock_return,
               lag(i.index_return) OVER(PARTITION BY f.symbol_id ORDER BY s.session_no) AS index_return_lagged,
               f.return_20s,f.turnover_proxy_vnd,f.realized_vol20,f.gap_open_1d,
               f.distance_52w_high,f.distance_52w_low
        FROM feat.features_daily f
        JOIN sessions s USING(trade_date)
        JOIN pg_temp.phase2_v3_symbol_batches bs
          ON bs.symbol_id=f.symbol_id AND bs.batch_no=v_batch.batch_no
        LEFT JOIN index_raw i ON i.session_no=s.session_no
        WHERE f.feature_version='phase2-v2'
    ), stock_market_prefix AS MATERIALIZED (
        SELECT x.*,
               count(x.stock_return) OVER w AS stock_count_prefix,
               count(x.index_return_lagged) OVER w AS market_count_prefix,
               sum(ln(1+x.stock_return)) OVER w AS stock_log_prefix,
               sum(ln(1+x.index_return_lagged)) OVER w AS market_log_prefix,
               count(*) FILTER(WHERE x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL)
                   OVER w AS pair_count_prefix,
               sum(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.stock_return ELSE 0 END) OVER w AS stock_sum_prefix,
               sum(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.index_return_lagged ELSE 0 END) OVER w AS market_sum_prefix,
               sum(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.stock_return*x.stock_return ELSE 0 END) OVER w AS stock_square_prefix,
               sum(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.index_return_lagged*x.index_return_lagged ELSE 0 END) OVER w AS market_square_prefix,
               sum(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL
                        THEN x.stock_return*x.index_return_lagged ELSE 0 END) OVER w AS cross_product_prefix,
               count(abs(x.stock_return)/nullif(x.turnover_proxy_vnd,0)) OVER w AS amihud_count_prefix,
               sum(abs(x.stock_return)/nullif(x.turnover_proxy_vnd,0)) OVER w AS amihud_sum_prefix
        FROM symbol_market x
        WINDOW w AS (PARTITION BY x.symbol_id ORDER BY x.session_no
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ), stock_market_prefix_lags AS MATERIALIZED (
        SELECT p.*,
               lag(p.stock_count_prefix,21) OVER w AS stock_count_lag21,
               lag(p.stock_count_prefix,252) OVER w AS stock_count_lag252,
               lag(p.market_count_prefix,21) OVER w AS market_count_lag21,
               lag(p.market_count_prefix,252) OVER w AS market_count_lag252,
               lag(p.stock_log_prefix,21) OVER w AS stock_log_lag21,
               lag(p.stock_log_prefix,252) OVER w AS stock_log_lag252,
               lag(p.market_log_prefix,21) OVER w AS market_log_lag21,
               lag(p.market_log_prefix,252) OVER w AS market_log_lag252,
               lag(p.pair_count_prefix,60) OVER w AS pair_count_lag60,
               lag(p.pair_count_prefix,250) OVER w AS pair_count_lag250,
               lag(p.stock_sum_prefix,60) OVER w AS stock_sum_lag60,
               lag(p.stock_sum_prefix,250) OVER w AS stock_sum_lag250,
               lag(p.market_sum_prefix,60) OVER w AS market_sum_lag60,
               lag(p.market_sum_prefix,250) OVER w AS market_sum_lag250,
               lag(p.stock_square_prefix,60) OVER w AS stock_square_lag60,
               lag(p.stock_square_prefix,250) OVER w AS stock_square_lag250,
               lag(p.market_square_prefix,60) OVER w AS market_square_lag60,
               lag(p.market_square_prefix,250) OVER w AS market_square_lag250,
               lag(p.cross_product_prefix,60) OVER w AS cross_product_lag60,
               lag(p.cross_product_prefix,250) OVER w AS cross_product_lag250,
               lag(p.stock_count_prefix,20) OVER w AS stock_count_lag20,
               lag(p.amihud_count_prefix,20) OVER w AS amihud_count_lag20,
               lag(p.amihud_sum_prefix,20) OVER w AS amihud_sum_lag20
        FROM stock_market_prefix p
        WINDOW w AS (PARTITION BY p.symbol_id ORDER BY p.session_no)
    ), stock_market_differences AS MATERIALIZED (
        SELECT p.*,
               coalesce(p.stock_count_lag21,0)-coalesce(p.stock_count_lag252,0) AS stock_n231,
               coalesce(p.market_count_lag21,0)-coalesce(p.market_count_lag252,0) AS market_n231,
               coalesce(p.stock_log_lag21,0)-coalesce(p.stock_log_lag252,0) AS stock_log_12_1,
               coalesce(p.market_log_lag21,0)-coalesce(p.market_log_lag252,0) AS market_log_12_1,
               p.pair_count_prefix-coalesce(p.pair_count_lag60,0) AS n60,
               p.pair_count_prefix-coalesce(p.pair_count_lag250,0) AS n250,
               p.stock_sum_prefix-coalesce(p.stock_sum_lag60,0) AS stock_sum60,
               p.stock_sum_prefix-coalesce(p.stock_sum_lag250,0) AS stock_sum250,
               p.market_sum_prefix-coalesce(p.market_sum_lag60,0) AS market_sum60,
               p.market_sum_prefix-coalesce(p.market_sum_lag250,0) AS market_sum250,
               p.stock_square_prefix-coalesce(p.stock_square_lag60,0) AS stock_square60,
               p.stock_square_prefix-coalesce(p.stock_square_lag250,0) AS stock_square250,
               p.market_square_prefix-coalesce(p.market_square_lag60,0) AS market_square60,
               p.market_square_prefix-coalesce(p.market_square_lag250,0) AS market_square250,
               p.cross_product_prefix-coalesce(p.cross_product_lag60,0) AS cross_product60,
               p.cross_product_prefix-coalesce(p.cross_product_lag250,0) AS cross_product250,
               p.stock_count_prefix-coalesce(p.stock_count_lag20,0) AS return_n20,
               (p.amihud_sum_prefix-coalesce(p.amihud_sum_lag20,0)) /
                    nullif(p.amihud_count_prefix-coalesce(p.amihud_count_lag20,0),0) AS amihud20
        FROM stock_market_prefix_lags p
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
        SELECT b.*,lag(b.beta60,21) OVER(PARTITION BY b.symbol_id ORDER BY b.session_no) AS beta60_at_12_1_start
        FROM stock_market_beta b
    ), ranks AS MATERIALIZED (
        SELECT r.* FROM pg_temp.phase2_v3_ranks r
        JOIN pg_temp.phase2_v3_symbol_batches bs USING(symbol_id)
        WHERE bs.batch_no=v_batch.batch_no
    ), stoch AS MATERIALIZED (
        SELECT t.symbol_id,t.trade_date,t.session_no,t.episode_key,
               CASE WHEN t.is_traded AND t.traded14=14 AND t.high14>t.low14
                    THEN 100*(t.c-t.low14)/(t.high14-t.low14) END AS k14
        FROM technical t
    ), stochd AS MATERIALIZED (
        SELECT s.*,
               avg(s.k14) OVER(PARTITION BY s.symbol_id,s.episode_key ORDER BY s.session_no ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS d3,
               count(s.k14) OVER(PARTITION BY s.symbol_id,s.episode_key ORDER BY s.session_no ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS n3
        FROM stoch s
    )
    INSERT INTO pg_temp.phase2_v3_computed (
        symbol_id,trade_date,momentum_12_1s,residual_momentum_12_1s,
        ema_5_ratio,ema_10_ratio,ema_20_ratio,ema_50_ratio,ema_100_ratio,ema_200_ratio,
        macd_histogram_pct,adx_14_sma,stochastic_k_14,stochastic_d_3,
        downside_vol5,downside_vol60,return_skew_pop60,return_excess_kurtosis_pop60,
        beta_vnindex_60,beta_vnindex_250,idio_vol_vnindex_60,idio_vol_vnindex_250,
        amihud_proxy_20,gap_mean20,gap_std20,rank_gaussian_return20,
        rank_gaussian_turnover_proxy,rank_gaussian_realized_vol20,
        market_advance_minus_decline,market_new_high_minus_low,market_turnover_z20,
        market_return_dispersion,vnindex_sma50_ratio,vnindex_sma200_ratio,
        vnindex_drawdown252,vnindex_realized_vol60,quarter_end_proximity_days
    )
    SELECT f.symbol_id,f.trade_date,
           CASE WHEN sm.stock_n231=231 THEN exp(sm.stock_log_12_1)-1 END,
           CASE WHEN sm.stock_n231=231 AND sm.market_n231=231 AND sm.beta60_at_12_1_start IS NOT NULL
                THEN (exp(sm.stock_log_12_1)-1)-sm.beta60_at_12_1_start*(exp(sm.market_log_12_1)-1) END,
           es.ema5_ratio,es.ema10_ratio,es.ema20_ratio,es.ema50_ratio,es.ema100_ratio,es.ema200_ratio,
           es.macd_histogram_pct,
           CASE WHEN a.adx_count14=14 THEN a.adx14_sma END,
           st.k14,
           CASE WHEN st.n3=3 THEN st.d3 END,
           CASE WHEN t.return_count5=5 THEN t.downside5 END,
           CASE WHEN a.return_count60=60 THEN a.downside60 END,
           CASE WHEN a.return_count60=60 AND a.sd60>0 THEN a.third_moment60/power(a.sd60,3) END,
           CASE WHEN a.return_count60=60 AND a.sd60>0 THEN a.fourth_moment60/power(a.sd60,4)-3 END,
           CASE WHEN sm.n60=60 AND sm.market_var60>0 THEN sm.beta60 END,
           CASE WHEN sm.n250=250 AND sm.market_var250>0 THEN sm.beta250 END,
           CASE WHEN sm.n60=60 AND sm.market_var60>0
                THEN sqrt(greatest(0,sm.stock_var60-sm.covar60*sm.covar60/sm.market_var60)) END,
           CASE WHEN sm.n250=250 AND sm.market_var250>0
                THEN sqrt(greatest(0,sm.stock_var250-sm.covar250*sm.covar250/sm.market_var250)) END,
           CASE WHEN sm.return_n20=20 THEN sm.amihud20 END,
           CASE WHEN t.gap_count20=20 THEN t.gap_mean20 END,
           CASE WHEN t.gap_count20=20 THEN t.gap_sd20 END,
           rk.gauss_return20,rk.gauss_turnover,rk.gauss_vol20,
           ml.advance_minus_decline,ml.new_high_minus_low,ml.turnover_z20,
           ml.return_dispersion,ml.index_sma50_ratio,ml.index_sma200_ratio,
           ml.index_drawdown252,ml.vol60,
           ((date_trunc('quarter',f.trade_date::timestamp)+interval '3 months'-interval '1 day')::date-f.trade_date)::smallint
    FROM feat.features_daily f
    JOIN pg_temp.phase2_v3_symbol_batches bs
      ON bs.symbol_id=f.symbol_id AND bs.batch_no=v_batch.batch_no
    JOIN sessions s ON s.trade_date=f.trade_date
    LEFT JOIN ema_signal es ON es.symbol_id=f.symbol_id AND es.trade_date=f.trade_date
    LEFT JOIN adx_calc a ON a.symbol_id=f.symbol_id AND a.trade_date=f.trade_date
    LEFT JOIN technical t ON t.symbol_id=f.symbol_id AND t.trade_date=f.trade_date
    LEFT JOIN stochd st ON st.symbol_id=f.symbol_id AND st.trade_date=f.trade_date
    LEFT JOIN stock_market_windows sm ON sm.symbol_id=f.symbol_id AND sm.trade_date=f.trade_date
    LEFT JOIN ranks rk ON rk.symbol_id=f.symbol_id AND rk.trade_date=f.trade_date
    LEFT JOIN market_lagged ml ON ml.session_no=s.session_no-1
    WHERE f.feature_version='phase2-v2'
      AND f.trade_date BETWEEN p_date_from AND p_date_to
    ;

    GET DIAGNOSTICS v_computed_rows=ROW_COUNT;
    ANALYZE pg_temp.phase2_v3_computed;
    UPDATE pg_temp.phase2_v3_output target
       SET momentum_12_1s=c.momentum_12_1s,
           residual_momentum_12_1s=c.residual_momentum_12_1s,
           ema_5_ratio=c.ema_5_ratio,
           ema_10_ratio=c.ema_10_ratio,
           ema_20_ratio=c.ema_20_ratio,
           ema_50_ratio=c.ema_50_ratio,
           ema_100_ratio=c.ema_100_ratio,
           ema_200_ratio=c.ema_200_ratio,
           macd_histogram_pct=c.macd_histogram_pct,
           adx_14_sma=c.adx_14_sma,
           stochastic_k_14=c.stochastic_k_14,
           stochastic_d_3=c.stochastic_d_3,
           downside_vol5=c.downside_vol5,
           downside_vol60=c.downside_vol60,
           return_skew_pop60=c.return_skew_pop60,
           return_excess_kurtosis_pop60=c.return_excess_kurtosis_pop60,
           beta_vnindex_60=c.beta_vnindex_60,
           beta_vnindex_250=c.beta_vnindex_250,
           idio_vol_vnindex_60=c.idio_vol_vnindex_60,
           idio_vol_vnindex_250=c.idio_vol_vnindex_250,
           amihud_proxy_20=c.amihud_proxy_20,
           gap_mean20=c.gap_mean20,
           gap_std20=c.gap_std20,
           rank_gaussian_return20=c.rank_gaussian_return20,
           rank_gaussian_turnover_proxy=c.rank_gaussian_turnover_proxy,
           rank_gaussian_realized_vol20=c.rank_gaussian_realized_vol20,
           market_advance_minus_decline=c.market_advance_minus_decline,
           market_new_high_minus_low=c.market_new_high_minus_low,
           market_turnover_z20=c.market_turnover_z20,
           market_return_dispersion=c.market_return_dispersion,
           vnindex_sma50_ratio=c.vnindex_sma50_ratio,
           vnindex_sma200_ratio=c.vnindex_sma200_ratio,
           vnindex_drawdown252=c.vnindex_drawdown252,
           vnindex_realized_vol60=c.vnindex_realized_vol60,
           quarter_end_proximity_days=c.quarter_end_proximity_days
      FROM pg_temp.phase2_v3_computed c
     WHERE target.symbol_id=c.symbol_id AND target.trade_date=c.trade_date;
    GET DIAGNOSTICS v_output_rows=ROW_COUNT;
    IF v_base_rows<>v_computed_rows OR v_computed_rows<>v_output_rows THEN
        RAISE EXCEPTION 'Phase 2 batch % row mismatch: base %, computed %, updated %',
            v_batch.batch_no,v_base_rows,v_computed_rows,v_output_rows;
    END IF;
    INSERT INTO feat.features_daily
    SELECT * FROM pg_temp.phase2_v3_output;
    GET DIAGNOSTICS v_batch_affected=ROW_COUNT;
    RAISE NOTICE 'Phase 2 batch % feature rows %, elapsed %',
        v_batch.batch_no,v_batch_affected,clock_timestamp()-v_batch_started;
    affected:=affected+v_batch_affected;
    END LOOP;

    RETURN affected;
END;
$build_price_features_v3$;

COMMENT ON FUNCTION feat.build_price_features_v3_internal(date,date) IS
    'Builds source-independent Phase 2 v3 features in symbol batches; the session-local vnpipe.phase2_symbol_batch_size defaults to 50 and is bounded to 1..250.';

CREATE OR REPLACE FUNCTION feat.build_price_features_v3(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    RETURN feat.build_price_features_v3_internal(p_date_from,p_date_to);
END;
$$;

CREATE OR REPLACE FUNCTION feat.build_features(p_date_from date,p_date_to date)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE built bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    PERFORM feat.build_features_v2(p_date_from,p_date_to);

    -- v2 computes rank_realized_vol20 in the insert from the same full-window
    -- population as realized_vol20. Avoid rewriting millions of target rows.
    built := feat.build_price_features_v3_internal(p_date_from,p_date_to);
    RETURN built;
END;
$$;

-- Rebuild the same raw label definition against v3 feature rows and hash.
DO $$
DECLARE def text;
BEGIN
    IF to_regprocedure('feat.build_labels_v2(date,date)') IS NOT NULL THEN
        def:=pg_get_functiondef('feat.build_labels_v2(date,date)'::regprocedure);
        def:=replace(def,'CREATE OR REPLACE FUNCTION feat.build_labels_v2(',
                         'CREATE OR REPLACE FUNCTION feat.build_labels(');
        def:=replace(def,'v_feature_hash constant text:=feat.phase2_feature_set_hash();',
                         'v_feature_hash constant text:=feat.phase2_feature_set_hash_v3();');
        def:=replace(def,'feature_version=''phase2-v2''','feature_version=''phase2-v3''');
        def:=replace(def,'ie.source=''vndirect''','ie.source=''vci''');
        def:=replace(def,'ix.source=''vndirect''','ix.source=''vci''');
        IF position('feat.phase2_feature_set_hash_v3()' in def)=0 OR position('phase2-v3' in def)=0 THEN
            RAISE EXCEPTION 'could not version label builder for phase2-v3';
        END IF;
        IF position('ie.source=''vci''' in def)=0 OR position('ix.source=''vci''' in def)=0 THEN
            RAISE EXCEPTION 'could not bind Phase 2 labels to the registered VCI VNINDEX history';
        END IF;
        EXECUTE def;
    END IF;
END $$;

-- Provide one transaction entry point for a complete Phase 2 feature and
-- label build. The public standalone builders refresh their own snapshot;
-- these internal copies reuse the snapshot created by the combined builder.
DO $$
DECLARE def text;
BEGIN
    def:=pg_get_functiondef('feat.build_features(date,date)'::regprocedure);
    def:=replace(def,'CREATE OR REPLACE FUNCTION feat.build_features(',
                     'CREATE OR REPLACE FUNCTION feat.build_features_internal(');
    def:=replace(def,'PERFORM feat.prepare_phase2_adjustment_rows(true);',
                     'PERFORM feat.prepare_phase2_adjustment_rows(false);');
    IF position('FUNCTION feat.build_features_internal(' in def)=0
       OR position('prepare_phase2_adjustment_rows(false)' in def)=0 THEN
        RAISE EXCEPTION 'could not create Phase 2 internal feature builder';
    END IF;
    EXECUTE def;

    def:=pg_get_functiondef('feat.build_labels(date,date)'::regprocedure);
    def:=replace(def,'CREATE OR REPLACE FUNCTION feat.build_labels(',
                     'CREATE OR REPLACE FUNCTION feat.build_labels_internal(');
    def:=replace(def,'PERFORM feat.prepare_phase2_adjustment_rows(true);',
                     'PERFORM feat.prepare_phase2_adjustment_rows(false);');
    IF position('FUNCTION feat.build_labels_internal(' in def)=0
       OR position('prepare_phase2_adjustment_rows(false)' in def)=0 THEN
        RAISE EXCEPTION 'could not create Phase 2 internal label builder';
    END IF;
    EXECUTE def;
END $$;

CREATE OR REPLACE FUNCTION feat.build_features_and_labels(p_date_from date,p_date_to date)
RETURNS TABLE(feature_rows bigint,label_rows bigint)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    feature_rows:=feat.build_features_internal(p_date_from,p_date_to);
    label_rows:=feat.build_labels_internal(p_date_from,p_date_to);
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION feat.build_features(date,date) IS
    'Builds both phase2-v2 and phase2-v3 feature rows. v3 adds price/index-only indicators; sourced share, exchange-limit, Tết, VN30, intraday and industry features remain NULL until their point-in-time source evidence is verified.';
COMMENT ON FUNCTION feat.build_price_features_v3(date,date) IS
    'Materializes v3 beside v2 using episode-neutral VNDIRECT OHLCV. EMA state is recursively warmed by up to 1000 effective sessions; 12-1 spans 231 return sessions, excluding the latest 21; market regressions use a one-session lagged VNINDEX return. ADX uses explicitly simple 14-session averages. Source-dependent columns remain NULL.';
COMMENT ON FUNCTION feat.build_price_features_v3_internal(date,date) IS
    'Internal builder used by the public Phase 2 builders after the transaction-local input snapshot has been refreshed.';
COMMENT ON FUNCTION feat.build_features_and_labels(date,date) IS
    'Builds v2/v3 features and labels using one refreshed transaction-local adjusted-price input snapshot.';
COMMENT ON FUNCTION feat.build_labels(date,date) IS
    'Builds raw 5/20-session VNINDEX excess-return targets from phase2-v3 feature rows. Entry is t+1 open and exit t+1+h close.';

COMMIT;

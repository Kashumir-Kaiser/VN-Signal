-- Phase 2: deterministic point-in-time market features and forward labels.
-- VNDIRECT prices are rebuilt through the signal/exit date with the dedicated
-- as-of endpoint; no current adjusted-price view is used here.
BEGIN;

CREATE TABLE IF NOT EXISTS feat.features_daily (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    feature_version text NOT NULL,
    feature_set_hash text NOT NULL CHECK (feature_set_hash ~ '^[0-9a-f]{64}$'),
    source text NOT NULL CHECK (source='vndirect'),
    price_basis text NOT NULL CHECK (price_basis='adjusted_as_of_reference'),
    adjustment_vintage_at timestamptz,
    as_of_factor double precision,
    bar_landing_id bigint REFERENCES raw.landings(landing_id),
    bar_source_row integer,
    bar_fetched_at timestamptz,
    is_traded boolean NOT NULL,
    volume double precision NOT NULL CHECK (volume>=0),
    ret_1 double precision,
    ret_5 double precision,
    return_1d double precision,
    return_5s double precision,
    return_20s double precision,
    return_60s double precision,
    return_2s double precision,
    return_3s double precision,
    return_10s double precision,
    return_120s double precision,
    return_250s double precision,
    momentum_20s double precision,
    momentum_60s double precision,
    close_sma5_ratio double precision,
    sma_5_ratio double precision,
    close_sma20_ratio double precision,
    close_sma60_ratio double precision,
    close_sma100_ratio double precision,
    close_sma200_ratio double precision,
    distance_52w_high double precision,
    distance_52w_low double precision,
    rsi_14 double precision,
    bollinger_pct_b_20 double precision,
    bollinger_bandwidth_20 double precision,
    downside_vol20 double precision,
    atr_pct_14 double precision,
    volume_zscore_20 double precision,
    obv_slope_20 double precision,
    close_sma50_ratio double precision,
    realized_vol20 double precision,
    realized_vol60 double precision,
    vol_5 double precision,
    turnover_proxy_vnd double precision,
    log_turnover_proxy_vnd double precision,
    turnover_sma20_vnd double precision,
    volume_sma20 double precision,
    gap_open_1d double precision,
    intraday_return double precision,
    intraday_range_pct double precision,
    close_location double precision,
    large_move_approx boolean,
    session_ordinal bigint,
    day_of_week smallint,
    month_of_year smallint,
    vnindex_return_20s double precision,
    vnindex_return_60s double precision,
    vnindex_realized_vol20 double precision,
    market_breadth_above_sma50 double precision,
    rank_momentum_20s double precision,
    rank_turnover_proxy double precision,
    rank_realized_vol20 double precision,
    built_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (symbol_id,trade_date,feature_version),
    CHECK (bar_source_row IS NULL OR bar_source_row>=0),
    CHECK (as_of_factor IS NULL OR (as_of_factor>0 AND as_of_factor<'Infinity'::double precision))
);
CREATE INDEX IF NOT EXISTS features_daily_date_version_idx
    ON feat.features_daily(trade_date,feature_version);
ALTER TABLE feat.features_daily
    ADD COLUMN IF NOT EXISTS return_2s double precision,
    ADD COLUMN IF NOT EXISTS return_3s double precision,
    ADD COLUMN IF NOT EXISTS return_10s double precision,
    ADD COLUMN IF NOT EXISTS return_120s double precision,
    ADD COLUMN IF NOT EXISTS return_250s double precision,
    ADD COLUMN IF NOT EXISTS close_sma100_ratio double precision,
    ADD COLUMN IF NOT EXISTS close_sma200_ratio double precision,
    ADD COLUMN IF NOT EXISTS distance_52w_high double precision,
    ADD COLUMN IF NOT EXISTS distance_52w_low double precision,
    ADD COLUMN IF NOT EXISTS rsi_14 double precision,
    ADD COLUMN IF NOT EXISTS bollinger_pct_b_20 double precision,
    ADD COLUMN IF NOT EXISTS bollinger_bandwidth_20 double precision,
    ADD COLUMN IF NOT EXISTS downside_vol20 double precision,
    ADD COLUMN IF NOT EXISTS atr_pct_14 double precision,
    ADD COLUMN IF NOT EXISTS volume_zscore_20 double precision,
    ADD COLUMN IF NOT EXISTS obv_slope_20 double precision;

CREATE TABLE IF NOT EXISTS feat.labels_daily (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    signal_date date NOT NULL,
    horizon_sessions smallint NOT NULL CHECK(horizon_sessions IN (5,20)),
    label_version text NOT NULL,
    feature_set_hash text NOT NULL CHECK (feature_set_hash ~ '^[0-9a-f]{64}$'),
    entry_date date,
    exit_date date,
    label_status text NOT NULL CHECK(label_status IN (
        'READY','MISSING_SESSION','INSUFFICIENT_SESSIONS','MISSING_ENTRY','MISSING_EXIT',
        'SUSPENDED_ENTRY','SUSPENDED_EXIT','EPISODE_CHANGED','MISSING_BENCHMARK','UNRESOLVED_ADJUSTMENT')),
    stock_return double precision,
    vnindex_return double precision,
    excess_return double precision,
    stock_entry_open double precision,
    stock_exit_close double precision,
    vnindex_entry_open double precision,
    vnindex_exit_close double precision,
    price_basis text NOT NULL CHECK(price_basis='adjusted_as_of_exit'),
    adjustment_vintage_at timestamptz,
    entry_adjustment_vintage_at timestamptz,
    exit_adjustment_vintage_at timestamptz,
    factor_log_span double precision,
    entry_landing_id bigint REFERENCES raw.landings(landing_id),
    exit_landing_id bigint REFERENCES raw.landings(landing_id),
    computed_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(symbol_id,signal_date,horizon_sessions,label_version),
    CHECK ((label_status='READY') = (stock_return IS NOT NULL AND vnindex_return IS NOT NULL AND excess_return IS NOT NULL))
);
ALTER TABLE feat.labels_daily
    ADD COLUMN IF NOT EXISTS entry_adjustment_vintage_at timestamptz,
    ADD COLUMN IF NOT EXISTS exit_adjustment_vintage_at timestamptz,
    ADD COLUMN IF NOT EXISTS factor_log_span double precision;
ALTER TABLE feat.labels_daily DROP CONSTRAINT IF EXISTS labels_daily_label_status_check;
ALTER TABLE feat.labels_daily ADD CONSTRAINT labels_daily_label_status_check CHECK(label_status IN (
    'READY','MISSING_SESSION','INSUFFICIENT_SESSIONS','MISSING_ENTRY','MISSING_EXIT',
    'SUSPENDED_ENTRY','SUSPENDED_EXIT','EPISODE_CHANGED','MISSING_BENCHMARK','UNRESOLVED_ADJUSTMENT'));
CREATE INDEX IF NOT EXISTS labels_daily_signal_version_idx
    ON feat.labels_daily(signal_date,label_version,horizon_sessions);

CREATE OR REPLACE VIEW core.effective_trading_sessions AS
SELECT coalesce(c.trade_date,o.trade_date) AS trade_date,
       coalesce(o.is_session,c.is_session,false) AS is_session,
       coalesce(o.reason,c.source) AS calendar_evidence
FROM core.calendar c
FULL OUTER JOIN core.calendar_overrides o USING(trade_date);

COMMENT ON TABLE feat.features_daily IS
    'Wide daily feature snapshot. Price ratios use VNDIRECT model prices multiplied by exp(-episode cumulative reference factor); this is equivalent to the endpoint as-of series up to a common positive episode factor. Raw zero-volume rows are retained and price-derived returns remain NULL when the session did not trade. feature_set_hash fingerprints the fixed SQL definition. Historical source corrections and vendor ingestion timestamps are retained as lineage; this table does not claim that a later-arriving backfill was known at the historical close.';
COMMENT ON TABLE feat.labels_daily IS
    'Raw, un-winsorized forward excess-return labels. Entry is the open of session t+1 and exit the close of t+1+h. Both security prices come from the VNDIRECT as-of endpoint at exit_date and must belong to one adjustment episode. VNINDEX uses VNDIRECT index bars at matching sessions.';
COMMENT ON COLUMN feat.features_daily.ret_1 IS
    'Close-to-close return from the immediately prior effective exchange session; NULL unless both endpoint sessions traded. No session compression or forward fill.';
COMMENT ON COLUMN feat.features_daily.ret_5 IS
    'Close-to-close return from five effective exchange sessions earlier; NULL unless both endpoint sessions traded.';
COMMENT ON COLUMN feat.features_daily.sma_5_ratio IS
    'Current traded close divided by the mean of exactly five traded closes in the five-session window, minus one; NULL unless all five sessions traded.';
COMMENT ON COLUMN feat.features_daily.vol_5 IS
    'Sample standard deviation of five consecutive effective-session daily returns; requires six consecutive traded closes and is NULL across a no-trade session.';
COMMENT ON COLUMN feat.features_daily.return_20s IS
    'Current traded close divided by the traded close exactly 20 effective sessions earlier, minus one; NULL if either endpoint is unavailable or non-trading.';
COMMENT ON COLUMN feat.features_daily.realized_vol20 IS
    'Sample standard deviation of 20 consecutive session close-to-close returns; requires 20 valid returns and is NULL across missing or zero-volume sessions.';
COMMENT ON COLUMN feat.features_daily.turnover_proxy_vnd IS
    'Volume multiplied by adjusted-as-of close and 1000 because vnstock prices are in thousand VND. This is a price-volume proxy, not source-reported executed turnover.';
COMMENT ON COLUMN feat.features_daily.large_move_approx IS
    'Approximation based on rounded exchange percentage limits; it is not an exchange tick/price-limit test. NULL when a comparable prior traded session is unavailable.';

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash()
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT md5(definition)||md5('VN-Signal:'||definition)
    FROM (VALUES ('phase2-v2|vndirect_asof_neutral|250_session_warmup|effective_calendar_sessions|close_to_close_session_offsets|traded_prices_only_full_sma_windows|full_return_count_volatility|share_above_sma50|sample_std_returns|v_times_model_close_times_1000_turnover_proxy|per_date_percent_rank|no_forward_fill|zero_volume_returns_null|returns_2_3_10_120_250|sma100_200|52w_extremes|rsi14|bollinger20|downside_vol20|atr14|skew_kurtosis60|volume_z20|obv_slope20_same_episode')) d(definition)
$$;

-- Set-oriented replacement for the earlier draft above. Neutral prices differ
-- from the endpoint's as-of prices only by a common positive factor within
-- one symbol/adjustment episode. That factor cancels in returns, trend ratios,
-- volatility, and labels. The current session's endpoint-adjusted close equals
-- model_c, so turnover uses model_c × volume × 1000. Fixtures must compare
-- these ratios/labels with core.vndirect_bars_as_of_with_episodes(as_of_date).
CREATE OR REPLACE FUNCTION feat.build_features(p_date_from date,p_date_to date)
RETURNS bigint
LANGUAGE plpgsql
AS $build_features_set$
DECLARE
    affected bigint;
    v_version constant text:='phase2-v2';
    v_hash constant text:=feat.phase2_feature_set_hash();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(false);
    DELETE FROM feat.features_daily
    WHERE trade_date BETWEEN p_date_from AND p_date_to AND feature_version=v_version;
    WITH prior_sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date DESC) AS prior_no
        FROM core.effective_trading_sessions
        WHERE trade_date<p_date_from AND is_session
    ), requested_sessions AS (
        SELECT trade_date FROM core.effective_trading_sessions
        WHERE trade_date BETWEEN p_date_from AND p_date_to AND is_session
    ), bounded AS (
        SELECT trade_date FROM requested_sessions
        UNION
        SELECT trade_date FROM prior_sessions WHERE prior_no<=250
    ), sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
        FROM bounded
    ), adjustment_rows AS MATERIALIZED (
        SELECT r.symbol_id,r.trade_date,r.v,r.is_traded,
               r.reference_adjustment_ratio,r.episode_start_date,
               r.model_o,r.model_h,r.model_l,r.model_c,
               r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
        FROM pg_temp.phase2_adjustment_rows r
        WHERE r.source='vndirect' AND r.trade_date<=p_date_to
    ), first_bad AS (
        SELECT r.symbol_id,min(r.trade_date) FILTER(WHERE
                   r.reference_adjustment_ratio IS NULL OR
                   r.reference_adjustment_ratio<=0 OR
                   r.reference_adjustment_ratio>='Infinity'::double precision) AS first_bad_date
        FROM adjustment_rows r
        GROUP BY r.symbol_id
    ), source_bars AS MATERIALIZED (
        SELECT r.*,s.session_no,
               sum(CASE WHEN r.reference_adjustment_ratio>0 AND
                                  r.reference_adjustment_ratio<'Infinity'::double precision
                        THEN ln(r.reference_adjustment_ratio) END) OVER (
                   PARTITION BY r.symbol_id,r.episode_start_date
                   ORDER BY r.trade_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS cumulative_log_factor
        FROM adjustment_rows r
        JOIN sessions s USING(trade_date)
    ), neutral_bars AS MATERIALIZED (
        SELECT b.symbol_id,b.trade_date,b.session_no,b.v,b.is_traded,
               b.model_o*exp(-b.cumulative_log_factor) AS o,
               b.model_h*exp(-b.cumulative_log_factor) AS h,
               b.model_l*exp(-b.cumulative_log_factor) AS l,
               b.model_c*exp(-b.cumulative_log_factor) AS c,
               b.model_c,b.adjustment_vintage_at,b.landing_id,b.source_row,b.fetched_at,
               b.episode_start_date
        FROM source_bars b
    ), symbols AS (
        SELECT DISTINCT symbol_id FROM neutral_bars
    ), spine0 AS (
        SELECT y.symbol_id,s.trade_date,s.session_no,
               b.o,b.h,b.l,b.c,b.model_c,b.v,b.is_traded,b.adjustment_vintage_at,
               b.landing_id,b.source_row,b.fetched_at,b.episode_start_date AS bar_episode,
               sym.exchange
        FROM symbols y
        CROSS JOIN sessions s
        LEFT JOIN neutral_bars b ON b.symbol_id=y.symbol_id AND b.trade_date=s.trade_date
        JOIN core.symbols sym ON sym.symbol_id=y.symbol_id
    ), spine AS (
        SELECT s0.*,
               max(s0.bar_episode) OVER (
                   PARTITION BY s0.symbol_id ORDER BY s0.session_no
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS episode_key
        FROM spine0 s0
    ), prior_daily AS (
        SELECT x.*,
               lag(x.is_traded) OVER w AS prior_is_traded,
               lag(x.c) OVER w AS prior_c,
               lag(x.session_no) OVER w AS prior_session_no
        FROM spine x
        WINDOW w AS (PARTITION BY x.symbol_id,x.episode_key ORDER BY x.session_no)
    ), daily AS (
        SELECT x.*,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.c>0 AND x.prior_c>0 THEN x.c/x.prior_c-1 END AS ret,
               CASE WHEN x.is_traded AND x.prior_is_traded AND x.c>0 AND x.prior_c>0 THEN x.o/x.prior_c-1 END AS gap_now,
               CASE WHEN x.is_traded AND x.o>0 THEN x.c/x.o-1 END AS intraday_now,
               CASE WHEN x.is_traded AND x.c>0 THEN (x.h-x.l)/x.c END AS range_now,
               CASE WHEN x.is_traded AND x.h>x.l THEN (x.c-x.l)/(x.h-x.l) END AS location_now,
               CASE WHEN x.is_traded THEN x.v*x.model_c*1000 END AS turnover_now,
               lag(CASE WHEN x.is_traded THEN x.c END,1) OVER w AS c1,
               lag(CASE WHEN x.is_traded THEN x.c END,2) OVER w AS c2,
               lag(CASE WHEN x.is_traded THEN x.c END,3) OVER w AS c3,
               lag(CASE WHEN x.is_traded THEN x.c END,5) OVER w AS c5,
               lag(CASE WHEN x.is_traded THEN x.c END,10) OVER w AS c10,
               lag(CASE WHEN x.is_traded THEN x.c END,20) OVER w AS c20,
               lag(CASE WHEN x.is_traded THEN x.c END,50) OVER w AS c50,
               lag(CASE WHEN x.is_traded THEN x.c END,60) OVER w AS c60,
               lag(CASE WHEN x.is_traded THEN x.c END,120) OVER w AS c120,
               lag(CASE WHEN x.is_traded THEN x.c END,250) OVER w AS c250,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w5 AS sma5,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w20 AS sma20,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w50 AS sma50,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w60 AS sma60,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w100 AS sma100,
               avg(x.c) FILTER(WHERE x.is_traded) OVER w200 AS sma200,
               max(x.h) FILTER(WHERE x.is_traded) OVER w250 AS high250,
               min(x.l) FILTER(WHERE x.is_traded) OVER w250 AS low250,
               stddev_samp(x.c) FILTER(WHERE x.is_traded) OVER w20 AS sd20_close,
               avg(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN greatest(0.0,x.prior_c-x.c)/x.prior_c END) OVER w14 AS avg_loss14,
               avg(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN greatest(0.0,x.c-x.prior_c)/x.prior_c END) OVER w14 AS avg_gain14,
               avg(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN greatest(x.h-x.l,abs(x.h-x.prior_c),abs(x.l-x.prior_c))/x.c END) OVER w14 AS atr14,
               avg(x.v) FILTER(WHERE x.is_traded) OVER w20 AS avg_volume20,
               stddev_samp(x.v) FILTER(WHERE x.is_traded) OVER w20 AS sd_volume20,
               sum(CASE WHEN x.is_traded THEN x.v*CASE
                   WHEN x.prior_session_no IS NOT NULL AND x.c>x.prior_c THEN 1
                   WHEN x.prior_session_no IS NOT NULL AND x.c<x.prior_c THEN -1
                   ELSE 0 END END) OVER w20 AS obv20,
               stddev_samp(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN x.c/x.prior_c-1 END) OVER w5 AS vol5,
               stddev_samp(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN x.c/x.prior_c-1 END) OVER w20 AS vol20,
               stddev_samp(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN x.c/x.prior_c-1 END) OVER w60 AS vol60,
               sqrt(avg(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN power(least(x.c/x.prior_c-1,0.0),2) END) OVER w20) AS downside_vol20,
               count(x.c) FILTER(WHERE x.is_traded) OVER w5 AS traded_n5,
               count(x.c) FILTER(WHERE x.is_traded) OVER w20 AS traded_n20,
               count(x.c) FILTER(WHERE x.is_traded) OVER w50 AS traded_n50,
               count(x.c) FILTER(WHERE x.is_traded) OVER w60 AS traded_n60,
               count(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN 1 END) OVER w5 AS return_n5,
               count(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN 1 END) OVER w20 AS return_n20,
               count(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN 1 END) OVER w60 AS return_n60,
               count(x.c) FILTER(WHERE x.is_traded) OVER w100 AS traded_n100,
               count(x.c) FILTER(WHERE x.is_traded) OVER w200 AS traded_n200,
               count(x.c) FILTER(WHERE x.is_traded) OVER w250 AS traded_n250,
               count(CASE WHEN x.is_traded AND x.prior_is_traded AND x.prior_c>0 THEN 1 END) OVER w14 AS return_n14,
               sum(CASE WHEN x.is_traded THEN x.v*CASE
                   WHEN x.prior_session_no IS NOT NULL AND x.c>x.prior_c THEN 1
                   WHEN x.prior_session_no IS NOT NULL AND x.c<x.prior_c THEN -1
                   ELSE 0 END END) OVER w AS obv_cumulative,
               avg(x.v*x.model_c*1000) FILTER(WHERE x.is_traded) OVER w20 AS turnover20,
               avg(x.v) FILTER(WHERE x.is_traded) OVER w20 AS volume20
        FROM prior_daily x
        WINDOW w AS (PARTITION BY x.symbol_id,x.episode_key ORDER BY x.session_no),
               w5 AS (w ROWS BETWEEN 4 PRECEDING AND CURRENT ROW),
               w20 AS (w ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
               w50 AS (w ROWS BETWEEN 49 PRECEDING AND CURRENT ROW),
               w60 AS (w ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),
               w14 AS (w ROWS BETWEEN 13 PRECEDING AND CURRENT ROW),
               w100 AS (w ROWS BETWEEN 99 PRECEDING AND CURRENT ROW),
               w200 AS (w ROWS BETWEEN 199 PRECEDING AND CURRENT ROW),
               w250 AS (w ROWS BETWEEN 249 PRECEDING AND CURRENT ROW)
    ), eligible_daily AS (
        SELECT d.*
        FROM daily d
        JOIN first_bad fb USING(symbol_id)
        WHERE fb.first_bad_date IS NULL OR fb.first_bad_date>d.trade_date
    ), breadth AS (
        SELECT d.session_no,
               count(*) FILTER(WHERE d.is_traded AND d.sma50>0 AND d.c>d.sma50)::double precision /
                   nullif(count(*) FILTER(WHERE d.is_traded AND d.sma50>0),0) AS breadth_sma50
        FROM eligible_daily d
        GROUP BY d.session_no
    ), index0 AS (
        SELECT s.trade_date,i.c AS index_close,lag(i.c) OVER(ORDER BY s.session_no) AS prior_close,
               lag(i.c,20) OVER(ORDER BY s.session_no) AS close20,
               lag(i.c,60) OVER(ORDER BY s.session_no) AS close60,
               s.session_no
        FROM sessions s
        LEFT JOIN core.index_bars i ON i.trade_date=s.trade_date
             AND i.index_symbol='VNINDEX' AND i.source='vndirect'
    ), market AS (
        SELECT i.*,
               CASE WHEN i.index_close>0 AND i.close20>0 THEN i.index_close/i.close20-1 END AS idx20,
               CASE WHEN i.index_close>0 AND i.close60>0 THEN i.index_close/i.close60-1 END AS idx60,
               stddev_samp(CASE WHEN i.index_close>0 AND i.prior_close>0 THEN i.index_close/i.prior_close-1 END)
                   OVER(ORDER BY i.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS idxvol20,
               count(CASE WHEN i.index_close>0 AND i.prior_close>0 THEN 1 END)
                   OVER(ORDER BY i.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS idxreturn_n20
        FROM index0 i
    ), market_context AS (
        SELECT m.*,b.breadth_sma50
        FROM market m
        LEFT JOIN breadth b USING(session_no)
    ), picked AS (
        SELECT q.*,m.idx20,m.idx60,m.breadth_sma50,
               CASE WHEN q.is_traded AND q.c>0 AND q.c2>0 THEN q.c/q.c2-1 END AS r2,
               CASE WHEN q.is_traded AND q.c>0 AND q.c3>0 THEN q.c/q.c3-1 END AS r3,
               CASE WHEN q.is_traded AND q.c>0 AND q.c10>0 THEN q.c/q.c10-1 END AS r10,
               CASE WHEN q.is_traded AND q.c>0 AND q.c120>0 THEN q.c/q.c120-1 END AS r120,
               CASE WHEN q.is_traded AND q.c>0 AND q.c250>0 THEN q.c/q.c250-1 END AS r250,
               CASE WHEN q.is_traded AND q.c>0 AND q.traded_n100=100 AND q.sma100>0 THEN q.c/q.sma100-1 END AS sma100_ratio,
               CASE WHEN q.is_traded AND q.c>0 AND q.traded_n200=200 AND q.sma200>0 THEN q.c/q.sma200-1 END AS sma200_ratio,
               CASE WHEN q.is_traded AND q.traded_n250=250 AND q.high250>0 THEN q.c/q.high250-1 END AS high52_distance,
               CASE WHEN q.is_traded AND q.traded_n250=250 AND q.low250>0 THEN q.c/q.low250-1 END AS low52_distance,
               CASE WHEN q.is_traded AND q.return_n14=14 AND q.avg_loss14=0 THEN 100.0
                    WHEN q.is_traded AND q.return_n14=14 THEN 100.0-100.0/(1+q.avg_gain14/nullif(q.avg_loss14,0)) END AS rsi14,
               CASE WHEN q.is_traded AND q.traded_n20=20 AND q.sd20_close>0 THEN (q.c-(q.sma20-2*q.sd20_close))/(4*q.sd20_close) END AS bb_pct_b20,
               CASE WHEN q.is_traded AND q.traded_n20=20 AND q.sma20>0 THEN 4*q.sd20_close/q.sma20 END AS bb_bandwidth20,
               CASE WHEN q.return_n20=20 THEN q.downside_vol20 END AS downside_vol20_full,
               CASE WHEN q.is_traded AND q.return_n14=14 THEN q.atr14 END AS atr_pct14,
               CASE WHEN q.is_traded AND q.avg_volume20>0 AND q.sd_volume20>0 THEN (q.v-q.avg_volume20)/q.sd_volume20 END AS volume_z20,
               regr_slope(q.obv_cumulative,q.session_no) OVER (PARTITION BY q.symbol_id,q.episode_key ORDER BY q.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW) AS obv_slope20,
               CASE WHEN m.idxreturn_n20=20 THEN m.idxvol20 END AS idxvol20,
               CASE WHEN q.is_traded AND q.c>0 AND q.c1>0 THEN q.c/q.c1-1 END AS r1,
               CASE WHEN q.is_traded AND q.c>0 AND q.c5>0 THEN q.c/q.c5-1 END AS r5,
               CASE WHEN q.is_traded AND q.c>0 AND q.c20>0 THEN q.c/q.c20-1 END AS r20,
               CASE WHEN q.is_traded AND q.c>0 AND q.c60>0 THEN q.c/q.c60-1 END AS r60
        FROM eligible_daily q
        JOIN core.effective_trading_sessions s ON s.trade_date=q.trade_date AND s.is_session
        -- Cross-asset market context is deliberately lagged by one effective
        -- session to avoid same-close availability skew between index and stock.
        LEFT JOIN market_context m ON m.session_no=q.session_no-1
        WHERE q.trade_date BETWEEN p_date_from AND p_date_to AND q.c IS NOT NULL
    ), ranked AS (
        SELECT p.*,rr.rank_r20,rt.rank_turnover,rv.rank_vol
        FROM picked p
        LEFT JOIN (SELECT symbol_id,trade_date,percent_rank() OVER(PARTITION BY trade_date ORDER BY r20) AS rank_r20 FROM picked WHERE r20 IS NOT NULL) rr USING(symbol_id,trade_date)
        LEFT JOIN (SELECT symbol_id,trade_date,percent_rank() OVER(PARTITION BY trade_date ORDER BY turnover_now) AS rank_turnover FROM picked WHERE turnover_now IS NOT NULL) rt USING(symbol_id,trade_date)
        -- Persist the rank over exactly the same complete 20-return population
        -- used by realized_vol20. Partial windows must stay NULL in both fields.
        LEFT JOIN (SELECT symbol_id,trade_date,percent_rank() OVER(PARTITION BY trade_date ORDER BY vol20) AS rank_vol
                   FROM picked WHERE vol20 IS NOT NULL AND return_n20=20) rv USING(symbol_id,trade_date)
    )
    INSERT INTO feat.features_daily(
        symbol_id,trade_date,feature_version,feature_set_hash,source,price_basis,
        adjustment_vintage_at,as_of_factor,bar_landing_id,bar_source_row,bar_fetched_at,
        is_traded,volume,ret_1,ret_5,return_1d,return_5s,return_20s,return_60s,momentum_20s,momentum_60s,
        close_sma5_ratio,sma_5_ratio,close_sma20_ratio,close_sma50_ratio,close_sma60_ratio,
        return_2s,return_3s,return_10s,return_120s,return_250s,close_sma100_ratio,close_sma200_ratio,
        distance_52w_high,distance_52w_low,rsi_14,bollinger_pct_b_20,bollinger_bandwidth_20,
        downside_vol20,atr_pct_14,volume_zscore_20,obv_slope_20,
        realized_vol20,realized_vol60,vol_5,turnover_proxy_vnd,log_turnover_proxy_vnd,
        turnover_sma20_vnd,volume_sma20,gap_open_1d,intraday_return,intraday_range_pct,
        close_location,large_move_approx,session_ordinal,day_of_week,month_of_year,
        vnindex_return_20s,vnindex_return_60s,vnindex_realized_vol20,
        market_breadth_above_sma50,rank_momentum_20s,rank_turnover_proxy,rank_realized_vol20
    )
    SELECT r.symbol_id,r.trade_date,v_version,v_hash,'vndirect','adjusted_as_of_reference',
           r.adjustment_vintage_at,1.0,r.landing_id,r.source_row,r.fetched_at,
           r.is_traded,coalesce(r.v,0),r.r1,r.r5,r.r1,r.r5,r.r20,r.r60,r.r20,r.r60,
           CASE WHEN r.is_traded AND r.traded_n5=5 AND r.sma5>0 THEN r.c/r.sma5-1 END,
           CASE WHEN r.is_traded AND r.traded_n5=5 AND r.sma5>0 THEN r.c/r.sma5-1 END,
           CASE WHEN r.is_traded AND r.traded_n20=20 AND r.sma20>0 THEN r.c/r.sma20-1 END,
           CASE WHEN r.is_traded AND r.traded_n50=50 AND r.sma50>0 THEN r.c/r.sma50-1 END,
           CASE WHEN r.is_traded AND r.traded_n60=60 AND r.sma60>0 THEN r.c/r.sma60-1 END,
           r.r2,r.r3,r.r10,r.r120,r.r250,r.sma100_ratio,r.sma200_ratio,
           r.high52_distance,r.low52_distance,r.rsi14,r.bb_pct_b20,r.bb_bandwidth20,
           r.downside_vol20_full,r.atr_pct14,r.volume_z20,r.obv_slope20,
           CASE WHEN r.return_n20=20 THEN r.vol20 END,
           CASE WHEN r.return_n60=60 THEN r.vol60 END,
           CASE WHEN r.return_n5=5 THEN r.vol5 END,
           r.turnover_now,ln(1+r.turnover_now),r.turnover20,r.volume20,r.gap_now,
           r.intraday_now,r.range_now,r.location_now,
           CASE WHEN r.is_traded AND r.c1>0 THEN abs(r.c/r.c1-1)>=CASE r.exchange WHEN 'HOSE' THEN 0.069 WHEN 'HNX' THEN 0.099 ELSE 0.149 END END,
           r.session_no,extract(isodow from r.trade_date)::smallint,extract(month from r.trade_date)::smallint,
           r.idx20,r.idx60,r.idxvol20,r.breadth_sma50,r.rank_r20,r.rank_turnover,r.rank_vol
    FROM ranked r
    JOIN first_bad fb ON fb.symbol_id=r.symbol_id
    WHERE fb.first_bad_date IS NULL OR fb.first_bad_date>r.trade_date
    ON CONFLICT(symbol_id,trade_date,feature_version) DO UPDATE SET
        feature_set_hash=EXCLUDED.feature_set_hash,source=EXCLUDED.source,price_basis=EXCLUDED.price_basis,
        adjustment_vintage_at=EXCLUDED.adjustment_vintage_at,as_of_factor=EXCLUDED.as_of_factor,
        bar_landing_id=EXCLUDED.bar_landing_id,bar_source_row=EXCLUDED.bar_source_row,bar_fetched_at=EXCLUDED.bar_fetched_at,
        is_traded=EXCLUDED.is_traded,volume=EXCLUDED.volume,ret_1=EXCLUDED.ret_1,ret_5=EXCLUDED.ret_5,
        return_1d=EXCLUDED.return_1d,return_5s=EXCLUDED.return_5s,return_20s=EXCLUDED.return_20s,
        return_60s=EXCLUDED.return_60s,momentum_20s=EXCLUDED.momentum_20s,momentum_60s=EXCLUDED.momentum_60s,
        close_sma5_ratio=EXCLUDED.close_sma5_ratio,sma_5_ratio=EXCLUDED.sma_5_ratio,
        close_sma20_ratio=EXCLUDED.close_sma20_ratio,close_sma50_ratio=EXCLUDED.close_sma50_ratio,
        close_sma60_ratio=EXCLUDED.close_sma60_ratio,realized_vol20=EXCLUDED.realized_vol20,
        return_2s=EXCLUDED.return_2s,return_3s=EXCLUDED.return_3s,return_10s=EXCLUDED.return_10s,
        return_120s=EXCLUDED.return_120s,return_250s=EXCLUDED.return_250s,
        close_sma100_ratio=EXCLUDED.close_sma100_ratio,close_sma200_ratio=EXCLUDED.close_sma200_ratio,
        distance_52w_high=EXCLUDED.distance_52w_high,distance_52w_low=EXCLUDED.distance_52w_low,
        rsi_14=EXCLUDED.rsi_14,bollinger_pct_b_20=EXCLUDED.bollinger_pct_b_20,
        bollinger_bandwidth_20=EXCLUDED.bollinger_bandwidth_20,downside_vol20=EXCLUDED.downside_vol20,
        atr_pct_14=EXCLUDED.atr_pct_14,volume_zscore_20=EXCLUDED.volume_zscore_20,
        obv_slope_20=EXCLUDED.obv_slope_20,
        realized_vol60=EXCLUDED.realized_vol60,vol_5=EXCLUDED.vol_5,turnover_proxy_vnd=EXCLUDED.turnover_proxy_vnd,
        log_turnover_proxy_vnd=EXCLUDED.log_turnover_proxy_vnd,turnover_sma20_vnd=EXCLUDED.turnover_sma20_vnd,
        volume_sma20=EXCLUDED.volume_sma20,gap_open_1d=EXCLUDED.gap_open_1d,
        intraday_return=EXCLUDED.intraday_return,intraday_range_pct=EXCLUDED.intraday_range_pct,
        close_location=EXCLUDED.close_location,large_move_approx=EXCLUDED.large_move_approx,
        session_ordinal=EXCLUDED.session_ordinal,day_of_week=EXCLUDED.day_of_week,month_of_year=EXCLUDED.month_of_year,
        vnindex_return_20s=EXCLUDED.vnindex_return_20s,vnindex_return_60s=EXCLUDED.vnindex_return_60s,
        vnindex_realized_vol20=EXCLUDED.vnindex_realized_vol20,
        market_breadth_above_sma50=EXCLUDED.market_breadth_above_sma50,
        rank_momentum_20s=EXCLUDED.rank_momentum_20s,rank_turnover_proxy=EXCLUDED.rank_turnover_proxy,
        rank_realized_vol20=EXCLUDED.rank_realized_vol20,built_at=now();
    GET DIAGNOSTICS affected=ROW_COUNT;
    RETURN affected;
END;
$build_features_set$;

CREATE OR REPLACE FUNCTION feat.build_labels(p_date_from date,p_date_to date)
RETURNS bigint
LANGUAGE plpgsql
AS $build_labels$
DECLARE
    affected bigint;
    v_label constant text:='close-next-open-v1';
    v_feature_hash constant text:=feat.phase2_feature_set_hash();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    DELETE FROM feat.labels_daily
    WHERE signal_date BETWEEN p_date_from AND p_date_to AND label_version=v_label;

    -- Generate t+1 and t+1+h from the effective session spine once. Within
    -- an adjustment episode, endpoint-as-of prices equal model prices times
    -- one common factor. The ratio over (entry,exit] is therefore sufficient:
    -- stock return = model_exit_close / (model_entry_open * exp(log_span)) - 1.
    -- This matches the exit-date as-of function without rebuilding a market
    -- wide as-of series for every signal date.
    WITH calendar_axis AS MATERIALIZED (
        SELECT trade_date,
               lead(trade_date,1) OVER(ORDER BY trade_date) AS entry_date,
               lead(trade_date,6) OVER(ORDER BY trade_date) AS exit_5_date,
               lead(trade_date,21) OVER(ORDER BY trade_date) AS exit_20_date
        FROM core.effective_trading_sessions
        WHERE is_session
    ), signals AS MATERIALIZED (
        SELECT c.trade_date AS signal_date,c.entry_date,h.horizon_sessions,
               CASE h.horizon_sessions WHEN 5 THEN c.exit_5_date ELSE c.exit_20_date END AS exit_date
        FROM calendar_axis c
        CROSS JOIN (VALUES (5::smallint),(20::smallint)) h(horizon_sessions)
        WHERE c.trade_date BETWEEN p_date_from AND p_date_to
    ), targets AS MATERIALIZED (
        SELECT s.signal_date,s.entry_date,s.exit_date,s.horizon_sessions,f.symbol_id
        FROM signals s
        JOIN feat.features_daily f ON f.trade_date=s.signal_date AND f.feature_version='phase2-v2'
    ), target_symbols AS MATERIALIZED (
        SELECT DISTINCT symbol_id FROM targets
    ), adjustment_rows AS MATERIALIZED (
        -- Resolve the complex adjusted-price view once per target symbol and
        -- reuse its narrow result for endpoints, factor spans, and bad-factor
        -- checks. Joining every history prefix to every exit date expanded the
        -- same rows repeatedly and made a full label rebuild quadratic.
        SELECT r.symbol_id,r.trade_date,r.model_o,r.model_c,r.v,r.is_traded,
               r.episode_start_date,r.adjustment_vintage_at,r.landing_id,
               r.reference_adjustment_ratio
        FROM pg_temp.phase2_adjustment_rows r
        JOIN target_symbols s USING(symbol_id)
        WHERE r.source='vndirect'
    ), endpoint_days AS MATERIALIZED (
        SELECT DISTINCT symbol_id,entry_date AS trade_date FROM targets
        UNION
        SELECT DISTINCT symbol_id,exit_date FROM targets WHERE exit_date IS NOT NULL
    ), endpoint_bars AS MATERIALIZED (
        SELECT r.symbol_id,r.trade_date,r.model_o,r.model_c,r.v AS volume,r.is_traded,
               r.episode_start_date,r.adjustment_vintage_at,r.landing_id
        FROM adjustment_rows r
        JOIN endpoint_days d
          USING(symbol_id,trade_date)
    ), latest_exit_by_symbol AS MATERIALIZED (
        SELECT symbol_id,max(exit_date) AS latest_exit_date
        FROM targets WHERE exit_date IS NOT NULL GROUP BY symbol_id
    ), first_bad_factor AS MATERIALIZED (
        SELECT r.symbol_id,min(r.trade_date) AS first_bad_date
        FROM adjustment_rows r
        JOIN latest_exit_by_symbol k ON k.symbol_id=r.symbol_id AND r.trade_date<=k.latest_exit_date
        WHERE (r.reference_adjustment_ratio IS NULL OR r.reference_adjustment_ratio<=0
               OR r.reference_adjustment_ratio>='Infinity'::double precision)
          AND NOT EXISTS (SELECT 1 FROM ops.ml_symbol_scope x
                          WHERE x.symbol_id=r.symbol_id AND x.scope_status='EXCLUDED')
        GROUP BY r.symbol_id
    ), spans AS MATERIALIZED (
        SELECT t.symbol_id,t.signal_date,t.horizon_sessions,
               sum(CASE WHEN r.reference_adjustment_ratio>0 AND
                                  r.reference_adjustment_ratio<'Infinity'::double precision
                        THEN ln(r.reference_adjustment_ratio) END) AS factor_log_span,
               count(r.trade_date) AS factor_rows,
               count(*) FILTER(WHERE r.trade_date IS NOT NULL AND
                   (r.reference_adjustment_ratio IS NULL OR r.reference_adjustment_ratio<=0 OR
                    r.reference_adjustment_ratio>='Infinity'::double precision)) AS bad_factor_rows,
               bool_and(r.episode_start_date=t_entry.episode_start_date) AS one_episode_span
        FROM targets t
        LEFT JOIN endpoint_bars t_entry ON t_entry.symbol_id=t.symbol_id AND t_entry.trade_date=t.entry_date
        LEFT JOIN adjustment_rows r
          ON r.symbol_id=t.symbol_id
         AND r.trade_date>t.entry_date AND r.trade_date<=t.exit_date
         AND r.episode_start_date=t_entry.episode_start_date
        GROUP BY t.symbol_id,t.signal_date,t.horizon_sessions
    ), index_points AS MATERIALIZED (
        SELECT t.signal_date,t.horizon_sessions,ie.trade_date AS index_entry_date,
               ix.trade_date AS index_exit_date,ie.o AS index_entry_open,ix.c AS index_exit_close
        FROM (SELECT DISTINCT signal_date,horizon_sessions,entry_date,exit_date FROM targets) t
        LEFT JOIN core.index_bars ie ON ie.index_symbol='VNINDEX' AND ie.source='vndirect' AND ie.trade_date=t.entry_date
        LEFT JOIN core.index_bars ix ON ix.index_symbol='VNINDEX' AND ix.source='vndirect' AND ix.trade_date=t.exit_date
    ), assembled AS (
        SELECT t.*,en.model_o AS entry_model_open,ex.model_c AS exit_model_close,
               en.volume AS entry_volume,ex.volume AS exit_volume,en.is_traded AS entry_traded,
               ex.is_traded AS exit_traded,en.episode_start_date AS entry_episode,
               ex.episode_start_date AS exit_episode,en.adjustment_vintage_at AS entry_vintage,
               ex.adjustment_vintage_at AS exit_vintage,en.landing_id AS entry_landing_id,
               ex.landing_id AS exit_landing_id,en.trade_date AS entry_bar_date,ex.trade_date AS exit_bar_date,
               sp.factor_log_span,sp.factor_rows,sp.bad_factor_rows,sp.one_episode_span,fb.first_bad_date,
               ip.index_entry_open,ip.index_exit_close,
               CASE
                 WHEN t.entry_date IS NULL OR t.exit_date IS NULL THEN 'INSUFFICIENT_SESSIONS'
                 WHEN en.trade_date IS NULL THEN 'MISSING_ENTRY'
                 WHEN ex.trade_date IS NULL THEN 'MISSING_EXIT'
                 WHEN fb.first_bad_date IS NOT NULL AND fb.first_bad_date<=t.exit_date THEN 'UNRESOLVED_ADJUSTMENT'
                 WHEN sp.bad_factor_rows>0 OR sp.factor_log_span IS NULL OR NOT coalesce(sp.one_episode_span,true)
                   THEN 'UNRESOLVED_ADJUSTMENT'
                 WHEN en.episode_start_date IS DISTINCT FROM ex.episode_start_date THEN 'EPISODE_CHANGED'
                 WHEN NOT en.is_traded OR en.volume<=0 THEN 'SUSPENDED_ENTRY'
                 WHEN NOT ex.is_traded OR ex.volume<=0 THEN 'SUSPENDED_EXIT'
                 WHEN ip.index_entry_date IS NULL OR ip.index_exit_date IS NULL OR
                      ip.index_entry_open<=0 OR ip.index_exit_close<=0 THEN 'MISSING_BENCHMARK'
                 ELSE 'READY'
               END AS label_status
        FROM targets t
        LEFT JOIN endpoint_bars en ON en.symbol_id=t.symbol_id AND en.trade_date=t.entry_date
        LEFT JOIN endpoint_bars ex ON ex.symbol_id=t.symbol_id AND ex.trade_date=t.exit_date
        LEFT JOIN spans sp ON sp.symbol_id=t.symbol_id
                          AND sp.signal_date=t.signal_date
                          AND sp.horizon_sessions=t.horizon_sessions
        LEFT JOIN first_bad_factor fb ON fb.symbol_id=t.symbol_id
        LEFT JOIN index_points ip ON ip.signal_date=t.signal_date
                                 AND ip.horizon_sessions=t.horizon_sessions
    )
    INSERT INTO feat.labels_daily(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,entry_date,exit_date,
        label_status,stock_return,vnindex_return,excess_return,stock_entry_open,stock_exit_close,
        vnindex_entry_open,vnindex_exit_close,price_basis,adjustment_vintage_at,
        entry_adjustment_vintage_at,exit_adjustment_vintage_at,factor_log_span,entry_landing_id,exit_landing_id
    )
    SELECT a.symbol_id,a.signal_date,a.horizon_sessions,v_label,v_feature_hash,a.entry_date,a.exit_date,a.label_status,
           CASE WHEN a.label_status='READY'
                THEN a.exit_model_close/(a.entry_model_open*exp(a.factor_log_span))-1 END,
           CASE WHEN a.label_status='READY' THEN a.index_exit_close/a.index_entry_open-1 END,
           CASE WHEN a.label_status='READY'
                THEN a.exit_model_close/(a.entry_model_open*exp(a.factor_log_span))-1
                     -(a.index_exit_close/a.index_entry_open-1) END,
           CASE WHEN a.label_status='READY' THEN a.entry_model_open*exp(a.factor_log_span) END,
           CASE WHEN a.label_status='READY' THEN a.exit_model_close END,
           a.index_entry_open,a.index_exit_close,'adjusted_as_of_exit',a.exit_vintage,
           a.entry_vintage,a.exit_vintage,a.factor_log_span,a.entry_landing_id,a.exit_landing_id
    FROM assembled a
    ON CONFLICT(symbol_id,signal_date,horizon_sessions,label_version) DO UPDATE SET
        feature_set_hash=EXCLUDED.feature_set_hash,entry_date=EXCLUDED.entry_date,exit_date=EXCLUDED.exit_date,
        label_status=EXCLUDED.label_status,stock_return=EXCLUDED.stock_return,
        vnindex_return=EXCLUDED.vnindex_return,excess_return=EXCLUDED.excess_return,
        stock_entry_open=EXCLUDED.stock_entry_open,stock_exit_close=EXCLUDED.stock_exit_close,
        vnindex_entry_open=EXCLUDED.vnindex_entry_open,vnindex_exit_close=EXCLUDED.vnindex_exit_close,
        price_basis=EXCLUDED.price_basis,adjustment_vintage_at=EXCLUDED.adjustment_vintage_at,
        entry_adjustment_vintage_at=EXCLUDED.entry_adjustment_vintage_at,
        exit_adjustment_vintage_at=EXCLUDED.exit_adjustment_vintage_at,factor_log_span=EXCLUDED.factor_log_span,
        entry_landing_id=EXCLUDED.entry_landing_id,exit_landing_id=EXCLUDED.exit_landing_id,computed_at=now();
    GET DIAGNOSTICS affected=ROW_COUNT;
    RETURN affected;
END;
$build_labels$;

COMMENT ON FUNCTION feat.build_features(date,date) IS
    'Builds/rebuilds inclusive exchange-session features with one set-oriented bounded 250-session warm-up. Neutral episode prices model_* × exp(-cumulative reference-factor log) are equivalent to core.vndirect_bars_as_of_with_episodes(session_date) for ratios/returns because the endpoint adds one common factor per episode. Session offsets use effective calendar overrides. Cross-sectional ranks and breadth are computed per date; breadth is share above SMA50. The fixed SQL definition is phase2-v2; source arrival-time vintages, intraday bars, and archived fundamental overlays are outside this version.';
COMMENT ON FUNCTION feat.build_labels(date,date) IS
    'Builds raw 5/20-session VNINDEX excess-return targets in one set-oriented pass over effective sessions. Entry is t+1 open; exit is t+1+h close. The stock return uses the adjustment-factor log span over (entry,exit] within one episode, algebraically matching the exit-date as-of series. Missing sessions/bars, zero-volume endpoints, unresolved factors, episode changes, and missing benchmark remain explicit statuses.';

COMMIT;

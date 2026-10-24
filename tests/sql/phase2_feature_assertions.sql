\set ON_ERROR_STOP on
-- Exercises the Phase 2 SQL builders against synthetic-only fixture data.
-- Everything, including generated feature/label rows, is rolled back.
BEGIN;
CREATE TEMP TABLE phase2_recursive_ema_golden (
    episode text NOT NULL,
    step integer NOT NULL,
    trade_date date NOT NULL,
    close double precision NOT NULL,
    traded boolean NOT NULL,
    ema_5_ratio double precision,
    ema_10_ratio double precision,
    ema_20_ratio double precision,
    ema_50_ratio double precision,
    ema_100_ratio double precision,
    ema_200_ratio double precision,
    macd_histogram_pct double precision,
    PRIMARY KEY (episode,step)
) ON COMMIT DROP;
\copy phase2_recursive_ema_golden FROM 'tests/golden/phase2_recursive_ema.csv' WITH (FORMAT csv, HEADER true, NULL '')
DO $$
DECLARE
    ema_values double precision[];
    reset_values double precision[];
    v3_function text;
    v3_hash_function text;
    label_function text;
    public_v3_function text;
    public_label_function text;
    factor_stage text;
    factor_get_rows integer;
    factor_restore integer;
    rank_repair_guard_rejected boolean;
BEGIN
    v3_function:=pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure);
    v3_hash_function:=pg_get_functiondef('feat.phase2_feature_set_hash_v3()'::regprocedure);
    label_function:=pg_get_functiondef('feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure);
    public_v3_function:=pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);
    public_label_function:=pg_get_functiondef('feat.build_labels_set_based(date,date)'::regprocedure);
    IF position('build_price_features_v3_shared(p_date_from,p_date_to,NULL)' IN public_v3_function)=0 OR
       position('build_labels_set_based_shared(p_date_from,p_date_to,NULL)' IN public_label_function)=0 THEN
        RAISE EXCEPTION 'public Phase 2 builders must delegate to the generated shared implementations';
    END IF;
    IF position('stable_pair_moments_v1' IN v3_function)=0 OR
       position('var_samp(CASE WHEN x.stock_return IS NOT NULL AND x.index_return_lagged IS NOT NULL' IN v3_function)=0 OR
       position('covar_samp(' IN v3_function)=0 THEN
        RAISE EXCEPTION 'shared V3 builder must compute rolling regression with stable pair moments';
    END IF;
    IF position('symbol_first_v3_eligibility_v1' IN v3_function)=0 OR
       position('CROSS JOIN LATERAL' IN v3_function)=0 OR
       position('r.symbol_id=c.symbol_id' IN v3_function)=0 OR
       position('r.trade_date BETWEEN' IN v3_function)=0 OR
       position('JOIN pg_temp.phase2_v3_sessions s ON s.trade_date=r.trade_date' IN v3_function)=0 OR
       position('JOIN pg_temp.phase2_adjustment_rows r ON r.trade_date=s.trade_date' IN v3_function)>0 THEN
        RAISE EXCEPTION 'V3 eligibility must use the symbol/date cache index with exact selected sessions';
    END IF;
    IF position('stable_pair_moments' IN v3_hash_function)=0 OR
       position('independent_nonnull_rank_populations_v1' IN v3_hash_function)=0 OR
       position('vnindex_inherited_returns_vol20_vci' IN v3_hash_function)=0 THEN
        RAISE EXCEPTION 'V3 feature hash must retain rank, inherited-return and stable-moment contracts';
    END IF;
    rank_repair_guard_rejected:=false;
    BEGIN
        PERFORM ops.repair_phase2_rank_chunk('rank-065-disabled',DATE '2020-01-02',DATE '2020-01-02');
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair is restricted to the audited 052-to-053 semantic upgrade%' THEN
            rank_repair_guard_rejected:=true;
        ELSE
            RAISE;
        END IF;
    END;
    IF NOT rank_repair_guard_rejected THEN
        RAISE EXCEPTION 'legacy rank repair must be disabled after the V3 feature hash advances';
    END IF;
    IF position('i.index_symbol=''VNINDEX'' AND i.source=''vci''' in
           v3_function)=0 OR
       position('ie.source = ''vci''' in
           label_function)=0 OR
       position('ix.source = ''vci''' in
           label_function)=0 THEN
        RAISE EXCEPTION 'V3 feature and label builders must use the registered VCI VNINDEX history';
    END IF;
    IF position('phase2_label_adjustment_prefix' in
           label_function)=0 OR
       position('phase2_label_endpoint_bounds' in
           label_function)=0 OR
       position('phase2_label_latest_exit active_symbols' in
           label_function)=0 OR
       position('LEFT JOIN adjustment_rows r' in
           label_function)>0 THEN
        RAISE EXCEPTION 'V3 label spans must use target-scoped cumulative adjustment-factor prefixes';
    END IF;
    IF position('WHEN sp.factor_rows IS DISTINCT FROM t.horizon_sessions::bigint'
                IN label_function)=0 OR
       position('THEN ''MISSING_SESSION''' IN label_function)=0 THEN
        RAISE EXCEPTION 'V3 label builder must reject an incomplete interior session window';
    END IF;
    IF position('PERFORM set_config(''enable_nestloop'',''off'',true);' in
           label_function)=0 OR
       position('PERFORM set_config(''enable_nestloop'',v_enable_nestloop,true);' in
           label_function)=0 THEN
        RAISE EXCEPTION 'V3 bad-factor validation must scope and restore its sequential-scan planner setting';
    END IF;
    factor_stage:=substring(label_function FROM position(
        'DROP TABLE IF EXISTS pg_temp.phase2_label_first_bad_factor;' IN label_function));
    factor_get_rows:=position('GET DIAGNOSTICS v_step_rows = ROW_COUNT;' IN factor_stage);
    factor_restore:=position(
        'PERFORM set_config(''enable_nestloop'',v_enable_nestloop,true);' IN factor_stage);
    IF factor_get_rows=0 OR factor_restore=0 OR factor_get_rows>=factor_restore THEN
        RAISE EXCEPTION 'V3 bad-factor scan must capture its row count before restoring the planner setting';
    END IF;
    IF position('SELECT symbol_id FROM eligible_symbols ORDER BY symbol_id' in
           v3_function)=0 OR
       position('SELECT symbol_id FROM symbols ORDER BY symbol_id' in
           v3_function)>0 THEN
        RAISE EXCEPTION 'V3 selected_symbols must read the defined eligible_symbols CTE';
    END IF;

    SELECT array_agg(v ORDER BY step) INTO ema_values
    FROM (
        SELECT step,feat.ema(x,0.5) OVER(ORDER BY step ROWS UNBOUNDED PRECEDING) AS v
        FROM (VALUES (1,10.0::double precision),(2,NULL::double precision),
                     (3,14.0::double precision),(4,16.0::double precision)) input(step,x)
    ) actual;
    IF ema_values IS DISTINCT FROM ARRAY[10.0,10.0,12.0,14.0]::double precision[] THEN
        RAISE EXCEPTION 'EMA aggregate lost first-value seeding or NULL carry: %',ema_values;
    END IF;

    SELECT array_agg(v ORDER BY step) INTO reset_values
    FROM (
        SELECT step,feat.ema(x,0.5) OVER(PARTITION BY episode ORDER BY step ROWS UNBOUNDED PRECEDING) AS v
        FROM (VALUES (1,1,10.0::double precision),(2,1,14.0::double precision),
                     (3,2,20.0::double precision),(4,2,24.0::double precision)) input(step,episode,x)
    ) actual;
    IF reset_values IS DISTINCT FROM ARRAY[10.0,12.0,20.0,22.0]::double precision[] THEN
        RAISE EXCEPTION 'EMA aggregate failed to reset at an episode boundary: %',reset_values;
    END IF;
END $$;
CREATE TEMP TABLE phase2_v3_batch_reference (
    symbol_id bigint NOT NULL,
    trade_date date NOT NULL,
    row_image jsonb NOT NULL,
    PRIMARY KEY(symbol_id,trade_date)
) ON COMMIT DROP;
DO $$
DECLARE
    d0 date;
    d1 date;
    d3 date;
    d6 date;
    d15 date;
    d16 date;
    d18 date;
    d21 date;
    d24 date;
    d253 date;
    d254 date;
    dlast date;
    ready_id bigint;
    stoch_id bigint;
    zero_id bigint;
    entry_id bigint;
    exit_id bigint;
    gap_id bigint;
    missing_id bigint;
    episode_id bigint;
    action_ratio double precision:=0.95;
    expected_entry_open double precision;
    expected_exit_close double precision;
    beta60_delta double precision;
    beta250_delta double precision;
    idio60_delta double precision;
    idio250_delta double precision;
    amihud20_delta double precision;
    vci_return20_delta double precision;
    vci_return60_delta double precision;
    vci_vol20_delta double precision;
    vci_source_changed boolean;
    ready_vol_rank double precision;
    stoch_vol_rank double precision;
    batch_mismatch_symbol bigint;
    batch_mismatch_date date;
    batch_mismatch_fields text;
    f feat.features_daily%ROWTYPE;
    l feat.labels_daily%ROWTYPE;
BEGIN
    SELECT trade_date INTO d0 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 0 LIMIT 1;
    SELECT trade_date INTO d1 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 1 LIMIT 1;
    SELECT trade_date INTO d6 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 6 LIMIT 1;
    SELECT trade_date INTO d15 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 15 LIMIT 1;
    SELECT trade_date INTO d16 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 16 LIMIT 1;
    SELECT trade_date INTO d18 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 18 LIMIT 1;
    SELECT trade_date INTO d3 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 3 LIMIT 1;
    SELECT trade_date INTO d21 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 21 LIMIT 1;
    SELECT trade_date INTO d24 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 24 LIMIT 1;
    SELECT trade_date INTO d253 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 253 LIMIT 1;
    SELECT trade_date INTO d254 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 254 LIMIT 1;
    SELECT trade_date INTO dlast FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 319 LIMIT 1;
    IF d0 IS NULL OR d1 IS NULL OR d6 IS NULL OR d21 IS NULL OR d24 IS NULL OR
       d253 IS NULL OR d254 IS NULL OR dlast IS NULL THEN
        RAISE EXCEPTION 'synthetic Phase 2 calendar fixture is incomplete';
    END IF;

    SELECT symbol_id INTO ready_id FROM core.symbols WHERE symbol='P2READY';
    SELECT symbol_id INTO stoch_id FROM core.symbols WHERE symbol='P2STOCH';
    SELECT symbol_id INTO zero_id FROM core.symbols WHERE symbol='P2ZERO';
    SELECT symbol_id INTO entry_id FROM core.symbols WHERE symbol='P2ENTRY';
    SELECT symbol_id INTO exit_id FROM core.symbols WHERE symbol='P2EXIT';
    SELECT symbol_id INTO gap_id FROM core.symbols WHERE symbol='P2GAP';
    SELECT symbol_id INTO missing_id FROM core.symbols WHERE symbol='P2MISS';
    SELECT symbol_id INTO episode_id FROM core.symbols WHERE symbol='P2EPISODE';

    -- Compare one large symbol batch with several small batches. The fixture
    -- has enough symbols to cross batch boundaries and includes tied/edge
    -- populations used by the rank and episode assertions below.
    PERFORM set_config('vnpipe.phase2_symbol_batch_size','250',true);
    PERFORM feat.build_features(d0,dlast);
    INSERT INTO phase2_v3_batch_reference(symbol_id,trade_date,row_image)
    SELECT fx.symbol_id,fx.trade_date,to_jsonb(fx)-'built_at'
    FROM feat.features_daily fx
    WHERE fx.feature_version='phase2-v3' AND fx.trade_date BETWEEN d0 AND dlast;
    PERFORM set_config('vnpipe.phase2_symbol_batch_size','2',true);
    PERFORM feat.build_features(d0,dlast);
    IF (SELECT count(DISTINCT batch_no) FROM pg_temp.phase2_v3_symbol_batches)<2 THEN
        RAISE EXCEPTION 'batch parity fixture did not span multiple symbol batches';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM phase2_v3_batch_reference old
        FULL JOIN (
            SELECT fx.symbol_id,fx.trade_date,to_jsonb(fx)-'built_at' AS row_image
            FROM feat.features_daily fx
            WHERE fx.feature_version='phase2-v3' AND fx.trade_date BETWEEN d0 AND dlast
        ) current USING(symbol_id,trade_date)
        WHERE old.symbol_id IS NULL OR current.symbol_id IS NULL
           OR old.row_image IS DISTINCT FROM current.row_image
    ) THEN
        SELECT coalesce(old.symbol_id,current.symbol_id),coalesce(old.trade_date,current.trade_date),
               CASE WHEN old.symbol_id IS NULL THEN 'row added'
                    WHEN current.symbol_id IS NULL THEN 'row removed'
                    ELSE 'feature values changed' END
          INTO batch_mismatch_symbol,batch_mismatch_date,batch_mismatch_fields
        FROM phase2_v3_batch_reference old
        FULL JOIN (
            SELECT fx.symbol_id,fx.trade_date,to_jsonb(fx)-'built_at' AS row_image
            FROM feat.features_daily fx
            WHERE fx.feature_version='phase2-v3' AND fx.trade_date BETWEEN d0 AND dlast
        ) current USING(symbol_id,trade_date)
        WHERE old.symbol_id IS NULL OR current.symbol_id IS NULL
           OR old.row_image IS DISTINCT FROM current.row_image
        ORDER BY coalesce(old.trade_date,current.trade_date),coalesce(old.symbol_id,current.symbol_id)
        LIMIT 1;
        IF batch_mismatch_fields='feature values changed' THEN
            SELECT string_agg(fields.key,',' ORDER BY fields.key)
              INTO batch_mismatch_fields
              FROM phase2_v3_batch_reference old
              JOIN feat.features_daily fx
                ON fx.symbol_id=old.symbol_id AND fx.trade_date=old.trade_date
               AND fx.feature_version='phase2-v3'
              CROSS JOIN LATERAL jsonb_each(old.row_image) fields
             WHERE old.symbol_id=batch_mismatch_symbol AND old.trade_date=batch_mismatch_date
               AND fields.value IS DISTINCT FROM (to_jsonb(fx)-'built_at')->fields.key;
        END IF;
        RAISE EXCEPTION 'batched Phase 2 v3 mismatch for symbol %, date %, fields %',
            batch_mismatch_symbol,batch_mismatch_date,batch_mismatch_fields;
    END IF;
    PERFORM set_config('vnpipe.phase2_symbol_batch_size','50',true);
    PERFORM feat.build_labels(d0,d0);
    PERFORM feat.build_labels(d24,d24);
    PERFORM feat.build_labels(dlast,dlast);
    PERFORM feat.build_labels(d253,d254);

    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=zero_id AND trade_date=d1 AND feature_version='phase2-v2';
    IF NOT FOUND OR f.is_traded OR f.volume<>0 OR f.return_1d IS NOT NULL OR f.ret_1 IS NOT NULL THEN
        RAISE EXCEPTION 'zero-volume session was not retained with NULL one-session returns';
    END IF;
    IF (SELECT count(*) FROM feat.features_daily x
         WHERE x.feature_version='phase2-v2'
           AND x.trade_date BETWEEN d0 AND d24
           AND x.symbol_id=ready_id
           AND x.ret_1 IS NOT NULL AND x.ret_5 IS NOT NULL
           AND x.sma_5_ratio IS NOT NULL AND x.vol_5 IS NOT NULL)<>20 THEN
        RAISE EXCEPTION 'fixture must provide exactly 20 fully eligible feature rows for Rust parity';
    END IF;
    SELECT rank_realized_vol20 INTO ready_vol_rank FROM feat.features_daily
     WHERE symbol_id=ready_id AND trade_date=d24 AND feature_version='phase2-v2';
    SELECT rank_realized_vol20 INTO stoch_vol_rank FROM feat.features_daily
     WHERE symbol_id=stoch_id AND trade_date=d24 AND feature_version='phase2-v2';
    IF ready_vol_rank IS DISTINCT FROM 1.0::double precision OR
       stoch_vol_rank IS DISTINCT FROM 0.0::double precision OR
       EXISTS (SELECT 1 FROM feat.features_daily x
               WHERE x.feature_version='phase2-v2'
                 AND x.trade_date BETWEEN d0 AND dlast
                 AND x.realized_vol20 IS NULL AND x.rank_realized_vol20 IS NOT NULL) THEN
        RAISE EXCEPTION 'volatility rank must preserve the full-window ordering and leave partial windows NULL';
    END IF;
    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=ready_id AND trade_date=(SELECT trade_date FROM core.calendar
       WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 10 LIMIT 1)
       AND feature_version='phase2-v2';
    IF f.return_2s IS NULL OR f.return_3s IS NULL OR f.return_10s IS NULL OR
       abs(f.return_2s-(121.0/117.0-1))>1e-12 OR
       abs(f.return_3s-(121.0/115.0-1))>1e-12 OR
       abs(f.return_10s-(121.0/101.0-1))>1e-12 THEN
        RAISE EXCEPTION 'synthetic multi-horizon returns have wrong session offsets';
    END IF;
    IF f.close_sma100_ratio IS NOT NULL OR f.close_sma200_ratio IS NOT NULL OR
       f.distance_52w_high IS NOT NULL OR f.distance_52w_low IS NOT NULL THEN
        RAISE EXCEPTION 'long-window features must remain NULL without full 250-session history';
    END IF;
    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=ready_id AND trade_date=(SELECT trade_date FROM core.calendar
       WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 20 LIMIT 1)
       AND feature_version='phase2-v2';
    IF f.rsi_14 IS NULL OR abs(f.rsi_14-100)>1e-10 OR f.bollinger_bandwidth_20 IS NULL OR
       f.downside_vol20 IS NULL OR f.atr_pct_14 IS NULL OR f.volume_zscore_20 IS NOT NULL OR
       f.obv_slope_20 IS NULL THEN
        RAISE EXCEPTION 'synthetic oscillator and volume features are unexpectedly NULL';
    END IF;

    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=ready_id AND trade_date=(SELECT trade_date FROM core.calendar
       WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 300 LIMIT 1)
       AND feature_version='phase2-v3';
    IF NOT FOUND OR f.feature_set_hash<>feat.phase2_feature_set_hash_v3() OR
       f.momentum_12_1s IS NULL OR f.residual_momentum_12_1s IS NULL OR
       f.ema_5_ratio IS NULL OR f.ema_10_ratio IS NULL OR f.ema_20_ratio IS NULL OR
       f.ema_50_ratio IS NULL OR f.ema_100_ratio IS NULL OR f.ema_200_ratio IS NULL OR
       f.macd_histogram_pct IS NULL OR f.adx_14_sma IS NULL OR
       f.stochastic_k_14 IS NULL OR f.stochastic_d_3 IS NULL OR
       f.downside_vol5 IS NULL OR f.downside_vol60 IS NULL OR
       f.return_skew_pop60 IS NULL OR f.return_excess_kurtosis_pop60 IS NULL OR
       f.beta_vnindex_60 IS NULL OR f.beta_vnindex_250 IS NULL OR
       f.idio_vol_vnindex_60 IS NULL OR f.idio_vol_vnindex_250 IS NULL OR
       f.amihud_proxy_20 IS NULL OR f.gap_mean20 IS NULL OR f.gap_std20 IS NULL OR
       f.rank_gaussian_return20 IS NULL OR f.rank_gaussian_turnover_proxy IS NULL OR
       f.rank_gaussian_realized_vol20 IS NULL OR f.market_advance_minus_decline IS NULL OR
       f.market_new_high_minus_low IS NULL OR f.market_turnover_z20 IS NULL OR
       f.market_return_dispersion IS NULL OR f.vnindex_sma50_ratio IS NULL OR
       f.vnindex_sma200_ratio IS NULL OR f.vnindex_drawdown252 IS NULL OR
       f.vnindex_realized_vol60 IS NULL OR f.quarter_end_proximity_days IS NULL THEN
        RAISE EXCEPTION 'source-independent v3 price/index features failed to materialize';
    END IF;

    WITH session_rows AS MATERIALIZED (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
        FROM core.effective_trading_sessions
        WHERE is_session AND trade_date BETWEEN d0 AND dlast
    ), index_rows AS MATERIALIZED (
        SELECT s.trade_date,s.session_no,i.c AS index_close,
               lag(i.c) OVER(ORDER BY s.session_no) AS prior_close
        FROM session_rows s
        LEFT JOIN core.index_bars i
          ON i.trade_date=s.trade_date AND i.index_symbol='VNINDEX' AND i.source='vci'
    ), index_returns AS MATERIALIZED (
        SELECT r.*,
               CASE WHEN r.index_close>0 AND r.prior_close>0
                    THEN r.index_close/r.prior_close-1 END AS index_return
        FROM index_rows r
    ), expected AS MATERIALIZED (
        SELECT r.*,
               lag(r.index_close,20) OVER(ORDER BY r.session_no) AS close20,
               lag(r.index_close,60) OVER(ORDER BY r.session_no) AS close60,
               stddev_samp(r.index_return) OVER w20 AS vol20,
               count(r.index_return) OVER w20 AS return_count20
        FROM index_returns r
        WINDOW w20 AS (ORDER BY r.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
    )
    SELECT abs(v3_row.vnindex_return_20s-
               CASE WHEN e.index_close>0 AND e.close20>0 THEN e.index_close/e.close20-1 END),
           abs(v3_row.vnindex_return_60s-
               CASE WHEN e.index_close>0 AND e.close60>0 THEN e.index_close/e.close60-1 END),
           abs(v3_row.vnindex_realized_vol20-
               CASE WHEN e.return_count20=20 THEN e.vol20 END),
           v3_row.vnindex_return_20s IS DISTINCT FROM v2_row.vnindex_return_20s AND
           v3_row.vnindex_return_60s IS DISTINCT FROM v2_row.vnindex_return_60s AND
           v3_row.vnindex_realized_vol20 IS DISTINCT FROM v2_row.vnindex_realized_vol20
      INTO vci_return20_delta,vci_return60_delta,vci_vol20_delta,vci_source_changed
      FROM session_rows target
      JOIN expected e ON e.session_no=target.session_no-1
      JOIN feat.features_daily v3_row
        ON v3_row.symbol_id=ready_id AND v3_row.trade_date=target.trade_date AND v3_row.feature_version='phase2-v3'
      JOIN feat.features_daily v2_row
        ON v2_row.symbol_id=v3_row.symbol_id AND v2_row.trade_date=v3_row.trade_date AND v2_row.feature_version='phase2-v2'
     WHERE target.trade_date=dlast;
    IF vci_return20_delta IS NULL OR vci_return20_delta>1e-12 OR
       vci_return60_delta IS NULL OR vci_return60_delta>1e-12 OR
       vci_vol20_delta IS NULL OR vci_vol20_delta>1e-12 OR
       NOT coalesce(vci_source_changed,false) THEN
        RAISE EXCEPTION 'V3 inherited VNINDEX return/volatility fields must use one-session-lagged VCI inputs: %, %, %, source_changed=%',
            vci_return20_delta,vci_return60_delta,vci_vol20_delta,vci_source_changed;
    END IF;

    IF f.correlation_vn30_60 IS NOT NULL OR f.turnover_listed_shares IS NOT NULL OR
       f.limit_up_hit IS NOT NULL OR f.limit_down_hit IS NOT NULL OR
       f.limit_up_streak IS NOT NULL OR f.limit_down_streak IS NOT NULL OR
       f.distance_to_price_limit IS NOT NULL OR f.sessions_to_tet IS NOT NULL OR
       f.sessions_from_tet IS NOT NULL OR f.intraday_realized_variance IS NOT NULL OR
       f.intraday_vwap_gap IS NOT NULL OR f.intraday_closing_auction_share IS NOT NULL OR
       f.rank_gaussian_momentum20_industry IS NOT NULL THEN
        RAISE EXCEPTION 'source-dependent v3 features must remain NULL without verified PIT evidence';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM feat.features_daily v3
        JOIN feat.features_daily v2
          ON v2.symbol_id=v3.symbol_id AND v2.trade_date=v3.trade_date
         AND v2.feature_version='phase2-v2'
        WHERE v3.symbol_id=ready_id AND v3.feature_version='phase2-v3'
          AND v3.trade_date BETWEEN d0 AND dlast
          AND (v3.source,v3.price_basis,v3.adjustment_vintage_at,v3.as_of_factor,
               v3.bar_landing_id,v3.bar_source_row,v3.bar_fetched_at,v3.is_traded,
               v3.volume,v3.ret_1,v3.return_20s,v3.turnover_proxy_vnd,v3.rank_realized_vol20)
              IS DISTINCT FROM
              (v2.source,v2.price_basis,v2.adjustment_vintage_at,v2.as_of_factor,
               v2.bar_landing_id,v2.bar_source_row,v2.bar_fetched_at,v2.is_traded,
               v2.volume,v2.ret_1,v2.return_20s,v2.turnover_proxy_vnd,v2.rank_realized_vol20)
    ) THEN
        RAISE EXCEPTION 'V3 direct-row assembly changed inherited V2 fields';
    END IF;

    WITH session_rows AS MATERIALIZED (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
        FROM core.effective_trading_sessions
        WHERE is_session AND trade_date BETWEEN d0 AND dlast
    ), index_rows AS MATERIALIZED (
        SELECT s.session_no,
               CASE WHEN i.c>0 AND lag(i.c) OVER(ORDER BY s.session_no)>0
                    THEN i.c/lag(i.c) OVER(ORDER BY s.session_no)-1 END AS index_return
        FROM session_rows s
        LEFT JOIN core.index_bars i
          ON i.trade_date=s.trade_date AND i.index_symbol='VNINDEX' AND i.source='vci'
    ), pair_rows AS MATERIALIZED (
        SELECT v2.trade_date,s.session_no,v2.ret_1 AS stock_return,
               lag(i.index_return) OVER(ORDER BY s.session_no) AS index_return_lagged,
               v2.turnover_proxy_vnd
        FROM feat.features_daily v2
        JOIN session_rows s USING(trade_date)
        LEFT JOIN index_rows i USING(session_no)
        WHERE v2.symbol_id=ready_id AND v2.feature_version='phase2-v2'
    ), aggregate_reference AS MATERIALIZED (
        SELECT p.trade_date,
               regr_slope(p.stock_return,p.index_return_lagged) OVER w60 AS beta60,
               var_samp(p.stock_return) OVER w60 AS stock_var60,
               var_samp(p.index_return_lagged) OVER w60 AS market_var60,
               covar_samp(p.stock_return,p.index_return_lagged) OVER w60 AS covar60,
               count(*) FILTER(WHERE p.stock_return IS NOT NULL AND p.index_return_lagged IS NOT NULL) OVER w60 AS n60,
               regr_slope(p.stock_return,p.index_return_lagged) OVER w250 AS beta250,
               var_samp(p.stock_return) OVER w250 AS stock_var250,
               var_samp(p.index_return_lagged) OVER w250 AS market_var250,
               covar_samp(p.stock_return,p.index_return_lagged) OVER w250 AS covar250,
               count(*) FILTER(WHERE p.stock_return IS NOT NULL AND p.index_return_lagged IS NOT NULL) OVER w250 AS n250,
               avg(abs(p.stock_return)/nullif(p.turnover_proxy_vnd,0)) OVER w20 AS amihud20,
               count(p.stock_return) OVER w20 AS return_n20
        FROM pair_rows p
        WINDOW w20 AS (ORDER BY p.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
               w60 AS (ORDER BY p.session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),
               w250 AS (ORDER BY p.session_no ROWS BETWEEN 249 PRECEDING AND CURRENT ROW)
    )
     SELECT abs(v3.beta_vnindex_60-r.beta60)/
                greatest(abs(v3.beta_vnindex_60),abs(r.beta60),1e-300),
            abs(v3.beta_vnindex_250-r.beta250)/
                greatest(abs(v3.beta_vnindex_250),abs(r.beta250),1e-300),
            abs(v3.idio_vol_vnindex_60-
                sqrt(greatest(0,r.stock_var60-r.covar60*r.covar60/r.market_var60)))/
                greatest(abs(v3.idio_vol_vnindex_60),
                         abs(sqrt(greatest(0,r.stock_var60-r.covar60*r.covar60/r.market_var60))),1e-300),
            abs(v3.idio_vol_vnindex_250-
                sqrt(greatest(0,r.stock_var250-r.covar250*r.covar250/r.market_var250)))/
                greatest(abs(v3.idio_vol_vnindex_250),
                         abs(sqrt(greatest(0,r.stock_var250-r.covar250*r.covar250/r.market_var250))),1e-300),
           abs(v3.amihud_proxy_20-r.amihud20)
      INTO beta60_delta,beta250_delta,idio60_delta,idio250_delta,amihud20_delta
      FROM aggregate_reference r
      JOIN feat.features_daily v3
        ON v3.symbol_id=ready_id AND v3.trade_date=r.trade_date AND v3.feature_version='phase2-v3'
     WHERE r.trade_date=dlast AND r.n60=60 AND r.n250=250 AND r.return_n20=20
       AND r.market_var60>0 AND r.market_var250>0;
    IF beta60_delta IS NULL OR beta60_delta>1e-9 OR
       beta250_delta IS NULL OR beta250_delta>1e-9 OR
       idio60_delta IS NULL OR idio60_delta>1e-9 OR
       idio250_delta IS NULL OR idio250_delta>1e-9 OR
       amihud20_delta IS NULL OR amihud20_delta>1e-9 THEN
         RAISE EXCEPTION 'relative beta/idiosyncratic volatility or Amihud differs from direct rolling reference: %, %, %, %, %',
            beta60_delta,beta250_delta,idio60_delta,idio250_delta,amihud20_delta;
    END IF;
    IF EXISTS (
        SELECT 1 FROM feat.features_daily
        WHERE symbol_id=stoch_id AND feature_version='phase2-v3'
          AND trade_date BETWEEN d3 AND d15
          AND (stochastic_k_14 IS NOT NULL OR stochastic_d_3 IS NOT NULL)
    ) THEN
        RAISE EXCEPTION 'stochastic feature used highs/lows from a prior adjustment episode';
    END IF;
    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=stoch_id AND trade_date=d16 AND feature_version='phase2-v3';
    IF f.stochastic_k_14 IS NULL OR abs(f.stochastic_k_14-50)>1e-10 OR f.stochastic_d_3 IS NOT NULL THEN
        RAISE EXCEPTION 'stochastic K did not wait for 14 traded bars in the new episode';
    END IF;
    SELECT * INTO f FROM feat.features_daily
     WHERE symbol_id=stoch_id AND trade_date=d18 AND feature_version='phase2-v3';
    IF f.stochastic_k_14 IS NULL OR abs(f.stochastic_k_14-50)>1e-10 OR
       f.stochastic_d_3 IS NULL OR abs(f.stochastic_d_3-50)>1e-10 THEN
        RAISE EXCEPTION 'stochastic D crossed episode boundary or used wrong window';
    END IF;
    IF abs(f.momentum_12_1s-(659.0/197.0-1))>1e-10 THEN
        RAISE EXCEPTION '12-1 momentum does not cover the expected 231 return sessions';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=ready_id AND signal_date=d0 AND horizon_sessions=5
       AND label_version='close-next-open-v1';
    IF NOT FOUND OR l.label_status<>'READY' OR l.entry_date<>d1 OR l.exit_date<>d6 OR
       l.feature_set_hash<>feat.phase2_feature_set_hash_v3() THEN
        RAISE EXCEPTION '5-session label has wrong status/entry/exit: %, %, %',l.label_status,l.entry_date,l.exit_date;
    END IF;
    IF abs(l.stock_entry_open-102)>1e-9 OR abs(l.stock_exit_close-113)>1e-9 OR
       abs(l.stock_return-(113.0/102.0-1))>1e-12 OR
       abs(l.vnindex_return-(3024.5/3004.0-1))>1e-12 OR
       abs(l.excess_return-((113.0/102.0-1)-(3024.5/3004.0-1)))>1e-12 THEN
        RAISE EXCEPTION '5-session label returns do not use t+1 open through t+6 close';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=ready_id AND signal_date=d0 AND horizon_sessions=20
       AND label_version='close-next-open-v1';
    IF NOT FOUND OR l.label_status<>'READY' OR l.entry_date<>d1 OR l.exit_date<>d21 OR
       abs(l.stock_entry_open-102)>1e-9 OR abs(l.stock_exit_close-143)>1e-9 OR
       abs(l.stock_return-(143.0/102.0-1))>1e-12 THEN
        RAISE EXCEPTION '20-session label has wrong session offsets or return';
    END IF;

    -- Add a deliberately synthetic action factor inside the 5-session label
    -- span. The surrounding transaction rolls this override back.
    INSERT INTO core.vndirect_reference_adjustment_overrides(
        symbol_id,trade_date,source,reference_adjustment_ratio,
        resolution_kind,evidence_url,evidence_note
    ) VALUES (
        ready_id,d3,'vndirect',action_ratio,'CORPORATE_ACTION',
        'https://example.invalid/synthetic-phase2-action-factor',
        'Synthetic-only Phase 2 corporate-action factor assertion; not market evidence'
    )
    ON CONFLICT(symbol_id,trade_date,source) DO UPDATE SET
        reference_adjustment_ratio=EXCLUDED.reference_adjustment_ratio,
        resolution_kind=EXCLUDED.resolution_kind,
        evidence_url=EXCLUDED.evidence_url,
        evidence_note=EXCLUDED.evidence_note;
    PERFORM feat.build_labels(d0,d0);
    SELECT o INTO expected_entry_open
      FROM core.vndirect_bars_as_of_with_episodes(ready_id,d6)
     WHERE trade_date=d1;
    SELECT c INTO expected_exit_close
      FROM core.vndirect_bars_as_of_with_episodes(ready_id,d6)
     WHERE trade_date=d6;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=ready_id AND signal_date=d0 AND horizon_sessions=5
       AND label_version='close-next-open-v1';
    IF NOT FOUND OR l.label_status<>'READY' OR
       abs(l.factor_log_span-ln(action_ratio))>1e-12 OR
       abs(l.stock_entry_open-expected_entry_open)>1e-9 OR
       abs(l.stock_exit_close-expected_exit_close)>1e-9 OR
       abs(l.stock_return-(expected_exit_close/expected_entry_open-1))>1e-12 THEN
        RAISE EXCEPTION 'corporate-action label factor or as-of endpoint prices do not reconcile';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=entry_id AND signal_date=d0 AND horizon_sessions=5;
    IF NOT FOUND OR l.label_status<>'SUSPENDED_ENTRY' OR l.stock_return IS NOT NULL THEN
        RAISE EXCEPTION 'zero-volume entry was treated as executable';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=exit_id AND signal_date=d0 AND horizon_sessions=5;
    IF NOT FOUND OR l.label_status<>'SUSPENDED_EXIT' OR l.stock_return IS NOT NULL THEN
        RAISE EXCEPTION 'zero-volume exit was treated as executable';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=missing_id AND signal_date=d0 AND horizon_sessions=5;
    IF NOT FOUND OR l.label_status<>'MISSING_ENTRY' OR l.stock_return IS NOT NULL THEN
        RAISE EXCEPTION 'missing ticker entry bar did not fail closed';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=gap_id AND signal_date=d0 AND horizon_sessions=5;
    IF NOT FOUND OR l.label_status<>'MISSING_SESSION' OR l.entry_date<>d1 OR l.exit_date<>d6 OR
       l.stock_return IS NOT NULL OR l.excess_return IS NOT NULL THEN
        RAISE EXCEPTION 'label with valid endpoints and a missing interior session did not fail closed';
    END IF;
    IF (SELECT count(*) FROM feat.labels_daily
         WHERE symbol_id=gap_id AND signal_date=d253 AND horizon_sessions=5
           AND label_version='close-next-open-v1' AND label_status='READY')<>1
       OR EXISTS (SELECT 1 FROM feat.phase2_training_eligible_v3
                   WHERE symbol_id=gap_id AND signal_date=d253 AND horizon_sessions=5)
       OR NOT EXISTS (SELECT 1 FROM feat.phase2_training_eligible_v3
                       WHERE symbol_id=gap_id AND signal_date=d254 AND horizon_sessions=5) THEN
        RAISE EXCEPTION 'Phase 3 eligibility must exclude the first 250 sessions after a gap and admit the first later READY row';
    END IF;
    SELECT * INTO l FROM feat.labels_daily
     WHERE symbol_id=episode_id AND signal_date=d0 AND horizon_sessions=5;
    IF NOT FOUND OR l.label_status<>'EPISODE_CHANGED' OR l.stock_return IS NOT NULL THEN
        RAISE EXCEPTION 'label crossed a documented delist/relist episode boundary';
    END IF;

    IF EXISTS (
        SELECT 1 FROM feat.labels_daily
        WHERE signal_date=dlast AND label_version='close-next-open-v1'
          AND label_status<>'INSUFFICIENT_SESSIONS'
    ) OR (SELECT count(*) FROM feat.labels_daily
           WHERE signal_date=dlast AND label_version='close-next-open-v1')<>16 THEN
        RAISE EXCEPTION 'insufficient future calendar sessions did not produce missing-session labels';
    END IF;
END $$;
DO $$
DECLARE
    fixture_rows bigint;
    mismatches bigint;
BEGIN
    SELECT count(*) INTO fixture_rows FROM phase2_recursive_ema_golden;
    IF fixture_rows<>430 THEN
        RAISE EXCEPTION 'pandas recursive-feature golden fixture has % rows, expected 430',fixture_rows;
    END IF;

    WITH inputs AS (
        SELECT g.*,
               row_number() OVER(PARTITION BY episode ORDER BY step) AS episode_step,
               count(*) FILTER(WHERE traded) OVER(PARTITION BY episode ORDER BY step
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS ema_count,
               CASE WHEN row_number() OVER(PARTITION BY episode ORDER BY step)=1 OR traded
                    THEN close END AS ema_input
        FROM phase2_recursive_ema_golden g
    ), ema_state AS (
        SELECT i.*,
               feat.ema(i.ema_input,2.0/6) OVER w AS ema5,
               feat.ema(i.ema_input,2.0/11) OVER w AS ema10,
               feat.ema(i.ema_input,2.0/21) OVER w AS ema20,
               feat.ema(i.ema_input,2.0/51) OVER w AS ema50,
               feat.ema(i.ema_input,2.0/101) OVER w AS ema100,
               feat.ema(i.ema_input,2.0/201) OVER w AS ema200,
               feat.ema(i.ema_input,2.0/13) OVER w AS ema12,
               feat.ema(i.ema_input,2.0/27) OVER w AS ema26
        FROM inputs i
        WINDOW w AS (PARTITION BY i.episode ORDER BY i.step
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
    ), macd_state AS (
        SELECT e.*,
               feat.ema(CASE WHEN e.traded AND e.ema_count>=26 THEN e.ema12-e.ema26 END,0.2)
                   OVER(PARTITION BY e.episode ORDER BY e.step
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS macd_signal,
               count(*) FILTER(WHERE e.traded AND e.ema_count>=26)
                   OVER(PARTITION BY e.episode ORDER BY e.step
                        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS macd_count
        FROM ema_state e
    ), actual AS (
        SELECT m.episode,m.step,
               CASE WHEN m.traded AND m.ema_count>=5 AND m.ema5>0 THEN m.close/m.ema5-1 END AS ema_5_ratio,
               CASE WHEN m.traded AND m.ema_count>=10 AND m.ema10>0 THEN m.close/m.ema10-1 END AS ema_10_ratio,
               CASE WHEN m.traded AND m.ema_count>=20 AND m.ema20>0 THEN m.close/m.ema20-1 END AS ema_20_ratio,
               CASE WHEN m.traded AND m.ema_count>=50 AND m.ema50>0 THEN m.close/m.ema50-1 END AS ema_50_ratio,
               CASE WHEN m.traded AND m.ema_count>=100 AND m.ema100>0 THEN m.close/m.ema100-1 END AS ema_100_ratio,
               CASE WHEN m.traded AND m.ema_count>=200 AND m.ema200>0 THEN m.close/m.ema200-1 END AS ema_200_ratio,
               CASE WHEN m.traded AND m.ema_count>=26 AND m.macd_count>=9 AND m.close>0
                    THEN ((m.ema12-m.ema26)-m.macd_signal)/m.close END AS macd_histogram_pct
        FROM macd_state m
    ), compared AS (
        SELECT a.episode,a.step,p.actual_value,p.expected_value
        FROM actual a
        JOIN phase2_recursive_ema_golden g USING(episode,step)
        CROSS JOIN LATERAL (VALUES
            (a.ema_5_ratio,g.ema_5_ratio),
            (a.ema_10_ratio,g.ema_10_ratio),
            (a.ema_20_ratio,g.ema_20_ratio),
            (a.ema_50_ratio,g.ema_50_ratio),
            (a.ema_100_ratio,g.ema_100_ratio),
            (a.ema_200_ratio,g.ema_200_ratio),
            (a.macd_histogram_pct,g.macd_histogram_pct)
        ) p(actual_value,expected_value)
    )
    SELECT count(*) FILTER(WHERE
               (actual_value IS NULL)<>(expected_value IS NULL) OR
               (actual_value IS NOT NULL AND expected_value IS NOT NULL AND
                abs(actual_value-expected_value)>1e-12*greatest(1.0,abs(expected_value))))
      INTO mismatches
    FROM compared;
    IF mismatches<>0 THEN
        RAISE EXCEPTION 'SQL recursive features differ from the pandas golden fixture on % feature rows',mismatches;
    END IF;
END $$;
ROLLBACK;

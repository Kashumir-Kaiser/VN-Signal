-- End-to-end recursive feature golden for the production V2/V3 builder.
-- Run after migrations and phase2_feature_fixture.sql, in a disposable test DB.
-- The entire feature rebuild and assertion is rolled back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='10min';
CREATE TEMP TABLE phase2_recursive_builder_golden (
    step integer PRIMARY KEY,
    open double precision NOT NULL,
    high double precision NOT NULL,
    low double precision NOT NULL,
    close double precision NOT NULL,
    traded boolean NOT NULL,
    ema_5_ratio double precision,
    ema_10_ratio double precision,
    ema_20_ratio double precision,
    ema_50_ratio double precision,
    ema_100_ratio double precision,
    ema_200_ratio double precision,
    macd_histogram_pct double precision,
    rsi_14 double precision,
    atr_pct_14 double precision,
    adx_14_sma double precision,
    trade_date date
) ON COMMIT DROP;
\copy phase2_recursive_builder_golden FROM 'tests/golden/phase2_recursive_builder_golden.csv' WITH (FORMAT csv, HEADER true, NULL '')

DO $$
DECLARE
    db_name text:=current_database();
    ready_id bigint;
    gold_id bigint;
    zero_id bigint;
    missing_id bigint;
    episode_id bigint;
    first_date date;
    last_date date;
    session_count bigint;
    feature_rows bigint;
    input_mismatches bigint;
    feature_mismatches bigint;
    snapshot_count bigint;
    output_count bigint;
    period_start date;
    period_end date;
    mismatch_rows bigint;
    year_impl text;
BEGIN
    IF db_name<>'vnsignal_test' AND db_name !~ '^vnsignal_phase2_[[:alnum:]_]+_disposable$' THEN
        RAISE EXCEPTION 'recursive builder golden is restricted to a disposable test database; got %',db_name;
    END IF;

    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2GOLD','HOSE','2098-01-05+07','2099-05-01+07')
    ON CONFLICT(symbol) DO NOTHING;

    -- Keep the synthetic series adjustment-neutral: HOSE basicPrice references
    -- the previous close. Setting it to today's close would create a fictitious
    -- daily corporate action and collapse model-neutral prices to a flat series.
    WITH fixture_rows AS (
        SELECT g.*,lag(g.close) OVER(ORDER BY g.step) AS previous_close
        FROM phase2_recursive_builder_golden g
    ), payload AS (
        SELECT jsonb_build_object('data',jsonb_agg(
            jsonb_build_object(
                'code','P2GOLD','date',to_char(g.trade_date,'YYYY-MM-DD'),
                'open',g.open,'high',g.high,'low',g.low,'close',g.close,
                'volume',CASE WHEN g.traded THEN 1000.0 ELSE 0.0 END,
                'basicPrice',coalesce(g.previous_close,g.close),
                'average',CASE WHEN g.traded THEN g.close ELSE 0.0 END,
                'floor','HOSE','adOpen',g.open,'adHigh',g.high,'adLow',g.low,'adClose',g.close
            ) ORDER BY g.step
        )) AS body
        FROM fixture_rows g
    ), landing AS (
        INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
        SELECT '20000000-0000-4000-8000-000000000212','vndirect','equity_ohlcv',
               '2099-05-01 10:00:00+07','P2GOLD',p.body,
               encode(sha256(convert_to(p.body::text,'UTF8')),'hex'),
               convert_to(p.body::text,'UTF8')
        FROM payload p
        RETURNING landing_id,ingest_id,fetched_at,symbol,payload
    )
    INSERT INTO core.bars_daily_sources
        (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,
         ingest_id,fetched_at,adjusted_o,adjusted_h,adjusted_l,adjusted_c,adjustment_vintage_at,
         basic_price,average_price,exchange_code)
    SELECT s.symbol_id,(x.item->>'date')::date,'vndirect',
           (x.item->>'open')::double precision,(x.item->>'high')::double precision,
           (x.item->>'low')::double precision,(x.item->>'close')::double precision,
           (x.item->>'volume')::double precision,'unadjusted',
           (x.item->>'volume')::double precision>0,
           l.landing_id,(x.ordinality-1)::integer,l.ingest_id,l.fetched_at,
           (x.item->>'open')::double precision,(x.item->>'high')::double precision,
           (x.item->>'low')::double precision,(x.item->>'close')::double precision,l.fetched_at,
           (x.item->>'basicPrice')::double precision,(x.item->>'average')::double precision,'HOSE'
    FROM landing l
    CROSS JOIN LATERAL jsonb_array_elements(l.payload->'data') WITH ORDINALITY AS x(item,ordinality)
    JOIN core.symbols s ON s.symbol=l.symbol;

    SELECT symbol_id INTO ready_id FROM core.symbols WHERE symbol='P2READY';
    SELECT symbol_id INTO gold_id FROM core.symbols WHERE symbol='P2GOLD';
    SELECT symbol_id INTO zero_id FROM core.symbols WHERE symbol='P2ZERO';
    SELECT symbol_id INTO missing_id FROM core.symbols WHERE symbol='P2MISS';
    SELECT symbol_id INTO episode_id FROM core.symbols WHERE symbol='P2EPISODE';
    SELECT min(trade_date),max(trade_date),count(*)
      INTO first_date,last_date,session_count
      FROM core.calendar WHERE source='phase2_test_fixture' AND is_session;
    IF ready_id IS NULL OR gold_id IS NULL OR zero_id IS NULL OR missing_id IS NULL OR episode_id IS NULL
       OR session_count<>320 OR first_date IS NULL OR last_date IS NULL THEN
        RAISE EXCEPTION 'the committed recursive-builder 320-session fixture is required';
    END IF;

    year_impl:=pg_get_functiondef(
        'feat.build_price_features_v3_year_impl(date,date,bigint[],date)'::regprocedure
    );
    IF position('WHERE trade_date<p_history_from AND is_session' IN year_impl)=0 OR
       position('prior_no<=1000' IN year_impl)=0 OR
       position('BETWEEN p_history_from AND p_date_to AND is_session' IN year_impl)=0 THEN
        RAISE EXCEPTION 'year implementation no longer uses exactly the bounded effective-session anchor';
    END IF;

    PERFORM feat.build_features(first_date,last_date);

    WITH sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS step
        FROM core.calendar WHERE source='phase2_test_fixture' AND is_session
    ), observed AS (
        SELECT s.step,s.trade_date,b.o AS source_open,b.h AS source_high,
               b.l AS source_low,b.c AS source_close,b.is_traded,
               f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,
               f.macd_histogram_pct,f.rsi_14,f.atr_pct_14,f.adx_14_sma
        FROM sessions s
        JOIN core.bars_daily_sources b
          ON b.symbol_id=gold_id AND b.trade_date=s.trade_date AND b.source='vndirect'
        JOIN feat.features_daily f
          ON f.symbol_id=gold_id AND f.trade_date=s.trade_date AND f.feature_version='phase2-v3'
    )
    SELECT count(*),count(*) FILTER(
        WHERE o.source_open IS DISTINCT FROM g.open OR o.source_high IS DISTINCT FROM g.high
           OR o.source_low IS DISTINCT FROM g.low OR o.source_close IS DISTINCT FROM g.close
           OR o.is_traded IS DISTINCT FROM g.traded
           OR o.trade_date IS DISTINCT FROM g.trade_date)
      INTO feature_rows,input_mismatches
      FROM observed o JOIN phase2_recursive_builder_golden g USING(step);
    IF feature_rows<>320 OR input_mismatches<>0 THEN
        RAISE EXCEPTION 'P2GOLD builder inputs/rows differ from the pandas fixture: rows %, input mismatches %',
            feature_rows,input_mismatches;
    END IF;

    WITH sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS step
        FROM core.calendar WHERE source='phase2_test_fixture' AND is_session
    ), observed AS (
        SELECT s.step,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,
               f.rsi_14,f.atr_pct_14,f.adx_14_sma
        FROM sessions s
        JOIN feat.features_daily f
          ON f.symbol_id=gold_id AND f.trade_date=s.trade_date AND f.feature_version='phase2-v3'
    ), compared AS (
        SELECT a.step,v.feature,v.actual_value,v.expected_value
        FROM observed a
        JOIN phase2_recursive_builder_golden g USING(step)
        CROSS JOIN LATERAL (VALUES
            ('ema_5_ratio',a.ema_5_ratio,g.ema_5_ratio),
            ('ema_10_ratio',a.ema_10_ratio,g.ema_10_ratio),
            ('ema_20_ratio',a.ema_20_ratio,g.ema_20_ratio),
            ('ema_50_ratio',a.ema_50_ratio,g.ema_50_ratio),
            ('ema_100_ratio',a.ema_100_ratio,g.ema_100_ratio),
            ('ema_200_ratio',a.ema_200_ratio,g.ema_200_ratio),
            ('macd_histogram_pct',a.macd_histogram_pct,g.macd_histogram_pct),
            ('rsi_14',a.rsi_14,g.rsi_14),
            ('atr_pct_14',a.atr_pct_14,g.atr_pct_14),
            ('adx_14_sma',a.adx_14_sma,g.adx_14_sma)
        ) v(feature,actual_value,expected_value)
    )
    SELECT count(*) FILTER(WHERE
        (actual_value IS NULL)<>(expected_value IS NULL) OR
        (actual_value IS NOT NULL AND expected_value IS NOT NULL AND
         abs(actual_value-expected_value)>1e-12))
      INTO feature_mismatches
      FROM compared;
    IF feature_mismatches<>0 THEN
        RAISE EXCEPTION 'production V3 recursive builder differs from pandas golden on % values/null masks',
            feature_mismatches;
    END IF;

    IF (SELECT f.ema_5_ratio FROM feat.features_daily f
        WHERE f.symbol_id=zero_id AND f.trade_date=(
            SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture'
            ORDER BY trade_date OFFSET 1 LIMIT 1
        ) AND f.feature_version='phase2-v3') IS NOT NULL OR
       (SELECT f.ema_5_ratio FROM feat.features_daily f
        WHERE f.symbol_id=zero_id AND f.trade_date=(
            SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture'
            ORDER BY trade_date OFFSET 29 LIMIT 1
        ) AND f.feature_version='phase2-v3') IS NULL THEN
        RAISE EXCEPTION 'zero-volume rows must carry state without counting as traded EMA warmup sessions';
    END IF;
    IF (SELECT f.ema_5_ratio FROM feat.features_daily f
        WHERE f.symbol_id=missing_id AND f.trade_date=(
            SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture'
            ORDER BY trade_date OFFSET 6 LIMIT 1
        ) AND f.feature_version='phase2-v3') IS NOT NULL THEN
        RAISE EXCEPTION 'missing-bar sessions must not count toward EMA warmup';
    END IF;
    IF (SELECT f.ema_5_ratio FROM feat.features_daily f
        WHERE f.symbol_id=episode_id AND f.trade_date=(
            SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture'
            ORDER BY trade_date OFFSET 6 LIMIT 1
        ) AND f.feature_version='phase2-v3') IS NOT NULL THEN
        RAISE EXCEPTION 'episode restart must clear recursive EMA warmup state';
    END IF;

    IF (SELECT count(*) FILTER (WHERE NOT traded) FROM phase2_recursive_builder_golden)<>1 THEN
        RAISE EXCEPTION 'P2GOLD must contain exactly one zero-volume carried-price session';
    END IF;

    IF EXISTS (
        SELECT 1 FROM feat.features_daily f
        WHERE f.symbol_id=gold_id AND f.trade_date BETWEEN first_date AND last_date
          AND f.feature_version='phase2-v3' AND f.intraday_realized_variance IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'source-dependent intraday variance must remain NULL without audited intraday evidence';
    END IF;

    CREATE TEMP TABLE phase2_recursive_builder_snapshot ON COMMIT DROP AS
    SELECT f.trade_date,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
           f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,
           f.rsi_14,f.atr_pct_14,f.adx_14_sma
    FROM feat.features_daily f
    WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
      AND f.trade_date BETWEEN first_date AND last_date;

    FOR period_start,period_end IN
        SELECT min(trade_date),max(trade_date)
        FROM core.calendar
        WHERE source='phase2_test_fixture' AND is_session
        GROUP BY date_trunc('year',trade_date::timestamp)
        ORDER BY min(trade_date)
    LOOP
        PERFORM feat.build_features(period_start,period_end);
    END LOOP;
    SELECT count(*) INTO snapshot_count FROM phase2_recursive_builder_snapshot;
    SELECT count(*) INTO output_count FROM feat.features_daily f
    WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
      AND f.trade_date BETWEEN first_date AND last_date;
    SELECT count(*) INTO mismatch_rows
    FROM phase2_recursive_builder_snapshot s
    FULL JOIN (
        SELECT f.trade_date,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,
               f.rsi_14,f.atr_pct_14,f.adx_14_sma
        FROM feat.features_daily f
        WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
          AND f.trade_date BETWEEN first_date AND last_date
    ) f ON f.trade_date=s.trade_date
    WHERE s.trade_date IS NULL OR f.trade_date IS NULL OR
       ROW(f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,f.ema_50_ratio,
           f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,f.rsi_14,
           f.atr_pct_14,f.adx_14_sma)
       IS DISTINCT FROM
          ROW(s.ema_5_ratio,s.ema_10_ratio,s.ema_20_ratio,s.ema_50_ratio,
              s.ema_100_ratio,s.ema_200_ratio,s.macd_histogram_pct,s.rsi_14,
              s.atr_pct_14,s.adx_14_sma);
    IF mismatch_rows<>0 OR snapshot_count<>output_count THEN
        RAISE EXCEPTION 'annual production builds changed % rows (snapshot %, rebuilt %)',
            mismatch_rows,snapshot_count,output_count;
    END IF;

    -- Rebuilding the same outputs by calendar month and quarter must be
    -- invariant with the full-range build above (including the 2099 anchor).
    FOR period_start,period_end IN
        SELECT min(trade_date),max(trade_date)
        FROM core.calendar
        WHERE source='phase2_test_fixture' AND is_session
        GROUP BY date_trunc('month',trade_date::timestamp)
        ORDER BY min(trade_date)
    LOOP
        PERFORM feat.build_features(period_start,period_end);
    END LOOP;
    SELECT count(*) INTO snapshot_count FROM phase2_recursive_builder_snapshot;
    SELECT count(*) INTO output_count FROM feat.features_daily f
    WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
      AND f.trade_date BETWEEN first_date AND last_date;
    SELECT count(*) INTO mismatch_rows
    FROM phase2_recursive_builder_snapshot s
    FULL JOIN (
        SELECT f.trade_date,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,
               f.rsi_14,f.atr_pct_14,f.adx_14_sma
        FROM feat.features_daily f
        WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
          AND f.trade_date BETWEEN first_date AND last_date
    ) f ON f.trade_date=s.trade_date
    WHERE s.trade_date IS NULL OR f.trade_date IS NULL OR
       ROW(f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,f.ema_50_ratio,
           f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,f.rsi_14,
           f.atr_pct_14,f.adx_14_sma)
       IS DISTINCT FROM
          ROW(s.ema_5_ratio,s.ema_10_ratio,s.ema_20_ratio,s.ema_50_ratio,
              s.ema_100_ratio,s.ema_200_ratio,s.macd_histogram_pct,s.rsi_14,
              s.atr_pct_14,s.adx_14_sma);
    IF mismatch_rows<>0 OR snapshot_count<>output_count THEN
        RAISE EXCEPTION 'monthly production builds changed % rows (snapshot %, rebuilt %)',
            mismatch_rows,snapshot_count,output_count;
    END IF;

    FOR period_start,period_end IN
        SELECT min(trade_date),max(trade_date)
        FROM core.calendar
        WHERE source='phase2_test_fixture' AND is_session
        GROUP BY date_trunc('quarter',trade_date::timestamp)
        ORDER BY min(trade_date)
    LOOP
        PERFORM feat.build_features(period_start,period_end);
    END LOOP;
    SELECT count(*) INTO snapshot_count FROM phase2_recursive_builder_snapshot;
    SELECT count(*) INTO output_count FROM feat.features_daily f
    WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
      AND f.trade_date BETWEEN first_date AND last_date;
    SELECT count(*) INTO mismatch_rows
    FROM phase2_recursive_builder_snapshot s
    FULL JOIN (
        SELECT f.trade_date,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,
               f.rsi_14,f.atr_pct_14,f.adx_14_sma
        FROM feat.features_daily f
        WHERE f.symbol_id=gold_id AND f.feature_version='phase2-v3'
          AND f.trade_date BETWEEN first_date AND last_date
    ) f ON f.trade_date=s.trade_date
    WHERE s.trade_date IS NULL OR f.trade_date IS NULL OR
       ROW(f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,f.ema_50_ratio,
           f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct,f.rsi_14,
           f.atr_pct_14,f.adx_14_sma)
       IS DISTINCT FROM
          ROW(s.ema_5_ratio,s.ema_10_ratio,s.ema_20_ratio,s.ema_50_ratio,
              s.ema_100_ratio,s.ema_200_ratio,s.macd_histogram_pct,s.rsi_14,
              s.atr_pct_14,s.adx_14_sma);
    IF mismatch_rows<>0 OR snapshot_count<>output_count THEN
        RAISE EXCEPTION 'quarterly production builds changed % rows (snapshot %, rebuilt %)',
            mismatch_rows,snapshot_count,output_count;
    END IF;
END $$;

ROLLBACK;

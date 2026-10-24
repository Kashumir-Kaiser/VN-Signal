-- End-to-end recursive feature golden for the production V2/V3 builder.
-- Run after migrations and phase2_feature_fixture.sql, in a disposable test DB.
-- The entire feature rebuild and assertion is rolled back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='10min';
CREATE TEMP TABLE phase2_recursive_builder_golden (
    step integer PRIMARY KEY,
    close double precision NOT NULL,
    traded boolean NOT NULL,
    ema_5_ratio double precision,
    ema_10_ratio double precision,
    ema_20_ratio double precision,
    ema_50_ratio double precision,
    ema_100_ratio double precision,
    ema_200_ratio double precision,
    macd_histogram_pct double precision
) ON COMMIT DROP;
\copy phase2_recursive_builder_golden FROM 'tests/golden/phase2_recursive_builder_golden.csv' WITH (FORMAT csv, HEADER true, NULL '')

DO $$
DECLARE
    db_name text:=current_database();
    ready_id bigint;
    first_date date;
    last_date date;
    session_count bigint;
    feature_rows bigint;
    input_mismatches bigint;
    feature_mismatches bigint;
BEGIN
    IF db_name<>'vnsignal_test' AND db_name !~ '^vnsignal_phase2_[[:alnum:]_]+_disposable$' THEN
        RAISE EXCEPTION 'recursive builder golden is restricted to a disposable test database; got %',db_name;
    END IF;

    SELECT symbol_id INTO ready_id FROM core.symbols WHERE symbol='P2READY';
    SELECT min(trade_date),max(trade_date),count(*)
      INTO first_date,last_date,session_count
      FROM core.calendar WHERE source='phase2_test_fixture' AND is_session;
    IF ready_id IS NULL OR session_count<>320 OR first_date IS NULL OR last_date IS NULL THEN
        RAISE EXCEPTION 'the committed P2READY 320-session fixture is required';
    END IF;

    PERFORM feat.build_features(first_date,last_date);

    WITH sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS step
        FROM core.calendar WHERE source='phase2_test_fixture' AND is_session
    ), observed AS (
        SELECT s.step,b.c AS source_close,b.is_traded,
               f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,
               f.macd_histogram_pct
        FROM sessions s
        JOIN core.bars_daily_sources b
          ON b.symbol_id=ready_id AND b.trade_date=s.trade_date AND b.source='vndirect'
        JOIN feat.features_daily f
          ON f.symbol_id=ready_id AND f.trade_date=s.trade_date AND f.feature_version='phase2-v3'
    )
    SELECT count(*),count(*) FILTER(
        WHERE o.source_close IS DISTINCT FROM g.close OR o.is_traded IS DISTINCT FROM g.traded)
      INTO feature_rows,input_mismatches
      FROM observed o JOIN phase2_recursive_builder_golden g USING(step);
    IF feature_rows<>320 OR input_mismatches<>0 THEN
        RAISE EXCEPTION 'P2READY builder inputs/rows differ from the pandas fixture: rows %, input mismatches %',
            feature_rows,input_mismatches;
    END IF;

    WITH sessions AS (
        SELECT trade_date,row_number() OVER(ORDER BY trade_date)::integer AS step
        FROM core.calendar WHERE source='phase2_test_fixture' AND is_session
    ), observed AS (
        SELECT s.step,f.ema_5_ratio,f.ema_10_ratio,f.ema_20_ratio,
               f.ema_50_ratio,f.ema_100_ratio,f.ema_200_ratio,f.macd_histogram_pct
        FROM sessions s
        JOIN feat.features_daily f
          ON f.symbol_id=ready_id AND f.trade_date=s.trade_date AND f.feature_version='phase2-v3'
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
            ('macd_histogram_pct',a.macd_histogram_pct,g.macd_histogram_pct)
        ) v(feature,actual_value,expected_value)
    )
    SELECT count(*) FILTER(WHERE
        (actual_value IS NULL)<>(expected_value IS NULL) OR
        (actual_value IS NOT NULL AND expected_value IS NOT NULL AND
         abs(actual_value-expected_value)>1e-12*greatest(1.0,abs(expected_value))))
      INTO feature_mismatches
      FROM compared;
    IF feature_mismatches<>0 THEN
        RAISE EXCEPTION 'production V3 recursive builder differs from pandas golden on % values/null masks',
            feature_mismatches;
    END IF;
END $$;

ROLLBACK;

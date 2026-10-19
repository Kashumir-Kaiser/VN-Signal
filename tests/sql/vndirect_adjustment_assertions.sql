DO $$
DECLARE
    sid bigint;
    dividend_sid bigint;
    normalized_previous_close double precision;
    row_count integer;
    partial_snapshot_rejected boolean := false;
BEGIN
    SELECT symbol_id INTO sid FROM core.symbols WHERE symbol='TSTADJ';
    IF sid IS NULL THEN RAISE EXCEPTION 'VNDIRECT adjusted-price fixture symbol is missing'; END IF;

    IF NOT EXISTS (
        SELECT 1 FROM core.bars_daily_sources
        WHERE symbol_id=sid AND trade_date='2024-11-29' AND source='vndirect'
          AND c=100 AND adjusted_c=75
          AND adjustment_vintage_at='2026-10-18 10:00:00+07'
    ) THEN
        RAISE EXCEPTION 'VNDIRECT backfill did not preserve raw close and materialize adjusted close with landing vintage';
    END IF;

    SELECT count(*),max(c) FILTER (WHERE trade_date='2024-11-29')
    INTO row_count,normalized_previous_close
    FROM core.vndirect_bars_as_of(sid,'2024-12-02');
    IF row_count <> 2 OR abs(normalized_previous_close-100)>0.000001 THEN
        RAISE EXCEPTION 'as-of history failed to remove adjustment after the requested date: rows %, prior close %',
            row_count,normalized_previous_close;
    END IF;

    SELECT symbol_id INTO dividend_sid FROM core.symbols WHERE symbol='TSTDIV';
    IF dividend_sid IS NULL THEN RAISE EXCEPTION 'VNDIRECT dividend-adjustment fixture symbol is missing'; END IF;

    SELECT c INTO normalized_previous_close
    FROM core.vndirect_bars_as_of(dividend_sid,'2023-03-29')
    WHERE trade_date='2023-03-29';
    IF normalized_previous_close IS NULL OR abs(normalized_previous_close-68)>0.000001 THEN
        RAISE EXCEPTION 'as-of date before ex-right must retain the traded close; got %',normalized_previous_close;
    END IF;

    SELECT c INTO normalized_previous_close
    FROM core.vndirect_bars_as_of(dividend_sid,'2023-03-30')
    WHERE trade_date='2023-03-29';
    IF normalized_previous_close IS NULL OR abs(normalized_previous_close-33)>0.01 THEN
        RAISE EXCEPTION 'cash-dividend ex-right must adjust prior close to the 33.0 reference price; got %',normalized_previous_close;
    END IF;

    SELECT count(*),max(c) FILTER (WHERE trade_date='2023-03-29')
    INTO row_count,normalized_previous_close
    FROM core.vndirect_bars_as_of(dividend_sid,'2026-10-16');
    IF row_count <> 3 OR abs(normalized_previous_close-10.01)>0.000001 THEN
        RAISE EXCEPTION 'latest same-vintage snapshot did not retain full adjusted dividend history: rows %, close %',
            row_count,normalized_previous_close;
    END IF;

    SELECT count(*),max(c) FILTER (WHERE trade_date='2023-03-29')
    INTO row_count,normalized_previous_close
    FROM core.vndirect_bars_as_of('2023-03-30')
    WHERE symbol_id=dividend_sid;
    IF row_count <> 2 OR abs(normalized_previous_close-33)>0.01 OR NOT EXISTS (
        SELECT 1 FROM core.vndirect_bars_as_of('2023-03-30')
        WHERE symbol_id=dividend_sid AND trade_date='2023-03-29'
          AND price_basis='adjusted_as_of' AND is_traded
    ) THEN
        RAISE EXCEPTION 'bulk Phase 2 price function failed to return dividend-adjusted history: rows %, prior close %',
            row_count,normalized_previous_close;
    END IF;

    INSERT INTO ops.ml_symbol_scope(symbol_id,scope_status,scope_reason,decision_ref)
    VALUES (dividend_sid,'EXCLUDED','test-only scope exclusion','test fixture');
    IF EXISTS (
        SELECT 1 FROM core.vndirect_bars_as_of(dividend_sid,'2026-10-16')
    ) OR EXISTS (
        SELECT 1 FROM core.vndirect_bars_as_of('2026-10-16')
        WHERE symbol_id=dividend_sid
    ) THEN
        RAISE EXCEPTION 'explicit Phase 2 symbol exclusion was ignored by a VNDIRECT as-of function';
    END IF;
    DELETE FROM ops.ml_symbol_scope WHERE symbol_id=dividend_sid;

    BEGIN
        INSERT INTO core.bars_daily_sources
            (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at,adjusted_o)
        SELECT sid,'2024-12-03','vndirect',74,75,73,74,1000,'unadjusted',true,
               landing_id,2,ingest_id,fetched_at,74
        FROM raw.landings WHERE ingest_id='00000000-0000-4000-8000-000000000066';
        RAISE EXCEPTION 'partial adjusted-price snapshot was accepted';
    EXCEPTION WHEN check_violation THEN
        partial_snapshot_rejected := true;
    END;
    IF NOT partial_snapshot_rejected THEN RAISE EXCEPTION 'partial adjusted-price snapshot was not rejected'; END IF;

    UPDATE core.bars_daily_sources
       SET adjustment_vintage_at='2026-10-19 10:00:00+07'
     WHERE symbol_id=sid AND trade_date='2024-11-29' AND source='vndirect';
    SELECT count(*) INTO row_count FROM core.vndirect_bars_as_of(sid,'2024-12-02');
    IF row_count <> 0 THEN RAISE EXCEPTION 'mixed adjustment vintages did not fail closed'; END IF;
END $$;

DO $$
DECLARE
    sid bigint;
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

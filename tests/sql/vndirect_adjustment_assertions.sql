DO $$
DECLARE
    sid bigint;
    dividend_sid bigint;
    upcom_sid bigint;
    carry_sid bigint;
    segment_sid bigint;
    model_bar_sid bigint;
    no_action_sid bigint;
    event_sid bigint;
    normalized_previous_close double precision;
    adjustment_ratio double precision;
    resolution_kind text;
    row_count integer;
    segment_count integer;
    segment_old_close double precision;
    segment_new_close double precision;
    model_open double precision;
    model_high double precision;
    model_low double precision;
    model_close double precision;
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
    IF row_count <> 2 OR abs(normalized_previous_close-99)>0.000001 THEN
        RAISE EXCEPTION 'as-of history failed to apply reference-price adjustment through the requested date: rows %, prior close %',
            row_count,normalized_previous_close;
    END IF;

    SELECT symbol_id INTO model_bar_sid FROM core.symbols WHERE symbol='TSTBAR';
    IF model_bar_sid IS NULL THEN RAISE EXCEPTION 'model-bar override fixture symbol is missing'; END IF;
    INSERT INTO core.vndirect_model_bar_overrides
        (symbol_id,trade_date,source,model_o,model_h,model_l,model_c,
         evidence_url,evidence_sha256,secondary_evidence_url,
         secondary_evidence_sha256,evidence_note)
    VALUES
        (model_bar_sid,'2024-01-02','vndirect',12,12.2,11.8,12.1,
         'https://example.invalid/test-model-bar','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
         'https://example.invalid/test-action','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
         'Synthetic test-only model OHLC override.');
    SELECT count(*),max(o) FILTER (WHERE trade_date='2024-01-02'),
           max(h) FILTER (WHERE trade_date='2024-01-02'),
           max(l) FILTER (WHERE trade_date='2024-01-02'),
           max(c) FILTER (WHERE trade_date='2024-01-02')
      INTO row_count,model_open,model_high,model_low,model_close
    FROM core.vndirect_bars_as_of(model_bar_sid,'2024-01-03');
    IF row_count<>2 OR abs(model_open-12)>0.000001 OR abs(model_high-12.2)>0.000001
       OR abs(model_low-11.8)>0.000001 OR abs(model_close-12.1)>0.000001 THEN
        RAISE EXCEPTION 'as-of ML series did not apply the evidence-linked model OHLC override: rows %, OHLC %/%/%/%',
            row_count,model_open,model_high,model_low,model_close;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.bars_daily_sources
        WHERE symbol_id=model_bar_sid AND trade_date='2024-01-02'
          AND source='vndirect' AND o=10 AND h=10.2 AND l=9.9 AND c=10
          AND v=1000 AND is_traded AND landing_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'model OHLC correction rewrote the raw source bar or its volume/lineage';
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
    IF row_count <> 3 OR abs(normalized_previous_close-33)>0.000001 THEN
        RAISE EXCEPTION 'reference-price history did not retain the full adjusted dividend history: rows %, close %',
            row_count,normalized_previous_close;
    END IF;

    SELECT symbol_id INTO upcom_sid FROM core.symbols WHERE symbol='TSTUPC';
    IF upcom_sid IS NULL THEN RAISE EXCEPTION 'VNDIRECT UPCoM reference fixture symbol is missing'; END IF;
    SELECT c INTO normalized_previous_close
    FROM core.vndirect_bars_as_of(upcom_sid,'2024-01-04')
    WHERE trade_date='2024-01-02';
    IF normalized_previous_close IS NULL OR abs(normalized_previous_close-(60.0/11.0))>0.000001 THEN
        RAISE EXCEPTION 'UPCoM reference adjustment did not use the last traded average across a zero-volume day: got %',normalized_previous_close;
    END IF;
    SELECT reference_adjustment_ratio INTO adjustment_ratio
    FROM core.vndirect_reference_adjustments
    WHERE symbol_id=upcom_sid AND trade_date='2024-01-03';
    IF adjustment_ratio IS NULL OR abs(adjustment_ratio-1)>0.000001 THEN
        RAISE EXCEPTION 'zero-volume UPCoM day created a false corporate-action factor: got %',adjustment_ratio;
    END IF;

    SELECT symbol_id INTO carry_sid FROM core.symbols WHERE symbol='TSTCARRY';
    IF carry_sid IS NULL THEN RAISE EXCEPTION 'VNDIRECT UPCoM carry fixture symbol is missing'; END IF;
    SELECT count(*),max(c) FILTER (WHERE trade_date='2024-01-02')
      INTO row_count,normalized_previous_close
    FROM core.vndirect_bars_as_of(carry_sid,'2024-01-08');
    IF row_count<>5 OR abs(normalized_previous_close-5)>0.000001 THEN
        RAISE EXCEPTION 'UPCoM action factor was not carried once across zero-volume sessions: rows %, adjusted prior close %',
            row_count,normalized_previous_close;
    END IF;
    IF (SELECT reference_adjustment_ratio FROM core.vndirect_reference_adjustments
        WHERE symbol_id=carry_sid AND trade_date='2024-01-03') IS DISTINCT FROM 0.5::double precision
       OR EXISTS (
        SELECT 1 FROM core.vndirect_reference_adjustments
        WHERE symbol_id=carry_sid AND trade_date IN ('2024-01-04','2024-01-05','2024-01-08')
          AND (reference_adjustment_ratio IS NULL OR abs(reference_adjustment_ratio-1)>0.000001)
       ) THEN
        RAISE EXCEPTION 'UPCoM no-match carry repeated or lost the one-time reference adjustment';
    END IF;

    SELECT symbol_id INTO segment_sid FROM core.symbols WHERE symbol='TSTSEG';
    IF segment_sid IS NULL THEN RAISE EXCEPTION 'VNDIRECT episode fixture symbol is missing'; END IF;
    SELECT count(*),count(DISTINCT episode_start_date),
           max(c) FILTER (WHERE trade_date='2024-01-02'),
           max(c) FILTER (WHERE trade_date='2024-01-05')
      INTO row_count,segment_count,segment_old_close,segment_new_close
    FROM core.vndirect_bars_as_of_with_episodes(segment_sid,'2024-01-08');
    IF row_count<>4 OR segment_count<>2 OR abs(segment_old_close-50)>0.000001
       OR abs(segment_new_close-20)>0.000001
       OR NOT EXISTS (
           SELECT 1 FROM core.vndirect_bars_as_of_with_episodes(segment_sid,'2024-01-08')
           WHERE trade_date='2024-01-02' AND episode_start_date='2024-01-02'
       ) OR NOT EXISTS (
           SELECT 1 FROM core.vndirect_bars_as_of_with_episodes(segment_sid,'2024-01-08')
           WHERE trade_date='2024-01-05' AND episode_start_date='2024-01-05'
       ) THEN
        RAISE EXCEPTION 'delist/relist episode boundary failed to preserve independent price bases: rows %, episodes %, old %, new %',
            row_count,segment_count,segment_old_close,segment_new_close;
    END IF;

    SELECT symbol_id INTO no_action_sid FROM core.symbols WHERE symbol='TSTREF';
    IF no_action_sid IS NULL THEN RAISE EXCEPTION '2019 no-action reference fixture symbol is missing'; END IF;
    SELECT r.reference_adjustment_ratio,o.resolution_kind
      INTO adjustment_ratio,resolution_kind
    FROM core.vndirect_reference_adjustments r
    JOIN core.vndirect_reference_adjustment_overrides o
      USING (symbol_id,trade_date,source)
    WHERE r.symbol_id=no_action_sid AND r.trade_date='2019-01-02';
    IF adjustment_ratio IS NULL OR abs(adjustment_ratio-1)>0.000001
       OR resolution_kind IS DISTINCT FROM 'NO_ACTION' THEN
        RAISE EXCEPTION 'audited no-action override did not resolve the missing source reference: ratio %, kind %',
            adjustment_ratio,resolution_kind;
    END IF;
    SELECT c INTO normalized_previous_close
    FROM core.vndirect_bars_as_of(no_action_sid,'2019-01-02')
    WHERE trade_date='2018-12-28';
    IF normalized_previous_close IS NULL OR abs(normalized_previous_close-10)>0.000001 THEN
        RAISE EXCEPTION 'no-action override changed the prior close: got %',normalized_previous_close;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.bars_daily_sources
        WHERE symbol_id=no_action_sid AND trade_date='2019-01-02'
          AND source='vndirect' AND basic_price=0
    ) THEN
        RAISE EXCEPTION 'no-action resolution rewrote or removed the raw zero basicPrice';
    END IF;

    SELECT symbol_id INTO event_sid FROM core.symbols WHERE symbol='DSN';
    IF event_sid IS NULL THEN RAISE EXCEPTION '2019 corporate-action fixture symbol is missing'; END IF;
    SELECT r.reference_adjustment_ratio,o.resolution_kind
      INTO adjustment_ratio,resolution_kind
    FROM core.vndirect_reference_adjustments r
    JOIN core.vndirect_reference_adjustment_overrides o
      USING (symbol_id,trade_date,source)
    WHERE r.symbol_id=event_sid AND r.trade_date='2019-01-02';
    IF adjustment_ratio IS NULL
       OR abs(adjustment_ratio-(59.3::double precision/62.9::double precision))>0.000000001
       OR resolution_kind IS DISTINCT FROM 'CORPORATE_ACTION' THEN
        RAISE EXCEPTION 'DSN 2019 cash-dividend override is incorrect: ratio %, kind %',
            adjustment_ratio,resolution_kind;
    END IF;
    SELECT c INTO normalized_previous_close
    FROM core.vndirect_bars_as_of(event_sid,'2019-01-02')
    WHERE trade_date='2018-12-28';
    IF normalized_previous_close IS NULL OR abs(normalized_previous_close-59.3)>0.000001 THEN
        RAISE EXCEPTION 'DSN pre-dividend close did not adjust to the 59.3 ex-right reference: got %',
            normalized_previous_close;
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.bars_daily_sources
        WHERE symbol_id=event_sid AND trade_date='2019-01-02'
          AND source='vndirect' AND basic_price=0
    ) THEN
        RAISE EXCEPTION 'DSN corporate-action resolution rewrote or removed the raw zero basicPrice';
    END IF;

    SELECT count(*),max(c) FILTER (WHERE trade_date='2023-03-29')
    INTO row_count,normalized_previous_close
    FROM core.vndirect_bars_as_of('2023-03-30')
    WHERE symbol_id=dividend_sid;
    IF row_count <> 2 OR abs(normalized_previous_close-33)>0.01 OR NOT EXISTS (
        SELECT 1 FROM core.vndirect_bars_as_of('2023-03-30')
        WHERE symbol_id=dividend_sid AND trade_date='2023-03-29'
          AND price_basis='adjusted_as_of_reference' AND is_traded
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
       SET basic_price=NULL
     WHERE symbol_id=sid AND trade_date='2024-12-02' AND source='vndirect';
    SELECT count(*) INTO row_count FROM core.vndirect_bars_as_of(sid,'2024-12-02');
    IF row_count <> 0 THEN RAISE EXCEPTION 'unresolved reference adjustment did not fail closed'; END IF;
    IF (SELECT count(*) FROM core.bars_daily_sources WHERE symbol_id=sid AND source='vndirect') <> 2 THEN
        RAISE EXCEPTION 'failed-closed as-of calculation deleted source observations';
    END IF;
END $$;

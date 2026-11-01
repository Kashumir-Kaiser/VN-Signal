\set ON_ERROR_STOP on
-- The Phase 2 feature rows here are synthetic fixtures. Confirm a monthly V3
-- chunk invalidates when an earlier V2 row in the same calendar year changes.
BEGIN;
DO $$
DECLARE
    chunk_from date:=DATE '2099-03-01';
    chunk_to date:=DATE '2099-03-31';
    v_symbol_id bigint;
    v_context_date date;
    v_original_return double precision;
    v_price_symbol_id bigint;
    v_price_date date;
    v_price_landing_id bigint;
    v_price_source_row integer;
    v_original_volume double precision;
    hash_before text;
    hash_changed text;
    hash_restored text;
    price_day_hash_before text;
    price_day_hash_changed text;
    price_day_hash_restored text;
    updated_rows bigint;
    hash_definition text;
    input_hash_changed text;
    input_hash_restored text;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM feat.features_daily f
         WHERE f.feature_version='phase2-v2'
           AND f.trade_date BETWEEN chunk_from AND chunk_to
    ) THEN
        RAISE EXCEPTION 'year-anchor manifest test requires March 2099 V2 fixture rows';
    END IF;

    SELECT f.symbol_id,f.trade_date,f.return_1d
      INTO v_symbol_id,v_context_date,v_original_return
      FROM feat.features_daily f
     WHERE f.feature_version='phase2-v2'
       AND f.trade_date>=DATE '2099-01-01'
       AND f.trade_date<chunk_from
     ORDER BY f.trade_date DESC,f.symbol_id
     LIMIT 1;
    IF v_symbol_id IS NULL OR v_context_date IS NULL THEN
        RAISE EXCEPTION 'year-anchor manifest test requires earlier 2099 V2 context';
    END IF;

    SELECT b.symbol_id,b.trade_date,b.landing_id,b.source_row,b.v
      INTO v_price_symbol_id,v_price_date,v_price_landing_id,v_price_source_row,v_original_volume
      FROM core.bars_daily_sources b
      JOIN core.symbols s USING(symbol_id)
      JOIN core.effective_trading_sessions ts
        ON ts.trade_date=b.trade_date AND ts.is_session
     WHERE s.symbol='P2READY' AND b.source='vndirect'
       AND b.trade_date<DATE '2099-01-01'
     ORDER BY b.trade_date DESC
     LIMIT 1;
    IF v_price_symbol_id IS NULL OR v_price_date IS NULL OR v_price_landing_id IS NULL THEN
        RAISE EXCEPTION 'year-anchor manifest test requires a synthetic raw-price warmup row';
    END IF;

    hash_definition:=pg_get_functiondef(
        'ops.phase2_chunk_input_hash(text,date,date)'::regprocedure
    );
    IF position('trade_date<v_year_anchor' IN hash_definition)=0
       OR position('v3_year_anchor=' IN hash_definition)=0
       OR position('v3_history_from=' IN hash_definition)=0
       OR position('trade_date BETWEEN v_year_anchor AND p_date_to' IN hash_definition)=0
       OR position('CASE WHEN p_stage=''features'' THEN ''3'' WHEN p_stage=''labels'' THEN ''4'' ELSE ''2'' END' IN hash_definition)=0 THEN
        RAISE EXCEPTION 'Phase 2 input hash does not declare the V3 year anchor, warmup, and independent feature/label stage domains';
    END IF;

    hash_before:=ops.phase2_chunk_input_hash('features',chunk_from,chunk_to);
    IF NOT EXISTS (
        SELECT 1 FROM pg_temp.phase2_price_day_hash_coverage
         WHERE trade_date=v_price_date
    ) THEN
        RAISE EXCEPTION 'selected synthetic raw-price row is outside the V3 pre-anchor hash window';
    END IF;

    SELECT day_sha256 INTO price_day_hash_before
      FROM pg_temp.phase2_price_day_hashes
     WHERE trade_date=v_price_date;
    UPDATE core.bars_daily_sources
       SET v=v+1
     WHERE symbol_id=v_price_symbol_id AND trade_date=v_price_date
       AND landing_id=v_price_landing_id AND source_row=v_price_source_row
       AND source='vndirect';
    GET DIAGNOSTICS updated_rows=ROW_COUNT;
    IF updated_rows<>1 THEN
        RAISE EXCEPTION 'year-anchor test did not modify exactly one raw-price warmup row';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    input_hash_changed:=ops.phase2_chunk_input_hash('features',chunk_from,chunk_to);
    IF input_hash_changed IS NOT DISTINCT FROM hash_before THEN
        RAISE EXCEPTION 'a raw price input in the pre-anchor EMA/MACD warmup was omitted from the V3 chunk hash';
    END IF;
    SELECT day_sha256 INTO price_day_hash_changed
      FROM pg_temp.phase2_price_day_hashes
     WHERE trade_date=v_price_date;
    IF price_day_hash_changed IS NOT DISTINCT FROM price_day_hash_before THEN
        RAISE EXCEPTION 'changing the synthetic raw-price warmup did not change its daily source hash';
    END IF;

    UPDATE core.bars_daily_sources
       SET v=v_original_volume
     WHERE symbol_id=v_price_symbol_id AND trade_date=v_price_date
       AND landing_id=v_price_landing_id AND source_row=v_price_source_row
       AND source='vndirect';
    GET DIAGNOSTICS updated_rows=ROW_COUNT;
    IF updated_rows<>1 THEN
        RAISE EXCEPTION 'year-anchor test did not restore exactly one raw-price warmup row';
    END IF;
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    input_hash_restored:=ops.phase2_chunk_input_hash('features',chunk_from,chunk_to);
    IF input_hash_restored IS DISTINCT FROM hash_before THEN
        RAISE EXCEPTION 'restoring the raw-price warmup input did not restore the original chunk hash';
    END IF;
    SELECT day_sha256 INTO price_day_hash_restored
      FROM pg_temp.phase2_price_day_hashes
     WHERE trade_date=v_price_date;
    IF price_day_hash_restored IS DISTINCT FROM price_day_hash_before THEN
        RAISE EXCEPTION 'restoring the raw-price warmup input did not restore its daily source hash';
    END IF;

    UPDATE feat.features_daily
       SET return_1d=coalesce(return_1d,0)+0.125
     WHERE symbol_id=v_symbol_id AND trade_date=v_context_date AND feature_version='phase2-v2';
    GET DIAGNOSTICS updated_rows=ROW_COUNT;
    IF updated_rows<>1 THEN
        RAISE EXCEPTION 'year-anchor test did not modify exactly one earlier V2 context row';
    END IF;
    hash_changed:=ops.phase2_chunk_input_hash('features',chunk_from,chunk_to);
    IF hash_changed IS NOT DISTINCT FROM hash_before THEN
        RAISE EXCEPTION 'a V2 input earlier in the output month was omitted from the V3 chunk hash';
    END IF;

    UPDATE feat.features_daily
       SET return_1d=v_original_return
     WHERE symbol_id=v_symbol_id AND trade_date=v_context_date AND feature_version='phase2-v2';
    hash_restored:=ops.phase2_chunk_input_hash('features',chunk_from,chunk_to);
    IF hash_restored IS DISTINCT FROM hash_before THEN
        RAISE EXCEPTION 'restoring the earlier V2 context did not restore the original chunk hash';
    END IF;
END
$$;
ROLLBACK;

DO $$
DECLARE
    correction_count integer;
    as_of_match_count integer;
BEGIN
    SELECT count(*) INTO correction_count
    FROM core.vndirect_model_bar_overrides m
    JOIN core.bars_daily_sources b USING (symbol_id,trade_date,source)
    WHERE m.source='vndirect'
      AND m.evidence_note LIKE 'CafeF same-session raw OHLC and matched volume confirm%';
    IF correction_count <> 20 THEN
        RAISE EXCEPTION 'expected 20 evidence-backed close-tick corrections, found %', correction_count;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM core.vndirect_model_bar_overrides m
        JOIN core.bars_daily_sources b USING (symbol_id,trade_date,source)
        WHERE m.source='vndirect'
          AND m.evidence_note LIKE 'CafeF same-session raw OHLC and matched volume confirm%'
          AND (m.model_o<>b.o OR m.model_h<>b.h OR m.model_l<>b.l
               OR m.model_c=b.c OR m.model_c<m.model_l OR m.model_c>m.model_h
               OR b.exchange_code<>'HOSE' OR NOT b.is_traded OR b.v<=0
               OR m.evidence_url NOT LIKE 'https://cafef.vn/%'
               OR length(m.evidence_sha256)<>64)
    ) THEN
        RAISE EXCEPTION 'close-tick correction rewrote raw OHLCV, lacks evidence, or fails trade/range invariants';
    END IF;

    WITH corrections AS (
        SELECT m.symbol_id,m.trade_date,m.model_c,b.c AS source_c,b.v,
               b.source_row,b.landing_id
        FROM core.vndirect_model_bar_overrides m
        JOIN core.bars_daily_sources b USING (symbol_id,trade_date,source)
        WHERE m.source='vndirect'
          AND m.evidence_note LIKE 'CafeF same-session raw OHLC and matched volume confirm%'
    ), as_of_rows AS (
        SELECT c.*,p.c AS asof_c,p.v AS asof_v,
               p.source_row AS asof_source_row,p.landing_id AS asof_landing_id
        FROM corrections c
        JOIN LATERAL core.vndirect_bars_as_of(c.symbol_id,c.trade_date) p
          ON p.trade_date=c.trade_date
    )
    SELECT count(*) FILTER (
        WHERE asof_c=model_c AND asof_c<>source_c AND asof_v=v
          AND asof_source_row=source_row AND asof_landing_id=landing_id
    ) INTO as_of_match_count
    FROM as_of_rows;
    IF as_of_match_count <> 20 THEN
        RAISE EXCEPTION 'expected all 20 point-in-time rows to use corrected closes and retain lineage; found %', as_of_match_count;
    END IF;
END $$;

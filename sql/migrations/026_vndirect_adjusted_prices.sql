-- Keep VNDIRECT's raw OHLC intact and materialize its separate ad* snapshot.
-- The as-of function removes adjustments applied after each requested date.
BEGIN;

ALTER TABLE core.bars_daily_sources
    ADD COLUMN IF NOT EXISTS adjusted_o double precision,
    ADD COLUMN IF NOT EXISTS adjusted_h double precision,
    ADD COLUMN IF NOT EXISTS adjusted_l double precision,
    ADD COLUMN IF NOT EXISTS adjusted_c double precision,
    ADD COLUMN IF NOT EXISTS adjustment_vintage_at timestamptz;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid='core.bars_daily_sources'::regclass
          AND conname='bars_daily_sources_adjusted_snapshot_complete'
    ) THEN
        ALTER TABLE core.bars_daily_sources
            ADD CONSTRAINT bars_daily_sources_adjusted_snapshot_complete CHECK (
                (adjusted_o IS NULL AND adjusted_h IS NULL AND adjusted_l IS NULL AND
                 adjusted_c IS NULL AND adjustment_vintage_at IS NULL)
                OR
                (adjusted_o IS NOT NULL AND adjusted_h IS NOT NULL AND adjusted_l IS NOT NULL AND
                 adjusted_c IS NOT NULL AND adjusted_o > 0 AND adjusted_h > 0 AND
                 adjusted_l > 0 AND adjusted_c > 0 AND
                 adjusted_h >= adjusted_l AND adjustment_vintage_at IS NOT NULL)
            );
    END IF;
END $$;

WITH candidate_landings AS (
    SELECT l.landing_id,l.fetched_at,l.payload
    FROM raw.landings l
    WHERE l.source='vndirect' AND l.route='equity_ohlcv'
      AND EXISTS (
          SELECT 1 FROM core.bars_daily_sources b
          WHERE b.source='vndirect' AND b.landing_id=l.landing_id
            AND b.adjusted_o IS NULL
      )
), parsed AS MATERIALIZED (
    SELECT l.landing_id,l.fetched_at,(e.ordinality-1)::integer AS source_row,
           CASE WHEN jsonb_typeof(e.item->'adOpen')='number' THEN (e.item->>'adOpen')::double precision END AS adjusted_o,
           CASE WHEN jsonb_typeof(e.item->'adHigh')='number' THEN (e.item->>'adHigh')::double precision END AS adjusted_h,
           CASE WHEN jsonb_typeof(e.item->'adLow')='number' THEN (e.item->>'adLow')::double precision END AS adjusted_l,
           CASE WHEN jsonb_typeof(e.item->'adClose')='number' THEN (e.item->>'adClose')::double precision END AS adjusted_c
    FROM candidate_landings l
    CROSS JOIN LATERAL jsonb_array_elements(l.payload->'data') WITH ORDINALITY AS e(item,ordinality)
)
UPDATE core.bars_daily_sources b
SET adjusted_o=CASE WHEN p.adjusted_o>0 AND p.adjusted_h>0 AND p.adjusted_l>0 AND p.adjusted_c>0 AND p.adjusted_h>=p.adjusted_l THEN p.adjusted_o END,
    adjusted_h=CASE WHEN p.adjusted_o>0 AND p.adjusted_h>0 AND p.adjusted_l>0 AND p.adjusted_c>0 AND p.adjusted_h>=p.adjusted_l THEN p.adjusted_h END,
    adjusted_l=CASE WHEN p.adjusted_o>0 AND p.adjusted_h>0 AND p.adjusted_l>0 AND p.adjusted_c>0 AND p.adjusted_h>=p.adjusted_l THEN p.adjusted_l END,
    adjusted_c=CASE WHEN p.adjusted_o>0 AND p.adjusted_h>0 AND p.adjusted_l>0 AND p.adjusted_c>0 AND p.adjusted_h>=p.adjusted_l THEN p.adjusted_c END,
    adjustment_vintage_at=CASE WHEN p.adjusted_o>0 AND p.adjusted_h>0 AND p.adjusted_l>0 AND p.adjusted_c>0 AND p.adjusted_h>=p.adjusted_l THEN p.fetched_at END
FROM parsed p
WHERE b.source='vndirect' AND b.landing_id=p.landing_id AND b.source_row=p.source_row;

CREATE OR REPLACE FUNCTION core.vndirect_bars_as_of(p_symbol_id bigint,p_as_of_date date)
RETURNS TABLE (
    symbol_id bigint,
    trade_date date,
    source text,
    o double precision,
    h double precision,
    l double precision,
    c double precision,
    v double precision,
    adjustment_vintage_at timestamptz,
    as_of_adjustment_factor double precision,
    landing_id bigint,
    source_row integer,
    ingest_id uuid,
    fetched_at timestamptz
)
LANGUAGE sql
STABLE
AS $$
    WITH anchor AS (
        SELECT b.symbol_id,b.adjustment_vintage_at,
               b.adjusted_c / NULLIF(b.c,0) AS adjustment_factor
        FROM core.bars_daily_sources b
        WHERE b.symbol_id=p_symbol_id AND b.source='vndirect'
          AND b.trade_date=p_as_of_date
          AND b.adjusted_o IS NOT NULL AND b.adjusted_h IS NOT NULL
          AND b.adjusted_l IS NOT NULL AND b.adjusted_c IS NOT NULL
          AND b.adjustment_vintage_at IS NOT NULL
    ), eligible_snapshot AS (
        SELECT a.symbol_id,a.adjustment_vintage_at,a.adjustment_factor
        FROM anchor a
        WHERE a.adjustment_factor>0
          AND NOT EXISTS (
              SELECT 1 FROM core.bars_daily_sources prior
              WHERE prior.symbol_id=a.symbol_id AND prior.source='vndirect'
                AND prior.trade_date<=p_as_of_date
                AND (prior.adjustment_vintage_at IS DISTINCT FROM a.adjustment_vintage_at
                     OR prior.adjusted_o IS NULL OR prior.adjusted_h IS NULL
                     OR prior.adjusted_l IS NULL OR prior.adjusted_c IS NULL)
          )
    )
    SELECT b.symbol_id,b.trade_date,b.source,
           b.adjusted_o/a.adjustment_factor,
           b.adjusted_h/a.adjustment_factor,
           b.adjusted_l/a.adjustment_factor,
           b.adjusted_c/a.adjustment_factor,
           b.v,b.adjustment_vintage_at,a.adjustment_factor,
           b.landing_id,b.source_row,b.ingest_id,b.fetched_at
    FROM core.bars_daily_sources b
    JOIN eligible_snapshot a ON a.symbol_id=b.symbol_id
    WHERE b.source='vndirect' AND b.trade_date<=p_as_of_date
      AND b.adjustment_vintage_at=a.adjustment_vintage_at
      AND b.adjusted_o IS NOT NULL AND b.adjusted_h IS NOT NULL
      AND b.adjusted_l IS NOT NULL AND b.adjusted_c IS NOT NULL
    ORDER BY b.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(bigint,date) IS
    'Returns VNDIRECT OHLC prices adjusted only for actions effective through the requested as-of session. Requires complete adjusted history from one landing vintage; returns no rows when the snapshot is mixed or incomplete.';

COMMIT;

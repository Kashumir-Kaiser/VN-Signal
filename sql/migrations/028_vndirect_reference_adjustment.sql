-- Preserve VNDIRECT's exchange reference inputs and derive point-in-time
-- adjustment factors from those exact values instead of rounded ad* snapshots.
BEGIN;

ALTER TABLE core.bars_daily_sources
    ADD COLUMN IF NOT EXISTS basic_price double precision,
    ADD COLUMN IF NOT EXISTS average_price double precision,
    ADD COLUMN IF NOT EXISTS exchange_code text;

WITH candidate_landings AS (
    SELECT l.landing_id,l.payload
    FROM raw.landings l
    WHERE l.source='vndirect' AND l.route='equity_ohlcv'
      AND EXISTS (
          SELECT 1 FROM core.bars_daily_sources b
          WHERE b.source='vndirect' AND b.landing_id=l.landing_id
            AND (b.basic_price IS NULL OR b.average_price IS NULL OR b.exchange_code IS NULL)
      )
), parsed AS MATERIALIZED (
    SELECT l.landing_id,(e.ordinality-1)::integer AS source_row,
           CASE WHEN jsonb_typeof(e.item->'basicPrice')='number'
                THEN (e.item->>'basicPrice')::double precision END AS basic_price,
           CASE WHEN jsonb_typeof(e.item->'average')='number'
                THEN (e.item->>'average')::double precision END AS average_price,
           NULLIF(upper(btrim(e.item->>'floor')),'') AS exchange_code
    FROM candidate_landings l
    CROSS JOIN LATERAL jsonb_array_elements(l.payload->'data')
        WITH ORDINALITY AS e(item,ordinality)
)
UPDATE core.bars_daily_sources b
SET basic_price=p.basic_price,
    average_price=p.average_price,
    exchange_code=p.exchange_code
FROM parsed p
WHERE b.source='vndirect'
  AND b.landing_id=p.landing_id
  AND b.source_row=p.source_row;

COMMENT ON COLUMN core.bars_daily_sources.basic_price IS
    'VNDIRECT basicPrice: exchange reference price for this session, in thousand VND; zero values are retained as source evidence.';
COMMENT ON COLUMN core.bars_daily_sources.average_price IS
    'VNDIRECT average traded price for this session, in thousand VND; used as the prior UPCoM reference basis.';
COMMENT ON COLUMN core.bars_daily_sources.exchange_code IS
    'VNDIRECT floor venue reported for this historical bar (HOSE, HNX, or UPCOM); retained for venue-specific adjustment rules.';

CREATE OR REPLACE VIEW core.vndirect_reference_adjustments AS
WITH ordered AS (
    SELECT b.*,
           lag(b.c) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_close,
           lag(b.basic_price) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_basic_price,
           lag(b.average_price) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_average_price,
           lag(b.adjusted_c) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_adjusted_close
    FROM core.bars_daily_sources b
    WHERE b.source='vndirect'
), reference_basis AS (
    SELECT o.*,
           CASE WHEN o.exchange_code='UPCOM'
                THEN COALESCE(NULLIF(o.prior_average_price,0),
                              NULLIF(o.prior_basic_price,0),
                              o.prior_close)
                ELSE o.prior_close
           END AS reference_baseline
    FROM ordered o
), reference_tolerance AS (
    SELECT r.*,
           CASE
             WHEN r.exchange_code='HOSE' AND r.reference_baseline<10 THEN 0.005::double precision
             WHEN r.exchange_code='HOSE' AND r.reference_baseline<50 THEN 0.025::double precision
             ELSE 0.05::double precision
           END AS half_tick
    FROM reference_basis r
)
SELECT r.symbol_id,r.trade_date,r.source,r.o,r.h,r.l,r.c,r.v,r.adj_basis,r.is_traded,
       r.landing_id,r.source_row,r.ingest_id,r.fetched_at,
       r.adjusted_o,r.adjusted_h,r.adjusted_l,r.adjusted_c,r.adjustment_vintage_at,
       r.basic_price,r.average_price,r.exchange_code,r.prior_close,r.prior_average_price,
       r.reference_baseline,
       CASE
         WHEN r.prior_close IS NULL THEN 1::double precision
         WHEN r.exchange_code IS NULL OR r.exchange_code NOT IN ('HOSE','HNX','UPCOM')
              THEN NULL::double precision
         WHEN r.basic_price>0 AND r.reference_baseline>0 THEN
              CASE WHEN abs(r.basic_price-r.reference_baseline)<=r.half_tick
                   THEN 1::double precision
                   ELSE r.basic_price/r.reference_baseline
              END
         WHEN r.v=0 AND r.c=r.prior_close
              AND r.adjusted_c IS NOT DISTINCT FROM r.prior_adjusted_close
              THEN 1::double precision
         ELSE NULL::double precision
       END AS reference_adjustment_ratio
FROM reference_tolerance r;

COMMENT ON VIEW core.vndirect_reference_adjustments IS
    'Per-session VNDIRECT adjustment ratio from basicPrice and the previous venue reference (UPCoM prior average, HOSE/HNX prior close). A zero/missing reference is accepted only for unchanged zero-volume observations; other unresolved rows remain visible with a NULL ratio.';

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
    WITH source_rows AS (
        SELECT r.*
        FROM core.vndirect_reference_adjustments r
        WHERE r.symbol_id=p_symbol_id AND r.trade_date<=p_as_of_date
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=r.symbol_id AND excluded.scope_status='EXCLUDED'
          )
    ), cumulative AS (
        SELECT r.*,
               exp(sum(ln(r.reference_adjustment_ratio)) OVER (
                   PARTITION BY r.symbol_id ORDER BY r.trade_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               )) AS cumulative_adjustment_factor
        FROM source_rows r
    ), eligible AS (
        SELECT r.symbol_id,
               exp(sum(ln(r.reference_adjustment_ratio))) AS as_of_factor
        FROM source_rows r
        GROUP BY r.symbol_id
        HAVING count(*) FILTER (WHERE r.trade_date=p_as_of_date)=1
           AND bool_and(r.reference_adjustment_ratio IS NOT NULL
                        AND r.reference_adjustment_ratio>0)
    )
    SELECT r.symbol_id,r.trade_date,r.source,
           r.o*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.h*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.l*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.c*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.v,r.adjustment_vintage_at,
           e.as_of_factor/r.cumulative_adjustment_factor,
           r.landing_id,r.source_row,r.ingest_id,r.fetched_at
    FROM cumulative r
    JOIN eligible e USING(symbol_id)
    ORDER BY r.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(bigint,date) IS
    'Returns raw VNDIRECT OHLC rescaled through the requested session using exchange reference-price adjustments. Uses prior UPCoM average or prior HOSE/HNX close, preserves every row and lineage, and returns no series only when a reference adjustment is unresolved or the exact as-of session is absent.';

CREATE OR REPLACE FUNCTION core.vndirect_bars_as_of(p_as_of_date date)
RETURNS TABLE (
    symbol_id bigint,
    trade_date date,
    source text,
    o double precision,
    h double precision,
    l double precision,
    c double precision,
    v double precision,
    is_traded boolean,
    price_basis text,
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
    WITH source_rows AS (
        SELECT r.*
        FROM core.vndirect_reference_adjustments r
        WHERE r.trade_date<=p_as_of_date
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=r.symbol_id AND excluded.scope_status='EXCLUDED'
          )
    ), cumulative AS (
        SELECT r.*,
               exp(sum(ln(r.reference_adjustment_ratio)) OVER (
                   PARTITION BY r.symbol_id ORDER BY r.trade_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               )) AS cumulative_adjustment_factor
        FROM source_rows r
    ), eligible AS (
        SELECT r.symbol_id,
               exp(sum(ln(r.reference_adjustment_ratio))) AS as_of_factor
        FROM source_rows r
        GROUP BY r.symbol_id
        HAVING count(*) FILTER (WHERE r.trade_date=p_as_of_date)=1
           AND bool_and(r.reference_adjustment_ratio IS NOT NULL
                        AND r.reference_adjustment_ratio>0)
    )
    SELECT r.symbol_id,r.trade_date,r.source,
           r.o*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.h*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.l*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.c*(e.as_of_factor/r.cumulative_adjustment_factor),
           r.v,r.is_traded,'adjusted_as_of_reference'::text,
           r.adjustment_vintage_at,
           e.as_of_factor/r.cumulative_adjustment_factor,
           r.landing_id,r.source_row,r.ingest_id,r.fetched_at
    FROM cumulative r
    JOIN eligible e USING(symbol_id)
    ORDER BY r.symbol_id,r.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(date) IS
    'Returns the full in-scope VNDIRECT history through the requested session, adjusted using exact exchange reference prices rather than rounded ad* snapshots. Preserves zero-volume rows and lineage; unresolved reference factors are reported by core.vndirect_reference_adjustments and prevent that symbol series from being used.';

COMMIT;

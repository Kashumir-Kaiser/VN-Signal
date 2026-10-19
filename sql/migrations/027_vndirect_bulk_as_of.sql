-- Expose one complete VNDIRECT point-in-time adjusted series across the universe.
-- The per-symbol function remains the narrow lookup; this set-based function
-- prevents Phase 2 from selecting mixed-provider adjustment vintages by accident.
BEGIN;

CREATE TABLE IF NOT EXISTS ops.ml_symbol_scope (
    symbol_id bigint PRIMARY KEY REFERENCES core.symbols(symbol_id),
    scope_status text NOT NULL CHECK (scope_status IN ('INCLUDED','EXCLUDED')),
    scope_reason text NOT NULL,
    decision_ref text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO ops.ml_symbol_scope(symbol_id,scope_status,scope_reason,decision_ref)
SELECT s.symbol_id,'EXCLUDED',
       'No positive executed-volume observation from the official 2025-10-17 first-trading date through 2026-10-16; reference-price rows are not trade bars.',
       'docs/DECISIONS.md — 2026-10-19 user-approved partial zero-volume classification and UTT exclusion'
FROM core.symbols s
WHERE s.symbol='UTT'
ON CONFLICT (symbol_id) DO NOTHING;

COMMENT ON TABLE ops.ml_symbol_scope IS
    'Explicit symbol-level Phase 2 model scope decisions. Missing rows are in-scope unless another project scope rule says otherwise.';

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
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=b.symbol_id AND excluded.scope_status='EXCLUDED'
          )
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
    'Returns VNDIRECT OHLC adjusted only for actions effective through the requested as-of session. Requires a complete single-vintage history; returns no rows for explicit Phase 2 symbol exclusions or incomplete/mixed snapshots.';

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
    WITH anchor AS (
        SELECT b.symbol_id,b.adjustment_vintage_at,
               b.adjusted_c / NULLIF(b.c,0) AS adjustment_factor
        FROM core.bars_daily_sources b
        WHERE b.source='vndirect'
          AND b.trade_date=p_as_of_date
          AND b.adjusted_o IS NOT NULL AND b.adjusted_h IS NOT NULL
          AND b.adjusted_l IS NOT NULL AND b.adjusted_c IS NOT NULL
          AND b.adjustment_vintage_at IS NOT NULL
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=b.symbol_id AND excluded.scope_status='EXCLUDED'
          )
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
           b.v,b.is_traded,'adjusted_as_of'::text,
           b.adjustment_vintage_at,a.adjustment_factor,
           b.landing_id,b.source_row,b.ingest_id,b.fetched_at
    FROM core.bars_daily_sources b
    JOIN eligible_snapshot a ON a.symbol_id=b.symbol_id
    WHERE b.source='vndirect'
      AND b.trade_date<=p_as_of_date
      AND b.adjustment_vintage_at=a.adjustment_vintage_at
      AND b.adjusted_o IS NOT NULL AND b.adjusted_h IS NOT NULL
      AND b.adjusted_l IS NOT NULL AND b.adjusted_c IS NOT NULL
    ORDER BY b.symbol_id,b.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(date) IS
    'Returns the full in-scope VNDIRECT market history through the requested session on a single, point-in-time adjusted basis. Applies ops.ml_symbol_scope exclusions, requires a complete single-vintage snapshot per symbol and an exact-date anchor, and never fills absent ticker sessions.';

COMMIT;

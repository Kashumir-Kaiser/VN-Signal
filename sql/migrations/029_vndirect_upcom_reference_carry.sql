-- UPCoM's reference price carries from its most recent prior session with
-- continuous matched trading; a zero-volume session contributes no new VWAP.
BEGIN;

CREATE OR REPLACE VIEW core.vndirect_reference_adjustments AS
WITH ordered AS (
    SELECT b.*,
           lag(b.c) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_close,
           lag(b.basic_price) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_basic_price,
           lag(b.average_price) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_average_price,
           lag(b.adjusted_c) OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS prior_adjusted_close,
           sum(CASE WHEN b.v>0 THEN 1::bigint ELSE 0::bigint END) OVER (
               PARTITION BY b.symbol_id ORDER BY b.trade_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS traded_sequence
    FROM core.bars_daily_sources b
    WHERE b.source='vndirect'
), traded_references AS (
    SELECT o.symbol_id,o.traded_sequence,max(o.average_price) AS last_traded_average_price
    FROM ordered o
    WHERE o.v>0
    GROUP BY o.symbol_id,o.traded_sequence
), reference_basis AS (
    SELECT o.*,
           CASE WHEN o.exchange_code='UPCOM'
                THEN COALESCE(NULLIF(t.last_traded_average_price,0),
                              NULLIF(o.prior_basic_price,0),
                              o.prior_close)
                ELSE o.prior_close
           END AS reference_baseline
    FROM ordered o
    LEFT JOIN traded_references t
      ON t.symbol_id=o.symbol_id
     AND t.traded_sequence=o.traded_sequence-
         CASE WHEN o.v>0 THEN 1::bigint ELSE 0::bigint END
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
    'Per-session VNDIRECT adjustment ratio from basicPrice and the previous venue reference (UPCoM average from the most recent prior traded session, HOSE/HNX prior close). Zero-volume UPCoM days carry the last matched-session VWAP forward. A zero/missing reference is accepted only for unchanged zero-volume observations; other unresolved rows remain visible with a NULL ratio.';

COMMIT;

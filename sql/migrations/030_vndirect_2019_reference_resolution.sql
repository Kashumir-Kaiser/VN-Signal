-- Resolve the missing VNDIRECT basicPrice values on the first 2019 session.
-- Source bars remain immutable; every manual reference resolution is audited.
BEGIN;

CREATE TABLE IF NOT EXISTS core.vndirect_reference_adjustment_overrides (
    symbol_id bigint NOT NULL,
    trade_date date NOT NULL,
    source text NOT NULL DEFAULT 'vndirect' CHECK (source='vndirect'),
    reference_adjustment_ratio double precision NOT NULL
        CHECK (reference_adjustment_ratio > 0
               AND reference_adjustment_ratio < 'Infinity'::double precision),
    resolution_kind text NOT NULL
        CHECK (resolution_kind IN ('NO_ACTION','CORPORATE_ACTION')),
    evidence_url text NOT NULL,
    secondary_evidence_url text,
    evidence_note text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (symbol_id,trade_date,source),
    FOREIGN KEY (symbol_id,trade_date,source)
        REFERENCES core.bars_daily_sources(symbol_id,trade_date,source),
    CHECK ((resolution_kind='NO_ACTION' AND reference_adjustment_ratio=1)
        OR (resolution_kind='CORPORATE_ACTION' AND reference_adjustment_ratio<>1))
);

COMMENT ON TABLE core.vndirect_reference_adjustment_overrides IS
    'Audited exchange-reference resolutions for VNDIRECT bars whose source basicPrice is zero or missing. The immutable source field is never rewritten.';

INSERT INTO core.vndirect_reference_adjustment_overrides
    (symbol_id,trade_date,source,reference_adjustment_ratio,resolution_kind,
     evidence_url,secondary_evidence_url,evidence_note)
SELECT r.symbol_id,r.trade_date,r.source,
       CASE WHEN s.symbol='DSN' THEN 59.3::double precision/62.9::double precision
            ELSE 1::double precision END,
       CASE WHEN s.symbol='DSN' THEN 'CORPORATE_ACTION' ELSE 'NO_ACTION' END,
       CASE WHEN s.symbol='DSN'
            THEN 'https://vsdc.vn/en/ad/125616'
            ELSE 'https://vsdc.vn/en/lich-giao-dich?date=03%2F01%2F2019&tab=LICH_THQ'
       END,
       CASE WHEN s.symbol='DSN'
            THEN 'https://cophieu68.vn/quote/event_calc.php?id=dsn'
            ELSE 'https://cafef.vn/diem-danh-nhung-doanh-nghiep-dau-tien-trong-nam-moi-2019-tra-co-tuc-bang-tien-co-phieu-va-co-phieu-thuong-20190101112129416.chn'
       END,
       CASE WHEN s.symbol='DSN'
            THEN 'VSD notice 125616 records a 3,600 VND/share cash dividend with 2019-01-03 record date. The 2019-01-02 ex-right reference is 62.9 prior close minus 3.6 dividend = 59.3; ratio 59.3/62.9. The observed 58.5 close is a valid traded price and is retained.'
            ELSE 'VNDIRECT basicPrice is zero on this bar. The VSDC record-date calendar for 2019-01-03 lists the full four notices: DSN cash dividend, HCB cash dividend, and FTV/PCN shareholder meetings. DSN is the only affected symbol in the current VNDIRECT scope with a reference-price action; HCB is absent from core.symbols. The archived VNDIRECT adjusted snapshots show factor continuity at 1 within their rounding precision. Resolve this session factor as 1 and preserve the raw zero basicPrice.'
       END
FROM core.vndirect_reference_adjustments r
JOIN core.symbols s USING (symbol_id)
WHERE r.source='vndirect'
  AND r.trade_date='2019-01-02'
  AND r.reference_adjustment_ratio IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM ops.ml_symbol_scope excluded
      WHERE excluded.symbol_id=r.symbol_id AND excluded.scope_status='EXCLUDED'
  )
ON CONFLICT (symbol_id,trade_date,source) DO NOTHING;

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
       COALESCE(x.reference_adjustment_ratio,
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
         END
       ) AS reference_adjustment_ratio
FROM reference_tolerance r
LEFT JOIN core.vndirect_reference_adjustment_overrides x
  ON x.symbol_id=r.symbol_id AND x.trade_date=r.trade_date AND x.source=r.source;

COMMENT ON VIEW core.vndirect_reference_adjustments IS
    'Per-session VNDIRECT adjustment ratio from exchange reference inputs, carrying prior matched UPCoM VWAP over zero-volume sessions. Audited overrides resolve known missing basicPrice values while retaining their source zero and exposing override evidence columns.';

COMMIT;

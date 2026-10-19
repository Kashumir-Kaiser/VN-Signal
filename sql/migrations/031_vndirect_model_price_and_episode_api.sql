-- Carry official reference prices through no-match sessions, isolate relisted
-- security episodes, and keep cumulative adjustments in log space.
BEGIN;

-- A prior version of this migration exposed episode columns on the public
-- view/functions. Replace those contracts safely while retaining richer
-- episode metadata through the companion details view and functions.
DROP FUNCTION IF EXISTS core.vndirect_bars_as_of(date);
DROP FUNCTION IF EXISTS core.vndirect_bars_as_of(bigint,date);
DROP FUNCTION IF EXISTS core.vndirect_bars_as_of_with_episodes(date);
DROP FUNCTION IF EXISTS core.vndirect_bars_as_of_with_episodes(bigint,date);
DROP VIEW IF EXISTS core.vndirect_reference_adjustments;

ALTER TABLE core.vndirect_reference_adjustment_overrides
    ADD COLUMN IF NOT EXISTS evidence_sha256 text,
    ADD COLUMN IF NOT EXISTS secondary_evidence_sha256 text;

CREATE TABLE IF NOT EXISTS core.vndirect_model_bar_overrides (
    symbol_id bigint NOT NULL,
    trade_date date NOT NULL,
    source text NOT NULL DEFAULT 'vndirect' CHECK (source='vndirect'),
    model_o double precision NOT NULL CHECK (model_o>0 AND model_o<'Infinity'::double precision),
    model_h double precision NOT NULL CHECK (model_h>0 AND model_h<'Infinity'::double precision),
    model_l double precision NOT NULL CHECK (model_l>0 AND model_l<'Infinity'::double precision),
    model_c double precision NOT NULL CHECK (model_c>0 AND model_c<'Infinity'::double precision),
    evidence_url text NOT NULL,
    evidence_sha256 text NOT NULL CHECK (evidence_sha256 ~ '^[0-9a-f]{64}$'),
    secondary_evidence_url text,
    secondary_evidence_sha256 text CHECK (
        secondary_evidence_sha256 IS NULL OR secondary_evidence_sha256 ~ '^[0-9a-f]{64}$'
    ),
    evidence_note text NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (symbol_id,trade_date,source),
    FOREIGN KEY (symbol_id,trade_date,source)
        REFERENCES core.bars_daily_sources(symbol_id,trade_date,source),
    CHECK (model_h>=GREATEST(model_o,model_c)),
    CHECK (model_l<=LEAST(model_o,model_c))
);

COMMENT ON TABLE core.vndirect_model_bar_overrides IS
    'Evidence-linked model OHLC corrections for VNDIRECT source bars that already embed a future adjustment. Immutable source OHLC, volume, trade status, and landing lineage remain unchanged.';

CREATE OR REPLACE VIEW core.vndirect_reference_adjustment_details AS
WITH source_rows AS (
    SELECT b.*,
           COALESCE(m.model_o,b.o) AS model_o,
           COALESCE(m.model_h,b.h) AS model_h,
           COALESCE(m.model_l,b.l) AS model_l,
           COALESCE(m.model_c,b.c) AS model_c,
           m.evidence_url AS model_bar_evidence_url,
           m.evidence_sha256 AS model_bar_evidence_sha256,
           m.secondary_evidence_url AS model_bar_secondary_evidence_url,
           m.secondary_evidence_sha256 AS model_bar_secondary_evidence_sha256,
           m.evidence_note AS model_bar_evidence_note,
           row_number() OVER (
               PARTITION BY b.symbol_id ORDER BY b.trade_date
           ) AS source_sequence,
           min(b.trade_date) OVER (PARTITION BY b.symbol_id) AS first_trade_date
    FROM core.bars_daily_sources b
    LEFT JOIN core.vndirect_model_bar_overrides m
      ON m.symbol_id=b.symbol_id AND m.trade_date=b.trade_date AND m.source=b.source
    WHERE b.source='vndirect'
), lifecycle_boundaries AS (
    SELECT DISTINCT e.symbol_id,e.date_from AS boundary_date
    FROM core.security_lifecycle_evidence e
    WHERE e.evidence_type='TRADE_ELIGIBLE'
      AND EXISTS (
          SELECT 1
          FROM core.security_lifecycle_evidence d
          WHERE d.symbol_id=e.symbol_id
            AND d.evidence_type='DELISTED'
            AND d.date_to IS NOT NULL
            AND d.date_to<e.date_from
      )
), episode_assignment AS (
    SELECT o.symbol_id,o.trade_date,o.source_sequence,
           COALESCE(max(b.boundary_date),o.first_trade_date) AS episode_start_date
    FROM source_rows o
    LEFT JOIN lifecycle_boundaries b
      ON b.symbol_id=o.symbol_id AND b.boundary_date<=o.trade_date
    GROUP BY o.symbol_id,o.trade_date,o.source_sequence,o.first_trade_date
), episode_rows AS (
    SELECT o.*,a.episode_start_date
    FROM source_rows o
    JOIN episode_assignment a
      ON a.symbol_id=o.symbol_id AND a.trade_date=o.trade_date
     AND a.source_sequence=o.source_sequence
), ordered AS (
    SELECT b.*,
           lag(b.c) OVER w AS prior_close,
           lag(b.basic_price) OVER w AS prior_basic_price,
           lag(b.average_price) OVER w AS prior_average_price,
           lag(b.v) OVER w AS prior_volume,
           lag(b.adjusted_c) OVER w AS prior_adjusted_close,
           sum(CASE WHEN b.v>0 THEN 1::bigint ELSE 0::bigint END) OVER w AS traded_sequence,
           row_number() OVER w AS episode_row_number
    FROM episode_rows b
    WINDOW w AS (
        PARTITION BY b.symbol_id,b.episode_start_date
        ORDER BY b.trade_date
    )
), traded_references AS (
    SELECT o.symbol_id,o.episode_start_date,o.traded_sequence,
           max(o.average_price) AS last_traded_average_price,
           max(o.c) AS last_traded_close
    FROM ordered o
    WHERE o.v>0
    GROUP BY o.symbol_id,o.episode_start_date,o.traded_sequence
), reference_basis AS (
    SELECT o.*,
           CASE
             WHEN o.episode_row_number=1 THEN NULL::double precision
             WHEN o.exchange_code='UPCOM' THEN
               CASE WHEN o.prior_volume>0
                    THEN COALESCE(NULLIF(o.prior_average_price,0),o.prior_close)
                    ELSE COALESCE(NULLIF(o.prior_basic_price,0),
                                  NULLIF(t.last_traded_average_price,0),
                                  o.prior_close)
               END
             ELSE
               CASE WHEN o.prior_volume>0
                    THEN o.prior_close
                    ELSE COALESCE(NULLIF(o.prior_basic_price,0),
                                  t.last_traded_close,
                                  o.prior_close)
               END
           END AS reference_baseline,
           x.reference_adjustment_ratio AS override_ratio,
           x.resolution_kind AS override_resolution_kind,
           x.evidence_url AS override_evidence_url,
           x.secondary_evidence_url AS override_secondary_evidence_url,
           x.evidence_note AS override_evidence_note
    FROM ordered o
    LEFT JOIN traded_references t
      ON t.symbol_id=o.symbol_id
     AND t.episode_start_date=o.episode_start_date
     AND t.traded_sequence=o.traded_sequence-
         CASE WHEN o.v>0 THEN 1::bigint ELSE 0::bigint END
    LEFT JOIN core.vndirect_reference_adjustment_overrides x
      ON x.symbol_id=o.symbol_id AND x.trade_date=o.trade_date AND x.source=o.source
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
       COALESCE(r.override_ratio,
         CASE
           WHEN r.episode_row_number=1 THEN 1::double precision
           WHEN r.exchange_code IS NULL OR r.exchange_code NOT IN ('HOSE','HNX','UPCOM')
                THEN NULL::double precision
           WHEN r.basic_price>0 AND r.reference_baseline>0 THEN
                CASE WHEN abs(r.basic_price-r.reference_baseline)<=r.half_tick+1e-9
                     THEN 1::double precision
                     ELSE r.basic_price/r.reference_baseline
                END
           WHEN r.v=0 AND r.c=r.prior_close
                AND r.adjusted_c IS NOT DISTINCT FROM r.prior_adjusted_close
                THEN 1::double precision
           ELSE NULL::double precision
         END
       ) AS reference_adjustment_ratio,
       r.episode_start_date,
       r.override_resolution_kind,
       r.override_evidence_url,
       r.override_secondary_evidence_url,
       r.override_evidence_note,
       r.model_o,r.model_h,r.model_l,r.model_c,
       r.model_bar_evidence_url,r.model_bar_evidence_sha256,
       r.model_bar_secondary_evidence_url,r.model_bar_secondary_evidence_sha256,
       r.model_bar_evidence_note
FROM reference_tolerance r;

-- Keep the long-standing adjustment-view column contract stable so numbered
-- migrations can be replayed; richer episode and evidence fields live above.
CREATE OR REPLACE VIEW core.vndirect_reference_adjustments AS
SELECT symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,
       landing_id,source_row,ingest_id,fetched_at,
       adjusted_o,adjusted_h,adjusted_l,adjusted_c,adjustment_vintage_at,
       basic_price,average_price,exchange_code,prior_close,prior_average_price,
       reference_baseline,reference_adjustment_ratio
FROM core.vndirect_reference_adjustment_details;

COMMENT ON VIEW core.vndirect_reference_adjustments IS
    'Per-session VNDIRECT reference-price factors. Use core.vndirect_reference_adjustment_overrides for factor evidence and core.vndirect_reference_adjustment_details for model OHLC corrections, evidence hashes, and adjustment episode boundaries.';
COMMENT ON VIEW core.vndirect_reference_adjustment_details IS
    'Extended VNDIRECT reference view including adjustment episodes, factor evidence, corrected model OHLC, and evidence hashes. The base reference view retains its stable output contract.';

COMMENT ON TABLE core.vndirect_reference_adjustment_overrides IS
    'Audited exchange-reference resolutions and source-reference corrections for VNDIRECT bars. Immutable source OHLC/basicPrice values are never rewritten; every manual factor carries evidence and a reason.';

DROP FUNCTION IF EXISTS core.vndirect_bars_as_of(bigint,date);
CREATE FUNCTION core.vndirect_bars_as_of(p_symbol_id bigint,p_as_of_date date)
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
        FROM core.vndirect_reference_adjustment_details r
        WHERE r.symbol_id=p_symbol_id AND r.trade_date<=p_as_of_date
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=r.symbol_id AND excluded.scope_status='EXCLUDED'
          )
    ), eligible_symbols AS (
        SELECT r.symbol_id
        FROM source_rows r
        GROUP BY r.symbol_id
        HAVING bool_or(r.trade_date=p_as_of_date)
           AND bool_and(r.reference_adjustment_ratio IS NOT NULL
                        AND r.reference_adjustment_ratio>0
                        AND r.reference_adjustment_ratio<'Infinity'::double precision)
    ), cumulative AS (
        SELECT r.*,
               sum(ln(r.reference_adjustment_ratio)) OVER (
                   PARTITION BY r.symbol_id,r.episode_start_date
                   ORDER BY r.trade_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS cumulative_log_factor
        FROM source_rows r
    ), episode_factors AS (
        SELECT r.symbol_id,r.episode_start_date,
               sum(ln(r.reference_adjustment_ratio)) AS as_of_log_factor
        FROM source_rows r
        JOIN eligible_symbols s USING(symbol_id)
        GROUP BY r.symbol_id,r.episode_start_date
    )
    SELECT r.symbol_id,r.trade_date,r.source,
           r.model_o*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_h*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_l*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_c*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.v,r.adjustment_vintage_at,
           exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.landing_id,r.source_row,r.ingest_id,r.fetched_at
    FROM cumulative r
    JOIN eligible_symbols s USING(symbol_id)
    JOIN episode_factors e USING(symbol_id,episode_start_date)
    ORDER BY r.episode_start_date,r.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(bigint,date) IS
    'Returns all VNDIRECT rows through an exact as-of session, preserving zero-volume observations and lineage. Corporate-action adjustments are accumulated in log space and independently within exchange-documented delist/relist episodes. Use the companion with_episodes function to obtain episode_start_date for return and label boundaries. A symbol fails closed as a whole if any included factor is unresolved.';

DROP FUNCTION IF EXISTS core.vndirect_bars_as_of(date);
CREATE FUNCTION core.vndirect_bars_as_of(p_as_of_date date)
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
        FROM core.vndirect_reference_adjustment_details r
        WHERE r.trade_date<=p_as_of_date
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=r.symbol_id AND excluded.scope_status='EXCLUDED'
          )
    ), eligible_symbols AS (
        SELECT r.symbol_id
        FROM source_rows r
        GROUP BY r.symbol_id
        HAVING bool_or(r.trade_date=p_as_of_date)
           AND bool_and(r.reference_adjustment_ratio IS NOT NULL
                        AND r.reference_adjustment_ratio>0
                        AND r.reference_adjustment_ratio<'Infinity'::double precision)
    ), cumulative AS (
        SELECT r.*,
               sum(ln(r.reference_adjustment_ratio)) OVER (
                   PARTITION BY r.symbol_id,r.episode_start_date
                   ORDER BY r.trade_date
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS cumulative_log_factor
        FROM source_rows r
    ), episode_factors AS (
        SELECT r.symbol_id,r.episode_start_date,
               sum(ln(r.reference_adjustment_ratio)) AS as_of_log_factor
        FROM source_rows r
        JOIN eligible_symbols s USING(symbol_id)
        GROUP BY r.symbol_id,r.episode_start_date
    )
    SELECT r.symbol_id,r.trade_date,r.source,
           r.model_o*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_h*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_l*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.model_c*exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.v,r.is_traded,'adjusted_as_of_reference'::text,
           r.adjustment_vintage_at,
           exp(e.as_of_log_factor-r.cumulative_log_factor),
           r.landing_id,r.source_row,r.ingest_id,r.fetched_at
    FROM cumulative r
    JOIN eligible_symbols s USING(symbol_id)
    JOIN episode_factors e USING(symbol_id,episode_start_date)
    ORDER BY r.symbol_id,r.episode_start_date,r.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of(date) IS
    'Returns every complete in-scope VNDIRECT history through the requested exact session, preserving zero-volume observations and lineage. Factors are accumulated in log space and independently within delist/relist episodes. Use the companion with_episodes function to obtain episode_start_date for return and label boundaries. Symbols with any unresolved factor fail closed rather than returning a partial history.';

DROP FUNCTION IF EXISTS core.vndirect_bars_as_of_with_episodes(bigint,date);
CREATE FUNCTION core.vndirect_bars_as_of_with_episodes(p_symbol_id bigint,p_as_of_date date)
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
    fetched_at timestamptz,
    episode_start_date date
)
LANGUAGE sql
STABLE
AS $$
    SELECT b.*,r.episode_start_date
    FROM core.vndirect_bars_as_of(p_symbol_id,p_as_of_date) b
    JOIN core.vndirect_reference_adjustment_details r
      USING (symbol_id,trade_date,source)
    ORDER BY r.episode_start_date,r.trade_date;
$$;

DROP FUNCTION IF EXISTS core.vndirect_bars_as_of_with_episodes(date);
CREATE FUNCTION core.vndirect_bars_as_of_with_episodes(p_as_of_date date)
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
    fetched_at timestamptz,
    episode_start_date date
)
LANGUAGE sql
STABLE
AS $$
    SELECT b.*,r.episode_start_date
    FROM core.vndirect_bars_as_of(p_as_of_date) b
    JOIN core.vndirect_reference_adjustment_details r
      USING (symbol_id,trade_date,source)
    ORDER BY r.symbol_id,r.episode_start_date,r.trade_date;
$$;

COMMENT ON FUNCTION core.vndirect_bars_as_of_with_episodes(bigint,date) IS
    'Per-symbol as-of price series with an explicit adjustment-episode key for safe return and label boundaries.';
COMMENT ON FUNCTION core.vndirect_bars_as_of_with_episodes(date) IS
    'Market-wide as-of price series with an explicit adjustment-episode key for safe return and label boundaries.';

-- These next-session basicPrice values repeat the pre-action reference and
-- would reverse an already-effective, VSDC-confirmed factor.
INSERT INTO core.vndirect_reference_adjustment_overrides
    (symbol_id,trade_date,source,reference_adjustment_ratio,resolution_kind,
     evidence_url,secondary_evidence_url,evidence_note)
SELECT s.symbol_id,x.trade_date,'vndirect',1,'NO_ACTION',
       x.evidence_url,x.secondary_evidence_url,x.evidence_note
FROM (VALUES
    ('PDN'::text,DATE '2023-06-15',
     'https://vsdc.vn/vi/ad1/159047',
     NULL::text,
     'VSDC notice 159047 records a 2023-06-15 record date, a VND 3,000 cash dividend, and a 1:1 owner-equity share issue. The 2023-06-14 ex-right reference is (179.7 - 3.0) / 2 = 88.35 thousand VND, rounded to the source basicPrice 88.4; its 88.4/179.7 factor is retained. On 2023-06-15 basicPrice returns to the stale pre-action 179.7 despite the already-effective 88.4 reference, so this session has factor 1. Raw OHLC and volume are unchanged.'),
    ('SVC'::text,DATE '2022-12-29',
     'https://vsdc.vn/vi/ad/155267',
     NULL::text,
     'VSD notice 155267 records a 2022-12-29 record date and a 1:1 bonus issue. The 2022-12-28 ex-right reference is 107 / 2 = 53.5 thousand VND, matching basicPrice; its 0.5 factor is retained. On 2022-12-29 basicPrice returns to the stale pre-action 107, while the current reference is already 53.5, so this session has factor 1. Raw OHLC and volume are unchanged.'),
    ('PTM'::text,DATE '2025-08-22',
     'https://hnx.vn/vi-vn/m-tin-tuc-hnx/32%20trieu%20co%20phieu%20CTCP%20San%20xuat%20Thuong%20mai%20va%20Dich%20vu%20O%20to%20PTM%20chinh%20thuc%20giao%20dich%20tren%20UPCoM%20tu%20ngay%202282025-60021478-0.html',
     'https://www.vpdt.hnx.vn/vi-vn/ModuleIssuer/UC_Issuer/Details/PTM/UC',
     'HNX identifies 2025-08-22 as PTM trading day one after its delisting, with a VND 20,000 initial reference price. Lifecycle evidence creates a separate episode on this date; the first-session factor is 1 and must not scale the pre-delisting history into the relisted series. Both historical episodes remain stored and returned with distinct episode_start_date values.')
) AS x(symbol,trade_date,evidence_url,secondary_evidence_url,evidence_note)
JOIN core.symbols s ON s.symbol=x.symbol
JOIN core.bars_daily_sources b
  ON b.symbol_id=s.symbol_id AND b.trade_date=x.trade_date AND b.source='vndirect'
ON CONFLICT (symbol_id,trade_date,source) DO UPDATE
SET reference_adjustment_ratio=EXCLUDED.reference_adjustment_ratio,
    resolution_kind=EXCLUDED.resolution_kind,
    evidence_url=EXCLUDED.evidence_url,
    secondary_evidence_url=EXCLUDED.secondary_evidence_url,
    evidence_note=EXCLUDED.evidence_note;

COMMIT;

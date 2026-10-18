-- Phase 1 liquidity estimate. Keep vendor-reported traded_value untouched;
-- expose this derived amount as a view field without rewriting canonical bars.
BEGIN;

CREATE OR REPLACE VIEW core.bars_daily_with_proxy AS
SELECT b.*,
       CASE WHEN b.is_traded AND b.v > 0
                  AND b.c < 'Infinity'::double precision
                  AND b.v < 'Infinity'::double precision
            THEN b.c::numeric * b.v::numeric * 1000::numeric
            ELSE NULL
       END AS traded_value_proxy_vnd
FROM core.bars_daily b;

COMMENT ON VIEW core.bars_daily_with_proxy IS
    'Canonical daily bars plus a separately named adjusted-close-times-volume liquidity proxy; the proxy is research data, not executed turnover.';
COMMENT ON COLUMN core.bars_daily_with_proxy.traded_value_proxy_vnd IS
    'Derived estimate: canonical close (vnstock equity prices are documented in thousand VND) × reported volume × 1000. Not source-reported or executed traded value; adj_basis remains separately tracked.';

COMMIT;

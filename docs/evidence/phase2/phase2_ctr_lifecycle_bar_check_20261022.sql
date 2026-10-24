\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Corrected, read-only CTR transition check. The earlier TSB-named artifact
-- joined core.symbols.symbol_id to core.security_master.security_id and is
-- retained with a .superseded suffix.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '60s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

SELECT 'curated_and_feature_rows' AS section,
       m.symbol,
       s.trade_date,
       b.source AS curated_bar_source,
       b.is_traded,
       b.o, b.h, b.l, b.c, b.v,
       coalesce(src.source_rows, 0) AS source_archive_rows,
       EXISTS (
           SELECT 1 FROM feat.features_daily f
           WHERE f.symbol_id = m.symbol_id AND f.trade_date = s.trade_date
             AND f.feature_version = 'phase2-v2'
       ) AS has_v2_feature,
       EXISTS (
           SELECT 1 FROM feat.features_daily f
           WHERE f.symbol_id = m.symbol_id AND f.trade_date = s.trade_date
             AND f.feature_version = 'phase2-v3'
       ) AS has_v3_feature
FROM core.symbols m
CROSS JOIN core.effective_trading_sessions s
LEFT JOIN core.bars_daily b
       ON b.symbol_id = m.symbol_id AND b.trade_date = s.trade_date
LEFT JOIN LATERAL (
    SELECT count(*)::bigint AS source_rows
    FROM core.bars_daily_sources d
    WHERE d.symbol_id = m.symbol_id AND d.trade_date = s.trade_date
) src ON true
WHERE m.symbol = 'CTR'
  AND s.is_session
  AND s.trade_date BETWEEN DATE '2022-02-14' AND DATE '2022-02-23'
ORDER BY s.trade_date;

SELECT 'raw_vci_landing_rows' AS section,
       l.landing_id,
       l.ingest_id,
       l.symbol,
       l.source,
       l.route,
       l.fetched_at,
       l.payload_sha256,
       r.ord AS source_row,
       (r.row->>'time')::timestamptz AS observed_at,
       (r.row->>'open')::double precision AS o,
       (r.row->>'high')::double precision AS h,
       (r.row->>'low')::double precision AS low,
       (r.row->>'close')::double precision AS c,
       (r.row->>'volume')::double precision AS v
FROM raw.landings l
CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') WITH ORDINALITY AS r(row, ord)
WHERE l.ingest_id = 'b0baf66d-9113-4bea-8739-c5d7ac32a3f3'
  AND (r.row->>'time')::date BETWEEN DATE '2022-02-14' AND DATE '2022-02-23'
ORDER BY observed_at;

SELECT 'audited_source_archive_rows' AS section,
       m.symbol,
       d.trade_date,
       d.source,
       d.landing_id,
       d.source_row,
       d.o, d.h, d.l, d.c, d.v,
       d.exchange_code,
       d.ingest_id
FROM core.bars_daily_sources d
JOIN core.symbols m USING (symbol_id)
WHERE m.symbol = 'CTR'
  AND d.trade_date BETWEEN DATE '2022-02-14' AND DATE '2022-02-23'
ORDER BY d.source, d.trade_date;

COMMIT;

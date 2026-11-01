\set ON_ERROR_STOP on
\pset pager off
\timing on

-- Read-only proof that a VCI canonical bar maps to one exact, checksum-verified
-- row occurrence in the immutable raw landing from the same ingest and symbol.
-- All derived tables are session-local temporary tables and are dropped by the
-- final rollback. The transaction writes no raw, core, or persistent feature
-- relation.
BEGIN;
SET LOCAL statement_timeout = '25min';

CREATE TEMP TABLE vci_source_rows ON COMMIT DROP AS
WITH vci_landings AS MATERIALIZED (
    SELECT l.landing_id,
           l.ingest_id,
           l.symbol,
           l.payload_sha256,
           CASE WHEN l.payload_bytes IS NOT NULL
                     AND encode(sha256(l.payload_bytes), 'hex') = lower(l.payload_sha256)
                THEN true ELSE false END AS payload_sha256_verified,
           l.payload -> 'rows' AS rows_json
    FROM raw.landings l
    WHERE l.source = 'vci'
      AND l.route = 'equity_ohlcv'
      AND jsonb_typeof(l.payload -> 'rows') = 'array'
)
SELECT l.landing_id,
       l.ingest_id,
       l.symbol,
       l.payload_sha256,
       l.payload_sha256_verified,
       r.row_ordinal::integer AS source_row,
       left(r.row_value ->> 'time', 10)::date AS trade_date,
       (r.row_value ->> 'open')::double precision AS o,
       (r.row_value ->> 'high')::double precision AS h,
       (r.row_value ->> 'low')::double precision AS low,
       (r.row_value ->> 'close')::double precision AS c,
       (r.row_value ->> 'volume')::double precision AS v
FROM vci_landings l
CROSS JOIN LATERAL jsonb_array_elements(l.rows_json)
    WITH ORDINALITY AS r(row_value, row_ordinal)
WHERE r.row_value ->> 'time' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}';

CREATE INDEX vci_source_rows_ingest_symbol_date_idx
    ON vci_source_rows(ingest_id, symbol, trade_date);
ANALYZE vci_source_rows;

SELECT count(*) AS archived_row_occurrences,
       count(DISTINCT landing_id) AS landings,
       count(*) FILTER (WHERE payload_sha256_verified) AS checksum_verified_rows,
       count(*) FILTER (WHERE NOT payload_sha256_verified) AS checksum_unverified_rows
FROM vci_source_rows;

CREATE TEMP TABLE vci_canonical_lineage ON COMMIT DROP AS
SELECT b.symbol_id,
       b.trade_date,
       b.ingest_id,
       b.v,
       b.is_traded,
       count(*) FILTER (
           WHERE r.payload_sha256_verified
             AND r.o IS NOT DISTINCT FROM b.o
             AND r.h IS NOT DISTINCT FROM b.h
             AND r.low IS NOT DISTINCT FROM b.l
             AND r.c IS NOT DISTINCT FROM b.c
             AND r.v IS NOT DISTINCT FROM b.v
       ) AS exact_row_matches,
       min(r.landing_id) FILTER (
           WHERE r.payload_sha256_verified
             AND r.o IS NOT DISTINCT FROM b.o
             AND r.h IS NOT DISTINCT FROM b.h
             AND r.low IS NOT DISTINCT FROM b.l
             AND r.c IS NOT DISTINCT FROM b.c
             AND r.v IS NOT DISTINCT FROM b.v
       ) AS exact_landing_id,
       min(r.source_row) FILTER (
           WHERE r.payload_sha256_verified
             AND r.o IS NOT DISTINCT FROM b.o
             AND r.h IS NOT DISTINCT FROM b.h
             AND r.low IS NOT DISTINCT FROM b.l
             AND r.c IS NOT DISTINCT FROM b.c
             AND r.v IS NOT DISTINCT FROM b.v
       ) AS exact_source_row
FROM core.bars_daily b
JOIN core.symbols s USING (symbol_id)
LEFT JOIN vci_source_rows r
  ON r.ingest_id = b.ingest_id
 AND r.symbol = s.symbol
 AND r.trade_date = b.trade_date
WHERE b.source = 'vci'
GROUP BY b.symbol_id, b.trade_date, b.ingest_id, b.v, b.is_traded;

CREATE INDEX vci_canonical_lineage_symbol_date_idx
    ON vci_canonical_lineage(symbol_id, trade_date);
ANALYZE vci_canonical_lineage;

SELECT count(*) AS canonical_vci_bars,
       count(*) FILTER (WHERE exact_row_matches = 1) AS uniquely_lineaged_bars,
       count(*) FILTER (WHERE exact_row_matches = 0) AS bars_without_exact_lineage,
       count(*) FILTER (WHERE exact_row_matches > 1) AS ambiguous_lineage_bars
FROM vci_canonical_lineage;

SELECT s.symbol,
       l.trade_date,
       l.v,
       l.is_traded,
       l.ingest_id,
       l.exact_row_matches
FROM vci_canonical_lineage l
JOIN core.symbols s USING (symbol_id)
WHERE l.exact_row_matches <> 1
ORDER BY s.symbol, l.trade_date, l.ingest_id;

SELECT count(*) AS vci_symbols,
       count(*) FILTER (WHERE verified_sessions >= 250) AS symbols_with_at_least_250_verified_sessions,
       max(verified_sessions) AS maximum_verified_sessions,
       count(*) FILTER (WHERE unmatched_positive_sessions > 0) AS symbols_with_any_unmatched_positive_session
FROM (
    SELECT symbol_id,
           count(*) FILTER (
               WHERE exact_row_matches = 1
                 AND v > 0
                 AND is_traded
                 AND trade_date < DATE '2026-10-17'
           ) AS verified_sessions,
           count(*) FILTER (
               WHERE exact_row_matches <> 1
                 AND v > 0
                 AND is_traded
                 AND trade_date < DATE '2026-10-17'
           ) AS unmatched_positive_sessions
    FROM vci_canonical_lineage
    GROUP BY symbol_id
) session_counts;

ROLLBACK;

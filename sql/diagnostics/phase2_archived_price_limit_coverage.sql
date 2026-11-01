-- Read-only inventory of source-reported daily bands already archived by the
-- VNDIRECT importer. Expand each response once; do not repeatedly index a wide
-- JSONB payload for every source row. This report does not create observations
-- or assign historical availability timestamps.
\set ON_ERROR_STOP on
\pset pager off
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout='5min';
WITH landing_keys AS MATERIALIZED (
    SELECT DISTINCT b.landing_id,b.ingest_id
      FROM core.bars_daily_sources b
     WHERE b.source='vndirect' AND b.landing_id IS NOT NULL
), source_rows AS MATERIALIZED (
    SELECT l.landing_id,l.ingest_id,(r.ordinality-1)::integer AS source_row,
           CASE WHEN jsonb_typeof(r.item->'ceilingPrice')='number'
                THEN (r.item->>'ceilingPrice')::double precision END AS ceiling,
           CASE WHEN jsonb_typeof(r.item->'floorPrice')='number'
                THEN (r.item->>'floorPrice')::double precision END AS floor
      FROM landing_keys k
      JOIN raw.landings l USING(landing_id,ingest_id)
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'data')
          WITH ORDINALITY AS r(item,ordinality)
     WHERE l.source='vndirect' AND l.route='equity_ohlcv'
), matched AS (
    SELECT b.symbol_id,b.trade_date,s.landing_id IS NOT NULL AS archived_row,
           s.ceiling,s.floor
      FROM core.bars_daily_sources b
      LEFT JOIN source_rows s USING(landing_id,ingest_id,source_row)
     WHERE b.source='vndirect'
)
SELECT extract(year FROM trade_date)::integer AS year,
       count(*) AS source_rows,count(DISTINCT symbol_id) AS symbols,
       count(*) FILTER(WHERE NOT archived_row) AS missing_archived_rows,
       count(*) FILTER(WHERE ceiling IS NOT NULL AND floor IS NOT NULL) AS numeric_band_pairs,
       count(*) FILTER(WHERE ceiling>0 AND floor>0 AND ceiling>=floor) AS valid_band_pairs,
       count(*) FILTER(WHERE ceiling IS NOT NULL AND floor IS NOT NULL
                          AND (ceiling<=0 OR floor<=0 OR ceiling<floor)) AS invalid_band_pairs
  FROM matched GROUP BY 1 ORDER BY 1;
ROLLBACK;

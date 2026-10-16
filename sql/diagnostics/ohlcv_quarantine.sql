-- Read-only forensic report for recorded successful-but-invalid vnstock OHLCV frames.
-- Never writes rows or invokes the provider. Prices and breaches are in 1,000 VND.
-- Run from repository root: psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f sql/diagnostics/ohlcv_quarantine.sql
\pset pager off
\echo '=== Blocked jobs and source archive availability ==='
SELECT j.symbol, j.attempts, j.last_error_type,
       CASE WHEN l.landing_id IS NULL THEN 'NOT_ARCHIVED_OLD_BLOCK'
            WHEN l.route = 'equity_ohlcv_quarantine' THEN 'RAW_ARCHIVED'
            ELSE l.route END AS archive_status
FROM ops.ingest_jobs AS j
LEFT JOIN raw.landings AS l ON l.landing_id = j.landed_id
WHERE j.route = 'equity_ohlcv' AND j.state = 'BLOCKED'
ORDER BY j.symbol;

\echo '=== Invalid source rows, with measured OHLC breach (nothing corrected) ==='
WITH frames AS (
    SELECT j.symbol, j.last_error_type,
           CASE WHEN jsonb_typeof(l.payload->'rows') = 'array'
                THEN l.payload->'rows' ELSE '[]'::jsonb END AS bars
    FROM ops.ingest_jobs AS j
    JOIN raw.landings AS l ON l.landing_id = j.landed_id
    WHERE j.route = 'equity_ohlcv' AND j.state = 'BLOCKED'
      AND l.route = 'equity_ohlcv_quarantine'
),
expanded AS (
    SELECT f.symbol, f.last_error_type,
           jsonb_array_length(f.bars) AS frame_rows,
           b.value AS bar, (b.ordinality - 1)::integer AS row_index
    FROM frames AS f
    CROSS JOIN LATERAL jsonb_array_elements(f.bars) WITH ORDINALITY AS b(value, ordinality)
),
parsed AS (
    SELECT symbol, last_error_type, frame_rows, row_index,
           left(coalesce(bar->>'time', bar->>'date', ''), 10) AS session_date,
           CASE WHEN (bar->>'open') ~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
                THEN (bar->>'open')::numeric END AS o,
           CASE WHEN (bar->>'high') ~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
                THEN (bar->>'high')::numeric END AS h,
           CASE WHEN (bar->>'low') ~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
                THEN (bar->>'low')::numeric END AS l,
           CASE WHEN (bar->>'close') ~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
                THEN (bar->>'close')::numeric END AS c,
           CASE WHEN (bar->>'volume') ~ '^[+-]?([0-9]+(\.[0-9]+)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
                THEN (bar->>'volume')::numeric END AS v
    FROM expanded
),
classified AS (
    SELECT *,
           CASE
             WHEN o IS NULL OR h IS NULL OR l IS NULL OR c IS NULL THEN 'missing_or_nonnumeric_price'
             WHEN least(o,h,l,c) <= 0 THEN 'nonpositive_price'
             WHEN v IS NULL OR v < 0 THEN 'missing_or_negative_volume'
             WHEN h < l THEN 'high_below_low'
             WHEN h < greatest(o,c) THEN 'high_below_open_or_close'
             WHEN l > least(o,c) THEN 'low_above_open_or_close'
             ELSE 'ok' END AS issue,
           CASE WHEN o IS NOT NULL AND h IS NOT NULL AND l IS NOT NULL AND c IS NOT NULL
                THEN greatest(0::numeric, greatest(o,c)-h, l-least(o,c), l-h)
                END AS breach_kvnd
    FROM parsed
),
reported AS (
    SELECT *,
           sum(CASE WHEN issue <> 'ok' THEN 1 ELSE 0 END)
               OVER (PARTITION BY symbol) AS affected_rows,
           CASE WHEN breach_kvnd IS NOT NULL AND
                     greatest(abs(o),abs(h),abs(l),abs(c)) > 0
                THEN round(10000 * breach_kvnd /
                           greatest(abs(o),abs(h),abs(l),abs(c)), 3)
           END AS breach_bps
    FROM classified
)
SELECT symbol, row_index, session_date, frame_rows, affected_rows,
       issue, o AS open, h AS high, l AS low, c AS close, v AS volume,
       breach_kvnd, breach_bps, last_error_type
FROM reported WHERE issue <> 'ok'
ORDER BY symbol, row_index
LIMIT 250;

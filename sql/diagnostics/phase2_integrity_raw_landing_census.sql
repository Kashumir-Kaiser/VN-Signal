\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Read-only audit of raw landing rows and exact-date listing snapshots inside
-- the feature-continuity gaps. Raw matches are evidence candidates only; this
-- query does not import or promote them into curated market data.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), feature_sequence AS MATERIALIZED (
    SELECT f.symbol_id,
           m.symbol,
           f.trade_date,
           s.session_no,
           lag(f.trade_date) OVER w AS prior_trade_date,
           lag(s.session_no) OVER w AS prior_session_no
    FROM feat.features_daily f
    JOIN sessions s USING (trade_date)
    JOIN core.symbols m ON m.symbol_id = f.symbol_id
    WHERE f.feature_version = 'phase2-v3'
    WINDOW w AS (PARTITION BY f.symbol_id ORDER BY f.trade_date)
), gaps AS MATERIALIZED (
    SELECT symbol_id, symbol, prior_trade_date, trade_date,
           prior_session_no, session_no,
           session_no - prior_session_no - 1 AS missing_effective_sessions
    FROM feature_sequence
    WHERE prior_session_no IS NOT NULL AND session_no - prior_session_no > 1
), missing AS MATERIALIZED (
    SELECT g.symbol_id, g.symbol, g.prior_trade_date, g.trade_date AS next_trade_date,
           g.missing_effective_sessions, s.trade_date AS missing_trade_date
    FROM gaps g
    JOIN sessions s
      ON s.session_no > g.prior_session_no
     AND s.session_no < g.session_no
), label_crossings AS MATERIALIZED (
    SELECT m.symbol_id, m.prior_trade_date, m.next_trade_date,
           count(DISTINCT (l.signal_date, l.horizon_sessions)) AS labels_crossing_gap,
           count(DISTINCT (l.signal_date, l.horizon_sessions))
               FILTER (WHERE l.label_status = 'READY') AS ready_labels_crossing_gap
    FROM missing m
    JOIN feat.labels_daily l
      ON l.symbol_id = m.symbol_id
     AND m.missing_trade_date BETWEEN l.entry_date AND l.exit_date
     AND l.label_version = 'close-next-open-v1'
    GROUP BY m.symbol_id, m.prior_trade_date, m.next_trade_date
), candidate_landings AS MATERIALIZED (
    SELECT l.landing_id, l.ingest_id, l.source, l.route, l.fetched_at,
           l.symbol, l.payload_sha256,
           CASE
               WHEN jsonb_typeof(l.payload->'rows') = 'array' THEN l.payload->'rows'
               WHEN jsonb_typeof(l.payload->'data') = 'array' THEN l.payload->'data'
               ELSE '[]'::jsonb
           END AS payload_rows
    FROM raw.landings l
    WHERE l.symbol IN (SELECT DISTINCT symbol FROM gaps)
), raw_rows AS MATERIALIZED (
    SELECT l.landing_id, l.ingest_id, l.source, l.route, l.fetched_at,
           l.symbol, l.payload_sha256,
           (e.ordinality - 1)::bigint AS source_row,
           e.row_payload,
           coalesce(e.row_payload->>'time', e.row_payload->>'date',
                    e.row_payload->>'tradingDate', e.row_payload->>'trading_date',
                    e.row_payload->>'Time', e.row_payload->>'Date') AS source_date_text
    FROM candidate_landings l
    CROSS JOIN LATERAL jsonb_array_elements(l.payload_rows)
        WITH ORDINALITY AS e(row_payload, ordinality)
), dated_raw_rows AS MATERIALIZED (
    SELECT r.*,
           CASE
               WHEN r.source_date_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}'
                   THEN substring(r.source_date_text FROM 1 FOR 10)::date
               WHEN r.source_date_text ~ '^[0-9]{13}$'
                   THEN to_timestamp(r.source_date_text::double precision / 1000)::date
               WHEN r.source_date_text ~ '^[0-9]{10}$'
                   THEN to_timestamp(r.source_date_text::double precision)::date
               ELSE NULL
           END AS source_trade_date
    FROM raw_rows r
)
SELECT g.symbol,
       g.symbol_id,
       g.prior_trade_date,
       g.trade_date AS next_trade_date,
       g.missing_effective_sessions,
       count(DISTINCT m.missing_trade_date) AS expanded_missing_sessions,
       count(DISTINCT r.source_trade_date) FILTER (WHERE r.landing_id IS NOT NULL)
           AS sessions_with_raw_rows,
       count(r.landing_id)::bigint AS raw_row_hits,
       count(DISTINCT ls.snapshot_date) AS exact_date_listing_snapshots,
       coalesce(lc.labels_crossing_gap, 0) AS labels_crossing_gap,
       coalesce(lc.ready_labels_crossing_gap, 0) AS ready_labels_crossing_gap,
       coalesce(
           jsonb_agg(
               jsonb_build_object(
                   'trade_date', r.source_trade_date,
                   'source', r.source,
                   'route', r.route,
                   'landing_id', r.landing_id,
                   'fetched_at', r.fetched_at,
                   'payload_sha256', r.payload_sha256,
                   'source_row', r.source_row,
                   'row_payload', r.row_payload
               ) ORDER BY r.source_trade_date, r.source, r.route, r.landing_id, r.source_row
           ) FILTER (WHERE r.landing_id IS NOT NULL),
           '[]'::jsonb
       ) AS raw_row_evidence
FROM gaps g
JOIN missing m
  ON m.symbol_id = g.symbol_id
 AND m.prior_trade_date = g.prior_trade_date
 AND m.next_trade_date = g.trade_date
LEFT JOIN dated_raw_rows r
  ON r.symbol = g.symbol
 AND r.source_trade_date = m.missing_trade_date
LEFT JOIN core.listing_snapshots ls
  ON ls.symbol_id = g.symbol_id
 AND ls.snapshot_date = m.missing_trade_date
LEFT JOIN label_crossings lc
  ON lc.symbol_id = g.symbol_id
 AND lc.prior_trade_date = g.prior_trade_date
 AND lc.next_trade_date = g.trade_date
GROUP BY g.symbol, g.symbol_id, g.prior_trade_date, g.trade_date,
         g.missing_effective_sessions, lc.labels_crossing_gap,
         lc.ready_labels_crossing_gap
ORDER BY g.symbol, g.prior_trade_date, g.trade_date;

COMMIT;

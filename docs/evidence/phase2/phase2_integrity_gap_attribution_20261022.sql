\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Read-only detail for the 221 V3 continuity gaps. Missing security snapshots
-- are not interpreted as delisting or suspension. Raw-bar coverage and
-- explicit lifecycle evidence are reported separately for review.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '180s';
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
), gaps AS (
    SELECT symbol_id, symbol, prior_trade_date, trade_date,
           prior_session_no, session_no,
           session_no - prior_session_no - 1 AS missing_effective_sessions
    FROM feature_sequence
    WHERE prior_session_no IS NOT NULL AND session_no - prior_session_no > 1
)
SELECT g.symbol,
       g.symbol_id,
       g.prior_trade_date,
       g.trade_date,
       g.missing_effective_sessions,
       bars.bar_rows_between,
       bars.traded_bar_rows_between,
       bars.nontraded_bar_rows_between,
       bars.sessions_without_daily_bar,
       sources.source_rows_between,
       sources.traded_source_rows_between,
       coalesce(sources.source_names, 'none') AS source_names,
       coalesce(lifecycle.overlapping_lifecycle_evidence, 'none')
           AS overlapping_lifecycle_evidence,
       coalesce(lifecycle.lifecycle_source_mismatch, false)
           AS lifecycle_source_mismatch,
       observations.security_observations_between,
       CASE
           WHEN lifecycle.overlapping_lifecycle_evidence IS NOT NULL
                AND lifecycle.lifecycle_source_mismatch
               THEN 'lifecycle/source ticker mismatch; manual review required'
           WHEN lifecycle.overlapping_lifecycle_evidence IS NOT NULL
               THEN 'lifecycle evidence and source ticker match; interval explained'
           WHEN bars.sessions_without_daily_bar = g.missing_effective_sessions
               THEN 'no daily bars in gap; suspension vs source gap unresolved'
           WHEN bars.bar_rows_between = g.missing_effective_sessions
                AND bars.traded_bar_rows_between = 0
               THEN 'explicit zero-volume bars; suspension not established'
           WHEN bars.bar_rows_between = g.missing_effective_sessions
               THEN 'daily bars cover gap; feature continuity requires review'
           ELSE 'mixed daily-bar coverage; suspension vs source gap unresolved'
       END AS review_classification
FROM gaps g
CROSS JOIN LATERAL (
    SELECT count(b.symbol_id)::bigint AS bar_rows_between,
           count(*) FILTER (WHERE b.is_traded IS TRUE)::bigint
               AS traded_bar_rows_between,
           count(*) FILTER (WHERE b.symbol_id IS NOT NULL AND b.is_traded IS FALSE)::bigint
               AS nontraded_bar_rows_between,
           count(*) FILTER (WHERE b.symbol_id IS NULL)::bigint
               AS sessions_without_daily_bar
    FROM sessions s
    LEFT JOIN core.bars_daily b
      ON b.symbol_id = g.symbol_id AND b.trade_date = s.trade_date
    WHERE s.session_no > g.prior_session_no AND s.session_no < g.session_no
) bars
CROSS JOIN LATERAL (
    SELECT count(*)::bigint AS source_rows_between,
           count(*) FILTER (WHERE src.is_traded IS TRUE)::bigint
               AS traded_source_rows_between,
           string_agg(DISTINCT src.source, ';' ORDER BY src.source) AS source_names
    FROM core.bars_daily_sources src
    WHERE src.symbol_id = g.symbol_id
      AND src.trade_date > g.prior_trade_date
      AND src.trade_date < g.trade_date
) sources
CROSS JOIN LATERAL (
    SELECT string_agg(
               e.evidence_type || ':' || e.date_from::text || '..' || coalesce(e.date_to::text, 'open')
                   || '[landing=' || coalesce(l.symbol, 'missing') ||
                   CASE WHEN l.symbol = g.symbol THEN ';ticker-match]' ELSE ';ticker-mismatch]' END,
               '; ' ORDER BY e.date_from, e.evidence_type
           ) AS overlapping_lifecycle_evidence,
           bool_or(l.symbol IS DISTINCT FROM g.symbol) AS lifecycle_source_mismatch
    FROM core.security_lifecycle_evidence e
    LEFT JOIN raw.landings l ON l.landing_id = e.source_landing_id
    WHERE e.symbol_id = g.symbol_id
      AND e.date_from <= g.trade_date
      AND coalesce(e.date_to, 'infinity'::date) >= g.prior_trade_date
) lifecycle
CROSS JOIN LATERAL (
    SELECT count(*)::bigint AS security_observations_between
    FROM core.security_observations o
    JOIN core.security_master sm ON sm.security_id = o.security_id
                              AND sm.symbol = g.symbol
    JOIN sessions s ON s.trade_date = o.observed_on
    WHERE s.session_no > g.prior_session_no AND s.session_no < g.session_no
) observations
ORDER BY g.symbol, g.prior_trade_date, g.trade_date;

COMMIT;

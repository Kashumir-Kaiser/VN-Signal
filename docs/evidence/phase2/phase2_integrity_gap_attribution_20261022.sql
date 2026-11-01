\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Read-only detail for the V3 continuity gaps. Missing security snapshots
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
       lifecycle.covered_gap_sessions,
       coalesce(lifecycle.conflicting_evidence_types, false)
           AS conflicting_evidence_types,
       transfer.exact_transfer_shapes,
       transfer.overlapping_transfer_shapes,
       coalesce(transfer.overlapping_transfer_evidence, 'none')
           AS overlapping_transfer_evidence,
       observations.security_observations_between,
       CASE
           WHEN lifecycle.overlapping_lifecycle_evidence IS NOT NULL
                AND lifecycle.lifecycle_source_mismatch
               THEN 'lifecycle/source ticker mismatch; manual review required'
           WHEN lifecycle.conflicting_evidence_types
               THEN 'conflicting lifecycle evidence; manual review required'
           WHEN lifecycle.overlapping_lifecycle_evidence IS NOT NULL
                AND lifecycle.covered_gap_sessions=g.missing_effective_sessions
               THEN 'lifecycle evidence and source ticker match; interval explained'
           WHEN lifecycle.overlapping_lifecycle_evidence IS NOT NULL
               THEN 'partial lifecycle evidence; interval unresolved'
           WHEN transfer.overlapping_transfer_shapes > 1
               THEN 'conflicting venue-transfer endpoints; interval unresolved'
           WHEN transfer.overlapping_transfer_shapes = 1
                AND transfer.exact_transfer_shapes = 0
               THEN 'partial or misaligned venue-transfer evidence; interval unresolved'
           WHEN transfer.exact_transfer_shapes = 1
                AND (bars.traded_bar_rows_between > 0
                     OR sources.traded_source_rows_between > 0)
               THEN 'venue-transfer endpoints conflict with positive-trade rows; review required'
           WHEN transfer.exact_transfer_shapes = 1
               THEN 'documented venue-transfer gap; no bars or labels imputed'
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
    SELECT count(DISTINCT (t.prior_venue,t.venue,t.prior_ceased_from,t.effective_date))
               FILTER (WHERE t.prior_ceased_from=(
                   SELECT min(missing.trade_date) FROM sessions missing
                   WHERE missing.session_no>g.prior_session_no
                     AND missing.session_no<g.session_no
               ) AND t.effective_date=g.trade_date) AS exact_transfer_shapes,
           count(DISTINCT (t.prior_venue,t.venue,t.prior_ceased_from,t.effective_date))
               AS overlapping_transfer_shapes,
           string_agg(DISTINCT
               t.prior_venue||'>'||t.venue||':'||t.prior_ceased_from::text||'..'||t.effective_date::text
                   ||'[source='||t.source_landing_id::text
                   ||';continuity='||t.continuity_landing_id::text||']',
               '; ' ORDER BY
               t.prior_venue||'>'||t.venue||':'||t.prior_ceased_from::text||'..'||t.effective_date::text
                   ||'[source='||t.source_landing_id::text
                   ||';continuity='||t.continuity_landing_id::text||']'
           ) AS overlapping_transfer_evidence
    FROM ops.phase2_verified_security_transfers t
    WHERE t.symbol_id=g.symbol_id
      AND t.prior_ceased_from<=g.trade_date
      AND t.effective_date>=g.prior_trade_date
) transfer
CROSS JOIN LATERAL (
    WITH missing AS (
        SELECT s.trade_date
        FROM sessions s
        WHERE s.session_no>g.prior_session_no AND s.session_no<g.session_no
    ), gap_evidence AS (
        SELECT e.evidence_id,e.evidence_type,e.date_from,e.date_to,l.symbol,
               l.symbol IS DISTINCT FROM g.symbol AS source_mismatch
        FROM core.security_lifecycle_evidence e
        LEFT JOIN raw.landings l ON l.landing_id=e.source_landing_id
        WHERE e.symbol_id=g.symbol_id
          AND EXISTS (
              SELECT 1 FROM missing m
              WHERE m.trade_date BETWEEN e.date_from AND coalesce(e.date_to,'infinity'::date)
          )
    )
    SELECT (SELECT string_agg(
               e.evidence_type||':'||e.date_from::text||'..'||coalesce(e.date_to::text,'open')
                   ||'[landing='||coalesce(e.symbol,'missing')||
                   CASE WHEN e.source_mismatch THEN ';ticker-mismatch]' ELSE ';ticker-match]' END,
               '; ' ORDER BY e.date_from,e.evidence_type,e.evidence_id
           ) FROM gap_evidence e) AS overlapping_lifecycle_evidence,
           coalesce((SELECT bool_or(e.source_mismatch) FROM gap_evidence e),false)
               AS lifecycle_source_mismatch,
           (SELECT count(*) FROM missing m
            WHERE EXISTS (
                SELECT 1 FROM gap_evidence e
                WHERE m.trade_date BETWEEN e.date_from AND coalesce(e.date_to,'infinity'::date)
            ))::bigint AS covered_gap_sessions,
           EXISTS (
               SELECT 1 FROM missing m
               JOIN core.security_lifecycle_evidence e ON e.symbol_id=g.symbol_id
                 AND m.trade_date BETWEEN e.date_from AND coalesce(e.date_to,'infinity'::date)
               GROUP BY m.trade_date
               HAVING count(DISTINCT e.evidence_type)>1
           ) AS conflicting_evidence_types
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

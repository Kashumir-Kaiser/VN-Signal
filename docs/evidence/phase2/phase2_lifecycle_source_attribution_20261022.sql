\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Confirm that lifecycle evidence belongs to the security named by the
-- referenced source landing. The lifecycle evidence uses core.symbols IDs;
-- core.security_master.security_id is a separate ID domain. Read-only and
-- restricted to the report clone.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '5s';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

SELECT m.symbol AS evidence_symbol,
       e.evidence_id,
       e.exchange,
       e.evidence_type,
       e.date_from,
       e.date_to,
       e.source_landing_id,
       l.symbol AS landing_symbol,
       l.source AS landing_source,
       l.route AS landing_route,
       e.source_url,
       e.source_document_date,
       l.payload_sha256
FROM core.security_lifecycle_evidence e
JOIN core.symbols m ON m.symbol_id = e.symbol_id
LEFT JOIN raw.landings l ON l.landing_id = e.source_landing_id
WHERE m.symbol IN ('CTR', 'PTM')
ORDER BY m.symbol, e.date_from, e.evidence_id;

COMMIT;

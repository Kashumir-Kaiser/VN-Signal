-- Read-only, bounded inspection of archived FPT balance-sheet landing 9802.
-- Report clone: vnsignal_phase2_report_20261019
SELECT row->>'period' AS period,row->>'id' AS id,row->>'name' AS name,row->>'unit' AS unit,row->>'value' AS value
FROM raw.landings l
CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') row
WHERE l.landing_id=9802 AND row->>'period'='2025-Q4' AND row->>'id' LIKE 'BS_%'
ORDER BY row->>'id';

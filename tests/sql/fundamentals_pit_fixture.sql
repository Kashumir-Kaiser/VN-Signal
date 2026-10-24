-- Migration compatibility fixture: this legacy row must survive migration 034.
-- Intended for a disposable PostgreSQL test database before 034 is applied.
BEGIN;
INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES ('PITLEGACY','HOSE','2026-10-01+07','2026-10-01+07')
ON CONFLICT(symbol) DO NOTHING;
INSERT INTO core.fundamentals_pit
    (symbol_id,line_item,period_end,period_type,value,source,payload,
     first_seen_at,available_at,last_seen_at,restated)
SELECT symbol_id,'legacy_fixture_line',DATE '2025-12-31','year',123.45,'fixture',
       '{"legacy_fixture":true}'::jsonb,'2026-01-01+07','2026-04-10+07',
       '2026-01-02+07',false
  FROM core.symbols WHERE symbol='PITLEGACY'
ON CONFLICT DO NOTHING;
COMMIT;

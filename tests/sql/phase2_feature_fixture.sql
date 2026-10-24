-- Synthetic-only market fixture for Phase 2 feature/label assertions.
-- Run after all migrations. Assertions run in their own transaction and roll back.
BEGIN;

-- Remove only this fixture's exact synthetic symbols and fixed index captures.
-- Never use a prefix here: other P2-prefixed symbols may be real project data.
DELETE FROM feat.labels_daily
WHERE symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol IN
    ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2GAP','P2MISS','P2EPISODE','P2STOCH'));
DELETE FROM feat.features_daily
WHERE symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol IN
    ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2GAP','P2MISS','P2EPISODE','P2STOCH'));
DELETE FROM core.bars_daily_sources
WHERE symbol_id IN (SELECT symbol_id FROM core.symbols WHERE symbol IN
    ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2GAP','P2MISS','P2EPISODE','P2STOCH'));
DELETE FROM core.index_bars WHERE ingest_id IN (
    '20000000-0000-4000-8000-000000000107','20000000-0000-4000-8000-000000000207',
    '20000000-0000-4000-8000-000000000209'
);
DELETE FROM core.calendar WHERE source='phase2_test_fixture';

INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES
    ('P2READY','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2ZERO','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2ENTRY','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2EXIT','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2GAP','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2MISS','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2EPISODE','HOSE','2098-01-05+07','2099-05-01+07'),
    ('P2STOCH','HOSE','2098-01-05+07','2099-05-01+07')
ON CONFLICT(symbol) DO NOTHING;

-- Three hundred twenty deterministic weekday sessions. They are deliberately synthetic
-- and do not claim to represent the Vietnamese exchange calendar.
INSERT INTO core.calendar(trade_date,is_session,source,notes)
SELECT d::date,true,'phase2_test_fixture','Synthetic-only Phase 2 SQL fixture'
FROM generate_series(DATE '2098-01-05',DATE '2099-04-30',INTERVAL '1 day') AS g(d)
WHERE extract(isodow FROM d) BETWEEN 1 AND 5
ORDER BY d
LIMIT 320
ON CONFLICT(trade_date) DO NOTHING;

WITH sessions AS (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)-1 AS n
    FROM core.calendar
    WHERE source='phase2_test_fixture'
), symbols(symbol,ingest_id) AS (
    VALUES
      ('P2READY','20000000-0000-4000-8000-000000000201'::uuid),
      ('P2ZERO','20000000-0000-4000-8000-000000000202'::uuid),
      ('P2ENTRY','20000000-0000-4000-8000-000000000203'::uuid),
      ('P2EXIT','20000000-0000-4000-8000-000000000204'::uuid),
      ('P2GAP','20000000-0000-4000-8000-000000000211'::uuid),
      ('P2MISS','20000000-0000-4000-8000-000000000205'::uuid),
      ('P2EPISODE','20000000-0000-4000-8000-000000000206'::uuid),
      ('P2STOCH','20000000-0000-4000-8000-000000000209'::uuid)
), base AS (
    SELECT s.symbol,s.ingest_id,ss.trade_date,ss.n,
           CASE WHEN s.symbol='P2READY' THEN 100.0+2*ss.n
                WHEN s.symbol='P2STOCH' AND ss.n<3 THEN 500.0 ELSE 100.0 END AS open_price,
           CASE WHEN s.symbol='P2READY' THEN 101.0+2*ss.n
                WHEN s.symbol='P2STOCH' AND ss.n<3 THEN 500.0 ELSE 100.0 END AS close_price,
           CASE
             WHEN s.symbol='P2READY' THEN 1000.0
             WHEN s.symbol='P2STOCH' THEN 1000.0
             WHEN s.symbol='P2ZERO' AND (ss.n=0 OR ss.n>=25) THEN 1000.0
             WHEN s.symbol='P2ENTRY' AND ss.n=0 THEN 1000.0
             WHEN s.symbol='P2EXIT' AND ss.n IN (0,1) THEN 1000.0
             WHEN s.symbol='P2GAP' THEN 1000.0
             WHEN s.symbol='P2MISS' AND ss.n IN (0,6) THEN 1000.0
             WHEN s.symbol='P2EPISODE' AND ss.n IN (0,1,6) THEN 1000.0
             ELSE 0.0
           END AS volume
    FROM symbols s CROSS JOIN sessions ss
    WHERE NOT (s.symbol='P2MISS' AND ss.n=1)
      AND NOT (s.symbol='P2GAP' AND ss.n=3)
), bars AS (
    SELECT b.*,
           CASE WHEN b.volume=0 THEN lag(b.close_price) OVER w ELSE b.open_price END AS effective_open,
           CASE WHEN b.volume=0 THEN lag(b.close_price) OVER w ELSE b.close_price END AS effective_close,
           lag(b.close_price) OVER w AS previous_close
    FROM base b
    WINDOW w AS (PARTITION BY b.symbol ORDER BY b.trade_date)
), docs AS (
    SELECT b.symbol,b.ingest_id,
           jsonb_build_object('data',jsonb_agg(
               jsonb_build_object(
                   'code',b.symbol,'date',to_char(b.trade_date,'YYYY-MM-DD'),
                   'open',b.effective_open,
                   'high',CASE WHEN b.symbol='P2STOCH' AND b.n<3 THEN 1000.0
                               WHEN b.symbol='P2STOCH' THEN b.effective_close+1
                               ELSE greatest(b.effective_open,b.effective_close) END,
                   'low',CASE WHEN b.symbol='P2STOCH' AND b.n<3 THEN 1.0
                              WHEN b.symbol='P2STOCH' THEN b.effective_close-1
                              ELSE least(b.effective_open,b.effective_close) END,
                   'close',b.effective_close,
                   'volume',b.volume,
                   'basicPrice',coalesce(b.previous_close,b.effective_close),
                   'average',CASE WHEN b.volume>0 THEN b.effective_close ELSE 0 END,
                   'floor','HOSE','adOpen',b.effective_open,
                   'adHigh',CASE WHEN b.symbol='P2STOCH' AND b.n<3 THEN 1000.0
                                 WHEN b.symbol='P2STOCH' THEN b.effective_close+1
                                 ELSE greatest(b.effective_open,b.effective_close) END,
                   'adLow',CASE WHEN b.symbol='P2STOCH' AND b.n<3 THEN 1.0
                                WHEN b.symbol='P2STOCH' THEN b.effective_close-1
                                ELSE least(b.effective_open,b.effective_close) END,
                   'adClose',b.effective_close
               ) ORDER BY b.trade_date
           )) AS payload
    FROM bars b
    GROUP BY b.symbol,b.ingest_id
), landings AS (
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    SELECT d.ingest_id,'vndirect','equity_ohlcv','2099-05-01 10:00:00+07',d.symbol,d.payload,
           encode(sha256(convert_to(d.payload::text,'UTF8')),'hex'),convert_to(d.payload::text,'UTF8')
    FROM docs d
    RETURNING landing_id,ingest_id,fetched_at,symbol,payload
)
INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,
     ingest_id,fetched_at,adjusted_o,adjusted_h,adjusted_l,adjusted_c,adjustment_vintage_at,
     basic_price,average_price,exchange_code)
SELECT s.symbol_id,(x.item->>'date')::date,'vndirect',
       (x.item->>'open')::double precision,(x.item->>'high')::double precision,
       (x.item->>'low')::double precision,(x.item->>'close')::double precision,
       (x.item->>'volume')::double precision,'unadjusted',
       (x.item->>'volume')::double precision>0,
       l.landing_id,(x.ordinality-1)::integer,l.ingest_id,l.fetched_at,
       (x.item->>'open')::double precision,(x.item->>'high')::double precision,
       (x.item->>'low')::double precision,(x.item->>'close')::double precision,l.fetched_at,
       (x.item->>'basicPrice')::double precision,(x.item->>'average')::double precision,'HOSE'
FROM landings l
CROSS JOIN LATERAL jsonb_array_elements(l.payload->'data') WITH ORDINALITY AS x(item,ordinality)
JOIN core.symbols s ON s.symbol=l.symbol;

-- Matched-index rows provide deterministic benchmark endpoints for both labels.
WITH sessions AS (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)-1 AS n
    FROM core.calendar WHERE source='phase2_test_fixture'
), landing AS (
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('20000000-0000-4000-8000-000000000207','vndirect','index_ohlcv',
            '2099-05-01 10:01:00+07','VNINDEX','{"fixture":"synthetic-only"}'::jsonb,
            encode(sha256(convert_to('{"fixture":"synthetic-only"}','UTF8')),'hex'),
            convert_to('{"fixture":"synthetic-only"}','UTF8'))
    RETURNING ingest_id,fetched_at
)
INSERT INTO core.index_bars(index_symbol,trade_date,o,h,l,c,v,source,ingest_id,fetched_at)
SELECT 'VNINDEX',s.trade_date,1000+s.n,1001+s.n,999+s.n,1000.5+s.n,1000000,
       'vndirect',l.ingest_id,l.fetched_at
FROM sessions s CROSS JOIN landing l;

-- V3's benchmark source is the registered VCI index route. Keep the synthetic
-- VNDIRECT index capture above for unchanged V2 fixture behavior.
WITH sessions AS (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)-1 AS n
    FROM core.calendar WHERE source='phase2_test_fixture'
), landing AS (
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    VALUES ('20000000-0000-4000-8000-000000000209','vci','index_ohlcv',
            '2099-05-01 10:03:00+07','VNINDEX','{"fixture":"synthetic-vci-only"}'::jsonb,
            encode(sha256(convert_to('{"fixture":"synthetic-vci-only"}','UTF8')),'hex'),
            convert_to('{"fixture":"synthetic-vci-only"}','UTF8'))
    RETURNING ingest_id,fetched_at
)
INSERT INTO core.index_bars(index_symbol,trade_date,o,h,l,c,v,source,ingest_id,fetched_at)
SELECT 'VNINDEX',s.trade_date,3000+4*s.n,3001+4*s.n,2999+4*s.n,3000.5+4*s.n,1000000,
       'vci',l.ingest_id,l.fetched_at
FROM sessions s CROSS JOIN landing l;

-- Valid, hash-verified notice bytes are required by migration 007's lifecycle
-- evidence trigger. These notices exist only to test episode separation.
WITH notice AS (
    SELECT '{"notice":"synthetic-only relisting test evidence"}'::text AS body
), landing AS (
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    SELECT '20000000-0000-4000-8000-000000000208','fixture','security_lifecycle_notice',
           '2099-05-01 10:02:00+07','P2EPISODE',body::jsonb,
           encode(sha256(convert_to(body,'UTF8')),'hex'),convert_to(body,'UTF8')
    FROM notice
    WHERE NOT EXISTS (
        SELECT 1 FROM core.security_lifecycle_evidence e
        JOIN core.symbols s ON s.symbol_id=e.symbol_id
        WHERE s.symbol='P2EPISODE'
    )
    RETURNING landing_id,fetched_at
)
INSERT INTO core.security_lifecycle_evidence
    (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,
     source_document_date,first_observed_at)
SELECT s.symbol_id,'HOSE',e.evidence_type,e.date_from,e.date_to,l.landing_id,
       'https://example.invalid/synthetic-phase2-fixture',e.date_from,l.fetched_at
FROM core.symbols s CROSS JOIN landing l
CROSS JOIN LATERAL (
    SELECT 'DELISTED'::text AS evidence_type,
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 2 LIMIT 1) AS date_from,
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 2 LIMIT 1) AS date_to
    UNION ALL
    SELECT 'TRADE_ELIGIBLE',
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 3 LIMIT 1),NULL::date
) e
WHERE s.symbol='P2EPISODE';

-- A second synthetic security keeps a complete feature window on both sides
-- of a relisting. Its pre-episode high/low are deliberately extreme so a
-- stochastic window that crosses the boundary gives a visibly wrong result.
WITH notice AS (
    SELECT '{"notice":"synthetic-only stochastic episode reset test"}'::text AS body
), landing AS (
    INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
    SELECT '20000000-0000-4000-8000-000000000210','fixture','security_lifecycle_notice',
           '2099-05-01 10:03:00+07','P2STOCH',body::jsonb,
           encode(sha256(convert_to(body,'UTF8')),'hex'),convert_to(body,'UTF8')
    FROM notice
    WHERE NOT EXISTS (
        SELECT 1 FROM core.security_lifecycle_evidence e
        JOIN core.symbols s ON s.symbol_id=e.symbol_id
        WHERE s.symbol='P2STOCH'
    )
    RETURNING landing_id,fetched_at
)
INSERT INTO core.security_lifecycle_evidence
    (symbol_id,exchange,evidence_type,date_from,date_to,source_landing_id,source_url,
     source_document_date,first_observed_at)
SELECT s.symbol_id,'HOSE',e.evidence_type,e.date_from,e.date_to,l.landing_id,
       'https://example.invalid/synthetic-phase2-stochastic-episode',e.date_from,l.fetched_at
FROM core.symbols s CROSS JOIN landing l
CROSS JOIN LATERAL (
    SELECT 'DELISTED'::text AS evidence_type,
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 2 LIMIT 1) AS date_from,
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 2 LIMIT 1) AS date_to
    UNION ALL
    SELECT 'TRADE_ELIGIBLE',
           (SELECT trade_date FROM core.calendar WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 3 LIMIT 1),NULL::date
) e
WHERE s.symbol='P2STOCH';

COMMIT;

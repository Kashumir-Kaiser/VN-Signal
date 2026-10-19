BEGIN;

INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES
    ('TSTADJ','HOSE','2024-11-29 00:00:00+07','2024-12-02 00:00:00+07'),
    ('TSTDIV','HNX','2023-03-29 00:00:00+07','2026-10-16 00:00:00+07'),
    ('TSTUPC','UPCOM','2024-01-02 00:00:00+07','2024-01-03 00:00:00+07'),
    ('TSTREF','HOSE','2018-12-28 00:00:00+07','2019-01-02 00:00:00+07'),
    ('DSN','HOSE','2018-12-28 00:00:00+07','2019-01-02 00:00:00+07');

INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES (
    '00000000-0000-4000-8000-000000000066',
    'vndirect',
    'equity_ohlcv',
    '2026-10-18 10:00:00+07',
    'TSTADJ',
    '{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"basicPrice":100,"average":100,"floor":"HOSE","adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"basicPrice":99,"average":74,"floor":"HOSE","adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}'::jsonb,
    encode(sha256(convert_to('{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"basicPrice":100,"average":100,"floor":"HOSE","adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"basicPrice":99,"average":74,"floor":"HOSE","adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}','UTF8')),'hex'),
    convert_to('{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"basicPrice":100,"average":100,"floor":"HOSE","adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"basicPrice":99,"average":74,"floor":"HOSE","adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}','UTF8')
);

INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES (
    '00000000-0000-4000-8000-000000000067',
    'vndirect',
    'equity_ohlcv',
    '2026-10-18 10:00:00+07',
    'TSTDIV',
    '{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"basicPrice":68,"average":68,"floor":"HNX","adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"basicPrice":33,"average":30.2,"floor":"HNX","adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"basicPrice":30.2,"average":8.8,"floor":"HNX","adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}'::jsonb,
    encode(sha256(convert_to('{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"basicPrice":68,"average":68,"floor":"HNX","adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"basicPrice":33,"average":30.2,"floor":"HNX","adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"basicPrice":30.2,"average":8.8,"floor":"HNX","adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')),'hex'),
    convert_to('{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"basicPrice":68,"average":68,"floor":"HNX","adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"basicPrice":33,"average":30.2,"floor":"HNX","adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"basicPrice":30.2,"average":8.8,"floor":"HNX","adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')
);

INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES (
    '00000000-0000-4000-8000-000000000068',
    'vndirect',
    'equity_ohlcv',
    '2026-10-18 10:00:00+07',
    'TSTUPC',
    '{"data":[{"code":"TSTUPC","date":"2024-01-02","open":10,"high":10.2,"low":9.9,"close":10,"basicPrice":10,"average":11,"floor":"UPCOM","adOpen":10,"adHigh":10.2,"adLow":9.9,"adClose":10},{"code":"TSTUPC","date":"2024-01-03","open":10,"high":10,"low":10,"close":10,"basicPrice":11,"average":10,"floor":"UPCOM","adOpen":10,"adHigh":10,"adLow":10,"adClose":10},{"code":"TSTUPC","date":"2024-01-04","open":6.1,"high":6.3,"low":6,"close":6.2,"basicPrice":6,"average":6.1,"floor":"UPCOM","adOpen":6.1,"adHigh":6.3,"adLow":6,"adClose":6.2}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}'::jsonb,
    encode(sha256(convert_to('{"data":[{"code":"TSTUPC","date":"2024-01-02","open":10,"high":10.2,"low":9.9,"close":10,"basicPrice":10,"average":11,"floor":"UPCOM","adOpen":10,"adHigh":10.2,"adLow":9.9,"adClose":10},{"code":"TSTUPC","date":"2024-01-03","open":10,"high":10,"low":10,"close":10,"basicPrice":11,"average":10,"floor":"UPCOM","adOpen":10,"adHigh":10,"adLow":10,"adClose":10},{"code":"TSTUPC","date":"2024-01-04","open":6.1,"high":6.3,"low":6,"close":6.2,"basicPrice":6,"average":6.1,"floor":"UPCOM","adOpen":6.1,"adHigh":6.3,"adLow":6,"adClose":6.2}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')),'hex'),
    convert_to('{"data":[{"code":"TSTUPC","date":"2024-01-02","open":10,"high":10.2,"low":9.9,"close":10,"basicPrice":10,"average":11,"floor":"UPCOM","adOpen":10,"adHigh":10.2,"adLow":9.9,"adClose":10},{"code":"TSTUPC","date":"2024-01-03","open":10,"high":10,"low":10,"close":10,"basicPrice":11,"average":10,"floor":"UPCOM","adOpen":10,"adHigh":10,"adLow":10,"adClose":10},{"code":"TSTUPC","date":"2024-01-04","open":6.1,"high":6.3,"low":6,"close":6.2,"basicPrice":6,"average":6.1,"floor":"UPCOM","adOpen":6.1,"adHigh":6.3,"adLow":6,"adClose":6.2}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')
);

WITH payload AS (
    SELECT '{"data":[{"code":"TSTREF","date":"2018-12-28","open":9.9,"high":10,"low":9.8,"close":10,"basicPrice":10,"average":9.95,"floor":"HOSE","adOpen":9.9,"adHigh":10,"adLow":9.8,"adClose":10},{"code":"TSTREF","date":"2019-01-02","open":10.1,"high":10.2,"low":10,"close":10.2,"basicPrice":0,"average":10.15,"floor":"HOSE","adOpen":10.1,"adHigh":10.2,"adLow":10,"adClose":10.2}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}'::text AS raw
), parsed AS (
    SELECT raw,raw::jsonb AS payload FROM payload
)
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT '00000000-0000-4000-8000-000000000069','vndirect','equity_ohlcv',
       '2026-10-18 10:00:00+07','TSTREF',payload,
       encode(sha256(convert_to(raw,'UTF8')),'hex'),convert_to(raw,'UTF8')
FROM parsed;

WITH payload AS (
    SELECT '{"data":[{"code":"DSN","date":"2018-12-28","open":63,"high":63.2,"low":62.8,"close":62.9,"basicPrice":63,"average":62.95,"floor":"HOSE","adOpen":34.242,"adHigh":34.351,"adLow":34.133,"adClose":34.188},{"code":"DSN","date":"2019-01-02","open":59.5,"high":59.5,"low":58.5,"close":58.5,"basicPrice":0,"average":59.27,"floor":"HOSE","adOpen":34.302,"adHigh":34.302,"adLow":33.726,"adClose":33.726}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}'::text AS raw
), parsed AS (
    SELECT raw,raw::jsonb AS payload FROM payload
)
INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT '00000000-0000-4000-8000-000000000070','vndirect','equity_ohlcv',
       '2026-10-18 10:00:00+07','DSN',payload,
       encode(sha256(convert_to(raw,'UTF8')),'hex'),convert_to(raw,'UTF8')
FROM parsed;

INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,x.trade_date,'vndirect',x.o,x.h,x.l,x.c,1000,'unadjusted',true,
       l.landing_id,x.source_row,l.ingest_id,l.fetched_at
FROM core.symbols s
CROSS JOIN (VALUES
    ('2024-11-29'::date,101.0::double precision,102.0::double precision,99.0::double precision,100.0::double precision,0),
    ('2024-12-02'::date,74.5::double precision,75.0::double precision,73.0::double precision,74.0::double precision,1)
) AS x(trade_date,o,h,l,c,source_row)
JOIN raw.landings l ON l.ingest_id='00000000-0000-4000-8000-000000000066'
WHERE s.symbol='TSTADJ';

INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,x.trade_date,'vndirect',x.o,x.h,x.l,x.c,x.v,'unadjusted',true,
       l.landing_id,x.source_row,l.ingest_id,l.fetched_at
FROM core.symbols s
CROSS JOIN (VALUES
    ('2023-03-29'::date,65.0::double precision,70.0::double precision,63.0::double precision,68.0::double precision,36000.0::double precision,0),
    ('2023-03-30'::date,33.0::double precision,33.0::double precision,30.1::double precision,30.2::double precision,36609.0::double precision,1),
    ('2026-10-16'::date,8.7::double precision,8.8::double precision,8.5::double precision,8.8::double precision,1260.0::double precision,2)
) AS x(trade_date,o,h,l,c,v,source_row)
JOIN raw.landings l ON l.ingest_id='00000000-0000-4000-8000-000000000067'
WHERE s.symbol='TSTDIV';

INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,x.trade_date,'vndirect',x.o,x.h,x.l,x.c,x.v,'unadjusted',x.v>0,
       l.landing_id,x.source_row,l.ingest_id,l.fetched_at
FROM core.symbols s
CROSS JOIN (VALUES
    ('2024-01-02'::date,10.0::double precision,10.2::double precision,9.9::double precision,10.0::double precision,1000.0::double precision,0),
    ('2024-01-03'::date,10.0::double precision,10.0::double precision,10.0::double precision,10.0::double precision,0.0::double precision,1),
    ('2024-01-04'::date,6.1::double precision,6.3::double precision,6.0::double precision,6.2::double precision,1000.0::double precision,2)
) AS x(trade_date,o,h,l,c,v,source_row)
JOIN raw.landings l ON l.ingest_id='00000000-0000-4000-8000-000000000068'
WHERE s.symbol='TSTUPC';

INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,x.trade_date,'vndirect',x.o,x.h,x.l,x.c,x.v,'unadjusted',true,
       l.landing_id,x.source_row,l.ingest_id,l.fetched_at
FROM core.symbols s
CROSS JOIN (VALUES
    ('2018-12-28'::date,9.9::double precision,10.0::double precision,9.8::double precision,10.0::double precision,1000.0::double precision,0),
    ('2019-01-02'::date,10.1::double precision,10.2::double precision,10.0::double precision,10.2::double precision,1000.0::double precision,1)
) AS x(trade_date,o,h,l,c,v,source_row)
JOIN raw.landings l ON l.ingest_id='00000000-0000-4000-8000-000000000069'
WHERE s.symbol='TSTREF';

INSERT INTO core.bars_daily_sources
    (symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,landing_id,source_row,ingest_id,fetched_at)
SELECT s.symbol_id,x.trade_date,'vndirect',x.o,x.h,x.l,x.c,x.v,'unadjusted',true,
       l.landing_id,x.source_row,l.ingest_id,l.fetched_at
FROM core.symbols s
CROSS JOIN (VALUES
    ('2018-12-28'::date,63.0::double precision,63.2::double precision,62.8::double precision,62.9::double precision,2000.0::double precision,0),
    ('2019-01-02'::date,59.5::double precision,59.5::double precision,58.5::double precision,58.5::double precision,3860.0::double precision,1)
) AS x(trade_date,o,h,l,c,v,source_row)
JOIN raw.landings l ON l.ingest_id='00000000-0000-4000-8000-000000000070'
WHERE s.symbol='DSN';

COMMIT;

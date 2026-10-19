BEGIN;

INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
VALUES
    ('TSTADJ','HOSE','2024-11-29 00:00:00+07','2024-12-02 00:00:00+07'),
    ('TSTDIV','HNX','2023-03-29 00:00:00+07','2026-10-16 00:00:00+07');

INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES (
    '00000000-0000-4000-8000-000000000066',
    'vndirect',
    'equity_ohlcv',
    '2026-10-18 10:00:00+07',
    'TSTADJ',
    '{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}'::jsonb,
    encode(sha256(convert_to('{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}','UTF8')),'hex'),
    convert_to('{"data":[{"code":"TSTADJ","date":"2024-11-29","open":101,"high":102,"low":99,"close":100,"adOpen":75.75,"adHigh":76.5,"adLow":74.25,"adClose":75},{"code":"TSTADJ","date":"2024-12-02","open":74.5,"high":75,"low":73,"close":74,"adOpen":55.875,"adHigh":56.25,"adLow":54.75,"adClose":55.5}],"currentPage":1,"size":5000,"totalElements":2,"totalPages":1}','UTF8')
);

INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
VALUES (
    '00000000-0000-4000-8000-000000000067',
    'vndirect',
    'equity_ohlcv',
    '2026-10-18 10:00:00+07',
    'TSTDIV',
    '{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}'::jsonb,
    encode(sha256(convert_to('{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')),'hex'),
    convert_to('{"data":[{"code":"TSTDIV","date":"2023-03-29","open":65,"high":70,"low":63,"close":68,"adOpen":9.569,"adHigh":10.305,"adLow":9.274,"adClose":10.01},{"code":"TSTDIV","date":"2023-03-30","open":33,"high":33,"low":30.1,"close":30.2,"adOpen":10.01,"adHigh":10.01,"adLow":9.13,"adClose":9.161},{"code":"TSTDIV","date":"2026-10-16","open":8.7,"high":8.8,"low":8.5,"close":8.8,"adOpen":8.7,"adHigh":8.8,"adLow":8.5,"adClose":8.8}],"currentPage":1,"size":5000,"totalElements":3,"totalPages":1}','UTF8')
);

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

COMMIT;

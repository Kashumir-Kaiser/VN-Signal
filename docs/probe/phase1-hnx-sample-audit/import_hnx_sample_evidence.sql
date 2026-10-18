\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE hnx_sample_import_stage (
    symbol text NOT NULL,
    market text NOT NULL,
    trade_date date NOT NULL,
    source_row integer NOT NULL,
    buy_order_count integer NOT NULL,
    buy_order_volume numeric(24,0) NOT NULL,
    sell_order_count integer NOT NULL,
    sell_order_volume numeric(24,0) NOT NULL,
    total_matched_volume numeric(24,0) NOT NULL,
    total_matched_value_vnd numeric(30,0) NOT NULL,
    source_url text NOT NULL,
    payload_sha256 text NOT NULL,
    payload_base64 text NOT NULL
) ON COMMIT DROP;

\copy hnx_sample_import_stage FROM 'docs/probe/phase1-hnx-sample-audit/sample-evidence-import.csv' WITH (FORMAT csv, HEADER true)

DO $validate_import$
BEGIN
    IF (SELECT count(*) FROM hnx_sample_import_stage) <> 16
       OR EXISTS (
           SELECT 1 FROM hnx_sample_import_stage s
           WHERE encode(sha256(decode(s.payload_base64,'base64')),'hex') <> lower(s.payload_sha256)
              OR s.market <> 'UPCOM'
              OR s.total_matched_volume <> 0
              OR s.total_matched_value_vnd <> 0
              OR s.symbol NOT IN ('CDG','GGG','HPI','NAS','SBD','SDD','SHC','SNC',
                                  'SPC','SVG','TNB','VFC','VNI','VNX','XMC','XPH')
       ) THEN
        RAISE EXCEPTION 'HNX sample import failed count, identity, zero-total, or raw-hash validation';
    END IF;
END;
$validate_import$;

INSERT INTO raw.landings
    (ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
SELECT gen_random_uuid(),'hnx','exchange_daily_report',now(),s.symbol,
       jsonb_build_object(
           'symbol',s.symbol,'market',s.market,
           'trade_date',to_char(s.trade_date,'YYYY-MM-DD'),
           'source_row',s.source_row,
           'buy_order_count',s.buy_order_count,
           'buy_order_volume',s.buy_order_volume,
           'sell_order_count',s.sell_order_count,
           'sell_order_volume',s.sell_order_volume,
           'total_matched_volume',s.total_matched_volume,
           'total_matched_value_vnd',s.total_matched_value_vnd,
           'source_url',s.source_url
       ),
       encode(sha256(decode(s.payload_base64,'base64')),'hex'),
       decode(s.payload_base64,'base64')
FROM hnx_sample_import_stage s
WHERE NOT EXISTS (
    SELECT 1 FROM raw.landings l
    WHERE l.source='hnx' AND l.route='exchange_daily_report'
      AND l.payload_sha256=lower(s.payload_sha256)
);

INSERT INTO ops.exchange_daily_bar_evidence
    (source,market,symbol_id,trade_date,source_row,buy_order_count,
     buy_order_volume,sell_order_count,sell_order_volume,
     total_matched_volume,total_matched_value_vnd,landing_id,source_url)
SELECT 'hnx',s.market,sym.symbol_id,s.trade_date,s.source_row,
       s.buy_order_count,s.buy_order_volume,s.sell_order_count,s.sell_order_volume,
       s.total_matched_volume,s.total_matched_value_vnd,l.landing_id,s.source_url
FROM hnx_sample_import_stage s
JOIN core.symbols sym ON sym.symbol=s.symbol
JOIN raw.landings l ON l.source='hnx' AND l.route='exchange_daily_report'
                    AND l.payload_sha256=lower(s.payload_sha256)
WHERE NOT EXISTS (
    SELECT 1 FROM ops.exchange_daily_bar_evidence e
    WHERE e.landing_id=l.landing_id AND e.source_row=s.source_row
);

COMMIT;

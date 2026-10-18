\set ON_ERROR_STOP on
BEGIN;

CREATE TEMP TABLE hnx_interpretation_stage (
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
    total_negotiated_volume numeric(24,0) NOT NULL,
    total_negotiated_value_vnd numeric(30,0) NOT NULL,
    total_market_volume numeric(24,0) NOT NULL,
    total_market_value_vnd numeric(30,0) NOT NULL,
    source_url text NOT NULL,
    payload_sha256 text NOT NULL,
    CHECK (total_matched_volume + total_negotiated_volume = total_market_volume),
    CHECK (total_matched_value_vnd + total_negotiated_value_vnd = total_market_value_vnd)
) ON COMMIT DROP;

\copy hnx_interpretation_stage FROM 'docs/probe/phase1-simplize-history-audit/hnx-interpretation-import.csv' WITH (FORMAT csv, HEADER true)

DO $validate_interpretation$
BEGIN
    IF (SELECT count(*) FROM hnx_interpretation_stage) <> 3
       OR EXISTS (
           SELECT 1 FROM hnx_interpretation_stage s
           WHERE s.symbol <> 'VNX' OR s.market <> 'UPCOM'
              OR s.total_matched_volume <> 0 OR s.total_matched_value_vnd <> 0
              OR s.source_url !~ '^https://(www\.)?hnx\.vn/'
              OR s.payload_sha256 !~ '^[0-9a-fA-F]{64}$'
       )
       OR EXISTS (
           SELECT 1 FROM (VALUES
               ('2026-01-29'::date,15100::numeric,175160000::numeric),
               ('2026-01-30'::date,4900::numeric,56840000::numeric),
               ('2026-02-12'::date,4900::numeric,56840000::numeric)
           ) expected(trade_date,negotiated_volume,negotiated_value)
           WHERE NOT EXISTS (
               SELECT 1 FROM hnx_interpretation_stage s
               WHERE s.trade_date=expected.trade_date
                 AND s.total_negotiated_volume=expected.negotiated_volume
                 AND s.total_negotiated_value_vnd=expected.negotiated_value
           )
       ) THEN
        RAISE EXCEPTION 'HNX interpretation stage failed exact-date or component validation';
    END IF;
    IF EXISTS (
        SELECT 1 FROM hnx_interpretation_stage s
        WHERE (SELECT count(*)
               FROM ops.exchange_daily_bar_evidence e
               JOIN core.symbols sym ON sym.symbol_id=e.symbol_id
               JOIN raw.landings l ON l.landing_id=e.landing_id
               WHERE e.source='hnx' AND e.market=s.market AND sym.symbol=s.symbol
                 AND e.trade_date=s.trade_date AND e.source_row=s.source_row
                 AND l.payload_sha256=lower(s.payload_sha256)
                 AND e.total_matched_volume=s.total_market_volume
                 AND e.total_matched_value_vnd=s.total_market_value_vnd) <> 1
    ) THEN
        RAISE EXCEPTION 'each correction must identify exactly one existing immutable HNX report row';
    END IF;
END;
$validate_interpretation$;

INSERT INTO ops.exchange_daily_bar_evidence_interpretations
    (evidence_id,parser_version,total_matched_volume,total_matched_value_vnd,
     total_negotiated_volume,total_negotiated_value_vnd,
     total_market_volume,total_market_value_vnd,source_field_map,interpretation_note)
SELECT e.evidence_id,'hnx_upcom_report_columns_v1',
       s.total_matched_volume,s.total_matched_value_vnd,
       s.total_negotiated_volume,s.total_negotiated_value_vnd,
       s.total_market_volume,s.total_market_value_vnd,
       jsonb_build_object(
           'matched_volume_columns',jsonb_build_array('Khớp lệnh liên tục','Khớp lệnh định kỳ đóng cửa','Phiên sau giờ'),
           'negotiated_volume_column','Thỏa thuận',
           'total_market_volume_column','Toàn thị trường',
           'raw_payload_sha256',lower(s.payload_sha256)),
       'Corrects the first-pass parser, which read the Toàn thị trường total as matched volume. The HNX report shows these VNX sessions had negotiated volume and zero order-book matched volume.'
FROM hnx_interpretation_stage s
JOIN core.symbols sym ON sym.symbol=s.symbol
JOIN ops.exchange_daily_bar_evidence e
  ON e.symbol_id=sym.symbol_id AND e.market=s.market AND e.trade_date=s.trade_date
 AND e.source='hnx' AND e.source_row=s.source_row
JOIN raw.landings l ON l.landing_id=e.landing_id
                    AND l.payload_sha256=lower(s.payload_sha256)
WHERE NOT EXISTS (
    SELECT 1 FROM ops.exchange_daily_bar_evidence_interpretations i
    WHERE i.evidence_id=e.evidence_id
      AND i.parser_version='hnx_upcom_report_columns_v1'
);

DO $verify_interpretation$
BEGIN
    IF (SELECT count(*) FROM ops.exchange_daily_bar_evidence_interpretations i
        JOIN ops.exchange_daily_bar_evidence e USING (evidence_id)
        JOIN core.symbols s USING (symbol_id)
        WHERE s.symbol='VNX' AND e.trade_date IN ('2026-01-29','2026-01-30','2026-02-12')
          AND i.parser_version='hnx_upcom_report_columns_v1'
          AND i.total_matched_volume=0 AND i.total_negotiated_volume>0) <> 3 THEN
        RAISE EXCEPTION 'expected three append-only negotiated-only HNX interpretations';
    END IF;
    IF EXISTS (
        SELECT 1 FROM ops.zero_volume_lifecycle_status
        WHERE symbol='VNX' AND trade_date IN ('2026-01-29','2026-01-30','2026-02-12')
          AND derived_lifecycle_status <> 'VERIFIED_NEGOTIATED_ONLY'
    ) THEN
        RAISE EXCEPTION 'zero-volume issue statuses do not reflect the corrected HNX interpretation';
    END IF;
END;
$verify_interpretation$;

COMMIT;

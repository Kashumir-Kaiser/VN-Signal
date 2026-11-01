\set ON_ERROR_STOP on
\pset format csv
\pset footer off

-- Full-range E4 continuity detail after GDW HNX final-session and first-trade notices were imported for the current-hash V3 candidate after the previously recorded transfers, the ABT/VFG/BSI/ASG HNX group-source transfers, the HBC/HNG HOSE-to-UPCoM transfers, and the PXT HOSE-to-UPCoM, BSR UPCoM-to-HOSE, and HVN, PGV, BCM, BVB, EVF, MZG, NTC, TAL, DSC, ECO, HTG, MCM, VIB, VTP, GEG, and GVR, TDM, KOS, NHH, SIP, MIG, PVP, TSA, and KLB UPCoM-to-HOSE transfers; and VGC, TV2, DBC, DGC, VIX, and NHA HNX-to-HOSE transfers; and HAP, LAF, PAN, QBS, SSC, TVB, and VND HOSE-to-HNX transfers; and AGF, CMT, DIC, GMC, ICF, LMH, MCG, NSC, PPI, PXI, SCD, UDC, and VHG HOSE-to-HNX/UPCoM transfers; and ABR, AFX, ANT, CCC, MCH, NAB, NHT, ORS, VAB, and VVS UPCoM-to-HOSE transfers; and HU3 and SII HOSE-to-UPCoM transfers; and HOT HOSE-to-UPCoM transfer; plus the SHB HNX-to-HOSE, SPC UPCoM-to-HNX, and TNA HOSE-to-UPCoM transfers.
-- It creates only a connection-local temporary table; the report transaction
-- and all permanent application data remain read-only. Run from the repository
-- root against the report clone. The \\copy output is the exact interval
-- population behind the 97-chunk census count.

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL statement_timeout = '900s';
SET LOCAL lock_timeout = '5s';
SET LOCAL work_mem = '8MB';
SET LOCAL temp_file_limit = '20GB';

SELECT current_database() = 'vnsignal_phase2_report_20261019' AS target_ok \gset
\if :target_ok
\else
  \echo 'Refusing to run outside vnsignal_phase2_report_20261019'
  \quit 2
\endif

DO $assert$
BEGIN
  IF feat.phase2_feature_set_hash_v3() <> '28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b' THEN
    RAISE EXCEPTION 'current feature hash differs from E4 census candidate';
  END IF;
END
$assert$;

DROP TABLE IF EXISTS pg_temp.e4_current_gap_pairs;
CREATE TEMP TABLE e4_current_gap_pairs ON COMMIT PRESERVE ROWS AS
WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), sequence AS (
    SELECT f.symbol_id, f.trade_date, s.session_no,
           lag(f.trade_date) OVER (
               PARTITION BY f.symbol_id ORDER BY s.session_no
           ) AS prior_trade_date,
           lag(s.session_no) OVER (
               PARTITION BY f.symbol_id ORDER BY s.session_no
           ) AS prior_session_no
    FROM feat.features_daily f
    JOIN sessions s USING (trade_date)
    WHERE f.feature_version = 'phase2-v3'
      AND f.feature_set_hash = feat.phase2_feature_set_hash_v3()
      AND f.trade_date >= DATE '2018-10-01'
      AND f.trade_date < DATE '2026-10-17'
), gaps AS (
    SELECT symbol_id, prior_trade_date, trade_date AS next_trade_date,
           (session_no - prior_session_no - 1)::integer AS missing_effective_sessions
    FROM sequence
    WHERE prior_session_no IS NOT NULL
      AND session_no - prior_session_no > 1
)
SELECT s.symbol, g.symbol_id, g.prior_trade_date, g.next_trade_date,
       g.missing_effective_sessions,
       (SELECT count(*)::integer FROM core.bars_daily b
        WHERE b.symbol_id=g.symbol_id
          AND b.trade_date>g.prior_trade_date AND b.trade_date<g.next_trade_date) AS bar_rows_between,
       (SELECT count(*)::integer FROM core.bars_daily_sources bs
        WHERE bs.symbol_id=g.symbol_id
          AND bs.trade_date>g.prior_trade_date AND bs.trade_date<g.next_trade_date) AS source_rows_between,
       EXISTS (
           SELECT 1 FROM ops.phase2_verified_security_transfers t
           JOIN core.security_listing_events e USING (event_id)
           WHERE t.symbol_id=g.symbol_id
             AND t.effective_date=g.next_trade_date
             AND t.prior_ceased_from>g.prior_trade_date
             AND t.prior_ceased_from<g.next_trade_date
       ) AS has_verified_transfer,
       (SELECT string_agg(
                   format('%s:%s>%s:%s:%s',t.event_id,t.prior_venue,t.venue,
                          t.prior_ceased_from,t.effective_date), '; ' ORDER BY t.event_id)
        FROM ops.phase2_verified_security_transfers t
        JOIN core.security_listing_events e USING (event_id)
        WHERE t.symbol_id=g.symbol_id
          AND t.effective_date=g.next_trade_date
          AND t.prior_ceased_from>g.prior_trade_date
          AND t.prior_ceased_from<g.next_trade_date) AS verified_transfer_refs
FROM gaps g
JOIN core.symbols s ON s.symbol_id=g.symbol_id;

COMMIT;

-- Reports below run against the connection-local snapshot table in a
-- read-only transaction. CTAS above writes only to PostgreSQL's temp schema.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout = '60s';

SELECT count(*) AS gap_intervals,
       coalesce(sum(missing_effective_sessions),0) AS missing_effective_sessions,
       count(*) FILTER (WHERE has_verified_transfer) AS verified_transfer_intervals,
       coalesce(sum(missing_effective_sessions) FILTER (WHERE has_verified_transfer),0) AS verified_transfer_sessions,
       count(*) FILTER (WHERE NOT has_verified_transfer) AS unclassified_intervals,
       coalesce(sum(missing_effective_sessions) FILTER (WHERE NOT has_verified_transfer),0) AS unclassified_sessions,
       count(*) FILTER (WHERE bar_rows_between<>0 OR source_rows_between<>0) AS intervals_with_bar_or_source_rows,
       count(*) FILTER (WHERE bar_rows_between<>0) AS intervals_with_bars,
       count(*) FILTER (WHERE source_rows_between<>0) AS intervals_with_source_rows
FROM e4_current_gap_pairs;

\copy (SELECT symbol,symbol_id,prior_trade_date,next_trade_date,missing_effective_sessions,bar_rows_between,source_rows_between,has_verified_transfer,verified_transfer_refs FROM e4_current_gap_pairs ORDER BY next_trade_date,symbol) TO 'docs\evidence\phase2\phase2_e4_remaining_gap_probe_20261031\gdw_hnx_deregistration_capture_20261102\phase2_e4_currenthash_gap_pairs_20261102_postgdw.csv' WITH (FORMAT csv,HEADER true)

COMMIT;















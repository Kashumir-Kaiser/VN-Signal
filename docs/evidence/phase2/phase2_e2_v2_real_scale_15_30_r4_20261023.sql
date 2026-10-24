\set ON_ERROR_STOP on
\pset pager off
\timing on

-- Rollback-only real-data timing probe for the V2 call that stalls in E2.
-- It uses the same PIT-stratified cohort and 40% cutoff as E2, but caches
-- adjustment rows for the nested 30-symbol subset before measuring 15/30.
BEGIN;
SET LOCAL statement_timeout = '9min';
SET LOCAL lock_timeout = '5s';
SET LOCAL idle_in_transaction_session_timeout = '25min';
SET LOCAL work_mem = '128MB';
SET LOCAL temp_file_limit = '90GB';
SET LOCAL jit = off;
SET LOCAL application_name = 'phase2_e2_v2_real_scale_15_30_r2';
LOAD 'auto_explain';
SET LOCAL auto_explain.log_min_duration = '1000ms';
SET LOCAL auto_explain.log_analyze = on;
SET LOCAL auto_explain.log_buffers = on;
SET LOCAL auto_explain.log_timing = on;
SET LOCAL auto_explain.log_nested_statements = on;
SET LOCAL auto_explain.log_level = 'log';
SET LOCAL client_min_messages = 'log';

DO $$
BEGIN
    IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'refusing real V2 profile outside disposable report clone';
    END IF;
    IF to_regprocedure('feat.build_features_v2_shared(date,date,bigint[])') IS NULL THEN
        RAISE EXCEPTION 'shared V2 builder is not installed';
    END IF;
END;
$$;

CREATE TEMP TABLE phase2_e2_profile_sessions ON COMMIT DROP AS
SELECT trade_date,row_number() OVER (ORDER BY trade_date)::bigint AS session_no
  FROM core.effective_trading_sessions
 WHERE is_session;
CREATE UNIQUE INDEX ON phase2_e2_profile_sessions(session_no);
CREATE UNIQUE INDEX ON phase2_e2_profile_sessions(trade_date);
ANALYZE phase2_e2_profile_sessions;

CREATE TEMP TABLE phase2_e2_profile_cut ON COMMIT DROP AS
SELECT s.trade_date AS cut_date
  FROM phase2_e2_profile_sessions s
 WHERE s.session_no = ceil((SELECT count(*) FROM phase2_e2_profile_sessions)*0.40)::bigint;

CREATE TEMP TABLE phase2_e2_profile_cohort ON COMMIT DROP AS
WITH pit_exchange AS MATERIALIZED (
    SELECT DISTINCT ON (b.symbol_id)
           b.symbol_id,b.exchange_code AS exchange,b.landing_id,b.source_row
      FROM core.bars_daily_sources b
     WHERE b.source='vndirect'
       AND b.trade_date<=(SELECT cut_date FROM phase2_e2_profile_cut)
     ORDER BY b.symbol_id,b.trade_date DESC
), trailing_turnover AS MATERIALIZED (
    SELECT f.symbol_id,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY f.turnover_proxy_vnd) AS median_turnover
      FROM feat.features_daily f
      JOIN core.effective_trading_sessions s ON s.trade_date=f.trade_date AND s.is_session
     WHERE f.feature_version='phase2-v2'
       AND f.trade_date<=(SELECT cut_date FROM phase2_e2_profile_cut)
       AND f.turnover_proxy_vnd>0
       AND s.trade_date>(
           SELECT trade_date FROM phase2_e2_profile_sessions
            WHERE session_no=greatest(1,ceil((SELECT count(*) FROM phase2_e2_profile_sessions)*0.40)::bigint-60)
       )
     GROUP BY f.symbol_id
    HAVING count(*)=60
), tiered AS (
    SELECT p.symbol_id,p.exchange,
           ntile(4) OVER (PARTITION BY p.exchange ORDER BY t.median_turnover,p.symbol_id) AS liquidity_tier
      FROM pit_exchange p
      JOIN trailing_turnover t USING(symbol_id)
     WHERE p.exchange IN ('HOSE','HNX','UPCOM')
       AND p.landing_id IS NOT NULL AND p.source_row IS NOT NULL
), strata AS (
    SELECT t.*,
           row_number() OVER (PARTITION BY exchange,liquidity_tier
                              ORDER BY md5(symbol_id::text||':phase2-e2'),symbol_id) AS within_stratum
      FROM tiered t
)
SELECT symbol_id,exchange,liquidity_tier,
       row_number() OVER (ORDER BY symbol_id)::integer AS symbol_ordinal
  FROM strata
 WHERE within_stratum<=5;
CREATE UNIQUE INDEX ON phase2_e2_profile_cohort(symbol_id);
ANALYZE phase2_e2_profile_cohort;

DO $$
BEGIN
    IF (SELECT count(*) FROM phase2_e2_profile_cohort)<>60
       OR EXISTS (SELECT 1 FROM phase2_e2_profile_cohort GROUP BY exchange,liquidity_tier HAVING count(*)<>5)
       OR (SELECT count(*) FROM (SELECT exchange,liquidity_tier FROM phase2_e2_profile_cohort GROUP BY 1,2) s)<>12 THEN
        RAISE EXCEPTION 'PIT cohort does not reproduce E2 60-symbol/12-stratum shape';
    END IF;
    RAISE NOTICE 'profile context: cohort=60, date_from=%, cut=%',
        (SELECT min(trade_date) FROM phase2_e2_profile_sessions),
        (SELECT cut_date FROM phase2_e2_profile_cut);
END;
$$;

-- Build the same canonical adjusted inputs as the production cache, limited
-- to the exact E2 cohort so the diagnostic does not touch the 1,518-symbol
-- universe. The builder's cache guard still validates the same reserved tables.
CREATE TEMP TABLE phase2_adjustment_rows ON COMMIT DROP AS
SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
       r.reference_adjustment_ratio,r.episode_start_date,
       r.model_o,r.model_h,r.model_l,r.model_c,
       r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
  FROM feat.phase2_vndirect_adjustment_details_for_symbols(
       (SELECT array_agg(symbol_id ORDER BY symbol_id) FROM phase2_e2_profile_cohort WHERE symbol_ordinal<=30)
  ) r
 WHERE r.source='vndirect';
COMMENT ON TABLE pg_temp.phase2_adjustment_rows IS
    'VN-Signal Phase 2 session-local point-in-time price input cache';
CREATE UNIQUE INDEX phase2_adjustment_rows_symbol_date_idx
    ON phase2_adjustment_rows(symbol_id,trade_date);
CREATE INDEX phase2_adjustment_rows_date_symbol_idx
    ON phase2_adjustment_rows(trade_date,symbol_id);
ANALYZE phase2_adjustment_rows;

CREATE TEMP TABLE phase2_adjustment_symbol_batches ON COMMIT DROP AS
SELECT symbol_id,0::integer AS batch_no,true AS loaded
  FROM phase2_adjustment_rows GROUP BY symbol_id;
COMMENT ON TABLE pg_temp.phase2_adjustment_symbol_batches IS
    'VN-Signal Phase 2 session-local cache symbol-batch manifest';
ALTER TABLE phase2_adjustment_symbol_batches ADD PRIMARY KEY(symbol_id);
CREATE INDEX phase2_adjustment_symbol_batches_batch_idx
    ON phase2_adjustment_symbol_batches(batch_no,symbol_id);
ANALYZE phase2_adjustment_symbol_batches;

CREATE TEMP TABLE phase2_adjustment_cache_state(
    cache_id integer PRIMARY KEY DEFAULT 1 CHECK(cache_id=1),
    ready boolean NOT NULL DEFAULT false,
    finalized_at timestamptz
) ON COMMIT DROP;
COMMENT ON TABLE pg_temp.phase2_adjustment_cache_state IS
    'VN-Signal Phase 2 session-local cache readiness state';
INSERT INTO phase2_adjustment_cache_state(ready,finalized_at)
VALUES(true,clock_timestamp());
SELECT feat.prepare_phase2_adjustment_rows(false);

CREATE TEMP TABLE phase2_e2_profile_metrics(
    cohort_symbols integer NOT NULL,
    sample_point text NOT NULL,
    recorded_at timestamptz NOT NULL,
    temp_files bigint NOT NULL,
    temp_bytes bigint NOT NULL
) ON COMMIT DROP;

\echo E2 V2 profile: 15-symbol call (rollback after measurement)
SELECT pg_stat_clear_snapshot();
INSERT INTO phase2_e2_profile_metrics
SELECT 15,'before',clock_timestamp(),temp_files,temp_bytes
  FROM pg_stat_database WHERE datname=current_database();
SAVEPOINT phase2_v2_profile_15;
SELECT feat.phase2_builder_set_context('core','feat','ops');
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT feat.build_features_v2_shared(
    (SELECT min(trade_date) FROM phase2_e2_profile_sessions),
    (SELECT cut_date FROM phase2_e2_profile_cut),
    (SELECT array_agg(symbol_id ORDER BY symbol_id)
       FROM phase2_e2_profile_cohort WHERE symbol_ordinal<=15)
);
ROLLBACK TO SAVEPOINT phase2_v2_profile_15;
SELECT pg_stat_clear_snapshot();
INSERT INTO phase2_e2_profile_metrics
SELECT 15,'after',clock_timestamp(),temp_files,temp_bytes
  FROM pg_stat_database WHERE datname=current_database();
SELECT cohort_symbols,
       max(recorded_at)-min(recorded_at) AS elapsed,
       max(temp_files)-min(temp_files) AS temp_files_delta,
       max(temp_bytes)-min(temp_bytes) AS temp_bytes_delta
  FROM phase2_e2_profile_metrics WHERE cohort_symbols=15 GROUP BY cohort_symbols;

\echo E2 V2 profile: 30-symbol call (rollback after measurement)
SELECT pg_stat_clear_snapshot();
INSERT INTO phase2_e2_profile_metrics
SELECT 30,'before',clock_timestamp(),temp_files,temp_bytes
  FROM pg_stat_database WHERE datname=current_database();
SAVEPOINT phase2_v2_profile_30;
SELECT feat.phase2_builder_set_context('core','feat','ops');
EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)
SELECT feat.build_features_v2_shared(
    (SELECT min(trade_date) FROM phase2_e2_profile_sessions),
    (SELECT cut_date FROM phase2_e2_profile_cut),
    (SELECT array_agg(symbol_id ORDER BY symbol_id)
       FROM phase2_e2_profile_cohort WHERE symbol_ordinal<=30)
);
ROLLBACK TO SAVEPOINT phase2_v2_profile_30;
SELECT pg_stat_clear_snapshot();
INSERT INTO phase2_e2_profile_metrics
SELECT 30,'after',clock_timestamp(),temp_files,temp_bytes
  FROM pg_stat_database WHERE datname=current_database();
SELECT cohort_symbols,
       max(recorded_at)-min(recorded_at) AS elapsed,
       max(temp_files)-min(temp_files) AS temp_files_delta,
       max(temp_bytes)-min(temp_bytes) AS temp_bytes_delta
  FROM phase2_e2_profile_metrics WHERE cohort_symbols=30 GROUP BY cohort_symbols;
ROLLBACK;

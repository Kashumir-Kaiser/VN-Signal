\set ON_ERROR_STOP on
\pset pager off
\timing on
BEGIN;
SET LOCAL statement_timeout='29min';
SET LOCAL lock_timeout='5s';
SET LOCAL idle_in_transaction_session_timeout='35min';
-- Keep this local to the isolated report transaction. The selected 60-symbol
-- windows spill at the server's 4 MB default; a moderate budget reduces that
-- scratch I/O without changing any feature or label expression.
SET LOCAL work_mem='16MB';
DO $guard$
BEGIN
    IF current_database()<>'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'E2 real-data test is restricted to disposable database vnsignal_phase2_report_20261019 (connected to %)',current_database();
    END IF;
    IF to_regprocedure('feat.build_features_and_labels_scoped(date,date,text,text,text,bigint[])') IS NULL THEN
        RAISE EXCEPTION 'apply Phase 2 shared-builder migration 052 before E2';
    END IF;
    IF to_regprocedure('feat.phase2_market_inputs_scoped(date,date,text,text,text)') IS NULL THEN
        RAISE EXCEPTION 'apply Phase 2 market projection migration 055 before E2';
    END IF;
END;
$guard$;

-- Instrument only this transaction-local copy of the production wrapper so a
-- long E2 branch reports whether V2, V3, or labels dominate its rebuild.
DO $instrument_scoped_builder$
DECLARE
    definition text:=pg_get_functiondef(
        'feat.build_features_and_labels_scoped(date,date,text,text,text,bigint[])'::regprocedure
    );
    anchor text;
    replacement text;
BEGIN
    anchor:='    v_scope_symbols bigint;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected scoped-builder declaration for E2 timing';
    END IF;
    definition:=replace(definition,anchor,
        anchor||E'\n    v_stage_started timestamptz;');

    anchor:='    PERFORM feat.prepare_phase2_adjustment_rows(false);';
    replacement:='    v_stage_started:=clock_timestamp();'||E'\n'
        ||anchor||E'\n'
        ||'    RAISE NOTICE ''E2 scoped cache preparation elapsed %'',clock_timestamp()-v_stage_started;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected scoped-builder cache-preparation stage for E2 timing';
    END IF;
    definition:=replace(definition,anchor,replacement);

    anchor:='    feature_rows:=feat.build_features_v2_shared(p_date_from,p_date_to,p_symbol_ids);';
    replacement:='    v_stage_started:=clock_timestamp();'||E'\n'
        ||anchor||E'\n'
        ||'    RAISE NOTICE ''E2 V2 feature rebuild elapsed %, rows %'',clock_timestamp()-v_stage_started,feature_rows;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected scoped-builder V2 stage for E2 timing';
    END IF;
    definition:=replace(definition,anchor,replacement);

    anchor:='    feature_rows:=feat.build_price_features_v3_shared(p_date_from,p_date_to,p_symbol_ids);';
    replacement:='    v_stage_started:=clock_timestamp();'||E'\n'
        ||anchor||E'\n'
        ||'    RAISE NOTICE ''E2 V3 feature rebuild elapsed %, rows %'',clock_timestamp()-v_stage_started,feature_rows;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected scoped-builder V3 stage for E2 timing';
    END IF;
    definition:=replace(definition,anchor,replacement);

    anchor:='    label_rows:=feat.build_labels_set_based_shared(p_date_from,p_date_to,p_symbol_ids);';
    replacement:='    v_stage_started:=clock_timestamp();'||E'\n'
        ||anchor||E'\n'
        ||'    RAISE NOTICE ''E2 scoped label rebuild elapsed %, rows %'',clock_timestamp()-v_stage_started,label_rows;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected scoped-builder label stage for E2 timing';
    END IF;
    definition:=replace(definition,anchor,replacement);
    EXECUTE definition;
END;
$instrument_scoped_builder$;

CREATE TEMP TABLE phase2_e2_report (
    cut_percent integer NOT NULL,
    cut_date date NOT NULL,
    cohort_symbols integer NOT NULL,
    pre_cut_feature_rows bigint NOT NULL,
    pre_cut_feature_mismatches bigint NOT NULL,
    labels_ending_by_cut bigint NOT NULL,
    labels_crossing_cut bigint NOT NULL,
    completed_label_mismatches bigint NOT NULL,
    label_boundary_mismatches bigint NOT NULL,
    perturbed_equity_rows bigint NOT NULL,
    perturbed_index_rows bigint NOT NULL,
    rank_population text NOT NULL CHECK(rank_population='selected_cohort_60'),
    perturbation_summary jsonb NOT NULL
) ON COMMIT DROP;

CREATE TEMP TABLE phase2_e2_session_axis ON COMMIT DROP AS
SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
FROM core.effective_trading_sessions
WHERE is_session;
CREATE UNIQUE INDEX ON phase2_e2_session_axis(session_no);
CREATE UNIQUE INDEX ON phase2_e2_session_axis(trade_date);
ANALYZE phase2_e2_session_axis;

CREATE TEMP TABLE phase2_e2_cut_dates ON COMMIT DROP AS
SELECT c.pct,s.trade_date AS cut_date
FROM (VALUES (40,0.40),(70,0.70),(95,0.95)) c(pct,fraction)
JOIN phase2_e2_session_axis s
  ON s.session_no=ceil((SELECT count(*) FROM phase2_e2_session_axis)*c.fraction)::bigint;
CREATE UNIQUE INDEX ON phase2_e2_cut_dates(pct);

\echo E2 checkpoint: selecting the PIT-stratified 60-symbol cohort
CREATE TEMP TABLE phase2_e2_cohort ON COMMIT DROP AS
WITH pit_exchange AS MATERIALIZED (
    SELECT DISTINCT ON (b.symbol_id)
           b.symbol_id,b.exchange_code AS exchange,b.trade_date AS exchange_as_of,
           b.landing_id AS exchange_landing_id,b.source_row AS exchange_source_row
    FROM core.bars_daily_sources b
    WHERE b.source='vndirect'
      AND b.trade_date<=(SELECT cut_date FROM phase2_e2_cut_dates WHERE pct=40)
    ORDER BY b.symbol_id,b.trade_date DESC
), trailing_turnover AS MATERIALIZED (
    SELECT f.symbol_id,
           percentile_cont(0.5) WITHIN GROUP(ORDER BY f.turnover_proxy_vnd) AS median_turnover
    FROM feat.features_daily f
    JOIN core.effective_trading_sessions s
      ON s.trade_date=f.trade_date AND s.is_session
    WHERE f.feature_version='phase2-v2'
      AND f.trade_date<=(SELECT cut_date FROM phase2_e2_cut_dates WHERE pct=40)
      AND f.turnover_proxy_vnd>0
      AND s.trade_date>(
          SELECT trade_date FROM phase2_e2_session_axis
          WHERE session_no=greatest(
              1,
              ceil((SELECT count(*) FROM phase2_e2_session_axis)*0.40)::bigint-60
          )
      )
    GROUP BY f.symbol_id
    HAVING count(*)=60
), tiered AS (
    SELECT p.symbol_id,p.exchange,p.exchange_as_of,
           p.exchange_landing_id,p.exchange_source_row,t.median_turnover,
           ntile(4) OVER(PARTITION BY p.exchange ORDER BY t.median_turnover,p.symbol_id) AS liquidity_tier
    FROM pit_exchange p JOIN trailing_turnover t USING(symbol_id)
    WHERE p.exchange IN ('HOSE','HNX','UPCOM')
      AND p.exchange_landing_id IS NOT NULL AND p.exchange_source_row IS NOT NULL
), strata AS (
    SELECT t.*,
           row_number() OVER(PARTITION BY exchange,liquidity_tier
                             ORDER BY md5(symbol_id::text||':phase2-e2'),symbol_id) AS within_stratum
    FROM tiered t
)
SELECT symbol_id,exchange,exchange_as_of,exchange_landing_id,exchange_source_row,liquidity_tier
FROM strata WHERE within_stratum<=5;
CREATE UNIQUE INDEX ON phase2_e2_cohort(symbol_id);
ANALYZE phase2_e2_cohort;
\echo E2 checkpoint: cohort selection complete

\echo E2 checkpoint: building the canonical adjustment cache for the selected cohort
CREATE TEMP TABLE phase2_adjustment_rows ON COMMIT DROP AS
SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
       r.reference_adjustment_ratio,r.episode_start_date,
       r.model_o,r.model_h,r.model_l,r.model_c,
       r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
FROM feat.phase2_vndirect_adjustment_details_for_symbols(
       (SELECT array_agg(symbol_id ORDER BY symbol_id) FROM phase2_e2_cohort)
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
COMMENT ON TABLE phase2_adjustment_cache_state IS
    'VN-Signal Phase 2 session-local cache readiness state';
INSERT INTO phase2_adjustment_cache_state(ready,finalized_at)
VALUES(true,clock_timestamp());
SELECT feat.prepare_phase2_adjustment_rows(false);
\echo E2 checkpoint: copying the finalized adjustment cache
CREATE TEMP TABLE phase2_e2_raw_inputs ON COMMIT DROP AS
SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
       r.reference_adjustment_ratio,r.episode_start_date,
       r.model_o,r.model_h,r.model_l,r.model_c,
       r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
FROM pg_temp.phase2_adjustment_rows r
WHERE r.source='vndirect';
CREATE UNIQUE INDEX ON phase2_e2_raw_inputs(symbol_id,trade_date);
ANALYZE phase2_e2_raw_inputs;
\echo E2 checkpoint: raw input snapshot is ready

CREATE TEMP TABLE phase2_e2_context (
    all_sessions bigint NOT NULL,
    min_date date NOT NULL,
    max_date date NOT NULL,
    cohort_ids bigint[] NOT NULL,
    cohort_count integer NOT NULL
) ON COMMIT DROP;
CREATE TEMP TABLE phase2_e2_branch_names (
    base_input text NOT NULL,
    base_output text NOT NULL,
    base_ops text NOT NULL
) ON COMMIT DROP;

\echo E2 checkpoint: validating the immutable current-hash baseline
DO $baseline$
DECLARE
    all_sessions bigint;
    min_date date;
    max_date date;
    cohort_ids bigint[];
    cohort_count integer;
    output_scope_mismatches bigint;
    feature_key_mismatches bigint;
    v3_feature_hash_mismatches bigint;
    label_hash_mismatches bigint;
    previous_path text;
    build_key text;
    base_in text;
    base_out text;
    base_ops text;
    index_view_sql text;
    baseline_feature_started timestamptz;
BEGIN
    SELECT count(*) INTO all_sessions FROM phase2_e2_session_axis;
    IF all_sessions<420 THEN
        RAISE EXCEPTION 'at least 420 effective sessions are required to exercise a 21-session crossing window at the 95%% cut';
    END IF;
    SELECT min(trade_date),max(trade_date) INTO min_date,max_date FROM phase2_e2_session_axis;
    SELECT count(*),array_agg(symbol_id ORDER BY symbol_id)
    INTO cohort_count,cohort_ids
    FROM phase2_e2_cohort;
    IF cohort_count<>60 THEN
        RAISE EXCEPTION 'PIT exchange/liquidity stratification produced % symbols; exactly 60 required',cohort_count;
    END IF;
    IF EXISTS (
        SELECT 1 FROM phase2_e2_cohort GROUP BY exchange,liquidity_tier HAVING count(*)<>5
    ) OR (SELECT count(*) FROM (SELECT exchange,liquidity_tier FROM phase2_e2_cohort GROUP BY 1,2) x)<>12 THEN
        RAISE EXCEPTION 'PIT cohort must contain five symbols in each exchange/liquidity stratum';
    END IF;

    build_key:='p2e2_'||pg_backend_pid()::text||'_'||txid_current()::text||'_base';
    base_in:=build_key||'_i';
    base_out:=build_key||'_o';
    base_ops:=build_key||'_x';
    EXECUTE format('CREATE SCHEMA %I',base_in);
    EXECUTE format('CREATE SCHEMA %I',base_out);
    EXECUTE format('CREATE SCHEMA %I',base_ops);

    EXECUTE format('CREATE TABLE %I.effective_trading_sessions AS SELECT trade_date,is_session FROM core.effective_trading_sessions',base_in);
    EXECUTE format('CREATE TABLE %I.symbols AS SELECT symbol_id,exchange FROM core.symbols',base_in);
    EXECUTE format('CREATE TABLE %I.index_bars AS SELECT * FROM core.index_bars',base_in);
    EXECUTE format('CREATE TABLE %I.phase2_adjustment_rows AS SELECT * FROM pg_temp.phase2_e2_raw_inputs',base_in);
    EXECUTE format('ANALYZE %I.effective_trading_sessions',base_in);
    EXECUTE format('ANALYZE %I.symbols',base_in);
    EXECUTE format('ANALYZE %I.index_bars',base_in);
    EXECUTE format('CREATE UNIQUE INDEX ON %I.phase2_adjustment_rows(symbol_id,trade_date)',base_in);
    EXECUTE format('ANALYZE %I.phase2_adjustment_rows',base_in);
    EXECUTE format('CREATE TABLE %I.ml_symbol_scope AS SELECT symbol_id,scope_status FROM ops.ml_symbol_scope WHERE symbol_id=ANY($1)',base_ops)
        USING cohort_ids;
    EXECUTE format('ANALYZE %I.ml_symbol_scope',base_ops);
    EXECUTE format('CREATE TABLE %I.features_daily (LIKE feat.features_daily INCLUDING ALL)',base_out);
    EXECUTE format('CREATE TABLE %I.labels_daily (LIKE feat.labels_daily INCLUDING ALL)',base_out);

    IF EXISTS (
        SELECT 1
        FROM feat.features_daily f
        WHERE f.feature_version='phase2-v2'
          AND f.feature_set_hash IS DISTINCT FROM feat.phase2_feature_set_hash()
    ) THEN
        RAISE EXCEPTION 'persistent full-market V2 projection contains stale feature hashes';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM feat.features_daily f
        WHERE f.symbol_id=ANY(cohort_ids)
          AND f.feature_version='phase2-v2'
          AND f.feature_set_hash IS DISTINCT FROM feat.phase2_feature_set_hash()
    ) THEN
        RAISE EXCEPTION 'persistent V2 source contains stale feature hashes for the selected cohort';
    END IF;

    EXECUTE format($sql$
        INSERT INTO %I.features_daily
        SELECT * FROM feat.features_daily
        WHERE symbol_id=ANY($1) AND feature_version IN ('phase2-v2','phase2-v3')
    $sql$,base_out) USING cohort_ids;
    EXECUTE format($sql$
        SELECT count(*) FROM (
            (SELECT symbol_id,trade_date FROM %I.features_daily WHERE feature_version='phase2-v2'
             EXCEPT
             SELECT symbol_id,trade_date FROM %I.features_daily WHERE feature_version='phase2-v3')
            UNION ALL
            (SELECT symbol_id,trade_date FROM %I.features_daily WHERE feature_version='phase2-v3'
             EXCEPT
             SELECT symbol_id,trade_date FROM %I.features_daily WHERE feature_version='phase2-v2')
        ) mismatch
    $sql$,base_out,base_out,base_out,base_out) INTO feature_key_mismatches;
    IF feature_key_mismatches<>0 THEN
        RAISE EXCEPTION 'current-hash V2/V3 baseline key coverage differs by % rows',feature_key_mismatches;
    END IF;
    EXECUTE format('ANALYZE %I.features_daily',base_out);

    -- Route the canonical production view to the baseline branch's index rows.
    index_view_sql:=pg_get_viewdef('feat.phase2_vci_index_features'::regclass,true);
    IF strpos(index_view_sql,'core.effective_trading_sessions')=0
       OR strpos(index_view_sql,'core.index_bars')=0 THEN
        RAISE EXCEPTION 'unexpected production VCI index view sources';
    END IF;
    EXECUTE format('CREATE TABLE %I.phase2_vci_index_features AS ',base_in)
        ||replace(replace(index_view_sql,
            'core.effective_trading_sessions',format('%I.effective_trading_sessions',base_in)),
            'core.index_bars',format('%I.index_bars',base_in));
    EXECUTE format('ANALYZE %I.phase2_vci_index_features',base_in);

    -- V2 rows are the verified production market projection. Reuse their
    -- exact stored values instead of recomputing the full-universe projection.
    EXECUTE format($sql$
        CREATE TABLE %I.phase2_market_features_daily AS
        SELECT symbol_id,trade_date,feature_version,ret_1,
               distance_52w_high,distance_52w_low,turnover_proxy_vnd
        FROM feat.features_daily
        WHERE feature_version='phase2-v2'
    $sql$,base_in);
    EXECUTE format('CREATE UNIQUE INDEX ON %I.phase2_market_features_daily(trade_date,symbol_id)',base_in);
    EXECUTE format('ANALYZE %I.phase2_market_features_daily',base_in);

    -- The persisted V2/V3 cohort may predate a semantics-preserving builder
    -- optimization and can differ by floating-point rounding. Rebuild its
    -- immutable baseline from the same unperturbed inputs with the current
    -- production builders so the branch comparison remains byte-exact without
    -- comparing against stale algorithm output.
    previous_path:=feat.phase2_builder_set_context(base_in,base_out,base_ops);
    baseline_feature_started:=clock_timestamp();
    PERFORM feat.build_features_v2_shared(min_date,max_date,cohort_ids);
    PERFORM feat.build_price_features_v3_shared(min_date,max_date,cohort_ids);
    RAISE NOTICE 'E2 baseline optimized V2/V3 feature rebuild elapsed %',clock_timestamp()-baseline_feature_started;
    EXECUTE format('SELECT count(*) FROM %I.features_daily WHERE feature_version=''phase2-v3'' AND feature_set_hash IS DISTINCT FROM $1',base_out)
        INTO v3_feature_hash_mismatches USING feat.phase2_feature_set_hash_v3();
    IF v3_feature_hash_mismatches<>0 THEN
        RAISE EXCEPTION 'rebuilt V3 baseline contains % stale feature hashes',v3_feature_hash_mismatches;
    END IF;

    -- Rebuild labels against the current-hash baseline using the production
    -- shared label builder; this also exercises migration 058.
    PERFORM feat.build_labels_set_based_shared(min_date,max_date,cohort_ids);
    PERFORM feat.phase2_builder_restore_context(previous_path);
    EXECUTE format('SELECT count(*) FROM %I.labels_daily WHERE feature_set_hash IS DISTINCT FROM $1',base_out)
        INTO label_hash_mismatches USING feat.phase2_feature_set_hash_v3();
    IF label_hash_mismatches<>0 THEN
        RAISE EXCEPTION 'baseline labels contain % stale V3 feature hashes',label_hash_mismatches;
    END IF;
    RAISE NOTICE 'E2 baseline reused the current-hash 60-symbol feature cohort and rebuilt labels with current hash %',
        feat.phase2_feature_set_hash_v3();

    EXECUTE format($sql$
        WITH expected AS (SELECT unnest($1)::bigint AS symbol_id),
             actual AS (
                 SELECT DISTINCT symbol_id FROM %I.features_daily
                  WHERE feature_version IN ('phase2-v2','phase2-v3')
             )
        SELECT count(*) FROM (
            (SELECT symbol_id FROM expected EXCEPT SELECT symbol_id FROM actual)
            UNION ALL
            (SELECT symbol_id FROM actual EXCEPT SELECT symbol_id FROM expected)
        ) mismatch
    $sql$,base_out) INTO output_scope_mismatches USING cohort_ids;
    IF output_scope_mismatches<>0 THEN
        RAISE EXCEPTION 'baseline feature output does not represent exactly the selected cohort (% scope mismatches)',
            output_scope_mismatches;
    END IF;

    INSERT INTO phase2_e2_context VALUES(all_sessions,min_date,max_date,cohort_ids,cohort_count);
    INSERT INTO phase2_e2_branch_names VALUES(base_in,base_out,base_ops);
END;
$baseline$;

CREATE FUNCTION pg_temp.phase2_e2_run_cut(p_pct integer) RETURNS void
LANGUAGE plpgsql AS $cut$
DECLARE
    cut_date date;
    suffix_start date;
    min_date date;
    cohort_ids bigint[];
    cohort_count integer;
    base_in text;
    base_out text;
    base_ops text;
    branch_key text;
    in_b text;
    out_b text;
    ops_b text;
    sch text;
    feature_rows bigint;
    feature_mismatches bigint;
    labels_ending bigint;
    labels_crossing bigint;
    completed_label_mismatches bigint;
    boundary_mismatches bigint;
    output_scope_mismatches bigint;
    equity_changed bigint;
    index_changed bigint;
    expected_count bigint;
    equity_price_up boolean;
    equity_price_down boolean;
    equity_volume_up boolean;
    equity_volume_down boolean;
    index_price_up boolean;
    index_price_down boolean;
    index_volume_up boolean;
    index_volume_down boolean;
    equity_price_max_delta double precision;
    equity_volume_max_delta double precision;
    index_price_max_delta double precision;
    index_volume_max_delta double precision;
    index_view_sql text;
    stage_started timestamptz := clock_timestamp();
    branch_equity_rows bigint;
BEGIN
    IF p_pct NOT IN (40,70,95) THEN RAISE EXCEPTION 'unsupported E2 cut percent %',p_pct; END IF;
    SELECT c.cut_date INTO cut_date FROM phase2_e2_cut_dates c WHERE c.pct=p_pct;
    SELECT x.min_date,x.cohort_ids,x.cohort_count,
           n.base_input,n.base_output,n.base_ops
    INTO min_date,cohort_ids,cohort_count,base_in,base_out,base_ops
    FROM phase2_e2_context x CROSS JOIN phase2_e2_branch_names n;
    SELECT min(trade_date) INTO suffix_start
    FROM phase2_e2_session_axis WHERE trade_date>cut_date;
    IF cut_date IS NULL OR suffix_start IS NULL THEN
        RAISE EXCEPTION 'missing cut or post-cut session for % percent',p_pct;
    END IF;

    branch_key:='p2e2_'||pg_backend_pid()::text||'_'||txid_current()::text||'_'||p_pct::text;
    in_b:=branch_key||'_ib';
    out_b:=branch_key||'_ob';
    ops_b:=branch_key||'_xb';
    FOREACH sch IN ARRAY ARRAY[in_b,out_b,ops_b] LOOP
        EXECUTE format('CREATE SCHEMA %I',sch);
    END LOOP;

    EXECUTE format('CREATE TABLE %I.effective_trading_sessions AS SELECT trade_date,is_session FROM core.effective_trading_sessions',in_b);
    EXECUTE format('CREATE TABLE %I.symbols AS SELECT symbol_id,exchange FROM core.symbols',in_b);
    EXECUTE format('CREATE TABLE %I.index_bars AS SELECT * FROM core.index_bars',in_b);
    -- The leakage comparison is limited to the selected 60 symbols. Keep the
    -- baseline snapshot broad for PIT cohort selection, then copy only those
    -- symbols into each independent branch before perturbing future inputs.
    EXECUTE format('CREATE TABLE %I.phase2_adjustment_rows AS SELECT * FROM pg_temp.phase2_e2_raw_inputs WHERE symbol_id=ANY($1)',in_b)
        USING cohort_ids;
    GET DIAGNOSTICS branch_equity_rows=ROW_COUNT;
    -- Preserve the production key indexes in these isolated copies. Without
    -- them, the shared V2 builder can choose repeated scans over the cohort
    -- spine and index/calendar inputs.
    EXECUTE format('CREATE UNIQUE INDEX ON %I.effective_trading_sessions(trade_date)',in_b);
    EXECUTE format('CREATE UNIQUE INDEX ON %I.symbols(symbol_id)',in_b);
    EXECUTE format('CREATE UNIQUE INDEX ON %I.index_bars(index_symbol,trade_date,source)',in_b);
    EXECUTE format('ANALYZE %I.effective_trading_sessions',in_b);
    EXECUTE format('ANALYZE %I.symbols',in_b);
    EXECUTE format('ANALYZE %I.index_bars',in_b);
    EXECUTE format('CREATE UNIQUE INDEX ON %I.phase2_adjustment_rows(symbol_id,trade_date)',in_b);
    EXECUTE format('ANALYZE %I.phase2_adjustment_rows',in_b);
    EXECUTE format('CREATE TABLE %I.ml_symbol_scope AS SELECT symbol_id,scope_status FROM ops.ml_symbol_scope WHERE symbol_id=ANY($1)',ops_b)
        USING cohort_ids;
    EXECUTE format('CREATE UNIQUE INDEX ON %I.ml_symbol_scope(symbol_id)',ops_b);
    EXECUTE format('ANALYZE %I.ml_symbol_scope',ops_b);
    EXECUTE format('CREATE TABLE %I.features_daily (LIKE feat.features_daily INCLUDING ALL)',out_b);
    EXECUTE format('CREATE TABLE %I.labels_daily (LIKE feat.labels_daily INCLUDING ALL)',out_b);

    RAISE NOTICE 'E2 % percent branch setup copied % equity rows for % cohort symbols; elapsed %',
        p_pct,branch_equity_rows,cohort_count,clock_timestamp()-stage_started;
    stage_started:=clock_timestamp();

    -- Perturb every post-cut equity model OHLC price and nonzero volume, and
    -- every post-cut index OHLC price and nonzero volume; preserve valid OHLC.
    EXECUTE format($sql$
        UPDATE %I.phase2_adjustment_rows r
           SET model_o=r.model_o*f.price_factor,model_h=r.model_h*f.price_factor,
               model_l=r.model_l*f.price_factor,model_c=r.model_c*f.price_factor,
               v=CASE WHEN r.v IS NULL OR r.v=0 THEN r.v ELSE r.v*f.volume_factor END
        FROM (SELECT symbol_id,trade_date,
                     0.8::double precision+mod(abs(hashtext(symbol_id::text||trade_date::text||':price')::bigint),4001)::double precision/10000.0::double precision AS price_factor,
                     0.8::double precision+mod(abs(hashtext(symbol_id::text||trade_date::text||':volume')::bigint),4001)::double precision/10000.0::double precision AS volume_factor
              FROM %I.phase2_adjustment_rows WHERE trade_date>$1) f
        WHERE r.symbol_id=f.symbol_id AND r.trade_date=f.trade_date
    $sql$,in_b,in_b) USING cut_date;
    GET DIAGNOSTICS equity_changed=ROW_COUNT;
    EXECUTE format($sql$
        UPDATE %I.index_bars i
           SET o=i.o*f.price_factor,h=i.h*f.price_factor,l=i.l*f.price_factor,c=i.c*f.price_factor,
               v=CASE WHEN i.v IS NULL OR i.v=0 THEN i.v ELSE i.v*f.volume_factor END
        FROM (SELECT index_symbol,trade_date,
                     0.8::double precision+mod(abs(hashtext(index_symbol||trade_date::text||':price')::bigint),4001)::double precision/10000.0::double precision AS price_factor,
                     0.8::double precision+mod(abs(hashtext(index_symbol||trade_date::text||':volume')::bigint),4001)::double precision/10000.0::double precision AS volume_factor
              FROM %I.index_bars WHERE trade_date>$1) f
        WHERE i.index_symbol=f.index_symbol AND i.trade_date=f.trade_date
    $sql$,in_b,in_b) USING cut_date;
    GET DIAGNOSTICS index_changed=ROW_COUNT;
    IF equity_changed=0 OR index_changed=0 THEN
        RAISE EXCEPTION 'future perturbation did not modify both equity and index inputs at %',cut_date;
    END IF;
    EXECUTE format($sql$
        SELECT bool_or(b.model_c/a.model_c>1),bool_or(b.model_c/a.model_c<1),
               bool_or(b.v/a.v>1) FILTER(WHERE a.v>0 AND b.v IS NOT NULL),
               bool_or(b.v/a.v<1) FILTER(WHERE a.v>0 AND b.v IS NOT NULL),
               max(abs(b.model_c/a.model_c-1)),
               max(abs(b.v/a.v-1)) FILTER(WHERE a.v>0 AND b.v IS NOT NULL)
        FROM %I.phase2_adjustment_rows a JOIN %I.phase2_adjustment_rows b USING(symbol_id,trade_date)
        WHERE a.trade_date>$1 AND a.model_c>0
    $sql$,base_in,in_b) INTO equity_price_up,equity_price_down,equity_volume_up,equity_volume_down,
         equity_price_max_delta,equity_volume_max_delta USING cut_date;
    EXECUTE format($sql$
        SELECT bool_or(b.c/a.c>1),bool_or(b.c/a.c<1),
               bool_or(b.v/a.v>1) FILTER(WHERE a.v>0 AND b.v IS NOT NULL),
               bool_or(b.v/a.v<1) FILTER(WHERE a.v>0 AND b.v IS NOT NULL),
               max(abs(b.c/a.c-1)),
               max(abs(b.v/a.v-1)) FILTER(WHERE a.v>0 AND b.v IS NOT NULL)
        FROM %I.index_bars a JOIN %I.index_bars b USING(index_symbol,trade_date)
        WHERE a.trade_date>$1 AND a.c>0
    $sql$,base_in,in_b) INTO index_price_up,index_price_down,index_volume_up,index_volume_down,
         index_price_max_delta,index_volume_max_delta USING cut_date;
    IF NOT coalesce(equity_price_up,false) OR NOT coalesce(equity_price_down,false)
       OR NOT coalesce(equity_volume_up,false) OR NOT coalesce(equity_volume_down,false)
       OR NOT coalesce(index_price_up,false) OR NOT coalesce(index_price_down,false)
       OR NOT coalesce(index_volume_up,false) OR NOT coalesce(index_volume_down,false)
       OR equity_price_max_delta>0.200000001 OR equity_volume_max_delta>0.200000001
       OR index_price_max_delta>0.200000001 OR index_volume_max_delta>0.200000001 THEN
        RAISE EXCEPTION 'future inputs must contain independent positive and negative price/volume perturbations within 20 percent';
    END IF;
    RAISE NOTICE 'E2 % percent future perturbations applied: % equity rows and % index rows; elapsed %',
        p_pct,equity_changed,index_changed,clock_timestamp()-stage_started;
    stage_started:=clock_timestamp();

    -- Preserve the canonical production index view equations for this branch.
    index_view_sql:=pg_get_viewdef('feat.phase2_vci_index_features'::regclass,true);
    IF strpos(index_view_sql,'core.effective_trading_sessions')=0
       OR strpos(index_view_sql,'core.index_bars')=0 THEN
        RAISE EXCEPTION 'unexpected production VCI index view sources';
    END IF;
    EXECUTE format('CREATE TABLE %I.phase2_vci_index_features AS ',in_b)
        ||replace(replace(index_view_sql,
            'core.effective_trading_sessions',format('%I.effective_trading_sessions',in_b)),
            'core.index_bars',format('%I.index_bars',in_b));
    EXECUTE format('ANALYZE %I.phase2_vci_index_features',in_b);

    -- Every feature row under test is dated on or before the cut. Market
    -- support through the cut is copied from the immutable baseline because
    -- all source inputs through the cut are byte-identical. The branch still
    -- contains every perturbed raw equity and index input after the cut, which
    -- the label builder can read for windows that cross the cut.
    EXECUTE format($sql$
        CREATE TABLE %I.phase2_market_features_daily AS
        SELECT * FROM %I.phase2_market_features_daily WHERE trade_date<=$1
    $sql$,in_b,base_in) USING cut_date;
    EXECUTE format('CREATE UNIQUE INDEX ON %I.phase2_market_features_daily(trade_date,symbol_id)',in_b);
    EXECUTE format('ANALYZE %I.phase2_market_features_daily',in_b);
    RAISE NOTICE 'E2 % percent branch inputs ready; elapsed %',p_pct,clock_timestamp()-stage_started;
    stage_started:=clock_timestamp();

    -- Rebuild the complete pre-cut feature history with the production builder.
    -- Post-cut feature values are outside the leakage assertion; the changed
    -- raw inputs above prove that the perturbation was applied, while future
    -- label endpoints remain available in the branch input tables.
    PERFORM feat.build_features_and_labels_scoped(min_date,cut_date,in_b,out_b,ops_b,cohort_ids);
    RAISE NOTICE 'E2 % percent production feature and label rebuild complete; elapsed %',
        p_pct,clock_timestamp()-stage_started;
    stage_started:=clock_timestamp();

    EXECUTE format($sql$
        WITH expected AS (SELECT unnest($1)::bigint AS symbol_id),
             actual AS (
                 SELECT DISTINCT symbol_id FROM %I.features_daily
                  WHERE feature_version IN ('phase2-v2','phase2-v3')
             )
        SELECT count(*) FROM (
            (SELECT symbol_id FROM expected EXCEPT SELECT symbol_id FROM actual)
            UNION ALL
            (SELECT symbol_id FROM actual EXCEPT SELECT symbol_id FROM expected)
        ) mismatch
    $sql$,out_b) INTO output_scope_mismatches USING cohort_ids;
    IF output_scope_mismatches<>0 THEN
        RAISE EXCEPTION 'perturbed feature output does not represent exactly the selected cohort (% scope mismatches)',
            output_scope_mismatches;
    END IF;

    EXECUTE format($sql$
        SELECT count(*) FROM (
            (SELECT symbol_id,trade_date,feature_version,pg_catalog.record_send(f) AS row_bytes
               FROM %I.features_daily f WHERE trade_date<=$1 AND feature_version IN ('phase2-v2','phase2-v3')
             EXCEPT
             SELECT symbol_id,trade_date,feature_version,pg_catalog.record_send(f) AS row_bytes
               FROM %I.features_daily f WHERE trade_date<=$1 AND feature_version IN ('phase2-v2','phase2-v3'))
            UNION ALL
            (SELECT symbol_id,trade_date,feature_version,pg_catalog.record_send(f) AS row_bytes
               FROM %I.features_daily f WHERE trade_date<=$1 AND feature_version IN ('phase2-v2','phase2-v3')
             EXCEPT
             SELECT symbol_id,trade_date,feature_version,pg_catalog.record_send(f) AS row_bytes
               FROM %I.features_daily f WHERE trade_date<=$1 AND feature_version IN ('phase2-v2','phase2-v3'))
        ) d
    $sql$,base_out,out_b,out_b,base_out) INTO feature_mismatches USING cut_date;
    EXECUTE format('SELECT count(*) FROM %I.features_daily WHERE trade_date<=$1 AND feature_version IN (''phase2-v2'',''phase2-v3'')',base_out)
        INTO feature_rows USING cut_date;
    IF feature_rows=0 THEN RAISE EXCEPTION 'no pre-cut baseline features built for cut %',p_pct; END IF;
    EXECUTE format('SELECT count(*) FROM %I.labels_daily WHERE signal_date<=$1 AND exit_date<=$1',base_out)
        INTO labels_ending USING cut_date;
    EXECUTE format('SELECT count(*) FROM %I.labels_daily WHERE signal_date<=$1 AND exit_date>$1',base_out)
        INTO labels_crossing USING cut_date;
    EXECUTE format($sql$
        SELECT count(*) FROM (
            (SELECT pg_catalog.record_send(l) AS row_bytes FROM %I.labels_daily l
              WHERE l.label_version='close-next-open-v1' AND l.signal_date<=$1 AND l.exit_date<=$1
             EXCEPT
             SELECT pg_catalog.record_send(l) AS row_bytes FROM %I.labels_daily l
              WHERE l.label_version='close-next-open-v1' AND l.signal_date<=$1 AND l.exit_date<=$1)
            UNION ALL
            (SELECT pg_catalog.record_send(l) AS row_bytes FROM %I.labels_daily l
              WHERE l.label_version='close-next-open-v1' AND l.signal_date<=$1 AND l.exit_date<=$1
             EXCEPT
             SELECT pg_catalog.record_send(l) AS row_bytes FROM %I.labels_daily l
              WHERE l.label_version='close-next-open-v1' AND l.signal_date<=$1 AND l.exit_date<=$1)
        ) d
    $sql$,base_out,out_b,out_b,base_out) INTO completed_label_mismatches USING cut_date;

    EXECUTE format($sql$
        WITH calendar_axis AS MATERIALIZED (
            SELECT trade_date,lead(trade_date,1) OVER(ORDER BY trade_date) entry_date,
                   lead(trade_date,6) OVER(ORDER BY trade_date) exit5,
                   lead(trade_date,21) OVER(ORDER BY trade_date) exit20
            FROM %I.effective_trading_sessions WHERE is_session
        ), expected AS (
            SELECT f.symbol_id,c.trade_date signal_date,h.horizon_sessions,c.entry_date,
                   CASE h.horizon_sessions WHEN 5 THEN c.exit5 ELSE c.exit20 END exit_date
            FROM %I.features_daily f JOIN calendar_axis c ON c.trade_date=f.trade_date
            CROSS JOIN (VALUES (5::smallint),(20::smallint)) h(horizon_sessions)
            WHERE f.feature_version='phase2-v3' AND f.trade_date<=$1
        ), actual AS (
            SELECT symbol_id,signal_date,horizon_sessions,entry_date,exit_date
            FROM %I.labels_daily WHERE label_version='close-next-open-v1' AND signal_date<=$1
        )
        SELECT count(*) FROM (
            (SELECT * FROM expected EXCEPT SELECT * FROM actual)
            UNION ALL
            (SELECT * FROM actual EXCEPT SELECT * FROM expected)
        ) mismatch
    $sql$,base_in,base_out,base_out) INTO boundary_mismatches USING cut_date;
    EXECUTE format($sql$
        WITH calendar_axis AS MATERIALIZED (
            SELECT trade_date,lead(trade_date,1) OVER(ORDER BY trade_date) entry_date,
                   lead(trade_date,6) OVER(ORDER BY trade_date) exit5,
                   lead(trade_date,21) OVER(ORDER BY trade_date) exit20
            FROM %I.effective_trading_sessions WHERE is_session
        ), expected AS (
            SELECT f.symbol_id,c.trade_date signal_date,h.horizon_sessions,c.entry_date,
                   CASE h.horizon_sessions WHEN 5 THEN c.exit5 ELSE c.exit20 END exit_date
            FROM %I.features_daily f JOIN calendar_axis c ON c.trade_date=f.trade_date
            CROSS JOIN (VALUES (5::smallint),(20::smallint)) h(horizon_sessions)
            WHERE f.feature_version='phase2-v3' AND f.trade_date<=$1
        ), actual AS (
            SELECT symbol_id,signal_date,horizon_sessions,entry_date,exit_date
            FROM %I.labels_daily WHERE label_version='close-next-open-v1' AND signal_date<=$1
        )
        SELECT count(*) FROM (
            (SELECT * FROM expected EXCEPT SELECT * FROM actual)
            UNION ALL
            (SELECT * FROM actual EXCEPT SELECT * FROM expected)
        ) mismatch
    $sql$,in_b,out_b,out_b) INTO expected_count USING cut_date;
    IF expected_count<>0 THEN
        RAISE EXCEPTION 'label row coverage/boundaries differ after perturbation at cut % (% mismatches)',p_pct,expected_count;
    END IF;

    INSERT INTO phase2_e2_report VALUES(
        p_pct,cut_date,cohort_count,feature_rows,feature_mismatches,labels_ending,
        labels_crossing,completed_label_mismatches,boundary_mismatches,
        equity_changed,index_changed,'selected_cohort_60',
        jsonb_build_object(
            'equity_price_positive_delta',equity_price_up,
            'equity_price_negative_delta',equity_price_down,
            'equity_price_max_abs_delta',equity_price_max_delta,
            'equity_volume_positive_delta',equity_volume_up,
            'equity_volume_negative_delta',equity_volume_down,
            'equity_volume_max_abs_delta',equity_volume_max_delta,
            'index_price_positive_delta',index_price_up,
            'index_price_negative_delta',index_price_down,
            'index_price_max_abs_delta',index_price_max_delta,
            'index_volume_positive_delta',index_volume_up,
            'index_volume_negative_delta',index_volume_down,
            'index_volume_max_abs_delta',index_volume_max_delta
        )
    );
    IF feature_mismatches<>0 OR completed_label_mismatches<>0
       OR boundary_mismatches<>0 OR labels_crossing=0 THEN
        RAISE EXCEPTION 'E2 failed for % cut: feature diffs %, completed-label diffs %, boundary diffs %, crossing labels %',
            p_pct,feature_mismatches,completed_label_mismatches,boundary_mismatches,labels_crossing;
    END IF;
    RAISE NOTICE 'E2 checkpoint: cut % (% percent), feature rows %, zero pre-cut and completed-label mismatches, crossing labels %, perturbed equity/index rows %/%',
        cut_date,p_pct,feature_rows,labels_crossing,equity_changed,index_changed;
    FOREACH sch IN ARRAY ARRAY[out_b,ops_b,in_b] LOOP
        EXECUTE format('DROP SCHEMA %I CASCADE',sch);
    END LOOP;
END;
$cut$;

\echo E2 checkpoint: running the independent 40 percent cutoff
SELECT pg_temp.phase2_e2_run_cut(40);
\echo E2 checkpoint: running the independent 70 percent cutoff
SELECT pg_temp.phase2_e2_run_cut(70);
\echo E2 checkpoint: running the independent 95 percent cutoff
SELECT pg_temp.phase2_e2_run_cut(95);

DO $report_guard$
BEGIN
    IF (SELECT count(*) FROM phase2_e2_report)<>3
       OR EXISTS (
            SELECT pct FROM unnest(ARRAY[40,70,95]) required(pct)
             WHERE NOT EXISTS (
                 SELECT 1 FROM phase2_e2_report r WHERE r.cut_percent=required.pct
             )
       ) THEN
        RAISE EXCEPTION 'E2 report must contain exactly the 40, 70, and 95 percent cut results';
    END IF;
END;
$report_guard$;

SELECT * FROM phase2_e2_report ORDER BY cut_percent;
SELECT jsonb_agg(jsonb_build_object(
           'symbol_id',symbol_id,'exchange',exchange,'exchange_as_of',exchange_as_of,
           'exchange_landing_id',exchange_landing_id,'exchange_source_row',exchange_source_row,
           'pit_liquidity_tier',liquidity_tier
       ) ORDER BY exchange,liquidity_tier,symbol_id) AS selected_cohort
FROM phase2_e2_cohort;
ROLLBACK;

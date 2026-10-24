\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    v_p01 double precision;
    v_p99 double precision;
    v_median double precision;
    v_scaled double precision;
    v_first date;
    v_last date;
    v_hash_first text;
    v_hash_second text;
    v_base_before text;
    v_base_after text;
    v_rows bigint;
    v_builder_def text;
    v_limit_hash_def text;
BEGIN
    SELECT percentile_cont(0.01) WITHIN GROUP (ORDER BY x),
           percentile_cont(0.99) WITHIN GROUP (ORDER BY x)
      INTO v_p01,v_p99
      FROM (VALUES (-0.2::double precision),(-0.1),(0),(0.1),(0.2)) sample(x);
    IF feat.phase2_winsorize_excess(-1,v_p01,v_p99) IS DISTINCT FROM v_p01
       OR feat.phase2_winsorize_excess(1,v_p01,v_p99) IS DISTINCT FROM v_p99
       OR feat.phase2_winsorize_excess(0,v_p01,v_p99) IS DISTINCT FROM 0::double precision THEN
        RAISE EXCEPTION 'date-wise winsorization fixture failed';
    END IF;

    v_scaled:=feat.phase2_volatility_scaled_excess(0.1,0.01,0.02,20::smallint);
    IF abs(v_scaled-(0.1/(0.02*sqrt(20::double precision))))>1e-12 THEN
        RAISE EXCEPTION 'volatility floor/scaling fixture failed';
    END IF;
    IF feat.phase2_volatility_scaled_excess(0.1,NULL,0.02,20::smallint) IS NOT NULL
       OR feat.phase2_volatility_scaled_excess(0.1,0.01,NULL,20::smallint) IS NOT NULL THEN
        RAISE EXCEPTION 'volatility scaling must preserve unavailable inputs as NULL';
    END IF;
    IF feat.phase2_average_float8_array(ARRAY[1,2,3]::double precision[]) IS DISTINCT FROM 2::double precision THEN
        RAISE EXCEPTION 'PIT turnover proxy average fixture failed';
    END IF;
    IF NOT feat.phase2_investable_membership_decision('ELIGIBLE',400,false)
       OR feat.phase2_investable_membership_decision('ELIGIBLE',401,false)
       OR NOT feat.phase2_investable_membership_decision('ELIGIBLE',500,true)
       OR feat.phase2_investable_membership_decision('ELIGIBLE',501,true)
       OR feat.phase2_investable_membership_decision('INDETERMINATE',1,true) THEN
        RAISE EXCEPTION 'Master membership hysteresis fixture failed';
    END IF;
    IF feat.phase2_target_uniform_rank(1,3) IS DISTINCT FROM (0.5/3)::double precision
       OR feat.phase2_target_uniform_rank(4,3) IS NOT NULL THEN
        RAISE EXCEPTION 'target uniform-rank formula fixture failed';
    END IF;
    IF EXISTS (
        WITH scores(symbol_id,signal_date,horizon_sessions,liquidity_tier,score,expected_rank,expected_count) AS (
            VALUES (1::bigint,DATE '2024-01-02',5::smallint,'L1',0.5::double precision,1,3),
                   (2::bigint,DATE '2024-01-02',5::smallint,'L1',0.5::double precision,2,3),
                   (3::bigint,DATE '2024-01-02',5::smallint,'L1',0.2::double precision,3,3),
                   (4::bigint,DATE '2024-01-02',5::smallint,'L2',0.1::double precision,1,1)
        ), ranked AS (
            SELECT *,row_number() OVER (
                       PARTITION BY signal_date,horizon_sessions,liquidity_tier
                       ORDER BY score DESC,symbol_id
                   )::integer AS target_rank,
                   count(*) OVER (PARTITION BY signal_date,horizon_sessions,liquidity_tier)::integer AS tier_count
              FROM scores
        )
        SELECT 1 FROM ranked
         WHERE target_rank<>expected_rank OR tier_count<>expected_count
            OR abs(feat.phase2_target_uniform_rank(target_rank,tier_count)-
                   ((expected_rank-0.5)::double precision/expected_count))>1e-12
    ) THEN
        RAISE EXCEPTION 'within-tier target ranking, deterministic ties, or date/horizon partition fixture failed';
    END IF;
    IF feat.phase2_execution_weight_decision(false,10,11,0) IS NOT NULL
       OR feat.phase2_execution_weight_decision(true,11,11,0) IS DISTINCT FROM 0::double precision
       OR feat.phase2_execution_weight_decision(true,10,11,2) IS DISTINCT FROM 0.5::double precision
       OR feat.phase2_execution_weight_decision(true,10,11,1) IS DISTINCT FROM 1::double precision THEN
        RAISE EXCEPTION 'exact-evidence execution weight decision fixture failed';
    END IF;

    v_median:=feat.phase2_median_float8_array(ARRAY[4,1,3,2]::double precision[]);
    IF v_median IS DISTINCT FROM 2.5::double precision THEN
        RAISE EXCEPTION 'point-in-time liquidity median fixture failed';
    END IF;

    v_builder_def:=pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure);
    v_limit_hash_def:=pg_get_functiondef('ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure);
    IF position('invalidated_at' IN v_builder_def)=0 OR position('date_to>=v_first_signal' IN v_builder_def)=0 THEN
        RAISE EXCEPTION 'downstream target chunk ledger invalidation is not wired to output deletion';
    END IF;
    IF position('BETWEEN w.entry_date AND w.exit_date' IN v_limit_hash_def)=0
       OR position('daily_price_limit_observations' IN v_limit_hash_def)=0 THEN
        RAISE EXCEPTION 'exact execution input hash does not cover each label entry-to-exit window';
    END IF;

    SELECT min(trade_date),max(trade_date) INTO v_first,v_last
      FROM core.bars_daily_sources WHERE source='vndirect';
    IF v_first IS NOT NULL THEN
        v_base_before:=ops.phase2_chunk_output_hash('labels',v_first,least(v_last,v_first+90));
        v_rows:=feat.build_phase2_label_targets_v3(v_first,least(v_last,v_first+90));
        v_hash_first:=ops.phase2_label_targets_chunk_hash(v_first,least(v_last,v_first+90));
        v_rows:=feat.build_phase2_label_targets_v3(v_first,least(v_last,v_first+90));
        v_hash_second:=ops.phase2_label_targets_chunk_hash(v_first,least(v_last,v_first+90));
        v_base_after:=ops.phase2_chunk_output_hash('labels',v_first,least(v_last,v_first+90));
        IF v_hash_first IS DISTINCT FROM v_hash_second OR v_hash_first !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'derived label chunk rebuild did not preserve its output hash';
        END IF;
        IF v_base_before IS DISTINCT FROM v_base_after THEN
            RAISE EXCEPTION 'derived target build changed the raw label chunk hash';
        END IF;
        IF EXISTS (
            SELECT 1
              FROM feat.phase2_label_targets_v3 t
              JOIN feat.labels_daily l USING(symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash)
             WHERE t.signal_date BETWEEN v_first AND least(v_last,v_first+90)
               AND t.execution_weight IS DISTINCT FROM CASE
                   WHEN l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL
                   THEN feat.phase2_exact_execution_weight(t.symbol_id,l.entry_date,l.exit_date)
                   ELSE NULL::double precision END
        ) THEN
            RAISE EXCEPTION 'stored execution weights differ from exact linked evidence decision';
        END IF;
        IF EXISTS (
            WITH expected AS (
                SELECT t.target_rank_in_tier,t.target_tier_count,t.target_uniform_rank,
                       row_number() OVER (PARTITION BY t.signal_date,t.horizon_sessions,t.liquidity_tier
                                          ORDER BY t.volatility_scaled_score DESC,t.symbol_id)::integer AS actual_rank,
                       count(*) OVER (PARTITION BY t.signal_date,t.horizon_sessions,t.liquidity_tier)::integer AS actual_count
                  FROM feat.phase2_label_targets_v3 t
                 WHERE t.signal_date BETWEEN v_first AND least(v_last,v_first+90)
                   AND t.liquidity_tier IS NOT NULL AND t.volatility_scaled_score IS NOT NULL
            )
            SELECT 1 FROM expected
             WHERE target_rank_in_tier IS DISTINCT FROM actual_rank
                OR target_tier_count IS DISTINCT FROM actual_count
                OR target_uniform_rank IS DISTINCT FROM feat.phase2_target_uniform_rank(actual_rank,actual_count)
        ) THEN
            RAISE EXCEPTION 'stored target rank/count/uniform outputs do not match score ordering';
        END IF;
    END IF;
END;
$$;
ROLLBACK;

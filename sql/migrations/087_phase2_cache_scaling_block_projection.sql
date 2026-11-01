BEGIN;

-- Timing drift across balanced blocks is environmental noise, not a scaling
-- exponent. Keep every sample, reject a material within-block size inversion,
-- and project from the worst block means with the worst block exponent.
CREATE OR REPLACE FUNCTION feat.validate_phase2_cache_samples()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_block_relation oid;
BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_cache_samples'),'pg_class') IS DISTINCT FROM
       'VN-Signal fixed 90-sample cache benchmark' THEN
        RAISE EXCEPTION 'run the fixed 90-sample cache benchmark before scaling validation';
    END IF;
    IF (SELECT count(*) FROM pg_temp.phase2_cache_samples)<>90
       OR EXISTS (SELECT 1 FROM pg_temp.phase2_cache_samples
          WHERE sample_no NOT BETWEEN 1 AND 90 OR symbol_count NOT IN (15,30,60)
             OR row_count<=0 OR duration_ms<=0
             OR configured_batch_size IS DISTINCT FROM coalesce(nullif(current_setting('vnpipe.phase2_symbol_batch_size',true),'')::integer,60)
             OR work_memory IS DISTINCT FROM current_setting('work_mem')
             OR maintenance_memory IS DISTINCT FROM current_setting('maintenance_work_mem'))
       OR EXISTS (SELECT 1 FROM pg_temp.phase2_cache_samples GROUP BY symbol_count
                  HAVING count(*)<>30 OR min(row_count)<>max(row_count))
       OR EXISTS (SELECT 1 FROM pg_temp.phase2_cache_samples
                  GROUP BY ((sample_no-1)/30),symbol_count HAVING count(*)<>10) THEN
        RAISE EXCEPTION 'cache benchmark samples are incomplete, inconsistent, or use a different configuration';
    END IF;

    v_block_relation:=to_regclass('pg_temp.phase2_cache_scaling_blocks');
    IF v_block_relation IS NOT NULL THEN
        IF obj_description(v_block_relation,'pg_class') IS DISTINCT FROM
           'VN-Signal cache benchmark block scaling evidence' THEN
            RAISE EXCEPTION 'temporary relation phase2_cache_scaling_blocks is reserved';
        END IF;
        DROP TABLE pg_temp.phase2_cache_scaling_blocks;
    END IF;
    CREATE TEMP TABLE phase2_cache_scaling_blocks(
        block_no integer PRIMARY KEY,
        mean_15_ms double precision NOT NULL CHECK(mean_15_ms>0),
        mean_30_ms double precision NOT NULL CHECK(mean_30_ms>0),
        mean_60_ms double precision NOT NULL CHECK(mean_60_ms>0),
        b_15_30 double precision NOT NULL CHECK(b_15_30>=0),
        b_30_60 double precision NOT NULL CHECK(b_30_60>=0)
    ) ON COMMIT PRESERVE ROWS;
    COMMENT ON TABLE pg_temp.phase2_cache_scaling_blocks IS
        'VN-Signal cache benchmark block scaling evidence';

    INSERT INTO pg_temp.phase2_cache_scaling_blocks(
        block_no,mean_15_ms,mean_30_ms,mean_60_ms,b_15_30,b_30_60
    )
    WITH block_means AS (
        SELECT ((sample_no-1)/30)::integer AS block_no,
               avg(duration_ms) FILTER(WHERE symbol_count=15) AS mean_15_ms,
               avg(duration_ms) FILTER(WHERE symbol_count=30) AS mean_30_ms,
               avg(duration_ms) FILTER(WHERE symbol_count=60) AS mean_60_ms
        FROM pg_temp.phase2_cache_samples
        GROUP BY ((sample_no-1)/30)::integer
    )
    SELECT block_no,mean_15_ms,mean_30_ms,mean_60_ms,
           CASE WHEN mean_30_ms>mean_15_ms
                THEN ln(mean_30_ms/mean_15_ms)/ln(2.0) ELSE 0.0 END,
           CASE WHEN mean_60_ms>mean_30_ms
                THEN ln(mean_60_ms/mean_30_ms)/ln(2.0) ELSE 0.0 END
    FROM block_means;

    IF (SELECT count(*) FROM pg_temp.phase2_cache_scaling_blocks)<>3 THEN
        RAISE EXCEPTION 'cache benchmark requires three complete balanced blocks';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
        WHERE mean_30_ms<mean_15_ms*0.8 OR mean_60_ms<mean_30_ms*0.8
    ) THEN
        RAISE EXCEPTION 'cache benchmark sample-size timings invert by more than 20 percent within a balanced block';
    END IF;

    -- Keep all raw observations. Use each size's slowest balanced-block mean
    -- for the time projection; do not select a favorable block or repetition.
    UPDATE pg_temp.phase2_adjustment_cache_probe_results p
       SET duration_ms=s.worst_block_mean_ms
    FROM (
        SELECT symbol_count,ceil(max(mean_ms))::bigint AS worst_block_mean_ms
        FROM (
            SELECT 15 AS symbol_count,mean_15_ms AS mean_ms
            FROM pg_temp.phase2_cache_scaling_blocks
            UNION ALL
            SELECT 30,mean_30_ms FROM pg_temp.phase2_cache_scaling_blocks
            UNION ALL
            SELECT 60,mean_60_ms FROM pg_temp.phase2_cache_scaling_blocks
        ) block_times
        GROUP BY symbol_count
    ) s
    WHERE p.symbol_count=s.symbol_count;
END;
$$;

DO $block_scaling_assert$
DECLARE
    v_definition text:=pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure);
    v_old text:=$old$
    IF v_t30<v_t15*0.8 OR v_t60<v_t30*0.8 THEN
        RAISE EXCEPTION 'cache probe timings vary by more than 20%% between adjacent samples; re-probe before the full build: %, %, % ms',
            v_t15,v_t30,v_t60;
    END IF;
    v_b15_30:=CASE WHEN v_t30>v_t15 THEN ln(v_t30/v_t15)/ln(2.0) ELSE 0.0 END;
    v_b30_60:=CASE WHEN v_t60>v_t30 THEN ln(v_t60/v_t30)/ln(2.0) ELSE 0.0 END;
    v_exponent:=greatest(0.0,v_b15_30,v_b30_60);$old$;
    v_new text:=$new$
    IF obj_description(to_regclass('pg_temp.phase2_cache_scaling_blocks'),'pg_class') IS DISTINCT FROM
       'VN-Signal cache benchmark block scaling evidence'
       OR (SELECT count(*) FROM pg_temp.phase2_cache_scaling_blocks)<>3 THEN
        RAISE EXCEPTION 'validated cache benchmark block scaling evidence is missing';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_temp.phase2_cache_scaling_blocks
        WHERE mean_30_ms<mean_15_ms*0.8 OR mean_60_ms<mean_30_ms*0.8
    ) THEN
        RAISE EXCEPTION 'cache benchmark sample-size timings invert by more than 20 percent within a balanced block';
    END IF;
    SELECT max(b_15_30),max(b_30_60)
      INTO v_b15_30,v_b30_60
      FROM pg_temp.phase2_cache_scaling_blocks;
    v_exponent:=greatest(0.0,v_b15_30,v_b30_60);$new$;
BEGIN
    IF position('phase2_cache_scaling_blocks' IN v_definition)>0 THEN RETURN; END IF;
    IF position(v_old IN v_definition)=0 THEN
        RAISE EXCEPTION 'cache block-scaling projection migration anchor missing';
    END IF;
    EXECUTE replace(v_definition,v_old,v_new);
END;
$block_scaling_assert$;

COMMENT ON FUNCTION feat.validate_phase2_cache_samples() IS
    'Validates all 90 balanced cache timings, builds per-block growth exponents, rejects material within-block size inversions, and retains worst-block means for projection.';
COMMENT ON FUNCTION feat.assert_phase2_adjustment_cache_scaling() IS
    'Projects the bounded adjustment-cache strategy using the maximum growth exponent across all balanced blocks and the worst observed block mean per sample size.';

COMMIT;

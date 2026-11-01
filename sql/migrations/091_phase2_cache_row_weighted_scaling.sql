BEGIN;

-- The deterministic 15/30/60 symbol cohorts can contain different numbers of
-- source rows. Compare and project workload by the rows actually processed.
CREATE OR REPLACE FUNCTION feat.phase2_cache_sample_batch_rows_ms(
    p_sample_symbols integer,
    p_sample_rows bigint,
    p_duration_ms double precision,
    p_configured_batch_size integer,
    p_target_batch_rows bigint,
    p_exponent double precision
) RETURNS double precision LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_sample_batches integer;
    v_sample_batch_ms double precision;
    v_sample_batch_rows double precision;
BEGIN
    IF p_sample_symbols IS NULL OR p_sample_symbols NOT IN (15,30,60)
       OR p_sample_rows IS NULL OR p_sample_rows<=0
       OR p_duration_ms IS NULL OR NOT (p_duration_ms>0 AND p_duration_ms<'Infinity'::double precision)
       OR p_configured_batch_size IS NULL OR p_configured_batch_size NOT BETWEEN 1 AND 250
       OR p_target_batch_rows IS NULL OR p_target_batch_rows<=0
       OR p_exponent IS NULL OR NOT (p_exponent>=0 AND p_exponent<=1.3) THEN
        RAISE EXCEPTION 'invalid row-weighted cache projection sample or strategy';
    END IF;

    v_sample_batches:=ceil(p_sample_symbols::numeric/p_configured_batch_size)::integer;
    v_sample_batch_ms:=p_duration_ms/v_sample_batches;
    v_sample_batch_rows:=p_sample_rows::double precision/v_sample_batches;
    IF p_target_batch_rows<=v_sample_batch_rows THEN
        -- Keep a measured per-batch cost when projecting a smaller workload.
        RETURN v_sample_batch_ms;
    END IF;
    -- Larger batches are never projected below linear cost.
    RETURN v_sample_batch_ms*power(
        p_target_batch_rows::double precision/v_sample_batch_rows,
        greatest(1.0,p_exponent)
    );
END;
$$;

CREATE OR REPLACE FUNCTION feat.validate_phase2_cache_samples()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_block_relation oid;
    v_rows_15 bigint;
    v_rows_30 bigint;
    v_rows_60 bigint;
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

    SELECT min(row_count) FILTER(WHERE symbol_count=15),
           min(row_count) FILTER(WHERE symbol_count=30),
           min(row_count) FILTER(WHERE symbol_count=60)
      INTO v_rows_15,v_rows_30,v_rows_60
      FROM pg_temp.phase2_cache_samples;
    IF v_rows_15 IS NULL OR v_rows_30<=v_rows_15 OR v_rows_60<=v_rows_30 THEN
        RAISE EXCEPTION 'cache benchmark row volume must increase across the 15/30/60 symbol cohorts';
    END IF;

    IF EXISTS (
        SELECT 1 FROM (
            SELECT ((sample_no-1)/30) AS block_no,symbol_count,avg(duration_ms) AS mean_ms
            FROM pg_temp.phase2_cache_samples GROUP BY 1,2
        ) blocks GROUP BY symbol_count
        HAVING stddev_pop(mean_ms)/avg(mean_ms)>0.20
    ) THEN
        RAISE EXCEPTION 'cache benchmark block means vary by more than 20 percent; evidence is unstable';
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
        rows_15 bigint NOT NULL CHECK(rows_15>0),
        rows_30 bigint NOT NULL CHECK(rows_30>rows_15),
        rows_60 bigint NOT NULL CHECK(rows_60>rows_30),
        b_15_30 double precision NOT NULL CHECK(b_15_30>=0),
        b_30_60 double precision NOT NULL CHECK(b_30_60>=0)
    ) ON COMMIT PRESERVE ROWS;
    COMMENT ON TABLE pg_temp.phase2_cache_scaling_blocks IS
        'VN-Signal cache benchmark block scaling evidence';

    INSERT INTO pg_temp.phase2_cache_scaling_blocks(
        block_no,mean_15_ms,mean_30_ms,mean_60_ms,rows_15,rows_30,rows_60,b_15_30,b_30_60
    )
    WITH block_means AS (
        SELECT ((sample_no-1)/30)::integer AS block_no,
               avg(duration_ms) FILTER(WHERE symbol_count=15) AS mean_15_ms,
               avg(duration_ms) FILTER(WHERE symbol_count=30) AS mean_30_ms,
               avg(duration_ms) FILTER(WHERE symbol_count=60) AS mean_60_ms,
               min(row_count) FILTER(WHERE symbol_count=15) AS rows_15,
               min(row_count) FILTER(WHERE symbol_count=30) AS rows_30,
               min(row_count) FILTER(WHERE symbol_count=60) AS rows_60
        FROM pg_temp.phase2_cache_samples
        GROUP BY ((sample_no-1)/30)::integer
    )
    SELECT block_no,mean_15_ms,mean_30_ms,mean_60_ms,rows_15,rows_30,rows_60,
           CASE WHEN mean_30_ms>mean_15_ms
                THEN ln(mean_30_ms/mean_15_ms)/ln(rows_30::double precision/rows_15::double precision) ELSE 0.0 END,
           CASE WHEN mean_60_ms>mean_30_ms
                THEN ln(mean_60_ms/mean_30_ms)/ln(rows_60::double precision/rows_30::double precision) ELSE 0.0 END
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
            SELECT 15 AS symbol_count,mean_15_ms AS mean_ms FROM pg_temp.phase2_cache_scaling_blocks
            UNION ALL SELECT 30,mean_30_ms FROM pg_temp.phase2_cache_scaling_blocks
            UNION ALL SELECT 60,mean_60_ms FROM pg_temp.phase2_cache_scaling_blocks
        ) block_times
        GROUP BY symbol_count
    ) s
    WHERE p.symbol_count=s.symbol_count;
END;
$$;

CREATE OR REPLACE FUNCTION feat.assert_phase2_adjustment_cache_scaling()
RETURNS double precision LANGUAGE plpgsql AS $$
DECLARE
    v_t15 double precision;
    v_t30 double precision;
    v_t60 double precision;
    v_rows_15 bigint;
    v_rows_30 bigint;
    v_rows_60 bigint;
    v_b15_30 double precision;
    v_b30_60 double precision;
    v_exponent double precision;
    v_universe_symbols integer;
    v_observed_batch_count integer;
    v_batch_size integer;
    v_batch_count integer;
    v_total_rows bigint;
    v_expected_batch_rows bigint;
    v_batch_ms double precision;
    v_projected_ms double precision;
    v_budget_minutes double precision;
BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_cache_probe_results'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache scaling probe results'
       OR obj_description(to_regclass('pg_temp.phase2_cache_scaling_blocks'),'pg_class') IS DISTINCT FROM
       'VN-Signal cache benchmark block scaling evidence'
       OR (SELECT count(*) FROM pg_temp.phase2_cache_scaling_blocks)<>3 THEN
        RAISE EXCEPTION 'run and validate the fixed cache benchmark before full-build projection';
    END IF;

    SELECT duration_ms::double precision,row_count INTO v_t15,v_rows_15
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=15;
    SELECT duration_ms::double precision,row_count INTO v_t30,v_rows_30
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=30;
    SELECT duration_ms::double precision,row_count INTO v_t60,v_rows_60
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=60;
    IF v_t15 IS NULL OR v_t30 IS NULL OR v_t60 IS NULL
       OR v_rows_15 IS NULL OR v_rows_30 IS NULL OR v_rows_60 IS NULL
       OR v_rows_30<=v_rows_15 OR v_rows_60<=v_rows_30 THEN
        RAISE EXCEPTION 'cache scaling evidence requires valid 15/30/60 symbol and row-volume samples';
    END IF;
    IF v_t30<v_t15*0.8 OR v_t60<v_t30*0.8 THEN
        RAISE EXCEPTION 'cache probe timings vary by more than 20%% between adjacent workloads; re-probe before the full build: %/%/% rows, %/%/% ms',
            v_rows_15,v_rows_30,v_rows_60,v_t15,v_t30,v_t60;
    END IF;

    SELECT max(b_15_30),max(b_30_60)
      INTO v_b15_30,v_b30_60
      FROM pg_temp.phase2_cache_scaling_blocks;
    v_exponent:=greatest(0.0,v_b15_30,v_b30_60);
    IF v_exponent>1.3 THEN
        RAISE EXCEPTION 'cache row-scaling exponent % exceeds 1.3; inspect the sampled plan and re-probe',
            round(v_exponent::numeric,3);
    END IF;

    v_batch_size:=COALESCE(NULLIF(current_setting('vnpipe.phase2_symbol_batch_size',true),'')::integer,60);
    IF v_batch_size<1 OR v_batch_size>250 THEN
        RAISE EXCEPTION 'vnpipe.phase2_symbol_batch_size must be between 1 and 250';
    END IF;
    v_budget_minutes:=COALESCE(NULLIF(current_setting('vnpipe.phase2_cache_time_budget_minutes',true),'')::double precision,40.0);
    IF v_budget_minutes<=0 THEN
        RAISE EXCEPTION 'vnpipe.phase2_cache_time_budget_minutes must be positive';
    END IF;

    -- Match the production symbol ordering and batch boundaries exactly. The
    -- source-row count is the expected adjustment-cache work for each batch.
    WITH eligible_symbols AS (
        SELECT s.symbol_id
        FROM core.symbols s
        WHERE EXISTS (
              SELECT 1 FROM core.bars_daily_sources b
              WHERE b.symbol_id=s.symbol_id AND b.source='vndirect'
          )
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=s.symbol_id AND excluded.scope_status='EXCLUDED'
          )
    ), ranked_symbols AS (
        SELECT symbol_id,
               row_number() OVER (ORDER BY md5(symbol_id::text),symbol_id) AS symbol_no
        FROM eligible_symbols
    ), batch_rows AS (
        SELECT ((s.symbol_no-1)/v_batch_size)::integer AS batch_no,
               count(DISTINCT s.symbol_id)::integer AS symbol_count,
               count(b.symbol_id)::bigint AS row_count
        FROM ranked_symbols s
        JOIN core.bars_daily_sources b
          ON b.symbol_id=s.symbol_id AND b.source='vndirect'
        GROUP BY ((s.symbol_no-1)/v_batch_size)::integer
    )
    SELECT sum(symbol_count)::integer,count(*)::integer,
           sum(row_count)::bigint,max(row_count)::bigint
      INTO v_universe_symbols,v_observed_batch_count,v_total_rows,v_expected_batch_rows
      FROM batch_rows;

    IF v_universe_symbols<60 THEN
        RAISE EXCEPTION 'cache scaling has only % in-scope symbols; 60-symbol probe cannot represent the full universe',
            v_universe_symbols;
    END IF;
    v_batch_count:=ceil(v_universe_symbols::double precision/v_batch_size)::integer;
    IF v_observed_batch_count IS DISTINCT FROM v_batch_count
       OR v_total_rows IS NULL OR v_total_rows<=0
       OR v_expected_batch_rows IS NULL OR v_expected_batch_rows<=0 THEN
        RAISE EXCEPTION 'could not derive exact source-row workload for each configured cache batch';
    END IF;

    v_batch_ms:=greatest(
        feat.phase2_cache_sample_batch_rows_ms(15,v_rows_15,v_t15,v_batch_size,v_expected_batch_rows,v_exponent),
        feat.phase2_cache_sample_batch_rows_ms(30,v_rows_30,v_t30,v_batch_size,v_expected_batch_rows,v_exponent),
        feat.phase2_cache_sample_batch_rows_ms(60,v_rows_60,v_t60,v_batch_size,v_expected_batch_rows,v_exponent)
    );
    v_projected_ms:=v_batch_ms*v_batch_count;
    IF v_projected_ms>v_budget_minutes*60000.0 THEN
        RAISE EXCEPTION 'projected full-universe adjustment cache time % minutes exceeds configured budget % minutes for % symbols and % source rows',
            round((v_projected_ms/60000.0)::numeric,2),v_budget_minutes,v_universe_symbols,v_total_rows;
    END IF;
    RAISE NOTICE 'Phase 2 adjustment-cache row-scaling exponent %, samples %/%/% symbols with %/%/% rows took %/%/% ms; % symbols and % source rows in % batches of % (largest batch % rows, estimated per-batch % ms), projected cache time % minutes (budget % minutes)',
        round(v_exponent::numeric,3),15,30,60,v_rows_15,v_rows_30,v_rows_60,
        v_t15,v_t30,v_t60,v_universe_symbols,v_total_rows,v_batch_count,v_batch_size,
        v_expected_batch_rows,round(v_batch_ms::numeric,1),
        round((v_projected_ms/60000.0)::numeric,2),v_budget_minutes;
    RETURN v_exponent;
END;
$$;

COMMENT ON FUNCTION feat.phase2_cache_sample_batch_rows_ms(integer,bigint,double precision,integer,bigint,double precision) IS
    'Conservative cache cost per configured batch, normalized by measured source rows per batch and never extrapolated below linear cost for larger batches.';
COMMENT ON FUNCTION feat.validate_phase2_cache_samples() IS
    'Validates all 90 balanced cache timings, computes per-block scaling exponents from actual source-row counts, and retains worst-block means for projection.';
COMMENT ON FUNCTION feat.assert_phase2_adjustment_cache_scaling() IS
    'Projects the bounded adjustment-cache strategy from row-weighted growth and exact production source-row counts per configured symbol batch, retaining the 1.3 exponent and 40-minute budget gates.';

COMMIT;

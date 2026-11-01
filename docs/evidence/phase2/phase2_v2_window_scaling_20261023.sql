-- Final bounded synthetic scaling probe for the only retained optimization:
-- native avg/stddev plus integrated exact block-prefix/suffix 250-row extrema.
-- Run only after the numerical fixture passes on the disposable report clone.
-- Captures five alternating/interleaved EXPLAIN ANALYZE plans at each size.
\set ON_ERROR_STOP on
\pset pager off
\timing on
SET work_mem='64MB';
SET statement_timeout='5min';

DO $guard$
BEGIN
    IF current_database()<>'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'scaling probe is restricted to disposable database vnsignal_phase2_report_20261019';
    END IF;
END;
$guard$;

CREATE TEMP TABLE phase2_window_scaling_input (
    symbol_id integer NOT NULL,
    session_no integer NOT NULL,
    episode_id integer NOT NULL,
    x double precision,
    high_value double precision,
    low_value double precision,
    PRIMARY KEY(symbol_id,session_no)
) ON COMMIT PRESERVE ROWS;

CREATE TEMP TABLE phase2_window_scaling_runs (
    symbol_count integer NOT NULL,
    repetition integer NOT NULL,
    variant text NOT NULL CHECK(variant IN ('direct','integrated')),
    execution_ms double precision NOT NULL,
    plan jsonb NOT NULL
) ON COMMIT PRESERVE ROWS;

CREATE TEMP VIEW phase2_window_scaling_direct AS
SELECT symbol_id,session_no,
       avg(x) OVER w20 AS avg20,stddev_samp(x) OVER w60 AS sd60,
       max(high_value) FILTER(WHERE high_value IS NOT NULL) OVER w250 AS high250,
       min(low_value) FILTER(WHERE low_value IS NOT NULL) OVER w250 AS low250
FROM phase2_window_scaling_input
WINDOW w20 AS(PARTITION BY symbol_id,episode_id ORDER BY session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
       w60 AS(PARTITION BY symbol_id,episode_id ORDER BY session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),
       w250 AS(PARTITION BY symbol_id,episode_id ORDER BY session_no ROWS BETWEEN 249 PRECEDING AND CURRENT ROW);

CREATE TEMP VIEW phase2_window_scaling_integrated AS
WITH extrema_rows AS (
    SELECT i.*,row_number() OVER(PARTITION BY symbol_id,episode_id ORDER BY session_no)-1 AS row_no
    FROM phase2_window_scaling_input i
), extrema_blocks AS (
    SELECT e.*,(row_no/250)::bigint AS block_no,
           max(high_value) OVER(PARTITION BY symbol_id,episode_id,(row_no/250) ORDER BY row_no ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS high_prefix,
           max(high_value) OVER(PARTITION BY symbol_id,episode_id,(row_no/250) ORDER BY row_no ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS high_suffix,
           min(low_value) OVER(PARTITION BY symbol_id,episode_id,(row_no/250) ORDER BY row_no ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS low_prefix,
           min(low_value) OVER(PARTITION BY symbol_id,episode_id,(row_no/250) ORDER BY row_no ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING) AS low_suffix
    FROM extrema_rows e
), extrema_lags AS (
    SELECT b.*,lag(high_suffix,249) OVER(PARTITION BY symbol_id,episode_id ORDER BY row_no) AS high_suffix_start,
           lag(low_suffix,249) OVER(PARTITION BY symbol_id,episode_id ORDER BY row_no) AS low_suffix_start
    FROM extrema_blocks b
), extrema250 AS (
    SELECT l.*,
           CASE WHEN row_no<249 OR block_no=((row_no-249)/250) THEN high_prefix
                ELSE greatest(high_prefix,high_suffix_start) END AS high250,
           CASE WHEN row_no<249 OR block_no=((row_no-249)/250) THEN low_prefix
                ELSE least(low_prefix,low_suffix_start) END AS low250
    FROM extrema_lags l
)
SELECT symbol_id,session_no,
       avg(x) OVER w20 AS avg20,stddev_samp(x) OVER w60 AS sd60,high250,low250
FROM extrema250
WINDOW w20 AS(PARTITION BY symbol_id,episode_id ORDER BY session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
       w60 AS(PARTITION BY symbol_id,episode_id ORDER BY session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW);

DO $probe$
DECLARE
    n_symbols integer;
    rep integer;
    variant_name text;
    plan_json jsonb;
    query_sql text;
    order_a text[]:=ARRAY['direct','integrated'];
    order_b text[]:=ARRAY['integrated','direct'];
BEGIN
    FOREACH n_symbols IN ARRAY ARRAY[15,30,60] LOOP
        TRUNCATE phase2_window_scaling_input;
        EXECUTE format($insert$
            INSERT INTO phase2_window_scaling_input
            SELECT s,n,CASE WHEN n<=1000 THEN 1 ELSE 2 END,
                   CASE WHEN n%%19=0 THEN NULL ELSE 100+s*0.1+sin(n::double precision/17) END,
                   CASE WHEN n%%17=0 THEN NULL ELSE 100+s*0.1+sin(n::double precision/17)+CASE WHEN n%%29=0 THEN 100 ELSE 3 END END,
                   CASE WHEN n%%23=0 THEN NULL ELSE 100+s*0.1+sin(n::double precision/17)-CASE WHEN n%%31=0 THEN 100 ELSE 2 END END
            FROM generate_series(1,%s) symbols(s) CROSS JOIN generate_series(1,2000) days(n)
        $insert$,n_symbols);
        ANALYZE phase2_window_scaling_input;

        -- Warm each branch once, excluded from reported medians.
        FOR variant_name IN SELECT unnest(order_a) LOOP
            query_sql:=format('SELECT count(*),sum(coalesce(avg20,0)+coalesce(sd60,0)+coalesce(high250,0)+coalesce(low250,0)) FROM phase2_window_scaling_%s',variant_name);
            EXECUTE format('EXPLAIN (ANALYZE,BUFFERS,TIMING OFF,FORMAT JSON) %s',query_sql) INTO plan_json;
        END LOOP;

        FOR rep IN 1..5 LOOP
            FOR variant_name IN SELECT unnest(CASE WHEN rep%2=1 THEN order_a ELSE order_b END) LOOP
                query_sql:=format('SELECT count(*),sum(coalesce(avg20,0)+coalesce(sd60,0)+coalesce(high250,0)+coalesce(low250,0)) FROM phase2_window_scaling_%s',variant_name);
                EXECUTE format('EXPLAIN (ANALYZE,BUFFERS,TIMING OFF,FORMAT JSON) %s',query_sql) INTO plan_json;
                INSERT INTO phase2_window_scaling_runs
                VALUES(n_symbols,rep,variant_name,(plan_json->0->>'Execution Time')::double precision,plan_json->0);
            END LOOP;
        END LOOP;
    END LOOP;
END;
$probe$;

-- Every captured JSON plan is retained in the query result for buffer/sort
-- and spill inspection. Medians and log-log scaling exponent summarize runs.
SELECT symbol_count,variant,count(*) AS repetitions,
       percentile_cont(0.5) WITHIN GROUP(ORDER BY execution_ms) AS median_ms,
       min(execution_ms) AS min_ms,max(execution_ms) AS max_ms,
       sum(coalesce((plan->'Plan'->>'Shared Hit Blocks')::bigint,0)) AS shared_hit_blocks,
       sum(coalesce((plan->'Plan'->>'Shared Read Blocks')::bigint,0)) AS shared_read_blocks,
       sum(coalesce((plan->'Plan'->>'Local Hit Blocks')::bigint,0)) AS local_hit_blocks,
       sum(coalesce((plan->'Plan'->>'Local Read Blocks')::bigint,0)) AS local_read_blocks,
       sum(coalesce((plan->'Plan'->>'Temp Read Blocks')::bigint,0)) AS temp_read_blocks,
       sum(coalesce((plan->'Plan'->>'Temp Written Blocks')::bigint,0)) AS temp_written_blocks
FROM phase2_window_scaling_runs
GROUP BY symbol_count,variant
ORDER BY symbol_count,variant;

WITH medians AS (
    SELECT symbol_count,variant,percentile_cont(0.5) WITHIN GROUP(ORDER BY execution_ms) AS median_ms
    FROM phase2_window_scaling_runs GROUP BY symbol_count,variant
)
SELECT variant,regr_slope(ln(median_ms),ln(symbol_count::double precision*2000)) AS row_count_scaling_exponent
FROM medians GROUP BY variant ORDER BY variant;

SELECT symbol_count,repetition,variant,execution_ms,
       plan->'Plan' AS top_plan_buffers_and_shape
FROM phase2_window_scaling_runs
ORDER BY symbol_count,repetition,variant;

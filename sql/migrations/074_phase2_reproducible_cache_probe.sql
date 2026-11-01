BEGIN;
CREATE OR REPLACE FUNCTION feat.validate_phase2_cache_samples()
RETURNS void LANGUAGE plpgsql AS $$
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
    IF EXISTS (
        SELECT 1 FROM (
            SELECT ((sample_no-1)/30) AS block_no,symbol_count,avg(duration_ms) AS mean_ms
            FROM pg_temp.phase2_cache_samples GROUP BY 1,2
        ) blocks GROUP BY symbol_count
        HAVING stddev_pop(mean_ms)/avg(mean_ms)>0.20
    ) THEN
        RAISE EXCEPTION 'cache benchmark block means vary by more than 20 percent; evidence is unstable';
    END IF;
    -- Use all observations, not a favorable sample or minimum.
    UPDATE pg_temp.phase2_adjustment_cache_probe_results p
    SET duration_ms=s.mean_ms
    FROM (SELECT symbol_count,ceil(avg(duration_ms))::bigint AS mean_ms
          FROM pg_temp.phase2_cache_samples GROUP BY symbol_count) s
    WHERE p.symbol_count=s.symbol_count;
END;
$$;

CREATE OR REPLACE FUNCTION feat.measure_phase2_cache_scaling()
RETURNS TABLE(sample_no integer,symbol_count integer,row_count bigint,duration_ms bigint)
LANGUAGE plpgsql AS $$
DECLARE
    sizes integer[]:=ARRAY[15,30,60,30,60,15,60,15,30];
    i integer; cycle integer; sample record;
BEGIN
    IF to_regclass('pg_temp.phase2_cache_samples') IS NOT NULL THEN
        IF obj_description(to_regclass('pg_temp.phase2_cache_samples'),'pg_class') IS DISTINCT FROM
           'VN-Signal fixed 90-sample cache benchmark' THEN
            RAISE EXCEPTION 'temporary relation phase2_cache_samples is reserved';
        END IF;
        DROP TABLE pg_temp.phase2_cache_samples;
    END IF;
    CREATE TEMP TABLE phase2_cache_samples(
        sample_no integer PRIMARY KEY,symbol_count integer NOT NULL,row_count bigint NOT NULL,
        duration_ms bigint NOT NULL,configured_batch_size integer NOT NULL,
        work_memory text NOT NULL,maintenance_memory text NOT NULL
    ) ON COMMIT PRESERVE ROWS;
    COMMENT ON TABLE pg_temp.phase2_cache_samples IS 'VN-Signal fixed 90-sample cache benchmark';
    PERFORM feat.probe_phase2_adjustment_cache(15);
    PERFORM feat.probe_phase2_adjustment_cache(30);
    PERFORM feat.probe_phase2_adjustment_cache(60);
    FOR cycle IN 1..10 LOOP
        FOR i IN 1..9 LOOP
            SELECT * INTO STRICT sample FROM feat.probe_phase2_adjustment_cache(sizes[i]);
            INSERT INTO pg_temp.phase2_cache_samples
            SELECT (cycle-1)*9+i,p.* FROM pg_temp.phase2_adjustment_cache_probe_results p
            WHERE p.symbol_count=sizes[i];
            RAISE NOTICE 'cache benchmark sample % size % rows % duration_ms %',
                (cycle-1)*9+i,sample.symbol_count,sample.row_count,sample.duration_ms;
        END LOOP;
    END LOOP;
    PERFORM feat.validate_phase2_cache_samples();
    RETURN QUERY SELECT s.sample_no,s.symbol_count,s.row_count,s.duration_ms
                 FROM pg_temp.phase2_cache_samples s ORDER BY s.sample_no;
END;
$$;

DO $samples_guard$
DECLARE
    definition text:=pg_get_functiondef('feat.assert_phase2_adjustment_cache_scaling()'::regprocedure);
    anchor text:=$anchor$BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_cache_probe_results'),'pg_class')$anchor$;
BEGIN
    IF position('PERFORM feat.validate_phase2_cache_samples();' IN definition)>0 THEN RETURN; END IF;
    IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'scaling sample guard anchor missing'; END IF;
    EXECUTE replace(definition,anchor,replace(anchor,'BEGIN','BEGIN'||chr(10)||'    PERFORM feat.validate_phase2_cache_samples();'));
END;
$samples_guard$;
COMMIT;

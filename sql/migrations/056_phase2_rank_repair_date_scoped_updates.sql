-- Keep rank writes constrained to the same monthly slice as their expected rows.
-- This enables the existing date/version index without changing output semantics.
BEGIN;

CREATE OR REPLACE FUNCTION ops.repair_phase2_rank_chunk(
    p_build_id text,p_date_from date,p_date_to date,p_force boolean DEFAULT false
)
RETURNS TABLE(v2_rows bigint,v3_rows bigint,changed_rows bigint,output_sha256 text,skipped boolean)
LANGUAGE plpgsql SET lock_timeout TO '5s' AS $$
DECLARE
    old_v2 constant text:='913bd125dbdc8e29fbac3c0b9d76965d7c71121768a5d0e2dab33db1b7e1380f';
    old_v3 constant text:='397fec9c226e5c8d1ad9742ac264bb07f2012f43f71f29fe67499d835444f11c';
    new_v2 constant text:='4f055e336c4721e9ea4dde9f6fb88fc381508a114a1895878d330d0d1eeb02b3';
    new_v3 constant text:='f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1';
    checkpoint ops.phase2_rank_repairs%ROWTYPE;
    n2 bigint; n3 bigint; changed bigint:=0; n_changed bigint;
    input_hash text; output_hash text; nonrank_hash text; previous_path text;
    started timestamptz:=clock_timestamp(); expected_relation oid;
BEGIN
    IF p_build_id IS NULL OR p_build_id !~ '^[A-Za-z0-9._-]{1,100}$'
       OR p_date_from IS NULL OR p_date_to IS NULL OR p_date_to<p_date_from
       OR p_date_to-p_date_from>30 OR p_force IS NULL THEN
        RAISE EXCEPTION 'rank repair requires a build ID and an inclusive range of 1..31 days';
    END IF;
    IF feat.phase2_feature_set_hash()<>new_v2 OR feat.phase2_feature_set_hash_v3()<>new_v3 THEN
        RAISE EXCEPTION 'rank repair is restricted to the audited 052-to-053 semantic upgrade';
    END IF;
    -- Serialize recovery writers; a chunk is atomic, so cancellation rolls it
    -- back and the caller can record failure in a separate transaction.
    PERFORM pg_advisory_xact_lock(hashtextextended('VN-Signal:phase2-rank-repair',0));
    LOCK TABLE feat.features_daily IN SHARE ROW EXCLUSIVE MODE;
    IF EXISTS (SELECT 1 FROM ops.phase2_rank_repairs c WHERE c.build_id=p_build_id
        AND daterange(c.date_from,c.date_to,'[]') && daterange(p_date_from,p_date_to,'[]')
        AND (c.date_from,c.date_to)<>(p_date_from,p_date_to)) THEN
        RAISE EXCEPTION 'overlapping rank repair chunks in the same build';
    END IF;
    SELECT * INTO checkpoint FROM ops.phase2_rank_repairs c
     WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to FOR UPDATE;
    input_hash:=ops.phase2_rank_panel_hash(p_date_from,p_date_to,false);
    nonrank_hash:=ops.phase2_rank_panel_hash(p_date_from,p_date_to,true);
    IF checkpoint.status='done' THEN
        IF input_hash IS DISTINCT FROM checkpoint.output_sha256
           OR nonrank_hash IS DISTINCT FROM checkpoint.nonrank_sha256 THEN
            RAISE EXCEPTION 'completed rank repair output changed; investigate before using a new build ID';
        END IF;
        IF NOT p_force THEN
            RETURN QUERY SELECT checkpoint.v2_rows,checkpoint.v3_rows,0::bigint,checkpoint.output_sha256,true;
            RETURN;
        END IF;
    END IF;
    SELECT count(*) FILTER(WHERE f.feature_version='phase2-v2'),
           count(*) FILTER(WHERE f.feature_version='phase2-v3') INTO n2,n3
      FROM feat.features_daily f WHERE f.trade_date BETWEEN p_date_from AND p_date_to
       AND f.feature_version IN ('phase2-v2','phase2-v3');
    IF n2=0 OR n2<>n3 THEN RAISE EXCEPTION 'rank repair requires matching non-empty V2/V3 panels'; END IF;
    IF EXISTS (SELECT 1 FROM feat.features_daily f
         WHERE f.trade_date BETWEEN p_date_from AND p_date_to
           AND ((f.feature_version='phase2-v2' AND (f.feature_set_hash IS NULL OR f.feature_set_hash NOT IN (old_v2,new_v2)))
             OR (f.feature_version='phase2-v3' AND (f.feature_set_hash IS NULL OR f.feature_set_hash NOT IN (old_v3,new_v3))))) THEN
        RAISE EXCEPTION 'rank repair found an unknown source semantic hash';
    END IF;
    IF EXISTS (
        WITH v2 AS (SELECT * FROM feat.features_daily f WHERE f.feature_version='phase2-v2'
                    AND f.trade_date BETWEEN p_date_from AND p_date_to),
             v3 AS (SELECT * FROM feat.features_daily f WHERE f.feature_version='phase2-v3'
                    AND f.trade_date BETWEEN p_date_from AND p_date_to)
        SELECT 1 FROM v2 FULL JOIN v3 USING(symbol_id,trade_date)
         WHERE v2.symbol_id IS NULL OR v3.symbol_id IS NULL
            OR (v2.return_20s,v2.turnover_proxy_vnd,v2.realized_vol20)
                IS DISTINCT FROM (v3.return_20s,v3.turnover_proxy_vnd,v3.realized_vol20)
    ) THEN RAISE EXCEPTION 'rank repair found different V2/V3 keys or rank inputs'; END IF;
    IF EXISTS (SELECT 1 FROM feat.features_daily f
        CROSS JOIN LATERAL (VALUES(f.return_20s),(f.turnover_proxy_vnd),(f.realized_vol20)) x(value)
        WHERE f.feature_version='phase2-v2' AND f.trade_date BETWEEN p_date_from AND p_date_to
          AND (x.value='NaN'::double precision OR abs(x.value)='Infinity'::double precision)) THEN
        RAISE EXCEPTION 'rank repair found a nonfinite input';
    END IF;
    expected_relation:=to_regclass('pg_temp.phase2_rank_repair_expected');
    IF expected_relation IS NOT NULL THEN
        IF obj_description(expected_relation,'pg_class') IS DISTINCT FROM 'VN-Signal rank repair expected rows' THEN
            RAISE EXCEPTION 'temporary relation phase2_rank_repair_expected is reserved';
        END IF;
        DROP TABLE pg_temp.phase2_rank_repair_expected;
    END IF;
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    CREATE TEMP TABLE phase2_rank_repair_expected ON COMMIT DROP AS
    SELECT * FROM feat.phase2_cross_sectional_ranks(p_date_from,p_date_to,NULL);
    COMMENT ON TABLE pg_temp.phase2_rank_repair_expected IS 'VN-Signal rank repair expected rows';
    ALTER TABLE pg_temp.phase2_rank_repair_expected ADD PRIMARY KEY(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_rank_repair_expected;
    -- The helper omits rows with no rankable input. Preserve those keys with
    -- NULL outputs too, so an old partial-window rank cannot survive.
    INSERT INTO pg_temp.phase2_rank_repair_expected
    SELECT f.symbol_id,f.trade_date,NULL,NULL,NULL,NULL FROM feat.features_daily f
     WHERE f.feature_version='phase2-v2' AND f.trade_date BETWEEN p_date_from AND p_date_to
       AND NOT EXISTS (SELECT 1 FROM pg_temp.phase2_rank_repair_expected r
                        WHERE r.symbol_id=f.symbol_id AND r.trade_date=f.trade_date);
    ANALYZE pg_temp.phase2_rank_repair_expected;
    UPDATE feat.features_daily f SET rank_realized_vol20=r.uniform_vol20,feature_set_hash=new_v2,built_at=now()
      FROM pg_temp.phase2_rank_repair_expected r
     WHERE f.symbol_id=r.symbol_id AND f.trade_date=r.trade_date AND f.feature_version='phase2-v2'
       AND f.trade_date BETWEEN p_date_from AND p_date_to
       AND (f.rank_realized_vol20,f.feature_set_hash) IS DISTINCT FROM (r.uniform_vol20,new_v2);
    GET DIAGNOSTICS n_changed=ROW_COUNT; changed:=changed+n_changed;
    UPDATE feat.features_daily f SET rank_realized_vol20=r.uniform_vol20,
           rank_gaussian_return20=r.gauss_return20,rank_gaussian_turnover_proxy=r.gauss_turnover,
           rank_gaussian_realized_vol20=r.gauss_vol20,feature_set_hash=new_v3,built_at=now()
      FROM pg_temp.phase2_rank_repair_expected r
     WHERE f.symbol_id=r.symbol_id AND f.trade_date=r.trade_date AND f.feature_version='phase2-v3'
       AND f.trade_date BETWEEN p_date_from AND p_date_to
       AND (f.rank_realized_vol20,f.rank_gaussian_return20,f.rank_gaussian_turnover_proxy,
            f.rank_gaussian_realized_vol20,f.feature_set_hash) IS DISTINCT FROM
           (r.uniform_vol20,r.gauss_return20,r.gauss_turnover,r.gauss_vol20,new_v3);
    GET DIAGNOSTICS n_changed=ROW_COUNT; changed:=changed+n_changed;
    PERFORM feat.phase2_builder_restore_context(previous_path);
    IF nonrank_hash IS DISTINCT FROM ops.phase2_rank_panel_hash(p_date_from,p_date_to,true) THEN
        RAISE EXCEPTION 'rank repair changed a non-rank field';
    END IF;
    output_hash:=ops.phase2_rank_panel_hash(p_date_from,p_date_to,false);
    IF checkpoint.status='done' AND output_hash IS DISTINCT FROM checkpoint.output_sha256 THEN
        RAISE EXCEPTION 'forced rank recomputation is not reproducible';
    END IF;
    INSERT INTO ops.phase2_rank_repairs AS c
        (build_id,date_from,date_to,status,attempts,v2_rows,v3_rows,changed_rows,first_input_sha256,
         output_sha256,nonrank_sha256,started_at,finished_at,error)
    VALUES(p_build_id,p_date_from,p_date_to,'done',1,n2,n3,changed,input_hash,output_hash,
           nonrank_hash,started,clock_timestamp(),NULL)
    ON CONFLICT(build_id,date_from,date_to) DO UPDATE SET status='done',attempts=c.attempts+1,
        v2_rows=EXCLUDED.v2_rows,v3_rows=EXCLUDED.v3_rows,changed_rows=EXCLUDED.changed_rows,
        first_input_sha256=coalesce(c.first_input_sha256,EXCLUDED.first_input_sha256),
        output_sha256=EXCLUDED.output_sha256,nonrank_sha256=EXCLUDED.nonrank_sha256,
        started_at=EXCLUDED.started_at,finished_at=EXCLUDED.finished_at,error=NULL;
    INSERT INTO ops.phase2_rank_repair_attempts
        (build_id,date_from,date_to,attempt,changed_rows,input_sha256,output_sha256,nonrank_sha256,started_at,finished_at)
    SELECT c.build_id,c.date_from,c.date_to,c.attempts,changed,input_hash,output_hash,nonrank_hash,started,clock_timestamp()
      FROM ops.phase2_rank_repairs c WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to;
    INSERT INTO ops.feature_chunks AS c
        (build_id,stage,chunk_key,date_from,date_to,status,rows,started_at,finished_at,input_sha256,output_sha256,error)
    VALUES(p_build_id,'features','ranks:'||p_date_from||':'||p_date_to,p_date_from,p_date_to,'done',n3,
           started,clock_timestamp(),input_hash,output_hash,NULL)
    ON CONFLICT(build_id,stage,chunk_key) DO UPDATE SET status='done',rows=EXCLUDED.rows,
        started_at=EXCLUDED.started_at,finished_at=EXCLUDED.finished_at,
        input_sha256=EXCLUDED.input_sha256,output_sha256=EXCLUDED.output_sha256,error=NULL;
    INSERT INTO ops.step_runs
        (build_id,stage,chunk_key,status,rows,started_at,finished_at,duration_ms,input_sha256,output_sha256)
    VALUES(p_build_id,'features','ranks:'||p_date_from||':'||p_date_to,'done',n3,started,clock_timestamp(),
           greatest(0,(extract(epoch FROM clock_timestamp()-started)*1000)::bigint),input_hash,output_hash);
    RETURN QUERY SELECT n2,n3,changed,output_hash,false;
END $$;

COMMIT;

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='180s';
DO $rank_repair$
DECLARE
    d date; sid bigint; n bigint; wanted text; preserved text; first_hash text;
    before_rejection text; actual record; rejected boolean;
    rank_function text; rank_update_block text; rank_update_start integer; rank_update_end integer;
    date_filter constant text:='AND f.trade_date BETWEEN p_date_from AND p_date_to';
    old2 constant text:='913bd125dbdc8e29fbac3c0b9d76965d7c71121768a5d0e2dab33db1b7e1380f';
    old3 constant text:='397fec9c226e5c8d1ad9742ac264bb07f2012f43f71f29fe67499d835444f11c';
BEGIN
    rank_function:=pg_get_functiondef('ops.repair_phase2_rank_chunk(text,date,date,boolean)'::regprocedure);
    rank_update_start:=strpos(rank_function,'UPDATE feat.features_daily f SET rank_realized_vol20=r.uniform_vol20,feature_set_hash=new_v2');
    rank_update_end:=strpos(rank_function,'PERFORM feat.phase2_builder_restore_context(previous_path)');
    IF rank_update_start=0 OR rank_update_end<=rank_update_start THEN
        RAISE EXCEPTION 'rank repair update anchors changed';
    END IF;
    rank_update_block:=substring(rank_function FROM rank_update_start FOR rank_update_end-rank_update_start);
    IF (length(rank_update_block)-length(replace(rank_update_block,date_filter,'')))/length(date_filter)<>2 THEN
        RAISE EXCEPTION 'both V2 and V3 rank updates must be bounded to the repaired date range';
    END IF;
    SELECT f.trade_date INTO STRICT d FROM feat.features_daily f
     WHERE f.feature_version='phase2-v2' GROUP BY f.trade_date
    HAVING count(*)>=4 AND count(*) FILTER(WHERE f.realized_vol20 IS NULL)>0
       AND count(*) FILTER(WHERE f.realized_vol20 IS NOT NULL)>0
     ORDER BY f.trade_date DESC LIMIT 1;
    SELECT min(f.symbol_id),count(*) INTO sid,n FROM feat.features_daily f
     WHERE f.feature_version='phase2-v2' AND f.trade_date=d;
    wanted:=ops.phase2_rank_panel_hash(d,d,false);
    preserved:=ops.phase2_rank_panel_hash(d,d,true);
    -- Synthetic old-version faults cover wrong ordering and NULL attachment.
    UPDATE feat.features_daily SET feature_set_hash=CASE feature_version WHEN 'phase2-v2' THEN old2 ELSE old3 END,
           rank_realized_vol20=0.75
     WHERE trade_date=d AND feature_version IN ('phase2-v2','phase2-v3');
    UPDATE feat.features_daily SET rank_gaussian_return20=0.125,
           rank_gaussian_turnover_proxy=0.125,rank_gaussian_realized_vol20=0.125
     WHERE trade_date=d AND feature_version='phase2-v3';

    rejected:=false;
    BEGIN
        UPDATE feat.features_daily SET feature_set_hash=repeat('0',64)
         WHERE trade_date=d AND symbol_id=sid AND feature_version='phase2-v2';
        PERFORM ops.repair_phase2_rank_chunk('rank-unknown',d,d);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair found an unknown source semantic hash%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'rank repair accepted an unknown source version'; END IF;
    rejected:=false;
    BEGIN
        DELETE FROM feat.features_daily WHERE trade_date=d AND symbol_id=sid AND feature_version='phase2-v3';
        PERFORM ops.repair_phase2_rank_chunk('rank-keys',d,d);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair requires matching non-empty V2/V3 panels%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'rank repair accepted missing V3 keys'; END IF;
    rejected:=false;
    BEGIN
        UPDATE feat.features_daily SET return_20s=coalesce(return_20s,0)+0.1
         WHERE trade_date=d AND symbol_id=sid AND feature_version='phase2-v3';
        PERFORM ops.repair_phase2_rank_chunk('rank-inputs',d,d);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair found different V2/V3 keys or rank inputs%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'rank repair accepted differing rank inputs'; END IF;
    rejected:=false;
    BEGIN
        UPDATE feat.features_daily SET return_20s='NaN'::double precision
         WHERE trade_date=d AND symbol_id=sid AND feature_version IN ('phase2-v2','phase2-v3');
        PERFORM ops.repair_phase2_rank_chunk('rank-nan',d,d);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair found a nonfinite input%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'rank repair accepted nonfinite inputs'; END IF;

    -- An interruption rolls back both feature writes and completion records.
    before_rejection:=ops.phase2_rank_panel_hash(d,d,false);
    BEGIN
        PERFORM ops.repair_phase2_rank_chunk('rank-interrupted',d,d);
        RAISE EXCEPTION 'synthetic interruption after rank writes';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM<>'synthetic interruption after rank writes' THEN RAISE; END IF;
    END;
    IF before_rejection IS DISTINCT FROM ops.phase2_rank_panel_hash(d,d,false)
       OR EXISTS(SELECT 1 FROM ops.phase2_rank_repairs WHERE build_id='rank-interrupted')
       OR EXISTS(SELECT 1 FROM ops.step_runs WHERE build_id='rank-interrupted') THEN
        RAISE EXCEPTION 'interrupted rank repair committed partial output or audit rows';
    END IF;
    rejected:=false;
    BEGIN
        EXECUTE $bad_hash$CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash()
            RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
            $value$ SELECT repeat('0',64) $value$$bad_hash$;
        PERFORM ops.repair_phase2_rank_chunk('rank-future-version',d,d);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair is restricted to the audited 052-to-053 semantic upgrade%' THEN
            rejected:=true;
        ELSE RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'rank repair accepted an unaudited target definition'; END IF;

    SELECT * INTO actual FROM ops.repair_phase2_rank_chunk('rank-repair-fixture',d,d);
    IF actual.v2_rows<>n OR actual.v3_rows<>n OR actual.changed_rows<>2*n OR actual.skipped
       OR actual.output_sha256 IS DISTINCT FROM wanted
       OR ops.phase2_rank_panel_hash(d,d,true) IS DISTINCT FROM preserved THEN
        RAISE EXCEPTION 'rank repair differs from the fresh production panel or changed other fields';
    END IF;
    first_hash:=actual.output_sha256;
    SELECT * INTO actual FROM ops.repair_phase2_rank_chunk('rank-repair-fixture',d,d,true);
    IF actual.output_sha256 IS DISTINCT FROM first_hash OR actual.changed_rows<>0 OR actual.skipped THEN
        RAISE EXCEPTION 'forced rank recomputation is not byte-reproducible';
    END IF;
    SELECT * INTO actual FROM ops.repair_phase2_rank_chunk('rank-repair-fixture',d,d);
    IF NOT actual.skipped OR actual.changed_rows<>0 OR actual.output_sha256 IS DISTINCT FROM first_hash
       OR (SELECT count(*) FROM ops.phase2_rank_repair_attempts WHERE build_id='rank-repair-fixture')<>2
       OR (SELECT count(*) FROM ops.step_runs WHERE build_id='rank-repair-fixture' AND status='done')<>2 THEN
        RAISE EXCEPTION 'rank repair resume lost its attempts, timing or output hash';
    END IF;
    before_rejection:=ops.phase2_rank_panel_hash(d,d,false);
    rejected:=false;
    BEGIN
        UPDATE feat.features_daily SET volume=volume+1
         WHERE trade_date=d AND symbol_id=sid AND feature_version='phase2-v2';
        PERFORM ops.repair_phase2_rank_chunk('rank-repair-fixture',d,d,true);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'completed rank repair output changed%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected OR before_rejection IS DISTINCT FROM ops.phase2_rank_panel_hash(d,d,false) THEN
        RAISE EXCEPTION 'completed-output drift was not rejected and rolled back';
    END IF;
    rejected:=false;
    BEGIN
        PERFORM ops.repair_phase2_rank_chunk('rank-repair-fixture',d,d+1);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'overlapping rank repair chunks%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'overlapping rank repair chunks were accepted'; END IF;
    rejected:=false;
    BEGIN
        PERFORM ops.repair_phase2_rank_chunk('rank-too-wide',d,d+31);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'rank repair requires a build ID%' THEN rejected:=true; ELSE RAISE; END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'unbounded rank repair range was accepted'; END IF;
    PERFORM ops.fail_phase2_rank_chunk('rank-failure-fixture',d,d,'synthetic rollback failure',23);
    IF (SELECT status FROM ops.phase2_rank_repairs WHERE build_id='rank-failure-fixture')<>'failed'
       OR NOT EXISTS (SELECT 1 FROM ops.step_runs WHERE build_id='rank-failure-fixture'
                       AND status='failed' AND duration_ms=23) THEN
        RAISE EXCEPTION 'rank repair failure did not retain a durable attempt record';
    END IF;
END;
$rank_repair$;
ROLLBACK;

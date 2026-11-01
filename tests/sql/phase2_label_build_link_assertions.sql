\set ON_ERROR_STOP on

-- A fresh psql session must be able to record an unassociated legacy-style
-- target build as NULL when the transaction-local runner GUC is absent.
BEGIN;
DO $missing_label_build_association$
DECLARE
    v_date date;
    v_started_at timestamptz;
    v_runs integer;
BEGIN
    IF NULLIF(current_setting('vnpipe.phase2_label_build_id',true),'') IS NOT NULL THEN
        RAISE EXCEPTION 'test requires an initially absent label-build GUC';
    END IF;
    SELECT min(f.trade_date) INTO v_date
      FROM feat.features_daily f
      JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.feature_version='phase2-v3'
       AND f.feature_set_hash=feat.phase2_feature_set_hash_v3();
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'label build-link assertion requires a current-hash P2READY feature';
    END IF;
    v_started_at:=clock_timestamp();
    PERFORM feat.build_phase2_label_targets_v3(v_date,v_date);
    SELECT count(*)::integer INTO v_runs
      FROM ops.phase2_label_target_chunk_runs
     WHERE date_from=v_date AND date_to=v_date AND status='done'
       AND started_at>=v_started_at AND label_build_id IS NULL
       AND build_id='phase2-label-targets-v1';
    IF v_runs<>1 THEN
        RAISE EXCEPTION 'absent GUC must persist exactly one completed target attempt with a NULL actual build association; found %',v_runs;
    END IF;
END;
$missing_label_build_association$;
ROLLBACK;

-- A transaction-local runner value must be stamped on the attempt without
-- changing the legacy builder-version column. Roll back the fixture writes.
BEGIN;
DO $stamped_label_build_association$
DECLARE
    v_date date;
    v_build_id constant text:='phase2-link-assertion';
    v_started_at timestamptz;
    v_runs integer;
BEGIN
    SELECT min(f.trade_date) INTO v_date
      FROM feat.features_daily f
      JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.feature_version='phase2-v3'
       AND f.feature_set_hash=feat.phase2_feature_set_hash_v3();
    IF v_date IS NULL THEN
        RAISE EXCEPTION 'label build-link assertion requires a current-hash P2READY feature';
    END IF;
    PERFORM set_config('vnpipe.phase2_label_build_id',v_build_id,true);
    IF current_setting('vnpipe.phase2_label_build_id',true) IS DISTINCT FROM v_build_id THEN
        RAISE EXCEPTION 'transaction-local label-build GUC was not retained';
    END IF;
    v_started_at:=clock_timestamp();
    PERFORM feat.build_phase2_label_targets_v3(v_date,v_date);
    SELECT count(*)::integer INTO v_runs
      FROM ops.phase2_label_target_chunk_runs
     WHERE date_from=v_date AND date_to=v_date AND status='done'
       AND started_at>=v_started_at AND label_build_id=v_build_id
       AND build_id='phase2-label-targets-v1';
    IF v_runs<>1 THEN
        RAISE EXCEPTION 'transaction-local build ID must be stamped exactly once while the legacy builder-version remains unchanged; found %',v_runs;
    END IF;
END;
$stamped_label_build_association$;
ROLLBACK;

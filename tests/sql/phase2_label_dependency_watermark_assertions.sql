\set ON_ERROR_STOP on
BEGIN;
DO $phase2_label_dependency_watermark_assertions$
DECLARE
    v_ctid tid;
    v_before text;
    v_after text;
    v_hash_before text;
    v_hash_after text;
    v_trigger_count integer;
    v_label_ctid tid;
BEGIN
    SELECT count(*) INTO v_trigger_count
      FROM pg_trigger t
     WHERE NOT t.tgisinternal
       AND t.tgname IN (
           'phase2_label_dependency_features_daily',
           'phase2_label_dependency_price_limits',
           'phase2_label_dependency_raw_landings'
       )
       AND t.tgrelid IN (
           'feat.features_daily'::regclass,
           'core.daily_price_limit_observations'::regclass,
           'raw.landings'::regclass
       );
    IF v_trigger_count<>3 THEN
        RAISE EXCEPTION 'expected three source-dependency triggers, found %',v_trigger_count;
    END IF;

    SELECT ctid INTO v_ctid FROM feat.features_daily ORDER BY symbol_id,trade_date LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'feature fixture row required to verify label watermark invalidation';
    END IF;

    v_before:=ops.phase2_label_dependency_watermark();
    v_hash_before:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');
    UPDATE feat.features_daily
       SET turnover_proxy_vnd=turnover_proxy_vnd
     WHERE ctid=v_ctid;
    v_after:=ops.phase2_label_dependency_watermark();
    v_hash_after:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');

    IF v_before=v_after THEN
        RAISE EXCEPTION 'feature-row mutation did not advance the label dependency watermark';
    END IF;
    IF v_hash_before=v_hash_after THEN
        RAISE EXCEPTION 'feature-row mutation did not invalidate the label input hash';
    END IF;

    SELECT ctid INTO v_label_ctid
      FROM feat.labels_daily
     ORDER BY symbol_id,signal_date,horizon_sessions,label_version
     LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'label fixture row required to verify output/source hash separation';
    END IF;
    v_before:=ops.phase2_label_dependency_watermark();
    v_hash_before:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');
    UPDATE feat.labels_daily
       SET label_status=label_status
     WHERE ctid=v_label_ctid;
    v_after:=ops.phase2_label_dependency_watermark();
    v_hash_after:=ops.phase2_label_target_chunk_input_hash(DATE '2099-01-01',DATE '2099-01-02');
    IF v_before<>v_after OR v_hash_before<>v_hash_after THEN
        RAISE EXCEPTION 'raw-label output mutation invalidated source-input hash cache';
    END IF;
END;
$phase2_label_dependency_watermark_assertions$;
ROLLBACK;

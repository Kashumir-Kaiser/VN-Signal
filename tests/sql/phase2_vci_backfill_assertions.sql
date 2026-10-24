-- Synthetic-only assertions for the resumable one-session-lag VCI repair.
-- All writes, including the deliberate stale-value injection, are rolled back.
BEGIN;

DO $phase2_vci_backfill_assertions$
DECLARE
    v_build_id constant text := 'phase2-vci-backfill-fixture';
    v_target_symbol bigint;
    v_target_date date;
    v_chunk_from date;
    v_chunk_to date;
    v_context_rows bigint;
    v_context_hash text;
    v_target_from date;
    v_target_to date;
    v_expected_chunks integer;
    v_result record;
    v_actual record;
    v_expected record;
    v_first_hash text;
    v_repeat_hash text;
    v_attempts_before integer;
    v_attempts_after integer;
    v_status text;
    v_done_chunks bigint;
BEGIN
    SELECT min(trade_date),max(trade_date)
      INTO v_target_from,v_target_to
      FROM feat.features_daily WHERE feature_version='phase2-v3';
    IF v_target_from IS NULL THEN
        RAISE EXCEPTION 'V3 fixture rows are required before the VCI backfill assertion';
    END IF;
    SELECT symbol_id,trade_date INTO v_target_symbol,v_target_date
      FROM feat.features_daily
     WHERE feature_version='phase2-v3'
     ORDER BY trade_date DESC,symbol_id
     LIMIT 1;

    UPDATE feat.features_daily
       SET vnindex_return_20s=999,vnindex_return_60s=999,
           vnindex_realized_vol20=999,feature_set_hash=repeat('0',64)
     WHERE symbol_id=v_target_symbol AND trade_date=v_target_date
       AND feature_version='phase2-v3';

    SELECT p.context_rows,p.context_sha256,p.target_from,p.target_to,p.expected_chunks
      INTO v_context_rows,v_context_hash,v_target_from,v_target_to,v_expected_chunks
      FROM ops.prepare_phase2_vci_backfill(v_build_id,30) p;
    IF v_context_rows<=0 OR v_context_hash !~ '^[0-9a-f]{64}$'
       OR v_expected_chunks<=0 THEN
        RAISE EXCEPTION 'VCI backfill context or planned chunk manifest is invalid';
    END IF;

    SELECT date_from,date_to INTO v_chunk_from,v_chunk_to
      FROM ops.phase2_vci_backfill_chunks
     WHERE build_id=v_build_id AND v_target_date BETWEEN date_from AND date_to;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'target date has no planned VCI repair chunk';
    END IF;
    PERFORM ops.fail_phase2_vci_chunk(v_build_id,v_chunk_from,v_chunk_to,
                                      'synthetic interruption for resume assertion');

    FOR v_result IN
        SELECT date_from,date_to
          FROM ops.phase2_vci_backfill_chunks
         WHERE build_id=v_build_id AND status<>'done'
         ORDER BY date_from
    LOOP
        SELECT b.output_sha256 INTO v_first_hash
          FROM ops.backfill_phase2_vci_chunk(v_build_id,v_result.date_from,v_result.date_to) b;
        IF v_result.date_from=v_chunk_from AND v_result.date_to=v_chunk_to THEN
            v_repeat_hash:=v_first_hash;
        END IF;
    END LOOP;

    SELECT attempts INTO v_attempts_before
      FROM ops.phase2_vci_backfill_chunks
     WHERE build_id=v_build_id AND date_from=v_chunk_from AND date_to=v_chunk_to;
    SELECT b.output_sha256 INTO v_first_hash
      FROM ops.backfill_phase2_vci_chunk(v_build_id,v_chunk_from,v_chunk_to) b;
    SELECT attempts INTO v_attempts_after
      FROM ops.phase2_vci_backfill_chunks
     WHERE build_id=v_build_id AND date_from=v_chunk_from AND date_to=v_chunk_to;
    IF v_first_hash IS DISTINCT FROM v_repeat_hash OR v_attempts_before<>v_attempts_after THEN
        RAISE EXCEPTION 'completed VCI chunk did not safely skip on repeat';
    END IF;

    SELECT f.vnindex_return_20s,f.vnindex_return_60s,
           f.vnindex_realized_vol20,f.feature_set_hash
      INTO v_actual
      FROM feat.features_daily f
     WHERE f.symbol_id=v_target_symbol AND f.trade_date=v_target_date
       AND f.feature_version='phase2-v3';
    SELECT c.vnindex_return_20s,c.vnindex_return_60s,c.vnindex_realized_vol20,
           feat.phase2_feature_set_hash_v3() AS feature_set_hash
      INTO v_expected
      FROM ops.phase2_vci_backfill_context c
     WHERE c.build_id=v_build_id AND c.trade_date=v_target_date;
    IF ROW(v_actual.vnindex_return_20s,v_actual.vnindex_return_60s,
           v_actual.vnindex_realized_vol20,v_actual.feature_set_hash)
       IS DISTINCT FROM
       ROW(v_expected.vnindex_return_20s,v_expected.vnindex_return_60s,
           v_expected.vnindex_realized_vol20,v_expected.feature_set_hash) THEN
        RAISE EXCEPTION 'VCI backfill did not restore the frozen lagged context and feature hash';
    END IF;

    SELECT r.status INTO v_status FROM ops.phase2_vci_backfill_runs r
     WHERE r.build_id=v_build_id;
    SELECT count(*) INTO v_done_chunks FROM ops.phase2_vci_backfill_chunks c
     WHERE c.build_id=v_build_id AND c.status='done';
    IF v_status<>'complete' OR v_done_chunks<>v_expected_chunks THEN
        RAISE EXCEPTION 'VCI backfill did not complete every planned chunk';
    END IF;
END;
$phase2_vci_backfill_assertions$;

ROLLBACK;

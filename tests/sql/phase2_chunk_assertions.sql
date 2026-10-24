\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
    v_symbol_id bigint;
    v_date date;
    v_rows bigint;
    v_input_a text;
    v_input_b text;
    v_output_a text;
    v_output_b text;
    v_output_c text;
    v_label_input text;
    v_label_input_again text;
    v_label_output text;
    v_hash_coverage_rows bigint;
    v_hash_coverage_rows_again bigint;
    v_fundamentals_input text;
    v_fundamentals_output text;
BEGIN
    SELECT symbol_id INTO v_symbol_id FROM core.symbols WHERE symbol='P2READY';
    SELECT min(trade_date) INTO v_date FROM feat.features_daily
     WHERE symbol_id=v_symbol_id AND feature_version='phase2-v2';
    IF v_symbol_id IS NULL OR v_date IS NULL THEN
        RAISE EXCEPTION 'Phase 2 chunk hash assertions require the built P2READY fixture';
    END IF;

    v_input_a:=ops.phase2_chunk_input_hash('features',v_date,v_date);
    v_input_b:=ops.phase2_chunk_input_hash('features',v_date,v_date);
    IF v_input_a IS DISTINCT FROM v_input_b OR v_input_a !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'identical Phase 2 feature inputs did not produce a stable SHA-256';
    END IF;

    v_output_a:=ops.phase2_chunk_output_hash('features',v_date,v_date);
    v_output_b:=ops.phase2_chunk_output_hash('features',v_date,v_date);
    IF v_output_a IS DISTINCT FROM v_output_b OR v_output_a !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'identical Phase 2 feature outputs did not produce a stable SHA-256';
    END IF;

    UPDATE feat.features_daily SET built_at=built_at+interval '1 second'
     WHERE symbol_id=v_symbol_id AND trade_date=v_date AND feature_version='phase2-v3';
    IF ops.phase2_chunk_output_hash('features',v_date,v_date) IS DISTINCT FROM v_output_a THEN
        RAISE EXCEPTION 'feature output hash included the volatile built_at timestamp';
    END IF;

    UPDATE feat.features_daily SET return_1d=coalesce(return_1d,0)+0.125
     WHERE symbol_id=v_symbol_id AND trade_date=v_date AND feature_version='phase2-v3';
    v_output_c:=ops.phase2_chunk_output_hash('features',v_date,v_date);
    IF v_output_c IS NOT DISTINCT FROM v_output_a THEN
        RAISE EXCEPTION 'changing a Phase 2 output value did not change its output hash';
    END IF;

    UPDATE feat.features_daily SET return_1d=coalesce(return_1d,0)+0.125
     WHERE symbol_id=v_symbol_id AND trade_date=v_date AND feature_version='phase2-v2';
    IF ops.phase2_chunk_input_hash('features',v_date,v_date) IS NOT DISTINCT FROM v_input_a THEN
        RAISE EXCEPTION 'changing a Phase 2 v2 source feature did not change the v3 input hash';
    END IF;

    v_label_input:=ops.phase2_chunk_input_hash('labels',v_date,v_date);
    SELECT count(*) INTO v_hash_coverage_rows
      FROM pg_temp.phase2_price_day_hash_coverage;
    v_label_input_again:=ops.phase2_chunk_input_hash('labels',v_date,v_date);
    SELECT count(*) INTO v_hash_coverage_rows_again
      FROM pg_temp.phase2_price_day_hash_coverage;
    v_label_output:=ops.phase2_chunk_output_hash('labels',v_date,v_date);
    v_fundamentals_input:=ops.phase2_chunk_input_hash('fundamentals',v_date,v_date);
    v_fundamentals_output:=ops.phase2_chunk_output_hash('fundamentals',v_date,v_date);
    IF v_label_input !~ '^[0-9a-f]{64}$' OR v_label_output !~ '^[0-9a-f]{64}$' OR
       v_fundamentals_input !~ '^[0-9a-f]{64}$' OR v_fundamentals_output !~ '^[0-9a-f]{64}$' THEN
        RAISE EXCEPTION 'Phase 2 label/fundamental hash helpers did not return SHA-256 values';
    END IF;
    IF v_label_input IS DISTINCT FROM v_label_input_again OR
       v_hash_coverage_rows < 1 OR
       v_hash_coverage_rows IS DISTINCT FROM v_hash_coverage_rows_again THEN
        RAISE EXCEPTION 'repeated label input hashing was unstable or recomputed covered price dates';
    END IF;

    SELECT count(*) INTO v_rows FROM feat.features_daily
     WHERE trade_date=v_date AND feature_version='phase2-v3';
    INSERT INTO ops.feature_chunks(build_id,stage,chunk_key,date_from,date_to,status,rows,
                                   started_at,finished_at,input_sha256,output_sha256)
    VALUES('phase2-hash-fixture','features',to_char(v_date,'YYYYMMDD'),v_date,v_date,'done',v_rows,
           clock_timestamp(),clock_timestamp(),v_input_a,v_output_a);
    INSERT INTO ops.step_runs(build_id,stage,chunk_key,status,rows,finished_at,input_sha256,output_sha256)
    VALUES('phase2-hash-fixture','features',to_char(v_date,'YYYYMMDD'),'done',v_rows,
           clock_timestamp(),v_input_a,v_output_a);

    IF NOT EXISTS (
        SELECT 1 FROM ops.feature_chunks c JOIN ops.step_runs r USING(build_id,stage,chunk_key)
         WHERE c.build_id='phase2-hash-fixture' AND c.stage='features'
           AND c.input_sha256=v_input_a AND c.output_sha256=v_output_a
           AND r.input_sha256=v_input_a AND r.output_sha256=v_output_a
           AND c.rows=v_rows AND r.rows=v_rows
    ) THEN
        RAISE EXCEPTION 'Phase 2 chunk/attempt records did not persist their deterministic hashes';
    END IF;
END $$;
ROLLBACK;

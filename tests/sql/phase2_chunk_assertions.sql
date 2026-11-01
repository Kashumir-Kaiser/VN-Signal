\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE phase2_v2_hash_cache_probe ON COMMIT DROP AS
SELECT * FROM feat.features_daily
 WHERE symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='P2READY')
   AND feature_version='phase2-v2'
 ORDER BY trade_date
 LIMIT 1;
DO $$
DECLARE
    v_symbol_id bigint;
    v_date date;
    v_probe_date date:=DATE '1901-01-02';
    v_probe_date_next date:=DATE '1901-01-03';
    v_rows bigint;
    v_probe_rows bigint;
    v_probe_hash text;
    v_reference_hash text;
    v_input_after_v2 text;
    v_input_after_probe text;
    v_input_after_schema text;
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

    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_date AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_date AND f.feature_version='phase2-v2';
    IF v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'cached V2 daily digest differs from the canonical row-by-row digest';
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
    v_input_after_v2:=ops.phase2_chunk_input_hash('features',v_date,v_date);
    IF v_input_after_v2 IS NOT DISTINCT FROM v_input_a THEN
        RAISE EXCEPTION 'changing a Phase 2 v2 source feature did not change the v3 input hash';
    END IF;
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_date AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_date AND f.feature_version='phase2-v2';
    IF v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'V2 UPDATE did not refresh the exact cached daily digest';
    END IF;

    IF v_probe_date>=date_trunc('year',v_date)::date THEN
        RAISE EXCEPTION 'synthetic V2 cache-probe date must precede the feature year anchor';
    END IF;
    IF EXISTS (SELECT 1 FROM feat.features_daily
                WHERE trade_date IN (v_probe_date,v_probe_date_next)) THEN
        RAISE EXCEPTION 'synthetic V2 cache-probe dates unexpectedly collide with fixture data';
    END IF;

    -- New V2 dates are added to the catalog by the INSERT statement trigger.
    UPDATE pg_temp.phase2_v2_hash_cache_probe SET trade_date=v_probe_date;
    INSERT INTO feat.features_daily SELECT * FROM pg_temp.phase2_v2_hash_cache_probe;
    PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_probe_date,v_probe_date);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_probe_date AND f.feature_version='phase2-v2';
    IF v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'V2 INSERT did not create an exact cached daily digest';
    END IF;
    v_input_after_probe:=ops.phase2_chunk_input_hash('features',v_date,v_date);
    IF v_input_after_probe IS DISTINCT FROM v_input_after_v2 THEN
        RAISE EXCEPTION 'an out-of-range V2 INSERT changed the year-anchored input hash';
    END IF;

    -- Moving a V2 row invalidates both its old and new trade dates.
    UPDATE feat.features_daily SET trade_date=v_probe_date_next
     WHERE symbol_id=v_symbol_id AND trade_date=v_probe_date AND feature_version='phase2-v2';
    PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_probe_date,v_probe_date_next);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date AND NOT is_dirty;
    IF v_probe_rows IS DISTINCT FROM 0 OR v_probe_hash IS NOT NULL THEN
        RAISE EXCEPTION 'V2 date move did not clear the old date digest';
    END IF;
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date_next AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_probe_date_next AND f.feature_version='phase2-v2';
    IF v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'V2 date move did not refresh the new date digest exactly';
    END IF;

    -- Changing out of V2 and back must invalidate the same date both times.
    UPDATE feat.features_daily SET feature_version='phase2-cache-probe-v1'
     WHERE symbol_id=v_symbol_id AND trade_date=v_probe_date_next AND feature_version='phase2-v2';
    PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_probe_date_next,v_probe_date_next);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date_next AND NOT is_dirty;
    IF v_probe_rows IS DISTINCT FROM 0 OR v_probe_hash IS NOT NULL THEN
        RAISE EXCEPTION 'V2 version transition did not clear the V2 date digest';
    END IF;
    UPDATE feat.features_daily SET feature_version='phase2-v2'
     WHERE symbol_id=v_symbol_id AND trade_date=v_probe_date_next AND feature_version='phase2-cache-probe-v1';
    PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_probe_date_next,v_probe_date_next);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date_next AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_probe_date_next AND f.feature_version='phase2-v2';
    IF v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'V2 version transition back did not restore the exact daily digest';
    END IF;

    -- Deleting the last V2 row for a date must leave a clean empty cache entry.
    DELETE FROM feat.features_daily
     WHERE symbol_id=v_symbol_id AND trade_date=v_probe_date_next AND feature_version='phase2-v2';
    PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_probe_date_next,v_probe_date_next);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_probe_date_next AND NOT is_dirty;
    IF v_probe_rows IS DISTINCT FROM 0 OR v_probe_hash IS NOT NULL THEN
        RAISE EXCEPTION 'deleting the last V2 row did not clear its daily digest';
    END IF;

    -- A row-shape change alters to_jsonb(f), so the schema signature must
    -- invalidate cached day digests before they are reused.
    EXECUTE 'ALTER TABLE feat.features_daily ADD COLUMN phase2_hash_cache_probe boolean NOT NULL DEFAULT false';
    v_input_after_schema:=ops.phase2_chunk_input_hash('features',v_date,v_date);
    SELECT row_count,day_sha256 INTO v_probe_rows,v_probe_hash
      FROM ops.phase2_v2_feature_day_hash_cache
     WHERE trade_date=v_date AND NOT is_dirty;
    SELECT count(*),ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                    ORDER BY f.symbol_id,f.trade_date))
      INTO v_rows,v_reference_hash
      FROM feat.features_daily f
     WHERE f.trade_date=v_date AND f.feature_version='phase2-v2';
    IF v_input_after_schema IS NOT DISTINCT FROM v_input_after_v2 OR
       v_probe_rows IS DISTINCT FROM v_rows OR v_probe_hash IS DISTINCT FROM v_reference_hash THEN
        RAISE EXCEPTION 'V2 daily digest cache was not invalidated after a feature row-shape change';
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

-- Record deterministic input/output fingerprints for every resumable Phase 2
-- chunk. Hash inputs include the exact stage dependencies plus version/config
-- domains; output hashes exclude only volatile build timestamps.
BEGIN;

ALTER TABLE ops.feature_chunks
    ADD COLUMN IF NOT EXISTS input_sha256 text,
    ADD COLUMN IF NOT EXISTS output_sha256 text;
ALTER TABLE ops.step_runs
    ADD COLUMN IF NOT EXISTS input_sha256 text,
    ADD COLUMN IF NOT EXISTS output_sha256 text;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='ops.feature_chunks'::regclass
                   AND conname='feature_chunks_input_sha256_check') THEN
        ALTER TABLE ops.feature_chunks ADD CONSTRAINT feature_chunks_input_sha256_check
            CHECK (input_sha256 IS NULL OR input_sha256 ~ '^[0-9a-f]{64}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='ops.feature_chunks'::regclass
                   AND conname='feature_chunks_output_sha256_check') THEN
        ALTER TABLE ops.feature_chunks ADD CONSTRAINT feature_chunks_output_sha256_check
            CHECK (output_sha256 IS NULL OR output_sha256 ~ '^[0-9a-f]{64}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='ops.step_runs'::regclass
                   AND conname='step_runs_input_sha256_check') THEN
        ALTER TABLE ops.step_runs ADD CONSTRAINT step_runs_input_sha256_check
            CHECK (input_sha256 IS NULL OR input_sha256 ~ '^[0-9a-f]{64}$');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='ops.step_runs'::regclass
                   AND conname='step_runs_output_sha256_check') THEN
        ALTER TABLE ops.step_runs ADD CONSTRAINT step_runs_output_sha256_check
            CHECK (output_sha256 IS NULL OR output_sha256 ~ '^[0-9a-f]{64}$');
    END IF;
END $$;

CREATE OR REPLACE FUNCTION ops.phase2_hash_text(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT encode(sha256(convert_to(coalesce(p_text,''),'UTF8')),'hex')
$$;

CREATE OR REPLACE FUNCTION ops.phase2_hash_jsonb(p_row jsonb)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT ops.phase2_hash_text(coalesce(p_row,'null'::jsonb)::text)
$$;

DROP FUNCTION IF EXISTS ops.phase2_prepare_price_day_hashes();
CREATE OR REPLACE FUNCTION ops.phase2_prepare_price_day_hashes(p_date_from date,p_date_to date)
RETURNS void LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    hash_relation oid;
    coverage_relation oid;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive price-hash date range required';
    END IF;

    hash_relation:=to_regclass('pg_temp.phase2_price_day_hashes');
    coverage_relation:=to_regclass('pg_temp.phase2_price_day_hash_coverage');
    IF hash_relation IS NOT NULL AND
       obj_description(hash_relation,'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 deterministic price-day hashes' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hashes is reserved by the Phase 2 builder';
    END IF;
    IF coverage_relation IS NOT NULL AND
       obj_description(coverage_relation,'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 deterministic price-hash date coverage' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hash_coverage is reserved by the Phase 2 builder';
    END IF;

    PERFORM feat.prepare_phase2_adjustment_rows(false);
    IF hash_relation IS NULL THEN
        CREATE TEMP TABLE phase2_price_day_hashes(
            trade_date date PRIMARY KEY,
            day_sha256 text NOT NULL CHECK(day_sha256 ~ '^[0-9a-f]{64}$')
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_price_day_hashes IS
            'VN-Signal Phase 2 deterministic price-day hashes';
    END IF;
    IF coverage_relation IS NULL THEN
        CREATE TEMP TABLE phase2_price_day_hash_coverage(
            trade_date date PRIMARY KEY
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_price_day_hash_coverage IS
            'VN-Signal Phase 2 deterministic price-hash date coverage';
    END IF;

    WITH requested_dates AS MATERIALIZED (
        SELECT s.trade_date
        FROM core.effective_trading_sessions s
        WHERE s.is_session AND s.trade_date BETWEEN p_date_from AND p_date_to
        UNION
        SELECT DISTINCT r.trade_date
        FROM pg_temp.phase2_adjustment_rows r
        WHERE r.trade_date BETWEEN p_date_from AND p_date_to
    ), new_dates AS MATERIALIZED (
        SELECT d.trade_date
        FROM requested_dates d
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_temp.phase2_price_day_hash_coverage c
            WHERE c.trade_date=d.trade_date
        )
    )
    INSERT INTO pg_temp.phase2_price_day_hashes(trade_date,day_sha256)
    SELECT r.trade_date,
           ops.phase2_hash_text(string_agg(to_jsonb(r)::text,E'\n' ORDER BY r.symbol_id))
    FROM pg_temp.phase2_adjustment_rows r
    JOIN new_dates d USING(trade_date)
    GROUP BY r.trade_date
    ON CONFLICT(trade_date) DO NOTHING;

    WITH requested_dates AS MATERIALIZED (
        SELECT s.trade_date
        FROM core.effective_trading_sessions s
        WHERE s.is_session AND s.trade_date BETWEEN p_date_from AND p_date_to
        UNION
        SELECT DISTINCT r.trade_date
        FROM pg_temp.phase2_adjustment_rows r
        WHERE r.trade_date BETWEEN p_date_from AND p_date_to
    )
    INSERT INTO pg_temp.phase2_price_day_hash_coverage(trade_date)
    SELECT trade_date FROM requested_dates
    ON CONFLICT(trade_date) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION ops.phase2_chunk_input_hash(p_stage text,p_date_from date,p_date_to date)
RETURNS text LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    v_manifest text;
    v_piece text;
    v_history_from date;
    v_future_to date;
    v_symbols bigint[];
BEGIN
    IF p_stage NOT IN ('features','labels','fundamentals') OR p_date_from IS NULL OR
       p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid Phase 2 stage and inclusive date range required';
    END IF;
    v_manifest:='phase2-input-v2|stage='||p_stage||'|from='||p_date_from||'|to='||p_date_to;

    IF p_stage='features' THEN
        SELECT coalesce(min(trade_date),p_date_from) INTO v_history_from
          FROM (SELECT trade_date
                  FROM core.effective_trading_sessions
                 WHERE is_session AND trade_date<p_date_from
                 ORDER BY trade_date DESC LIMIT 1000) warmup;
        PERFORM ops.phase2_prepare_price_day_hashes(v_history_from,p_date_to);
        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece FROM pg_temp.phase2_price_day_hashes
         WHERE trade_date BETWEEN v_history_from AND p_date_to;
        v_manifest:=v_manifest||'|prices='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.trade_date),'')
          INTO v_piece FROM core.effective_trading_sessions s
         WHERE s.trade_date BETWEEN v_history_from AND p_date_to;
        v_manifest:=v_manifest||'|calendar='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(i)),''
                                   ORDER BY i.trade_date,i.index_symbol,i.source),'')
          INTO v_piece FROM core.index_bars i
         WHERE i.trade_date BETWEEN v_history_from AND p_date_to;
        v_manifest:=v_manifest||'|indexes='||v_piece;

        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece
          FROM (
              SELECT f.trade_date,
                     ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                      ORDER BY f.symbol_id,f.trade_date)) AS day_sha256
                FROM feat.features_daily f
               WHERE f.feature_version='phase2-v2'
                 AND f.trade_date BETWEEN p_date_from AND p_date_to
               GROUP BY f.trade_date
          ) v2_days;
        v_manifest:=v_manifest||'|v2='||v_piece||
                    '|feature_set='||feat.phase2_feature_set_hash_v3()||
                    '|symbol_batch_size='||coalesce(current_setting('vnpipe.phase2_symbol_batch_size',true),'50');

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.symbol_id),'')
          INTO v_piece FROM ops.ml_symbol_scope s;
        v_manifest:=v_manifest||'|scope='||v_piece;

    ELSIF p_stage='labels' THEN
        SELECT max(trade_date) INTO v_future_to
          FROM (SELECT trade_date FROM core.effective_trading_sessions
                 WHERE is_session AND trade_date>p_date_to
                 ORDER BY trade_date LIMIT 21) future_sessions;
        v_future_to:=coalesce(v_future_to,p_date_to);
        PERFORM ops.phase2_prepare_price_day_hashes(p_date_from,v_future_to);

        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece FROM pg_temp.phase2_price_day_hashes
         WHERE trade_date BETWEEN p_date_from AND v_future_to;
        v_manifest:=v_manifest||'|prices='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.trade_date),'')
          INTO v_piece FROM core.effective_trading_sessions s
         WHERE s.trade_date BETWEEN p_date_from AND v_future_to;
        v_manifest:=v_manifest||'|calendar='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(i)),''
                                   ORDER BY i.trade_date,i.index_symbol,i.source),'')
          INTO v_piece FROM core.index_bars i
         WHERE i.trade_date BETWEEN p_date_from AND v_future_to;
        v_manifest:=v_manifest||'|indexes='||v_piece;

        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece
          FROM (
              SELECT f.trade_date,
                     ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                      ORDER BY f.symbol_id,f.trade_date)) AS day_sha256
                FROM feat.features_daily f
               WHERE f.feature_version='phase2-v3'
                 AND f.trade_date BETWEEN p_date_from AND p_date_to
               GROUP BY f.trade_date
          ) v3_days;
        v_manifest:=v_manifest||'|features_v3='||v_piece||
                    '|feature_set='||feat.phase2_feature_set_hash_v3()||
                    '|label_version=close-next-open-v1|horizons=5,20';

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.symbol_id),'')
          INTO v_piece FROM ops.ml_symbol_scope s;
        v_manifest:=v_manifest||'|scope='||v_piece;

    ELSE
        SELECT coalesce(array_agg(symbol_id ORDER BY symbol_id),'{}'::bigint[])
          INTO v_symbols
          FROM (SELECT DISTINCT symbol_id FROM feat.features_daily
                 WHERE feature_version='phase2-v2'
                   AND trade_date BETWEEN p_date_from AND p_date_to) symbols;

        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece
          FROM (
              SELECT f.trade_date,
                     ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                      ORDER BY f.symbol_id,f.trade_date)) AS day_sha256
                FROM feat.features_daily f
               WHERE f.feature_version='phase2-v2'
                 AND f.trade_date BETWEEN p_date_from AND p_date_to
               GROUP BY f.trade_date
          ) v2_days;
        v_manifest:=v_manifest||'|v2='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(p)),''
                                   ORDER BY p.symbol_id,p.trade_date,p.source,p.landing_id,p.source_row),'')
          INTO v_piece
          FROM core.vndirect_reference_adjustment_details p
          JOIN unnest(v_symbols) AS syms(symbol_id) ON syms.symbol_id=p.symbol_id
         WHERE p.source='vndirect' AND p.trade_date BETWEEN p_date_from AND p_date_to;
        v_manifest:=v_manifest||'|prices='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(p)),''
                                   ORDER BY p.symbol_id,p.statement_type,p.period_type,p.period_end,p.row_id,
                                            p.available_at,p.first_seen_at,p.snapshot_id),'')
          INTO v_piece FROM core.fundamentals_pit p
         WHERE p.archive_managed AND p.source='vci' AND p.period_end<=p_date_to
           AND p.symbol_id=ANY(v_symbols);
        v_manifest:=v_manifest||'|fundamentals_pit='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(o)),''
                                   ORDER BY o.symbol_id,o.trade_date,o.available_at,o.observation_id),'')
          INTO v_piece FROM core.listed_share_observations o
         WHERE o.trade_date<=p_date_to AND o.symbol_id=ANY(v_symbols);
        v_manifest:=v_manifest||'|shares='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(l)),''
                                   ORDER BY l.symbol_id,l.snapshot_date),'')
          INTO v_piece FROM core.listing_snapshots l
         WHERE l.snapshot_date<=p_date_to AND l.symbol_id=ANY(v_symbols);
        v_manifest:=v_manifest||'|listings='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(m)),''
                                   ORDER BY m.source,m.statement_type,m.row_id,m.mapping_scope,m.mapping_version),'')
          INTO v_piece FROM feat.fundamental_line_item_map m;
        v_manifest:=v_manifest||'|line_item_map='||v_piece;

        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(i)),''
                                   ORDER BY i.industry,i.industry_class,i.mapping_version),'')
          INTO v_piece FROM feat.fundamental_industry_class_map i;
        v_manifest:=v_manifest||'|industry_map='||v_piece||'|fundamental_version=fundamental-overlay-v1';
    END IF;

    RETURN ops.phase2_hash_text(v_manifest);
END;
$$;

CREATE OR REPLACE FUNCTION ops.phase2_chunk_output_hash(p_stage text,p_date_from date,p_date_to date)
RETURNS text LANGUAGE plpgsql STABLE SET TimeZone TO 'UTC' AS $$
DECLARE v_rows text;
BEGIN
    IF p_stage='features' THEN
        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)-'built_at'),''
                                   ORDER BY f.symbol_id,f.trade_date,f.feature_version),'')
          INTO v_rows FROM feat.features_daily f
         WHERE f.feature_version='phase2-v3' AND f.trade_date BETWEEN p_date_from AND p_date_to;
    ELSIF p_stage='labels' THEN
        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(l)-'computed_at'),''
                                   ORDER BY l.symbol_id,l.signal_date,l.horizon_sessions,l.label_version),'')
          INTO v_rows FROM feat.labels_daily l
         WHERE l.label_version='close-next-open-v1' AND l.signal_date BETWEEN p_date_from AND p_date_to;
    ELSIF p_stage='fundamentals' THEN
        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)-'built_at'),''
                                   ORDER BY f.symbol_id,f.trade_date,f.feature_version,f.mapping_hash),'')
          INTO v_rows FROM feat.fundamental_features_daily f
         WHERE f.feature_version='fundamental-overlay-v1' AND f.trade_date BETWEEN p_date_from AND p_date_to;
    ELSE
        RAISE EXCEPTION 'unknown Phase 2 stage: %',p_stage;
    END IF;
    RETURN ops.phase2_hash_text('phase2-output-v1|stage='||p_stage||'|from='||p_date_from||
                                '|to='||p_date_to||'|'||v_rows);
END;
$$;

COMMENT ON COLUMN ops.feature_chunks.input_sha256 IS
    'SHA-256 of the canonical stage-specific input manifest and all source rows/config that can affect this inclusive date chunk.';
COMMENT ON COLUMN ops.feature_chunks.output_sha256 IS
    'SHA-256 of canonical materialized output rows for this chunk; volatile build timestamps are excluded.';
COMMENT ON COLUMN ops.step_runs.input_sha256 IS
    'Input manifest SHA-256 captured for this individual chunk attempt.';
COMMENT ON COLUMN ops.step_runs.output_sha256 IS
    'Canonical output SHA-256 captured for this successful chunk attempt.';

COMMIT;

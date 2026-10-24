-- Keep a compact date manifest beside the session-local adjustment cache.
-- Input hashing needs the distinct dates represented by the cache, not every
-- cached bar row. Tracking dates as each symbol batch is inserted avoids a
-- wide scan and de-duplication over millions of cache rows for every chunk.
BEGIN;

CREATE OR REPLACE FUNCTION feat.populate_phase2_adjustment_rows(p_batch_no integer)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_rows bigint;
    v_date_rows bigint;
    v_symbol_ids bigint[];
    v_enable_nestloop text:=current_setting('enable_nestloop');
    v_started_at timestamptz:=clock_timestamp();
    v_date_manifest oid;
BEGIN
    IF p_batch_no IS NULL OR p_batch_no<0 THEN
        RAISE EXCEPTION 'cache batch number must be zero or greater';
    END IF;
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_rows'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local point-in-time price input cache'
       OR obj_description(to_regclass('pg_temp.phase2_adjustment_symbol_batches'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache symbol-batch manifest'
       OR obj_description(to_regclass('pg_temp.phase2_adjustment_cache_state'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache readiness state' THEN
        RAISE EXCEPTION 'initialize the reserved Phase 2 adjustment cache before populating a batch';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_temp.phase2_adjustment_symbol_batches WHERE batch_no=p_batch_no
    ) THEN
        RAISE EXCEPTION 'Phase 2 adjustment-cache batch % does not exist',p_batch_no;
    END IF;
    SELECT array_agg(symbol_id ORDER BY symbol_id)
      INTO v_symbol_ids
      FROM pg_temp.phase2_adjustment_symbol_batches
     WHERE batch_no=p_batch_no;
    IF v_symbol_ids IS NULL OR cardinality(v_symbol_ids)=0 THEN
        RAISE EXCEPTION 'Phase 2 adjustment-cache batch % has no symbols',p_batch_no;
    END IF;

    v_date_manifest:=to_regclass('pg_temp.phase2_adjustment_batch_dates');
    IF v_date_manifest IS NULL THEN
        CREATE TEMP TABLE phase2_adjustment_batch_dates(
            batch_no integer NOT NULL,
            trade_date date NOT NULL,
            PRIMARY KEY(batch_no,trade_date)
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_adjustment_batch_dates IS
            'VN-Signal Phase 2 session-local adjustment-cache batch dates';
        CREATE INDEX phase2_adjustment_batch_dates_date_idx
            ON pg_temp.phase2_adjustment_batch_dates(trade_date);
    ELSIF obj_description(v_date_manifest,'pg_class') IS DISTINCT FROM
          'VN-Signal Phase 2 session-local adjustment-cache batch dates' THEN
        RAISE EXCEPTION 'temporary relation phase2_adjustment_batch_dates is reserved by the Phase 2 builder';
    END IF;

    UPDATE pg_temp.phase2_adjustment_cache_state
       SET ready=false,finalized_at=NULL;

    -- A retry replaces only this batch, including its compact date manifest.
    DELETE FROM pg_temp.phase2_adjustment_batch_dates WHERE batch_no=p_batch_no;
    DELETE FROM pg_temp.phase2_adjustment_rows r
    USING pg_temp.phase2_adjustment_symbol_batches s
    WHERE s.batch_no=p_batch_no AND r.symbol_id=s.symbol_id;

    -- This helper's bounded CTE cardinality estimates can otherwise select a
    -- nested loop against the per-traded-sequence lookup. Keep the planner
    -- override local to this batch fill and restore the caller value.
    PERFORM set_config('enable_nestloop','off',true);
    WITH inserted_rows AS (
        INSERT INTO pg_temp.phase2_adjustment_rows(
            symbol_id,trade_date,source,v,is_traded,reference_adjustment_ratio,
            episode_start_date,model_o,model_h,model_l,model_c,
            adjustment_vintage_at,landing_id,source_row,fetched_at
        )
        SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
               r.reference_adjustment_ratio,r.episode_start_date,
               r.model_o,r.model_h,r.model_l,r.model_c,
               r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
        FROM feat.phase2_vndirect_adjustment_details_for_symbols(v_symbol_ids) r
        RETURNING trade_date
    ), recorded_dates AS (
        INSERT INTO pg_temp.phase2_adjustment_batch_dates(batch_no,trade_date)
        SELECT p_batch_no,trade_date
        FROM inserted_rows
        GROUP BY trade_date
        ON CONFLICT(batch_no,trade_date) DO NOTHING
        RETURNING trade_date
    )
    SELECT (SELECT count(*) FROM inserted_rows),
           (SELECT count(*) FROM recorded_dates)
      INTO v_rows,v_date_rows;
    PERFORM set_config('enable_nestloop',v_enable_nestloop,true);
    UPDATE pg_temp.phase2_adjustment_symbol_batches
       SET loaded=true
     WHERE batch_no=p_batch_no;
    RAISE NOTICE 'Phase 2 adjustment cache batch % rows %, dates %, elapsed %',
        p_batch_no,v_rows,v_date_rows,clock_timestamp()-v_started_at;
    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION feat.populate_phase2_adjustment_rows(integer) IS
    'Loads each in-scope VNDIRECT cache batch and records its distinct trade dates for bounded input hashing.';

CREATE OR REPLACE FUNCTION ops.phase2_prepare_price_day_hashes(
    p_date_from date,
    p_date_to date
)
RETURNS void
LANGUAGE plpgsql
SET TimeZone TO 'UTC'
AS $$
DECLARE
    hash_relation oid;
    coverage_relation oid;
    requested_relation oid;
    new_relation oid;
    batch_dates_relation oid;
    v_requested_dates bigint;
    v_new_dates bigint;
    v_hashed_dates bigint;
    v_started timestamptz := clock_timestamp();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
        RAISE EXCEPTION 'valid inclusive price-hash date range required';
    END IF;

    PERFORM feat.prepare_phase2_adjustment_rows(false);

    batch_dates_relation := to_regclass('pg_temp.phase2_adjustment_batch_dates');
    IF batch_dates_relation IS NULL THEN
        -- Compatibility for a cache assembled before the batch-date manifest
        -- was introduced. New cache fills maintain the manifest incrementally.
        CREATE TEMP TABLE phase2_adjustment_batch_dates(
            batch_no integer NOT NULL,
            trade_date date NOT NULL,
            PRIMARY KEY(batch_no,trade_date)
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_adjustment_batch_dates IS
            'VN-Signal Phase 2 session-local adjustment-cache batch dates';
        INSERT INTO pg_temp.phase2_adjustment_batch_dates(batch_no,trade_date)
        SELECT DISTINCT s.batch_no,r.trade_date
        FROM pg_temp.phase2_adjustment_symbol_batches s
        JOIN pg_temp.phase2_adjustment_rows r USING(symbol_id)
        ON CONFLICT(batch_no,trade_date) DO NOTHING;
        CREATE INDEX phase2_adjustment_batch_dates_date_idx
            ON pg_temp.phase2_adjustment_batch_dates(trade_date);
    ELSIF obj_description(batch_dates_relation,'pg_class') IS DISTINCT FROM
          'VN-Signal Phase 2 session-local adjustment-cache batch dates' THEN
        RAISE EXCEPTION 'temporary relation phase2_adjustment_batch_dates is reserved by the Phase 2 builder';
    END IF;

    hash_relation := to_regclass('pg_temp.phase2_price_day_hashes');
    coverage_relation := to_regclass('pg_temp.phase2_price_day_hash_coverage');
    IF hash_relation IS NOT NULL AND
       obj_description(hash_relation, 'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 deterministic price-day hashes' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hashes is reserved by the Phase 2 builder';
    END IF;
    IF coverage_relation IS NOT NULL AND
       obj_description(coverage_relation, 'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 deterministic price-hash date coverage' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hash_coverage is reserved by the Phase 2 builder';
    END IF;

    IF hash_relation IS NULL THEN
        CREATE TEMP TABLE phase2_price_day_hashes (
            trade_date date PRIMARY KEY,
            day_sha256 text NOT NULL CHECK (day_sha256 ~ '^[0-9a-f]{64}$')
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_price_day_hashes IS
            'VN-Signal Phase 2 deterministic price-day hashes';
    END IF;
    IF coverage_relation IS NULL THEN
        CREATE TEMP TABLE phase2_price_day_hash_coverage (
            trade_date date PRIMARY KEY
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_price_day_hash_coverage IS
            'VN-Signal Phase 2 deterministic price-hash date coverage';
    END IF;

    requested_relation := to_regclass('pg_temp.phase2_price_day_hash_requested_work');
    IF requested_relation IS NOT NULL AND
       obj_description(requested_relation, 'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 requested price-day hash dates' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hash_requested_work is reserved by the Phase 2 builder';
    END IF;
    IF requested_relation IS NOT NULL THEN
        DROP TABLE pg_temp.phase2_price_day_hash_requested_work;
    END IF;
    CREATE TEMP TABLE phase2_price_day_hash_requested_work (
        trade_date date PRIMARY KEY
    ) ON COMMIT DROP;
    COMMENT ON TABLE pg_temp.phase2_price_day_hash_requested_work IS
        'VN-Signal Phase 2 requested price-day hash dates';

    INSERT INTO pg_temp.phase2_price_day_hash_requested_work(trade_date)
    SELECT s.trade_date
    FROM core.effective_trading_sessions s
    WHERE s.is_session AND s.trade_date BETWEEN p_date_from AND p_date_to
    UNION
    SELECT d.trade_date
    FROM pg_temp.phase2_adjustment_batch_dates d
    WHERE d.trade_date BETWEEN p_date_from AND p_date_to;
    GET DIAGNOSTICS v_requested_dates = ROW_COUNT;
    ANALYZE pg_temp.phase2_price_day_hash_requested_work;

    new_relation := to_regclass('pg_temp.phase2_price_day_hash_new_work');
    IF new_relation IS NOT NULL AND
       obj_description(new_relation, 'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 uncovered price-day hash dates' THEN
        RAISE EXCEPTION 'temporary relation phase2_price_day_hash_new_work is reserved by the Phase 2 builder';
    END IF;
    IF new_relation IS NOT NULL THEN
        DROP TABLE pg_temp.phase2_price_day_hash_new_work;
    END IF;
    CREATE TEMP TABLE phase2_price_day_hash_new_work (
        trade_date date PRIMARY KEY
    ) ON COMMIT DROP;
    COMMENT ON TABLE pg_temp.phase2_price_day_hash_new_work IS
        'VN-Signal Phase 2 uncovered price-day hash dates';

    INSERT INTO pg_temp.phase2_price_day_hash_new_work(trade_date)
    SELECT d.trade_date
    FROM pg_temp.phase2_price_day_hash_requested_work d
    WHERE NOT EXISTS (
        SELECT 1
        FROM pg_temp.phase2_price_day_hash_coverage c
        WHERE c.trade_date = d.trade_date
    );
    GET DIAGNOSTICS v_new_dates = ROW_COUNT;
    ANALYZE pg_temp.phase2_price_day_hash_new_work;
    RAISE NOTICE 'Phase 2 price-day hash range % through %: requested %, uncovered %, date planning elapsed %',
        p_date_from, p_date_to, v_requested_dates, v_new_dates,
        clock_timestamp() - v_started;

    IF v_new_dates > 0 THEN
        INSERT INTO pg_temp.phase2_price_day_hashes(trade_date, day_sha256)
        SELECT r.trade_date,
               ops.phase2_hash_text(
                   string_agg(to_jsonb(r)::text, E'\n' ORDER BY r.symbol_id)
               )
        FROM pg_temp.phase2_price_day_hash_new_work d
        JOIN pg_temp.phase2_adjustment_rows r
          ON r.trade_date = d.trade_date
        WHERE r.trade_date BETWEEN p_date_from AND p_date_to
        GROUP BY r.trade_date
        ON CONFLICT (trade_date) DO NOTHING;
        GET DIAGNOSTICS v_hashed_dates = ROW_COUNT;
        RAISE NOTICE 'Phase 2 price-day hash aggregate completed: % dates, elapsed %',
            v_hashed_dates, clock_timestamp() - v_started;
    END IF;

    INSERT INTO pg_temp.phase2_price_day_hash_coverage(trade_date)
    SELECT trade_date
    FROM pg_temp.phase2_price_day_hash_requested_work
    ON CONFLICT (trade_date) DO NOTHING;
    RAISE NOTICE 'Phase 2 price-day hash coverage recorded: % requested dates, total elapsed %',
        v_requested_dates, clock_timestamp() - v_started;
END;
$$;

COMMENT ON FUNCTION ops.phase2_prepare_price_day_hashes(date, date) IS
    'Builds canonical per-day price hashes using the compact batch-date manifest and full adjustment cache.';

COMMIT;

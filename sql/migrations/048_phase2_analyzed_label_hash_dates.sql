-- Materialize and analyze the small label-hash date set before joining it to
-- the full adjustment cache.  The old MATERIALIZED CTE hid its cardinality
-- from the planner and could repeat a full cache scan once per date.
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
    v_requested_dates bigint;
    v_new_dates bigint;
    v_hashed_dates bigint;
    v_started timestamptz := clock_timestamp();
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from > p_date_to THEN
        RAISE EXCEPTION 'valid inclusive price-hash date range required';
    END IF;

    PERFORM feat.prepare_phase2_adjustment_rows(false);

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
    SELECT r.trade_date
    FROM pg_temp.phase2_adjustment_rows r
    WHERE r.trade_date BETWEEN p_date_from AND p_date_to;
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
    'Builds canonical per-day price hashes from the full adjustment cache using analyzed temporary date work tables.';

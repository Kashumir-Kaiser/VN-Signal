\set ON_ERROR_STOP on
-- The resumable builder must keep one frozen adjustment snapshot across
-- separately committed year chunks in the same psql session.
DO $$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.phase2_vndirect_adjustment_details_for_symbols(bigint[])'::regprocedure
    );
BEGIN
    IF position('ANY(p_symbol_ids)' IN v_definition) = 0 OR
       position('requested_symbols AS MATERIALIZED' IN v_definition) > 0 THEN
        RAISE EXCEPTION 'Phase 2 adjustment helper must filter source bars with the symbol-array index predicate';
    END IF;
END
$$;

DO $$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.populate_phase2_adjustment_rows(integer)'::regprocedure
    );
BEGIN
    IF position('FROM feat.phase2_vndirect_adjustment_details_for_symbols(v_symbol_ids) r' IN v_definition) = 0 OR
       position('ORDER BY r.trade_date, r.symbol_id' IN v_definition) = 0 OR
       position('INSERT INTO pg_temp.phase2_adjustment_batch_dates' IN v_definition) = 0 OR
       position('WHERE r.source' IN v_definition) > 0 OR
       position('FROM ops.ml_symbol_scope excluded' IN v_definition) > 0 THEN
        RAISE EXCEPTION 'Phase 2 cache fill must insert exact helper rows in date order and record each batch date';
    END IF;
END
$$;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SET LOCAL work_mem='64MB';
SET LOCAL statement_timeout='5min';
SET LOCAL vnpipe.phase2_symbol_batch_size='2';
SET LOCAL application_name='phase2_features_cache_test';
SELECT feat.begin_phase2_adjustment_rows(2);
SELECT format('SELECT feat.populate_phase2_adjustment_rows(%s);',batch_no)
FROM (SELECT DISTINCT batch_no
      FROM pg_temp.phase2_adjustment_symbol_batches
      ORDER BY batch_no) batches
\gexec
SELECT min(batch_no) AS retry_batch FROM pg_temp.phase2_adjustment_symbol_batches \gset
SELECT feat.populate_phase2_adjustment_rows(:retry_batch);
DO $$
DECLARE
    v_rejected boolean:=false;
BEGIN
    BEGIN
        PERFORM feat.prepare_phase2_adjustment_rows(false);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM<>'Phase 2 adjustment cache is incomplete; load every batch and call finish before reuse' THEN
            RAISE;
        END IF;
        v_rejected:=true;
    END;
    IF NOT v_rejected THEN
        RAISE EXCEPTION 'unfinished Phase 2 cache was accepted for reuse';
    END IF;
END
$$;

DO $$
DECLARE
    v_definition text := pg_get_functiondef(
        'ops.phase2_prepare_price_day_hashes(date,date)'::regprocedure
    );
BEGIN
    IF position('FROM pg_temp.phase2_adjustment_batch_dates d' IN v_definition) = 0 THEN
        RAISE EXCEPTION 'Phase 2 price-day hashing must read the compact adjustment-cache date manifest';
    END IF;
END
$$;
SELECT feat.finish_phase2_adjustment_rows();
COMMIT;

DO $$
BEGIN
    IF EXISTS (
        WITH source_rows AS (
            SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
                   r.reference_adjustment_ratio,r.episode_start_date,
                   r.model_o,r.model_h,r.model_l,r.model_c,
                   r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
            FROM core.vndirect_reference_adjustment_details r
            WHERE r.source='vndirect'
              AND NOT EXISTS (
                  SELECT 1 FROM ops.ml_symbol_scope excluded
                  WHERE excluded.symbol_id=r.symbol_id
                    AND excluded.scope_status='EXCLUDED'
              )
        )
        SELECT 1
        FROM pg_temp.phase2_adjustment_rows c
        FULL JOIN source_rows s USING(symbol_id,trade_date)
        WHERE c.symbol_id IS NULL OR s.symbol_id IS NULL
           OR ROW(c.source,c.v,c.is_traded,c.reference_adjustment_ratio,c.episode_start_date,
                  c.model_o,c.model_h,c.model_l,c.model_c,c.adjustment_vintage_at,
                  c.landing_id,c.source_row,c.fetched_at)
              IS DISTINCT FROM
              ROW(s.source,s.v,s.is_traded,s.reference_adjustment_ratio,s.episode_start_date,
                  s.model_o,s.model_h,s.model_l,s.model_c,s.adjustment_vintage_at,
                  s.landing_id,s.source_row,s.fetched_at)
    ) THEN
        RAISE EXCEPTION 'batched Phase 2 cache differs from the adjustment view';
    END IF;
END
$$;

-- Physical insertion order must not affect the canonical date hash. Reverse
-- the copied heap order while retaining the same JSON and symbol sort keys.
CREATE TEMP TABLE phase2_session_cache_reordered_fixture
ON COMMIT PRESERVE ROWS AS
SELECT *
FROM pg_temp.phase2_adjustment_rows
ORDER BY trade_date DESC, symbol_id DESC;

DO $$
DECLARE
    v_mismatch_count bigint;
BEGIN
    WITH cached_hashes AS (
        SELECT r.trade_date,
               ops.phase2_hash_text(
                   string_agg(to_jsonb(r)::text, E'\n' ORDER BY r.symbol_id)
               ) AS day_sha256
        FROM pg_temp.phase2_adjustment_rows r
        GROUP BY r.trade_date
    ), reordered_hashes AS (
        SELECT r.trade_date,
               ops.phase2_hash_text(
                   string_agg(to_jsonb(r)::text, E'\n' ORDER BY r.symbol_id)
               ) AS day_sha256
        FROM pg_temp.phase2_session_cache_reordered_fixture r
        GROUP BY r.trade_date
    )
    SELECT count(*) INTO v_mismatch_count
    FROM (
        (SELECT * FROM cached_hashes
         EXCEPT ALL
         SELECT * FROM reordered_hashes)
        UNION ALL
        (SELECT * FROM reordered_hashes
         EXCEPT ALL
         SELECT * FROM cached_hashes)
    ) mismatches;
    IF v_mismatch_count<>0 THEN
        RAISE EXCEPTION 'Phase 2 per-day hashes changed with physical cache order: % mismatches',
            v_mismatch_count;
    END IF;
END
$$;

DO $$
BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_batch_dates'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local adjustment-cache batch dates'
       OR EXISTS (
            SELECT batch_no,trade_date
            FROM (
                SELECT DISTINCT s.batch_no,r.trade_date
                FROM pg_temp.phase2_adjustment_symbol_batches s
                JOIN pg_temp.phase2_adjustment_rows r USING(symbol_id)
                EXCEPT
                SELECT batch_no,trade_date
                FROM pg_temp.phase2_adjustment_batch_dates
            ) missing
       )
       OR EXISTS (
            SELECT batch_no,trade_date
            FROM (
                SELECT batch_no,trade_date
                FROM pg_temp.phase2_adjustment_batch_dates
                EXCEPT
                SELECT DISTINCT s.batch_no,r.trade_date
                FROM pg_temp.phase2_adjustment_symbol_batches s
                JOIN pg_temp.phase2_adjustment_rows r USING(symbol_id)
            ) extra
       ) THEN
        RAISE EXCEPTION 'Phase 2 cache date manifest differs from its cached adjustment rows';
    END IF;
END
$$;

BEGIN;
SET LOCAL work_mem='64MB';
SET LOCAL vnpipe.phase2_symbol_batch_size='2';
SET LOCAL application_name='phase2_features_cache_test';
SELECT feat.build_price_features_v3_internal(DATE '2098-01-05',DATE '2098-12-31');
COMMIT;

SELECT to_regclass('pg_temp.phase2_adjustment_rows')::oid AS phase2_cache_oid \gset
BEGIN;
SET LOCAL work_mem='64MB';
SET LOCAL vnpipe.phase2_symbol_batch_size='2';
SET LOCAL application_name='phase2_features_cache_test';
SELECT feat.build_price_features_v3_internal(DATE '2099-01-01',DATE '2099-04-30');
COMMIT;

SELECT to_regclass('pg_temp.phase2_adjustment_rows')::oid=:phase2_cache_oid::oid AS phase2_cache_kept \gset
\if :phase2_cache_kept
\echo PASS phase2 adjustment cache persisted across chunk commits
\else
\echo FAIL phase2 adjustment cache was replaced across chunk commits
\quit 1
\endif

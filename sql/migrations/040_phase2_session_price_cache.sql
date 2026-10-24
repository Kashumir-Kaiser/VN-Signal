-- Preserve the point-in-time adjustment snapshot across resumable chunks in one
-- database session. Each chunk still commits independently; the runner closes
-- the session after its stage, dropping this temporary cache.
BEGIN;

CREATE OR REPLACE FUNCTION feat.prepare_phase2_adjustment_rows(p_refresh boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    cache_relation oid;
    v_started_at timestamptz:=clock_timestamp();
BEGIN
    IF p_refresh IS NULL THEN
        RAISE EXCEPTION 'p_refresh must be true or false';
    END IF;
    cache_relation:=to_regclass('pg_temp.phase2_adjustment_rows');
    IF cache_relation IS NOT NULL THEN
        IF obj_description(cache_relation,'pg_class')='VN-Signal Phase 2 session-local point-in-time price input cache' THEN
            IF NOT p_refresh THEN
                RETURN;
            END IF;
            DROP TABLE pg_temp.phase2_adjustment_rows;
        ELSE
            RAISE EXCEPTION 'temporary relation phase2_adjustment_rows is reserved by the Phase 2 builder';
        END IF;
    END IF;

    -- This is a frozen input snapshot for one build session. Public builders
    -- explicitly refresh it; resumable chunk builders reuse it across commits.
    CREATE TEMP TABLE phase2_adjustment_rows ON COMMIT PRESERVE ROWS AS
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
      );
    COMMENT ON TABLE pg_temp.phase2_adjustment_rows IS
        'VN-Signal Phase 2 session-local point-in-time price input cache';
    CREATE INDEX phase2_adjustment_rows_date_symbol_idx
        ON pg_temp.phase2_adjustment_rows(trade_date,symbol_id);
    CREATE INDEX phase2_adjustment_rows_symbol_date_idx
        ON pg_temp.phase2_adjustment_rows(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_adjustment_rows;
    RAISE NOTICE 'Phase 2 adjustment cache rows %, elapsed %',
        (SELECT count(*) FROM pg_temp.phase2_adjustment_rows),clock_timestamp()-v_started_at;
END;
$$;

COMMENT ON FUNCTION feat.prepare_phase2_adjustment_rows(boolean) IS
    'Creates a frozen session-local point-in-time input cache. Public builders refresh it; resumable chunk builders reuse it across per-chunk commits.';

COMMIT;

-- The cache batch manifest is built from in-scope VNDIRECT symbols, and the
-- adjustment helper filters to those IDs and that source before its window
-- work. Avoid reapplying those predicates outside the opaque set-returning
-- function: PostgreSQL estimates Function Scan output poorly and the redundant
-- joins can inflate the batch plan as symbol count grows.
BEGIN;

CREATE OR REPLACE FUNCTION feat.populate_phase2_adjustment_rows(p_batch_no integer)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_rows bigint;
    v_symbol_ids bigint[];
    v_enable_nestloop text:=current_setting('enable_nestloop');
    v_started_at timestamptz:=clock_timestamp();
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

    UPDATE pg_temp.phase2_adjustment_cache_state
       SET ready=false,finalized_at=NULL;

    -- A retry replaces only this batch, so it is deterministic and idempotent.
    DELETE FROM pg_temp.phase2_adjustment_rows r
    USING pg_temp.phase2_adjustment_symbol_batches s
    WHERE s.batch_no=p_batch_no AND r.symbol_id=s.symbol_id;

    -- This helper's bounded CTE cardinality estimates can otherwise select a
    -- nested loop against the per-traded-sequence lookup. Keep the planner
    -- override local to this batch fill and restore the caller value.
    PERFORM set_config('enable_nestloop','off',true);
    INSERT INTO pg_temp.phase2_adjustment_rows(
        symbol_id,trade_date,source,v,is_traded,reference_adjustment_ratio,
        episode_start_date,model_o,model_h,model_l,model_c,
        adjustment_vintage_at,landing_id,source_row,fetched_at
    )
    SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
           r.reference_adjustment_ratio,r.episode_start_date,
           r.model_o,r.model_h,r.model_l,r.model_c,
           r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
    FROM feat.phase2_vndirect_adjustment_details_for_symbols(v_symbol_ids) r;
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    PERFORM set_config('enable_nestloop',v_enable_nestloop,true);
    UPDATE pg_temp.phase2_adjustment_symbol_batches
       SET loaded=true
     WHERE batch_no=p_batch_no;
    RAISE NOTICE 'Phase 2 adjustment cache batch % rows %, elapsed %',
        p_batch_no,v_rows,clock_timestamp()-v_started_at;
    RETURN v_rows;
END;
$$;

COMMENT ON FUNCTION feat.populate_phase2_adjustment_rows(integer) IS
    'Loads the exact in-scope VNDIRECT rows selected by the session batch manifest without redundant outer filters.';

COMMIT;

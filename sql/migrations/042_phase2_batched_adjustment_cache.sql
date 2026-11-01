-- Bound the point-in-time input-cache work by symbol batch. This keeps the
-- existing core adjustment view and feature meanings intact while allowing
-- the build runner to checkpoint each cache fill as a separate SQL statement.
BEGIN;

CREATE OR REPLACE FUNCTION feat.begin_phase2_adjustment_rows(
    p_symbol_batch_size integer,
    p_symbol_limit integer DEFAULT NULL
)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE
    v_cache_relation oid;
    v_symbol_relation oid;
    v_state_relation oid;
    v_batch_count integer;
BEGIN
    IF p_symbol_batch_size IS NULL OR p_symbol_batch_size<1 OR p_symbol_batch_size>250 THEN
        RAISE EXCEPTION 'symbol batch size must be between 1 and 250';
    END IF;
    IF p_symbol_limit IS NOT NULL AND p_symbol_limit<1 THEN
        RAISE EXCEPTION 'symbol limit must be positive when provided';
    END IF;

    v_cache_relation:=to_regclass('pg_temp.phase2_adjustment_rows');
    IF v_cache_relation IS NOT NULL THEN
        IF obj_description(v_cache_relation,'pg_class')=
           'VN-Signal Phase 2 session-local point-in-time price input cache' THEN
            DROP TABLE pg_temp.phase2_adjustment_rows;
        ELSE
            RAISE EXCEPTION 'temporary relation phase2_adjustment_rows is reserved by the Phase 2 builder';
        END IF;
    END IF;

    v_symbol_relation:=to_regclass('pg_temp.phase2_adjustment_symbol_batches');
    IF v_symbol_relation IS NOT NULL THEN
        IF obj_description(v_symbol_relation,'pg_class')=
           'VN-Signal Phase 2 session-local cache symbol-batch manifest' THEN
            DROP TABLE pg_temp.phase2_adjustment_symbol_batches;
        ELSE
            RAISE EXCEPTION 'temporary relation phase2_adjustment_symbol_batches is reserved by the Phase 2 builder';
        END IF;
    END IF;

    v_state_relation:=to_regclass('pg_temp.phase2_adjustment_cache_state');
    IF v_state_relation IS NOT NULL THEN
        IF obj_description(v_state_relation,'pg_class')=
           'VN-Signal Phase 2 session-local cache readiness state' THEN
            DROP TABLE pg_temp.phase2_adjustment_cache_state;
        ELSE
            RAISE EXCEPTION 'temporary relation phase2_adjustment_cache_state is reserved by the Phase 2 builder';
        END IF;
    END IF;

    -- WHERE FALSE preserves the exact view column types without evaluating its
    -- full-history windows. Each subsequent call fills one disjoint symbol set.
    CREATE TEMP TABLE phase2_adjustment_rows ON COMMIT PRESERVE ROWS AS
    SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
           r.reference_adjustment_ratio,r.episode_start_date,
           r.model_o,r.model_h,r.model_l,r.model_c,
           r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
    FROM core.vndirect_reference_adjustment_details r
    WHERE false;
    COMMENT ON TABLE pg_temp.phase2_adjustment_rows IS
        'VN-Signal Phase 2 session-local point-in-time price input cache';

    CREATE TEMP TABLE phase2_adjustment_symbol_batches ON COMMIT PRESERVE ROWS AS
    WITH eligible_symbols AS (
        -- core.symbols is the canonical one-row-per-security directory. Probe
        -- its symbol/date/source index for coverage rather than scanning and
        -- hashing every row in the 2.84M-row price table. Do not filter active:
        -- historical delisted names remain part of Phase 2.
        SELECT s.symbol_id
        FROM core.symbols s
        WHERE EXISTS (
              SELECT 1 FROM core.bars_daily_sources b
              WHERE b.symbol_id=s.symbol_id AND b.source='vndirect'
          )
          AND NOT EXISTS (
              SELECT 1 FROM ops.ml_symbol_scope excluded
              WHERE excluded.symbol_id=s.symbol_id
                AND excluded.scope_status='EXCLUDED'
          )
    ), ranked_symbols AS (
        SELECT e.symbol_id,
               row_number() OVER(ORDER BY md5(e.symbol_id::text),e.symbol_id) AS symbol_no
        FROM eligible_symbols e
    )
    SELECT s.symbol_id,
           ((s.symbol_no-1)/p_symbol_batch_size)::integer AS batch_no,
           false AS loaded
    FROM ranked_symbols s
    WHERE p_symbol_limit IS NULL OR s.symbol_no<=p_symbol_limit;
    COMMENT ON TABLE pg_temp.phase2_adjustment_symbol_batches IS
        'VN-Signal Phase 2 session-local cache symbol-batch manifest';
    ALTER TABLE pg_temp.phase2_adjustment_symbol_batches
        ADD PRIMARY KEY(symbol_id);
    CREATE INDEX phase2_adjustment_symbol_batches_batch_idx
        ON pg_temp.phase2_adjustment_symbol_batches(batch_no,symbol_id);
    ANALYZE pg_temp.phase2_adjustment_symbol_batches;

    CREATE TEMP TABLE phase2_adjustment_cache_state(
        cache_id integer PRIMARY KEY DEFAULT 1 CHECK(cache_id=1),
        ready boolean NOT NULL DEFAULT false,
        finalized_at timestamptz
    ) ON COMMIT PRESERVE ROWS;
    COMMENT ON TABLE pg_temp.phase2_adjustment_cache_state IS
        'VN-Signal Phase 2 session-local cache readiness state';
    INSERT INTO pg_temp.phase2_adjustment_cache_state(ready,finalized_at)
    VALUES(false,NULL);

    SELECT count(DISTINCT batch_no)::integer
      INTO v_batch_count
      FROM pg_temp.phase2_adjustment_symbol_batches;
    IF v_batch_count=0 THEN
        RAISE EXCEPTION 'no in-scope VNDIRECT bar symbols are available for the Phase 2 cache';
    END IF;
    RAISE NOTICE 'Phase 2 adjustment cache initialized for % batches of up to % symbols',
        v_batch_count,p_symbol_batch_size;
    RETURN v_batch_count;
END;
$$;

-- Preserve the canonical adjustment SQL while restricting source rows before
-- its shared/window CTEs materialize. This avoids rebuilding every security's
-- full history for each Phase 2 symbol batch; fixture assertions compare this
-- helper's cached output against the unchanged core view.
DROP FUNCTION IF EXISTS feat.phase2_vndirect_adjustment_details_for_symbols(bigint[]);
CREATE OR REPLACE FUNCTION feat.phase2_vndirect_adjustment_details_for_symbols(p_symbol_ids bigint[])
RETURNS TABLE(
    symbol_id bigint,
    trade_date date,
    source text,
    v double precision,
    is_traded boolean,
    reference_adjustment_ratio double precision,
    episode_start_date date,
    model_o double precision,
    model_h double precision,
    model_l double precision,
    model_c double precision,
    adjustment_vintage_at timestamptz,
    landing_id bigint,
    source_row integer,
    fetched_at timestamptz
)
LANGUAGE SQL STABLE
AS $phase2_vndirect_adjustment_details$
WITH requested_symbols AS MATERIALIZED (
         SELECT DISTINCT unnest(p_symbol_ids) AS symbol_id
        ), source_rows AS (
         SELECT b.symbol_id,
            b.trade_date,
            b.source,
            b.o,
            b.h,
            b.l,
            b.c,
            b.v,
            b.adj_basis,
            b.is_traded,
            b.landing_id,
            b.source_row,
            b.ingest_id,
            b.fetched_at,
            b.adjusted_o,
            b.adjusted_h,
            b.adjusted_l,
            b.adjusted_c,
            b.adjustment_vintage_at,
            b.basic_price,
            b.average_price,
            b.exchange_code,
            COALESCE(m.model_o, b.o) AS model_o,
            COALESCE(m.model_h, b.h) AS model_h,
            COALESCE(m.model_l, b.l) AS model_l,
            COALESCE(m.model_c, b.c) AS model_c,
            m.evidence_url AS model_bar_evidence_url,
            m.evidence_sha256 AS model_bar_evidence_sha256,
            m.secondary_evidence_url AS model_bar_secondary_evidence_url,
            m.secondary_evidence_sha256 AS model_bar_secondary_evidence_sha256,
            m.evidence_note AS model_bar_evidence_note,
            row_number() OVER (PARTITION BY b.symbol_id ORDER BY b.trade_date) AS source_sequence,
            min(b.trade_date) OVER (PARTITION BY b.symbol_id) AS first_trade_date
          FROM requested_symbols requested
            JOIN LATERAL (
                SELECT source_bar.*
                FROM core.bars_daily_sources source_bar
                WHERE source_bar.symbol_id=requested.symbol_id
                  AND source_bar.source='vndirect'::text
            ) b ON true
             LEFT JOIN core.vndirect_model_bar_overrides m ON m.symbol_id = b.symbol_id AND m.trade_date = b.trade_date AND m.source = b.source
          WHERE b.source = 'vndirect'::text
        ), lifecycle_boundaries AS (
         SELECT DISTINCT e.symbol_id,
            e.date_from AS boundary_date
           FROM core.security_lifecycle_evidence e
          WHERE e.evidence_type = 'TRADE_ELIGIBLE'::text AND (EXISTS ( SELECT 1
                   FROM core.security_lifecycle_evidence d
                  WHERE d.symbol_id = e.symbol_id AND d.evidence_type = 'DELISTED'::text AND d.date_to IS NOT NULL AND d.date_to < e.date_from))
        ), episode_assignment AS (
         SELECT o.symbol_id,
            o.trade_date,
            o.source_sequence,
            COALESCE(max(b.boundary_date), o.first_trade_date) AS episode_start_date
           FROM source_rows o
             LEFT JOIN lifecycle_boundaries b ON b.symbol_id = o.symbol_id AND b.boundary_date <= o.trade_date
          GROUP BY o.symbol_id, o.trade_date, o.source_sequence, o.first_trade_date
        ), episode_rows AS (
         SELECT o.symbol_id,
            o.trade_date,
            o.source,
            o.o,
            o.h,
            o.l,
            o.c,
            o.v,
            o.adj_basis,
            o.is_traded,
            o.landing_id,
            o.source_row,
            o.ingest_id,
            o.fetched_at,
            o.adjusted_o,
            o.adjusted_h,
            o.adjusted_l,
            o.adjusted_c,
            o.adjustment_vintage_at,
            o.basic_price,
            o.average_price,
            o.exchange_code,
            o.model_o,
            o.model_h,
            o.model_l,
            o.model_c,
            o.model_bar_evidence_url,
            o.model_bar_evidence_sha256,
            o.model_bar_secondary_evidence_url,
            o.model_bar_secondary_evidence_sha256,
            o.model_bar_evidence_note,
            o.source_sequence,
            o.first_trade_date,
            a.episode_start_date
           FROM source_rows o
             JOIN episode_assignment a ON a.symbol_id = o.symbol_id AND a.trade_date = o.trade_date AND a.source_sequence = o.source_sequence
        ), ordered AS (
         SELECT b.symbol_id,
            b.trade_date,
            b.source,
            b.o,
            b.h,
            b.l,
            b.c,
            b.v,
            b.adj_basis,
            b.is_traded,
            b.landing_id,
            b.source_row,
            b.ingest_id,
            b.fetched_at,
            b.adjusted_o,
            b.adjusted_h,
            b.adjusted_l,
            b.adjusted_c,
            b.adjustment_vintage_at,
            b.basic_price,
            b.average_price,
            b.exchange_code,
            b.model_o,
            b.model_h,
            b.model_l,
            b.model_c,
            b.model_bar_evidence_url,
            b.model_bar_evidence_sha256,
            b.model_bar_secondary_evidence_url,
            b.model_bar_secondary_evidence_sha256,
            b.model_bar_evidence_note,
            b.source_sequence,
            b.first_trade_date,
            b.episode_start_date,
            lag(b.c) OVER w AS prior_close,
            lag(b.basic_price) OVER w AS prior_basic_price,
            lag(b.average_price) OVER w AS prior_average_price,
            lag(b.v) OVER w AS prior_volume,
            lag(b.adjusted_c) OVER w AS prior_adjusted_close,
            sum(
                CASE
                    WHEN b.v > 0::double precision THEN 1::bigint
                    ELSE 0::bigint
                END) OVER w AS traded_sequence,
            row_number() OVER w AS episode_row_number
           FROM episode_rows b
          WINDOW w AS (PARTITION BY b.symbol_id, b.episode_start_date ORDER BY b.trade_date)
        ), traded_references AS (
         SELECT o.symbol_id,
            o.episode_start_date,
            o.traded_sequence,
            max(o.average_price) AS last_traded_average_price,
            max(o.c) AS last_traded_close
           FROM ordered o
          WHERE o.v > 0::double precision
          GROUP BY o.symbol_id, o.episode_start_date, o.traded_sequence
        ), reference_basis AS (
         SELECT o.symbol_id,
            o.trade_date,
            o.source,
            o.o,
            o.h,
            o.l,
            o.c,
            o.v,
            o.adj_basis,
            o.is_traded,
            o.landing_id,
            o.source_row,
            o.ingest_id,
            o.fetched_at,
            o.adjusted_o,
            o.adjusted_h,
            o.adjusted_l,
            o.adjusted_c,
            o.adjustment_vintage_at,
            o.basic_price,
            o.average_price,
            o.exchange_code,
            o.model_o,
            o.model_h,
            o.model_l,
            o.model_c,
            o.model_bar_evidence_url,
            o.model_bar_evidence_sha256,
            o.model_bar_secondary_evidence_url,
            o.model_bar_secondary_evidence_sha256,
            o.model_bar_evidence_note,
            o.source_sequence,
            o.first_trade_date,
            o.episode_start_date,
            o.prior_close,
            o.prior_basic_price,
            o.prior_average_price,
            o.prior_volume,
            o.prior_adjusted_close,
            o.traded_sequence,
            o.episode_row_number,
                CASE
                    WHEN o.episode_row_number = 1 THEN NULL::double precision
                    WHEN o.exchange_code = 'UPCOM'::text THEN
                    CASE
                        WHEN o.prior_volume > 0::double precision THEN COALESCE(NULLIF(o.prior_average_price, 0::double precision), o.prior_close)
                        ELSE COALESCE(NULLIF(o.prior_basic_price, 0::double precision), NULLIF(t.last_traded_average_price, 0::double precision), o.prior_close)
                    END
                    ELSE
                    CASE
                        WHEN o.prior_volume > 0::double precision THEN o.prior_close
                        ELSE COALESCE(NULLIF(o.prior_basic_price, 0::double precision), t.last_traded_close, o.prior_close)
                    END
                END AS reference_baseline,
            x.reference_adjustment_ratio AS override_ratio,
            x.resolution_kind AS override_resolution_kind,
            x.evidence_url AS override_evidence_url,
            x.secondary_evidence_url AS override_secondary_evidence_url,
            x.evidence_note AS override_evidence_note
           FROM ordered o
             LEFT JOIN traded_references t ON t.symbol_id = o.symbol_id AND t.episode_start_date = o.episode_start_date AND t.traded_sequence = (o.traded_sequence -
                CASE
                    WHEN o.v > 0::double precision THEN 1::bigint
                    ELSE 0::bigint
                END::numeric)
             LEFT JOIN core.vndirect_reference_adjustment_overrides x ON x.symbol_id = o.symbol_id AND x.trade_date = o.trade_date AND x.source = o.source
        ), reference_tolerance AS (
         SELECT r_1.symbol_id,
            r_1.trade_date,
            r_1.source,
            r_1.o,
            r_1.h,
            r_1.l,
            r_1.c,
            r_1.v,
            r_1.adj_basis,
            r_1.is_traded,
            r_1.landing_id,
            r_1.source_row,
            r_1.ingest_id,
            r_1.fetched_at,
            r_1.adjusted_o,
            r_1.adjusted_h,
            r_1.adjusted_l,
            r_1.adjusted_c,
            r_1.adjustment_vintage_at,
            r_1.basic_price,
            r_1.average_price,
            r_1.exchange_code,
            r_1.model_o,
            r_1.model_h,
            r_1.model_l,
            r_1.model_c,
            r_1.model_bar_evidence_url,
            r_1.model_bar_evidence_sha256,
            r_1.model_bar_secondary_evidence_url,
            r_1.model_bar_secondary_evidence_sha256,
            r_1.model_bar_evidence_note,
            r_1.source_sequence,
            r_1.first_trade_date,
            r_1.episode_start_date,
            r_1.prior_close,
            r_1.prior_basic_price,
            r_1.prior_average_price,
            r_1.prior_volume,
            r_1.prior_adjusted_close,
            r_1.traded_sequence,
            r_1.episode_row_number,
            r_1.reference_baseline,
            r_1.override_ratio,
            r_1.override_resolution_kind,
            r_1.override_evidence_url,
            r_1.override_secondary_evidence_url,
            r_1.override_evidence_note,
                CASE
                    WHEN r_1.exchange_code = 'HOSE'::text AND r_1.reference_baseline < 10::double precision THEN 0.005::double precision
                    WHEN r_1.exchange_code = 'HOSE'::text AND r_1.reference_baseline < 50::double precision THEN 0.025::double precision
                    ELSE 0.05::double precision
                END AS half_tick
           FROM reference_basis r_1
        )
 SELECT symbol_id,
    trade_date,
    source,
    v,
    is_traded,

    COALESCE(override_ratio,
        CASE
            WHEN episode_row_number = 1 THEN 1::double precision
            WHEN exchange_code IS NULL OR (exchange_code <> ALL (ARRAY['HOSE'::text, 'HNX'::text, 'UPCOM'::text])) THEN NULL::double precision
            WHEN basic_price > 0::double precision AND reference_baseline > 0::double precision THEN
            CASE
                WHEN abs(basic_price - reference_baseline) <= (half_tick + 0.000000001::double precision) THEN 1::double precision
                ELSE basic_price / reference_baseline
            END
            WHEN v = 0::double precision AND c = prior_close AND NOT adjusted_c IS DISTINCT FROM prior_adjusted_close THEN 1::double precision
            ELSE NULL::double precision
        END) AS reference_adjustment_ratio,
    episode_start_date,
    model_o,
    model_h,
    model_l,
    model_c,
    adjustment_vintage_at,
    landing_id,
    source_row,
    fetched_at
   FROM reference_tolerance r;
$phase2_vndirect_adjustment_details$;

COMMENT ON FUNCTION feat.phase2_vndirect_adjustment_details_for_symbols(bigint[]) IS
    'Returns canonical VNDIRECT adjustment details for selected symbol IDs, filtering before adjustment CTE evaluation for bounded Phase 2 batches.';

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
    -- nested loop against the per-traded-sequence lookup. On the 30-symbol
    -- report-clone profile that caused 316M join-filter comparisons. Keep the
    -- planner override local to this batch fill and restore the caller value.
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
    FROM feat.phase2_vndirect_adjustment_details_for_symbols(v_symbol_ids) r
    WHERE r.source='vndirect'
      AND EXISTS (
          SELECT 1 FROM pg_temp.phase2_adjustment_symbol_batches s
          WHERE s.batch_no=p_batch_no AND s.symbol_id=r.symbol_id
      )
      AND NOT EXISTS (
          SELECT 1 FROM ops.ml_symbol_scope excluded
          WHERE excluded.symbol_id=r.symbol_id
            AND excluded.scope_status='EXCLUDED'
      );
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

CREATE OR REPLACE FUNCTION feat.finish_phase2_adjustment_rows()
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_missing_batch integer;
    v_rows bigint;
    v_state_rows integer;
    v_started_at timestamptz:=clock_timestamp();
BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_rows'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local point-in-time price input cache'
       OR obj_description(to_regclass('pg_temp.phase2_adjustment_symbol_batches'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache symbol-batch manifest'
       OR obj_description(to_regclass('pg_temp.phase2_adjustment_cache_state'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache readiness state' THEN
        RAISE EXCEPTION 'initialize the reserved Phase 2 adjustment cache before finishing it';
    END IF;

    SELECT batch_no INTO v_missing_batch
    FROM pg_temp.phase2_adjustment_symbol_batches
    WHERE NOT loaded
    ORDER BY batch_no
    LIMIT 1;
    IF v_missing_batch IS NOT NULL THEN
        RAISE EXCEPTION 'Phase 2 adjustment-cache batch % has not been loaded',v_missing_batch;
    END IF;

    CREATE UNIQUE INDEX IF NOT EXISTS phase2_adjustment_rows_symbol_date_idx
        ON pg_temp.phase2_adjustment_rows(symbol_id,trade_date);
    CREATE INDEX IF NOT EXISTS phase2_adjustment_rows_date_symbol_idx
        ON pg_temp.phase2_adjustment_rows(trade_date,symbol_id);
    ANALYZE pg_temp.phase2_adjustment_rows;
    SELECT count(*) INTO v_rows FROM pg_temp.phase2_adjustment_rows;
    IF v_rows=0 THEN
        RAISE EXCEPTION 'Phase 2 adjustment cache is empty';
    END IF;
    UPDATE pg_temp.phase2_adjustment_cache_state
       SET ready=true,finalized_at=clock_timestamp();
    GET DIAGNOSTICS v_state_rows=ROW_COUNT;
    IF v_state_rows<>1 THEN
        RAISE EXCEPTION 'Phase 2 cache readiness marker is missing, duplicated, or already finalized';
    END IF;
    RAISE NOTICE 'Phase 2 adjustment cache rows %, finalize elapsed %',
        v_rows,clock_timestamp()-v_started_at;
    RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION feat.probe_phase2_adjustment_cache(p_symbol_count integer)
RETURNS TABLE(symbol_count integer,row_count bigint,duration_ms bigint)
LANGUAGE plpgsql AS $$
DECLARE
    v_started_at timestamptz:=clock_timestamp();
    v_actual_symbols integer;
    v_batches integer;
    v_rows bigint;
    v_metrics_relation oid;
BEGIN
    IF p_symbol_count IS NULL OR p_symbol_count NOT IN (15,30,60) THEN
        RAISE EXCEPTION 'cache scaling probes require exactly 15, 30, or 60 symbols';
    END IF;
    PERFORM feat.begin_phase2_adjustment_rows(p_symbol_count,p_symbol_count);
    SELECT count(*)::integer,count(DISTINCT batch_no)::integer
      INTO v_actual_symbols,v_batches
      FROM pg_temp.phase2_adjustment_symbol_batches;
    IF v_actual_symbols<>p_symbol_count OR v_batches<>1 THEN
        RAISE EXCEPTION 'cache scaling probe requested % symbols but found % in % batches',
            p_symbol_count,v_actual_symbols,v_batches;
    END IF;
    v_rows:=feat.populate_phase2_adjustment_rows(0);
    v_rows:=feat.finish_phase2_adjustment_rows();

    v_metrics_relation:=to_regclass('pg_temp.phase2_adjustment_cache_probe_results');
    IF v_metrics_relation IS NULL THEN
        CREATE TEMP TABLE phase2_adjustment_cache_probe_results(
            symbol_count integer PRIMARY KEY,
            row_count bigint NOT NULL CHECK(row_count>0),
            duration_ms bigint NOT NULL CHECK(duration_ms>0)
        ) ON COMMIT PRESERVE ROWS;
        COMMENT ON TABLE pg_temp.phase2_adjustment_cache_probe_results IS
            'VN-Signal Phase 2 session-local cache scaling probe results';
    ELSIF obj_description(v_metrics_relation,'pg_class') IS DISTINCT FROM
          'VN-Signal Phase 2 session-local cache scaling probe results' THEN
        RAISE EXCEPTION 'temporary relation phase2_adjustment_cache_probe_results is reserved by the Phase 2 builder';
    END IF;
    duration_ms:=GREATEST(1,(extract(epoch FROM (clock_timestamp()-v_started_at))*1000)::bigint);
    INSERT INTO pg_temp.phase2_adjustment_cache_probe_results(symbol_count,row_count,duration_ms)
    VALUES(p_symbol_count,v_rows,duration_ms)
    ON CONFLICT ON CONSTRAINT phase2_adjustment_cache_probe_results_pkey DO UPDATE
      SET row_count=EXCLUDED.row_count,duration_ms=EXCLUDED.duration_ms;
    symbol_count:=p_symbol_count;
    row_count:=v_rows;
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION feat.assert_phase2_adjustment_cache_scaling()
RETURNS double precision LANGUAGE plpgsql AS $$
DECLARE
    v_t15 double precision;
    v_t30 double precision;
    v_t60 double precision;
    v_b15_30 double precision;
    v_b30_60 double precision;
    v_exponent double precision;
    v_universe_symbols integer;
    v_batch_size integer;
    v_batch_count integer;
    v_batch_ms double precision;
    v_projected_ms double precision;
    v_budget_minutes double precision;
BEGIN
    IF obj_description(to_regclass('pg_temp.phase2_adjustment_cache_probe_results'),'pg_class') IS DISTINCT FROM
       'VN-Signal Phase 2 session-local cache scaling probe results' THEN
        RAISE EXCEPTION 'run the 15, 30, and 60 symbol cache probes before the full build';
    END IF;
    SELECT duration_ms::double precision INTO v_t15
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=15;
    SELECT duration_ms::double precision INTO v_t30
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=30;
    SELECT duration_ms::double precision INTO v_t60
      FROM pg_temp.phase2_adjustment_cache_probe_results WHERE symbol_count=60;
    IF v_t15 IS NULL OR v_t30 IS NULL OR v_t60 IS NULL THEN
        RAISE EXCEPTION 'cache scaling evidence requires completed 15, 30, and 60 symbol probes';
    END IF;
    IF v_t30<v_t15*0.8 OR v_t60<v_t30*0.8 THEN
        RAISE EXCEPTION 'cache probe timings vary by more than 20%% between adjacent samples; re-probe before the full build: %, %, % ms',
            v_t15,v_t30,v_t60;
    END IF;
    v_b15_30:=CASE WHEN v_t30>v_t15 THEN ln(v_t30/v_t15)/ln(2.0) ELSE 0.0 END;
    v_b30_60:=CASE WHEN v_t60>v_t30 THEN ln(v_t60/v_t30)/ln(2.0) ELSE 0.0 END;
    v_exponent:=greatest(0.0,v_b15_30,v_b30_60);
    IF v_exponent>1.3 THEN
        RAISE EXCEPTION 'cache scaling exponent % exceeds 1.3; inspect the sampled plan and re-probe',
            round(v_exponent::numeric,3);
    END IF;
    SELECT count(*)::integer INTO v_universe_symbols
    FROM core.symbols s
    WHERE EXISTS (
          SELECT 1 FROM core.bars_daily_sources b
          WHERE b.symbol_id=s.symbol_id AND b.source='vndirect'
      )
      AND NOT EXISTS (
          SELECT 1 FROM ops.ml_symbol_scope excluded
          WHERE excluded.symbol_id=s.symbol_id AND excluded.scope_status='EXCLUDED'
      );
    IF v_universe_symbols<60 THEN
        RAISE EXCEPTION 'cache scaling has only % in-scope symbols; 60-symbol probe cannot represent the full universe',
            v_universe_symbols;
    END IF;
    v_batch_size:=COALESCE(
        NULLIF(current_setting('vnpipe.phase2_symbol_batch_size',true),'')::integer,
        60
    );
    IF v_batch_size<1 OR v_batch_size>250 THEN
        RAISE EXCEPTION 'vnpipe.phase2_symbol_batch_size must be between 1 and 250';
    END IF;
    v_batch_count:=ceil(v_universe_symbols::double precision/v_batch_size)::integer;
    v_budget_minutes:=COALESCE(
        NULLIF(current_setting('vnpipe.phase2_cache_time_budget_minutes',true),'')::double precision,
        40.0
    );
    IF v_budget_minutes<=0 THEN
        RAISE EXCEPTION 'vnpipe.phase2_cache_time_budget_minutes must be positive';
    END IF;
    v_batch_ms:=greatest(
        v_t15*power(v_batch_size::double precision/15.0,v_exponent),
        v_t30*power(v_batch_size::double precision/30.0,v_exponent),
        v_t60*power(v_batch_size::double precision/60.0,v_exponent)
    );
    v_projected_ms:=v_batch_ms*v_batch_count;
    IF v_projected_ms>v_budget_minutes*60000.0 THEN
        RAISE EXCEPTION 'projected full-universe adjustment cache time % minutes exceeds configured budget % minutes for % symbols',
            round((v_projected_ms/60000.0)::numeric,2),v_budget_minutes,v_universe_symbols;
    END IF;
    RAISE NOTICE 'Phase 2 adjustment cache scaling exponent %, 15/30/60 timings %/%/% ms, % symbols in % batches of % (estimated per-batch % ms), projected cache time % minutes (budget % minutes)',
        round(v_exponent::numeric,3),v_t15,v_t30,v_t60,v_universe_symbols,v_batch_count,v_batch_size,
        round(v_batch_ms::numeric,1),
        round((v_projected_ms/60000.0)::numeric,2),v_budget_minutes;
    RETURN v_exponent;
END;
$$;

CREATE OR REPLACE FUNCTION feat.prepare_phase2_adjustment_rows(p_refresh boolean)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    cache_relation oid;
    symbol_relation oid;
    state_relation oid;
    v_batch record;
    v_universe_symbols integer;
    v_ready_indexes integer;
    v_batch_size integer:=COALESCE(NULLIF(current_setting('vnpipe.phase2_symbol_batch_size',true),''),'60')::integer;
BEGIN
    IF p_refresh IS NULL THEN
        RAISE EXCEPTION 'p_refresh must be true or false';
    END IF;
    IF v_batch_size<1 OR v_batch_size>250 THEN
        RAISE EXCEPTION 'vnpipe.phase2_symbol_batch_size must be between 1 and 250';
    END IF;

    cache_relation:=to_regclass('pg_temp.phase2_adjustment_rows');
    symbol_relation:=to_regclass('pg_temp.phase2_adjustment_symbol_batches');
    state_relation:=to_regclass('pg_temp.phase2_adjustment_cache_state');
    IF NOT p_refresh
       AND (cache_relation IS NOT NULL OR symbol_relation IS NOT NULL OR state_relation IS NOT NULL) THEN
        IF cache_relation IS NULL OR symbol_relation IS NULL OR state_relation IS NULL
           OR obj_description(cache_relation,'pg_class') IS DISTINCT FROM
              'VN-Signal Phase 2 session-local point-in-time price input cache'
           OR obj_description(symbol_relation,'pg_class') IS DISTINCT FROM
              'VN-Signal Phase 2 session-local cache symbol-batch manifest'
           OR obj_description(state_relation,'pg_class') IS DISTINCT FROM
              'VN-Signal Phase 2 session-local cache readiness state' THEN
            RAISE EXCEPTION 'initialize and finish the Phase 2 adjustment cache before reusing it';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_temp.phase2_adjustment_cache_state WHERE ready)
           OR EXISTS (SELECT 1 FROM pg_temp.phase2_adjustment_symbol_batches WHERE NOT loaded) THEN
            RAISE EXCEPTION 'Phase 2 adjustment cache is incomplete; load every batch and call finish before reuse';
        END IF;
        SELECT count(*)::integer INTO v_ready_indexes
        FROM pg_index
        WHERE indexrelid IN (
            to_regclass('pg_temp.phase2_adjustment_rows_symbol_date_idx'),
            to_regclass('pg_temp.phase2_adjustment_rows_date_symbol_idx')
        )
          AND indisvalid AND indisready;
        IF v_ready_indexes<>2 THEN
            RAISE EXCEPTION 'Phase 2 adjustment cache is marked ready without both valid lookup indexes';
        END IF;
        RETURN;
    END IF;

    -- The convenience API must not hide a market-wide PL/pgSQL batch loop in
    -- one statement. Small SQL fixtures remain convenient; large builds must
    -- call begin/populate per committed batch through ops/phase2_build.ps1.
    -- A false refresh with no session cache keeps the legacy small-fixture
    -- fallback, while the same size limit still blocks full-universe work.
    SELECT count(*)::integer INTO v_universe_symbols
    FROM core.symbols s
    WHERE EXISTS (
          SELECT 1 FROM core.bars_daily_sources b
          WHERE b.symbol_id=s.symbol_id AND b.source='vndirect'
      )
      AND NOT EXISTS (
          SELECT 1 FROM ops.ml_symbol_scope excluded
          WHERE excluded.symbol_id=s.symbol_id AND excluded.scope_status='EXCLUDED'
      );
    IF v_universe_symbols>60 THEN
        RAISE EXCEPTION 'direct adjustment-cache preparation is limited to 60 symbols; use staged begin/populate calls for % in-scope symbols',
            v_universe_symbols;
    END IF;

    PERFORM feat.begin_phase2_adjustment_rows(v_batch_size);
    FOR v_batch IN
        SELECT DISTINCT batch_no
        FROM pg_temp.phase2_adjustment_symbol_batches
        ORDER BY batch_no
    LOOP
        PERFORM feat.populate_phase2_adjustment_rows(v_batch.batch_no);
    END LOOP;
    PERFORM feat.finish_phase2_adjustment_rows();
END;
$$;

COMMENT ON FUNCTION feat.begin_phase2_adjustment_rows(integer,integer) IS
    'Creates empty session-local Phase 2 price cache tables and assigns in-scope VNDIRECT symbols to deterministic batches.';
COMMENT ON FUNCTION feat.populate_phase2_adjustment_rows(integer) IS
    'Populates one idempotent symbol batch in the session-local Phase 2 price cache; call once per batch for statement-level checkpoints.';
COMMENT ON FUNCTION feat.finish_phase2_adjustment_rows() IS
    'Validates that every session-local Phase 2 cache batch loaded, then indexes and analyzes the frozen price inputs.';
COMMENT ON FUNCTION feat.probe_phase2_adjustment_cache(integer) IS
    'Times one deterministic 15, 30, or 60 symbol adjusted-price cache probe and retains the result in a session-local manifest.';
COMMENT ON FUNCTION feat.assert_phase2_adjustment_cache_scaling() IS
    'Computes adjacent cache exponents, projects full-universe cache time, and blocks runs above configured exponent or time budget.';
COMMENT ON FUNCTION feat.prepare_phase2_adjustment_rows(boolean) IS
    'Builds small fixture caches or validates a finalized cache; market-wide cache work must use explicit staged batches.';

COMMIT;

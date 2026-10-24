BEGIN;

-- Missing exit bars are classified as MISSING_EXIT before factor-span values
-- are consulted. Do not issue a per-target lateral prefix lookup for them.
DO $phase2_label_missing_exit_span$
DECLARE
    v_signature text := 'feat.build_labels_set_based_shared(date,date,bigint[])';
    v_definition text := pg_get_functiondef(v_signature::regprocedure);
    v_anchor constant text :=
        '           AND (t.exit_bar_date IS NULL'
        || E'\n                OR t.entry_episode IS DISTINCT FROM t.exit_episode)';
    v_replacement constant text :=
        '           AND t.exit_bar_date IS NOT NULL'
        || E'\n           AND t.entry_episode IS DISTINCT FROM t.exit_episode';
BEGIN
    IF position(v_replacement IN v_definition) > 0 THEN
        RETURN;
    END IF;
    IF length(v_definition)-length(replace(v_definition,v_anchor,'')) <> length(v_anchor) THEN
        RAISE EXCEPTION 'unexpected missing-exit factor-span fallback in shared label builder';
    END IF;
    EXECUTE replace(v_definition,v_anchor,v_replacement);
END;
$phase2_label_missing_exit_span$;

CREATE OR REPLACE FUNCTION feat.phase2_winsorize_excess(
    p_excess double precision,
    p_p01 double precision,
    p_p99 double precision
)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN p_excess IS NULL OR p_p01 IS NULL OR p_p99 IS NULL THEN NULL
                ELSE greatest(p_p01,least(p_p99,p_excess)) END
$$;

CREATE OR REPLACE FUNCTION feat.phase2_volatility_scaled_excess(
    p_excess double precision,
    p_sigma60 double precision,
    p_sigma60_floor double precision,
    p_horizon smallint
)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE
             WHEN p_excess IS NULL OR p_sigma60 IS NULL OR p_sigma60_floor IS NULL
               OR p_horizon NOT IN (5,20) THEN NULL
             WHEN greatest(p_sigma60,p_sigma60_floor) <= 0 THEN NULL
             ELSE p_excess /
                  (greatest(p_sigma60,p_sigma60_floor) * sqrt(p_horizon::double precision))
           END
$$;

CREATE OR REPLACE FUNCTION feat.phase2_median_float8_array(p_values double precision[])
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY x)
      FROM unnest(p_values) AS valueset(x)
     WHERE x IS NOT NULL AND x > '-Infinity'::double precision
       AND x < 'Infinity'::double precision
$$;

CREATE OR REPLACE FUNCTION feat.phase2_average_float8_array(p_values double precision[])
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT avg(x) FROM unnest(p_values) AS valueset(x)
     WHERE x IS NOT NULL AND x > '-Infinity'::double precision AND x < 'Infinity'::double precision
$$;

CREATE OR REPLACE FUNCTION feat.phase2_investable_membership_decision(
    p_gate_status text,
    p_membership_rank20 integer,
    p_was_member boolean
)
RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT coalesce(p_gate_status='ELIGIBLE' AND (
               p_membership_rank20<=400 OR
               (p_membership_rank20<=500 AND coalesce(p_was_member,false))
           ),false)
$$;

CREATE OR REPLACE FUNCTION feat.phase2_target_uniform_rank(p_rank integer,p_count integer)
RETURNS double precision
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN p_rank IS NULL OR p_count IS NULL OR p_rank<1 OR p_count<1 OR p_rank>p_count
                THEN NULL
                ELSE (p_rank-0.5)::double precision/p_count END
$$;

CREATE TABLE IF NOT EXISTS feat.phase2_liquidity_tiers_v3 (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    feature_set_hash text NOT NULL CHECK(feature_set_hash ~ '^[0-9a-f]{64}$'),
    median_turnover_proxy20 double precision,
    average_turnover_proxy20 double precision,
    verified_listed_sessions integer,
    membership_gate_status text NOT NULL CHECK(membership_gate_status IN ('ELIGIBLE','INELIGIBLE','INDETERMINATE')),
    membership_rank20 integer,
    median_turnover_proxy60 double precision,
    tier_liquidity_rank60 integer,
    is_investable_member boolean NOT NULL,
    liquidity_tier text CHECK(liquidity_tier IN ('L1','L2','L3')),
    tier_rank integer,
    tier_count integer,
    tier_uniform_rank double precision,
    PRIMARY KEY(symbol_id,trade_date),
    CHECK ((liquidity_tier IS NULL) = (tier_uniform_rank IS NULL)),
    CHECK (tier_uniform_rank IS NULL OR tier_uniform_rank > 0 AND tier_uniform_rank < 1)
);
CREATE INDEX IF NOT EXISTS phase2_liquidity_tiers_date_idx
    ON feat.phase2_liquidity_tiers_v3(trade_date,liquidity_tier,tier_liquidity_rank60);

CREATE TABLE IF NOT EXISTS feat.phase2_label_targets_v3 (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    signal_date date NOT NULL,
    horizon_sessions smallint NOT NULL CHECK(horizon_sessions IN (5,20)),
    label_version text NOT NULL,
    feature_set_hash text NOT NULL CHECK(feature_set_hash ~ '^[0-9a-f]{64}$'),
    raw_excess_return double precision NOT NULL,
    winsorized_excess_p01 double precision NOT NULL,
    winsorized_excess_p99 double precision NOT NULL,
    winsorized_excess_return double precision NOT NULL,
    realized_vol60 double precision,
    sigma60_date_floor double precision,
    volatility_scaled_score double precision,
    point_in_time_turnover_proxy_vnd double precision,
    median_turnover_proxy20 double precision,
    average_turnover_proxy20 double precision,
    verified_listed_sessions integer,
    membership_gate_status text NOT NULL CHECK(membership_gate_status IN ('ELIGIBLE','INELIGIBLE','INDETERMINATE')),
    membership_rank20 integer,
    median_turnover_proxy60 double precision,
    tier_liquidity_rank60 integer,
    is_investable_member boolean NOT NULL,
    liquidity_tier text CHECK(liquidity_tier IN ('L1','L2','L3')),
    tier_rank integer,
    tier_count integer,
    tier_uniform_rank double precision,
    target_rank_in_tier integer,
    target_tier_count integer,
    target_uniform_rank double precision,
    built_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(symbol_id,signal_date,horizon_sessions,label_version),
    CHECK(winsorized_excess_p01 <= winsorized_excess_p99),
    CHECK(winsorized_excess_return BETWEEN winsorized_excess_p01 AND winsorized_excess_p99),
    CHECK((liquidity_tier IS NULL) = (tier_uniform_rank IS NULL)),
    CHECK(tier_uniform_rank IS NULL OR tier_uniform_rank > 0 AND tier_uniform_rank < 1),
    CHECK((target_rank_in_tier IS NULL) = (target_uniform_rank IS NULL)),
    CHECK(target_uniform_rank IS NULL OR target_uniform_rank > 0 AND target_uniform_rank < 1),
    CHECK(target_tier_count IS NULL OR target_tier_count>0)
);
CREATE INDEX IF NOT EXISTS phase2_label_targets_date_idx
    ON feat.phase2_label_targets_v3(signal_date,horizon_sessions,label_version);

CREATE TABLE IF NOT EXISTS ops.phase2_label_target_chunk_runs (
    run_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    build_id text NOT NULL DEFAULT 'phase2-label-targets-v1',
    chunk_key text NOT NULL,
    date_from date NOT NULL,
    date_to date NOT NULL,
    status text NOT NULL CHECK(status IN ('running','done')),
    input_hash text NOT NULL CHECK(input_hash ~ '^[0-9a-f]{64}$'),
    output_hash text CHECK(output_hash IS NULL OR output_hash ~ '^[0-9a-f]{64}$'),
    rows bigint CHECK(rows IS NULL OR rows>=0),
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    finished_at timestamptz,
    CHECK(date_from<=date_to),
    CHECK((status='done')=(finished_at IS NOT NULL)),
    CHECK(status<>'done' OR (output_hash IS NOT NULL AND rows IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS phase2_label_target_chunk_runs_range_idx
    ON ops.phase2_label_target_chunk_runs(date_from,date_to,run_id);

ALTER TABLE ops.phase2_label_target_chunk_runs
    ADD COLUMN IF NOT EXISTS invalidated_at timestamptz,
    ADD COLUMN IF NOT EXISTS invalidation_reason text;

CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_base_input_hash(p_date_from date,p_date_to date)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_first_signal date; v_prior_session date; v_warmup_from date;
    v_hash text; v_context text; v_prior_state text;
    v_feature_hash text:=feat.phase2_feature_set_hash_v3();
BEGIN
    SELECT min(trade_date) INTO v_first_signal FROM core.effective_trading_sessions
     WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to;
    IF v_first_signal IS NULL THEN RETURN ops.phase2_chunk_input_hash('labels',p_date_from,p_date_to); END IF;
    SELECT max(trade_date) INTO v_prior_session FROM core.effective_trading_sessions
     WHERE is_session AND trade_date<v_first_signal;
    SELECT min(trade_date) INTO v_warmup_from FROM (
        SELECT trade_date FROM core.effective_trading_sessions WHERE is_session AND trade_date<v_first_signal
         ORDER BY trade_date DESC LIMIT 59
    ) prior_sessions;
    v_warmup_from:=coalesce(v_warmup_from,v_first_signal);
    SELECT ops.phase2_hash_text(coalesce(string_agg(
        ops.phase2_hash_jsonb(jsonb_build_object('symbol_id',f.symbol_id,'trade_date',f.trade_date,
                                                 'turnover_proxy_vnd',f.turnover_proxy_vnd)),''
        ORDER BY f.trade_date,f.symbol_id),'')) INTO v_context
      FROM feat.features_daily f
     WHERE f.feature_version='phase2-v3' AND f.feature_set_hash=v_feature_hash
       AND f.trade_date BETWEEN v_warmup_from AND p_date_to;
    SELECT ops.phase2_hash_text(coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(s)),'' ORDER BY s.symbol_id),''))
      INTO v_prior_state FROM feat.phase2_liquidity_tiers_v3 s
     WHERE s.trade_date=v_prior_session AND s.feature_set_hash=v_feature_hash;
    v_hash:=ops.phase2_chunk_input_hash('labels',p_date_from,p_date_to);
    RETURN ops.phase2_hash_text(v_hash||'|liquidity_context='||v_context||'|prior_membership='||v_prior_state);
END;
$$;

CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_input_hash(p_date_from date,p_date_to date)
RETURNS text LANGUAGE sql STABLE AS $$
    SELECT ops.phase2_label_target_chunk_base_input_hash(p_date_from,p_date_to)
$$;

CREATE OR REPLACE FUNCTION feat.build_phase2_label_targets_v3(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_first_signal date;
    v_first_feature date;
    v_prior_session date;
    v_warmup_from date;
    v_date date;
    v_hash text := feat.phase2_feature_set_hash_v3();
    v_input_hash text;
    v_output_hash text;
    v_context text;
    v_prior_state text;
    v_run_id bigint;
    v_rows bigint;
    v_sessions integer;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    SELECT count(*) INTO v_sessions
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to;
    IF v_sessions>300 THEN
        RAISE EXCEPTION 'label-derived chunks are limited to 300 trade sessions; requested %',v_sessions;
    END IF;
    SELECT min(trade_date) INTO v_first_feature
      FROM feat.features_daily
     WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash;
    SELECT min(trade_date) INTO v_first_signal
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to;
    IF v_first_signal IS NULL THEN
        DELETE FROM feat.phase2_label_targets_v3
         WHERE signal_date BETWEEN p_date_from AND p_date_to;
        RETURN 0;
    END IF;

    SELECT max(trade_date) INTO v_prior_session
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date<v_first_signal;
    IF v_prior_session IS NOT NULL AND v_first_signal>coalesce(v_first_feature,v_first_signal)
       AND NOT EXISTS (
           SELECT 1 FROM feat.phase2_liquidity_tiers_v3
            WHERE trade_date=v_prior_session AND feature_set_hash=v_hash
            GROUP BY trade_date
            HAVING count(*)=(SELECT count(*) FROM (
                                SELECT symbol_id,min(trade_date) AS first_date
                                  FROM feat.features_daily
                                 WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash
                                 GROUP BY symbol_id
                              ) starts WHERE first_date<=v_prior_session)
       ) THEN
        RAISE EXCEPTION 'liquidity membership checkpoint missing before chunk start %',v_first_signal;
    END IF;

    SELECT min(trade_date) INTO v_warmup_from
      FROM (
          SELECT trade_date FROM core.effective_trading_sessions
           WHERE is_session AND trade_date<v_first_signal
           ORDER BY trade_date DESC LIMIT 59
      ) prior_sessions;
    v_warmup_from:=coalesce(v_warmup_from,v_first_signal);

    v_input_hash:=ops.phase2_label_target_chunk_input_hash(p_date_from,p_date_to);

    INSERT INTO ops.phase2_label_target_chunk_runs(
        chunk_key,date_from,date_to,status,input_hash
    ) VALUES (
        to_char(p_date_from,'YYYYMMDD')||'-'||to_char(p_date_to,'YYYYMMDD'),
        p_date_from,p_date_to,'running',v_input_hash
    ) RETURNING run_id INTO v_run_id;

    UPDATE ops.phase2_label_target_chunk_runs
       SET invalidated_at=clock_timestamp(),
           invalidation_reason='upstream chunk rebuild invalidated downstream state and targets'
     WHERE date_to>=v_first_signal AND invalidated_at IS NULL AND status='done';
    DELETE FROM feat.phase2_label_targets_v3
     WHERE signal_date>=v_first_signal;
    DELETE FROM feat.phase2_liquidity_tiers_v3
     WHERE trade_date>=v_first_signal;

    DROP TABLE IF EXISTS pg_temp.phase2_label_liquidity_median;
    CREATE TEMP TABLE phase2_label_liquidity_median ON COMMIT DROP AS
    WITH symbol_start AS MATERIALIZED (
        SELECT symbol_id,min(trade_date) AS first_date
          FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash AND trade_date<=p_date_to
         GROUP BY symbol_id
    ), series AS MATERIALIZED (
        SELECT sy.symbol_id,s.trade_date,f.turnover_proxy_vnd
          FROM symbol_start sy
          JOIN core.effective_trading_sessions s
            ON s.is_session AND s.trade_date>=greatest(sy.first_date,v_warmup_from) AND s.trade_date<=p_date_to
          LEFT JOIN feat.features_daily f
            ON f.symbol_id=sy.symbol_id AND f.trade_date=s.trade_date
           AND f.feature_version='phase2-v3' AND f.feature_set_hash=v_hash
    ), windows AS (
        SELECT symbol_id,trade_date,
               feat.phase2_median_float8_array(array_agg(turnover_proxy_vnd) OVER (
                   PARTITION BY symbol_id ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
               )) AS median_turnover_proxy20,
               feat.phase2_median_float8_array(array_agg(turnover_proxy_vnd) OVER (
                   PARTITION BY symbol_id ORDER BY trade_date ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
               )) AS median_turnover_proxy60,
               feat.phase2_average_float8_array(array_agg(turnover_proxy_vnd) OVER (
                   PARTITION BY symbol_id ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
               )) AS average_turnover_proxy20,
               count(turnover_proxy_vnd) OVER (
                   PARTITION BY symbol_id ORDER BY trade_date ROWS BETWEEN 19 PRECEDING AND CURRENT ROW
               ) AS proxy_count20,
               count(turnover_proxy_vnd) OVER (
                   PARTITION BY symbol_id ORDER BY trade_date ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
               ) AS proxy_count60
          FROM series
    )
    -- VCI canonical bars do not store landing_id/source_row. Do not treat an
    -- ingest-batch match as proof of exact-row provenance for listing tenure.
    -- Keep the 250-session gate indeterminate until that lineage is persisted.
    SELECT symbol_id,trade_date,median_turnover_proxy20,average_turnover_proxy20,
           NULL::integer AS verified_listed_sessions,
           CASE WHEN proxy_count20=20 AND average_turnover_proxy20<5000000000 THEN 'INELIGIBLE'
                ELSE 'INDETERMINATE' END AS membership_gate_status,
           CASE WHEN proxy_count60=60 THEN median_turnover_proxy60 END AS median_turnover_proxy60
      FROM windows WHERE trade_date BETWEEN v_first_signal AND p_date_to;
    ALTER TABLE pg_temp.phase2_label_liquidity_median ADD PRIMARY KEY(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_label_liquidity_median;

    DROP TABLE IF EXISTS pg_temp.phase2_label_membership_rank;
    CREATE TEMP TABLE phase2_label_membership_rank ON COMMIT DROP AS
    SELECT symbol_id,trade_date,median_turnover_proxy20,average_turnover_proxy20,verified_listed_sessions,
           membership_gate_status,
           row_number() OVER (PARTITION BY trade_date ORDER BY median_turnover_proxy20 DESC,symbol_id)::integer AS membership_rank20
      FROM pg_temp.phase2_label_liquidity_median
     WHERE membership_gate_status='ELIGIBLE' AND median_turnover_proxy20 IS NOT NULL;
    ALTER TABLE pg_temp.phase2_label_membership_rank ADD PRIMARY KEY(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_label_membership_rank;

    DROP TABLE IF EXISTS pg_temp.phase2_label_tier_rank;
    CREATE TEMP TABLE phase2_label_tier_rank ON COMMIT DROP AS
    SELECT m.symbol_id,m.trade_date,m.median_turnover_proxy60,
           row_number() OVER (PARTITION BY m.trade_date ORDER BY m.median_turnover_proxy60 DESC,m.symbol_id)::integer AS tier_liquidity_rank60
      FROM pg_temp.phase2_label_liquidity_median m
      JOIN pg_temp.phase2_label_membership_rank r USING(symbol_id,trade_date)
     WHERE m.median_turnover_proxy60 IS NOT NULL AND r.membership_rank20<=400;
    ALTER TABLE pg_temp.phase2_label_tier_rank ADD PRIMARY KEY(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_label_tier_rank;

    FOR v_date IN
        SELECT trade_date FROM core.effective_trading_sessions WHERE is_session AND trade_date BETWEEN v_first_signal AND p_date_to ORDER BY trade_date
    LOOP
        DROP TABLE IF EXISTS pg_temp.phase2_label_liquidity_day;
        CREATE TEMP TABLE phase2_label_liquidity_day ON COMMIT DROP AS
        SELECT m.symbol_id,m.trade_date,m.median_turnover_proxy20,m.average_turnover_proxy20,m.verified_listed_sessions,m.membership_gate_status,
               m.median_turnover_proxy60,r.membership_rank20,tr.tier_liquidity_rank60,
               feat.phase2_investable_membership_decision(
                   m.membership_gate_status,r.membership_rank20,prev.is_investable_member
               ) AS is_member
          FROM pg_temp.phase2_label_liquidity_median m
          LEFT JOIN pg_temp.phase2_label_membership_rank r USING(symbol_id,trade_date)
          LEFT JOIN pg_temp.phase2_label_tier_rank tr USING(symbol_id,trade_date)
          LEFT JOIN feat.phase2_liquidity_tiers_v3 prev ON prev.symbol_id=m.symbol_id AND prev.trade_date=v_prior_session
         WHERE m.trade_date=v_date;
        ANALYZE pg_temp.phase2_label_liquidity_day;
        INSERT INTO feat.phase2_liquidity_tiers_v3(
            symbol_id,trade_date,feature_set_hash,median_turnover_proxy20,average_turnover_proxy20,verified_listed_sessions,membership_gate_status,
            membership_rank20,median_turnover_proxy60,tier_liquidity_rank60,is_investable_member,liquidity_tier,tier_rank,tier_count,tier_uniform_rank
        )
        SELECT symbol_id,trade_date,v_hash,median_turnover_proxy20,average_turnover_proxy20,verified_listed_sessions,membership_gate_status,
               membership_rank20,median_turnover_proxy60,tier_liquidity_rank60,is_member,
               CASE WHEN is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100 THEN 'L1'
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250 THEN 'L2'
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400 THEN 'L3' END,
               CASE WHEN is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100 THEN tier_liquidity_rank60
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250 THEN tier_liquidity_rank60-100
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400 THEN tier_liquidity_rank60-250 END,
               CASE WHEN is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100 THEN count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100) OVER ()
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250 THEN count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250) OVER ()
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400 THEN count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400) OVER () END,
               CASE WHEN is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100 THEN (tier_liquidity_rank60-0.5)::double precision/nullif(count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 1 AND 100) OVER (),0)
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250 THEN (tier_liquidity_rank60-100.5)::double precision/nullif(count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 101 AND 250) OVER (),0)
                    WHEN is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400 THEN (tier_liquidity_rank60-250.5)::double precision/nullif(count(*) FILTER (WHERE is_member AND tier_liquidity_rank60 BETWEEN 251 AND 400) OVER (),0) END
          FROM pg_temp.phase2_label_liquidity_day;
        v_prior_session:=v_date;
    END LOOP;

    WITH current_ready AS MATERIALIZED (
        SELECT l.symbol_id,l.signal_date,l.horizon_sessions,l.label_version,
               l.feature_set_hash,l.excess_return,f.realized_vol60,
               f.turnover_proxy_vnd
          FROM feat.labels_daily l
          JOIN feat.features_daily f
            ON f.symbol_id=l.symbol_id AND f.trade_date=l.signal_date
           AND f.feature_version='phase2-v3' AND f.feature_set_hash=l.feature_set_hash
         WHERE l.label_version='close-next-open-v1'
           AND l.feature_set_hash=v_hash AND l.label_status='READY'
           AND l.signal_date BETWEEN p_date_from AND p_date_to
    ), daily_bounds AS (
        SELECT signal_date,horizon_sessions,
               percentile_cont(0.01) WITHIN GROUP (ORDER BY excess_return) AS excess_p01,
               percentile_cont(0.99) WITHIN GROUP (ORDER BY excess_return) AS excess_p99
          FROM current_ready
         GROUP BY signal_date,horizon_sessions
    ), volatility_floor AS (
        SELECT signal_date,percentile_cont(0.05) WITHIN GROUP (ORDER BY realized_vol60)
                   FILTER (WHERE realized_vol60 IS NOT NULL) AS sigma60_p05
          FROM (SELECT DISTINCT signal_date,symbol_id,realized_vol60 FROM current_ready) by_symbol_date
         GROUP BY signal_date
    ), target_values AS MATERIALIZED (
        SELECT r.symbol_id,r.signal_date,r.horizon_sessions,r.label_version,r.feature_set_hash,
               r.excess_return,b.excess_p01,b.excess_p99,
               feat.phase2_winsorize_excess(r.excess_return,b.excess_p01,b.excess_p99) AS winsorized_excess_return,
               r.realized_vol60,vf.sigma60_p05,
               feat.phase2_volatility_scaled_excess(r.excess_return,r.realized_vol60,vf.sigma60_p05,
                                                    r.horizon_sessions) AS volatility_scaled_score,
               r.turnover_proxy_vnd,q.median_turnover_proxy20,q.average_turnover_proxy20,
               q.verified_listed_sessions,q.membership_gate_status,q.membership_rank20,
               q.median_turnover_proxy60,q.tier_liquidity_rank60,q.is_investable_member,
               q.liquidity_tier,q.tier_rank,q.tier_count,q.tier_uniform_rank
          FROM current_ready r
          JOIN daily_bounds b USING(signal_date,horizon_sessions)
          JOIN volatility_floor vf USING(signal_date)
          JOIN feat.phase2_liquidity_tiers_v3 q
            ON q.symbol_id=r.symbol_id AND q.trade_date=r.signal_date
    ), ranked_targets AS MATERIALIZED (
        SELECT symbol_id,signal_date,horizon_sessions,label_version,
               row_number() OVER (
                   PARTITION BY signal_date,horizon_sessions,liquidity_tier
                   ORDER BY volatility_scaled_score DESC,symbol_id
               )::integer AS target_rank_in_tier,
               count(*) OVER (PARTITION BY signal_date,horizon_sessions,liquidity_tier)::integer AS target_tier_count
          FROM target_values
         WHERE liquidity_tier IS NOT NULL AND volatility_scaled_score IS NOT NULL
    )
    INSERT INTO feat.phase2_label_targets_v3(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,
        raw_excess_return,winsorized_excess_p01,winsorized_excess_p99,
        winsorized_excess_return,realized_vol60,sigma60_date_floor,
        volatility_scaled_score,point_in_time_turnover_proxy_vnd,
        median_turnover_proxy20,average_turnover_proxy20,verified_listed_sessions,membership_gate_status,membership_rank20,
        median_turnover_proxy60,tier_liquidity_rank60,is_investable_member,
        liquidity_tier,tier_rank,tier_count,tier_uniform_rank,
        target_rank_in_tier,target_tier_count,target_uniform_rank
    )
    SELECT t.symbol_id,t.signal_date,t.horizon_sessions,t.label_version,t.feature_set_hash,
           t.excess_return,t.excess_p01,t.excess_p99,t.winsorized_excess_return,
           t.realized_vol60,t.sigma60_p05,t.volatility_scaled_score,t.turnover_proxy_vnd,
           t.median_turnover_proxy20,t.average_turnover_proxy20,t.verified_listed_sessions,
           t.membership_gate_status,t.membership_rank20,t.median_turnover_proxy60,t.tier_liquidity_rank60,
           t.is_investable_member,t.liquidity_tier,t.tier_rank,t.tier_count,t.tier_uniform_rank,
           rr.target_rank_in_tier,rr.target_tier_count,
           feat.phase2_target_uniform_rank(rr.target_rank_in_tier,rr.target_tier_count)
      FROM target_values t
      LEFT JOIN ranked_targets rr USING(symbol_id,signal_date,horizon_sessions,label_version);
    GET DIAGNOSTICS v_rows=ROW_COUNT;
    v_output_hash:=ops.phase2_label_targets_chunk_hash(p_date_from,p_date_to);
    UPDATE ops.phase2_label_target_chunk_runs
       SET status='done',output_hash=v_output_hash,rows=v_rows,finished_at=clock_timestamp()
     WHERE run_id=v_run_id;
    RETURN v_rows;
END;
$$;

CREATE OR REPLACE FUNCTION ops.phase2_label_targets_chunk_hash(
    p_date_from date,
    p_date_to date
)
RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT ops.phase2_hash_text(coalesce(string_agg(
               ops.phase2_hash_jsonb(to_jsonb(t)-'built_at'),''
               ORDER BY t.signal_date,t.symbol_id,t.horizon_sessions,t.label_version
           ),''))
      FROM feat.phase2_label_targets_v3 t
     WHERE t.signal_date BETWEEN p_date_from AND p_date_to
$$;

COMMENT ON TABLE feat.phase2_label_targets_v3 IS
    'Durable, date-chunked, current-hash training targets. Keeps feat.labels_daily raw and hash-stable; stores date-wise winsorized excess return, volatility-scaled score, PIT membership/tier metrics, and a separate within-tier/date/horizon target rank by volatility-scaled score. Target score ties break by symbol_id.';
COMMENT ON TABLE feat.phase2_liquidity_tiers_v3 IS
    'Durable PIT liquidity state. Master membership rank20 uses median20 turnover_proxy_vnd, >=250 verified positive-volume VCI sessions, avg20 proxy >=VND5B, and enter<=400/retain<=500. Recovery tiers use a separate median60 rank among eligible top-400 members; tiers are L1 1-100, L2 101-250, L3 251-400. Retained ranks 401-500 get no tier rank. turnover_proxy_vnd is a research estimate, not executed turnover.';
COMMENT ON COLUMN feat.phase2_liquidity_tiers_v3.tier_uniform_rank IS
    'Uniform position of the security by liquidity within its L1/L2/L3 band and trade date; this is not a label target rank.';
COMMENT ON COLUMN feat.phase2_label_targets_v3.tier_uniform_rank IS
    'Uniform position by liquidity within its tier and trade date; distinct from the score-based target_uniform_rank.';
COMMENT ON COLUMN feat.phase2_label_targets_v3.target_uniform_rank IS
    'Uniform label target rank within signal_date, horizon_sessions, and liquidity_tier, ordered by volatility_scaled_score descending then symbol_id ascending; computed as (target_rank_in_tier-0.5)/target_tier_count.';
COMMENT ON TABLE ops.phase2_label_target_chunk_runs IS
    'Durable attempts for bounded derived-label chunks. Each successful run records the input context hash, row count, and deterministic derived-target output hash; repeated E5 runs retain separate records.';
COMMENT ON FUNCTION feat.build_phase2_label_targets_v3(date,date) IS
    'Builds at most 300 sessions of durable Phase 2 derived labels per call. Chunks require a prior liquidity-state checkpoint unless they start at the first feature session.';

DO $phase2_label_targets_assert$
DECLARE
    v_label_definition text := pg_get_functiondef(
        'feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure
    );
    v_forbidden_fallback constant text :=
        '           AND (t.exit_bar_date IS NULL'
        || E'\n                OR t.entry_episode IS DISTINCT FROM t.exit_episode)';
    v_guarded_span constant text :=
        '           AND t.exit_bar_date IS NOT NULL'
        || E'\n           AND t.entry_episode IS DISTINCT FROM t.exit_episode';
BEGIN
    -- The builder still needs the IS NULL branch in its label-status CASE to
    -- emit MISSING_EXIT. Only the factor-span fallback predicate is forbidden.
    IF position(v_guarded_span IN v_label_definition) = 0
       OR position(v_forbidden_fallback IN v_label_definition) > 0 THEN
        RAISE EXCEPTION 'missing-exit labels must not run a factor-span fallback lookup';
    END IF;
    IF to_regclass('feat.phase2_label_targets_v3') IS NULL
       OR to_regprocedure('feat.build_phase2_label_targets_v3(date,date)') IS NULL
       OR to_regprocedure('ops.phase2_label_targets_chunk_hash(date,date)') IS NULL THEN
        RAISE EXCEPTION 'durable derived label outputs were not installed';
    END IF;
END;
$phase2_label_targets_assert$;

COMMIT;

-- V3 inherits the V2 row shape, but its benchmark contract is VCI. Refresh
-- the three V2-named benchmark fields on V3 rows and keep future builds aligned.
BEGIN;

CREATE OR REPLACE FUNCTION feat.phase2_feature_set_hash_v3()
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT md5(definition||'|'||base_hash)||md5('VN-Signal:'||definition||'|'||base_hash)
    FROM (VALUES ('phase2-v3|effective_sessions|episode_neutral_prices|12_1_231_return_sessions|market_model_beta_60_250_one_session_lag|ordered_window_ema_5_10_20_50_100_200_1000_session_warmup|macd_12_26_9|adx_14_simple_average|stochastic_14_3_same_adjustment_episode|downside_vol_5_60|population_skew_kurtosis_60|amihud_turnover_proxy_20|gap_stats_20|rank_gaussian_tie_averaged_midrank|lagged_market_context|vnindex_sma50_200_drawdown252_vol60|vnindex_source_vci|vnindex_inherited_returns_vol20_vci|quarter_end_calendar_days|strict_full_window_cross_sectional_vol_rank|source_dependent_features_null_without_evidence')) d(definition)
    CROSS JOIN LATERAL (SELECT feat.phase2_feature_set_hash() AS base_hash) h
$$;

CREATE OR REPLACE VIEW feat.phase2_vci_index_features AS
WITH sessions AS MATERIALIZED (
    SELECT trade_date,row_number() OVER(ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), index_rows AS MATERIALIZED (
    SELECT s.trade_date,s.session_no,i.c AS index_close,
           lag(i.c) OVER(ORDER BY s.session_no) AS prior_close,
           CASE WHEN i.c>0 AND lag(i.c) OVER(ORDER BY s.session_no)>0
                THEN i.c/lag(i.c) OVER(ORDER BY s.session_no)-1 END AS index_return
    FROM sessions s
    LEFT JOIN core.index_bars i ON i.trade_date=s.trade_date
      AND i.index_symbol='VNINDEX' AND i.source='vci'
), windows AS MATERIALIZED (
    SELECT r.*,
           lag(r.index_close,20) OVER(ORDER BY r.session_no) AS close20,
           lag(r.index_close,60) OVER(ORDER BY r.session_no) AS close60,
           stddev_samp(r.index_return) OVER w20 AS vol20,
           count(r.index_return) OVER w20 AS return_count20
    FROM index_rows r
    WINDOW w20 AS (ORDER BY r.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW)
)
SELECT trade_date,session_no,
       CASE WHEN index_close>0 AND close20>0 THEN index_close/close20-1 END AS vnindex_return_20s,
       CASE WHEN index_close>0 AND close60>0 THEN index_close/close60-1 END AS vnindex_return_60s,
       CASE WHEN return_count20=20 THEN vol20 END AS vnindex_realized_vol20
FROM windows;

DO $phase2_vci_function_patch$
DECLARE
    definition text;
    old_text text;
    new_text text;
BEGIN
    definition:=pg_get_functiondef('feat.build_price_features_v3_internal(date,date)'::regprocedure);

    old_text:=$old$
    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_market_lagged ON COMMIT DROP AS
    SELECT 0::bigint AS session_no,NULL::bigint AS advance_minus_decline,
           NULL::bigint AS new_high_minus_low,NULL::double precision AS turnover_z20,
           NULL::double precision AS return_dispersion,NULL::double precision AS index_sma50_ratio,
           NULL::double precision AS index_sma200_ratio,NULL::double precision AS index_drawdown252,
           NULL::double precision AS vol60
    WHERE false;$old$;
    new_text:=$new$
    CREATE TEMP TABLE IF NOT EXISTS phase2_v3_market_lagged ON COMMIT DROP AS
    SELECT 0::bigint AS session_no,NULL::bigint AS advance_minus_decline,
           NULL::bigint AS new_high_minus_low,NULL::double precision AS turnover_z20,
           NULL::double precision AS return_dispersion,NULL::double precision AS index_sma50_ratio,
           NULL::double precision AS index_sma200_ratio,NULL::double precision AS index_drawdown252,
           NULL::double precision AS vol60,
           NULL::double precision AS vnindex_return_20s,
           NULL::double precision AS vnindex_return_60s,
           NULL::double precision AS vnindex_realized_vol20
    WHERE false;$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 market context temp-table declaration was not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    old_text:=$old$        SELECT i.*,
               avg(i.index_close) FILTER(WHERE i.index_close>0) OVER w50 AS index_sma50,$old$;
    new_text:=$new$        SELECT i.*,
               lag(i.index_close,20) OVER(ORDER BY i.session_no) AS close20,
               lag(i.index_close,60) OVER(ORDER BY i.session_no) AS close60,
               avg(i.index_close) FILTER(WHERE i.index_close>0) OVER w50 AS index_sma50,$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 index window input declaration was not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    old_text:=$old$               stddev_samp(i.index_return) OVER w60 AS vol60,
               count(i.index_return) OVER w60 AS return_count60,$old$;
    new_text:=$new$               stddev_samp(i.index_return) OVER w20 AS vol20,
               count(i.index_return) OVER w20 AS return_count20,
               stddev_samp(i.index_return) OVER w60 AS vol60,
               count(i.index_return) OVER w60 AS return_count60,$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 index return-window aggregates were not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    old_text:=$old$        WINDOW w50 AS (ORDER BY i.session_no ROWS BETWEEN 49 PRECEDING AND CURRENT ROW),
               w60 AS (ORDER BY i.session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),$old$;
    new_text:=$new$        WINDOW w20 AS (ORDER BY i.session_no ROWS BETWEEN 19 PRECEDING AND CURRENT ROW),
               w50 AS (ORDER BY i.session_no ROWS BETWEEN 49 PRECEDING AND CURRENT ROW),
               w60 AS (ORDER BY i.session_no ROWS BETWEEN 59 PRECEDING AND CURRENT ROW),$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 index window definitions were not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    old_text:=$old$           CASE WHEN i.close_count252=252 THEN i.index_close/i.high252-1 END AS index_drawdown252,
           CASE WHEN i.return_count60=60 THEN i.vol60 END AS vol60
    FROM sessions s
    LEFT JOIN market_daily_stats m ON m.session_no=s.session_no$old$;
    new_text:=$new$           CASE WHEN i.close_count252=252 THEN i.index_close/i.high252-1 END AS index_drawdown252,
           CASE WHEN i.return_count60=60 THEN i.vol60 END AS vol60,
           CASE WHEN i.index_close>0 AND i.close20>0 THEN i.index_close/i.close20-1 END AS vnindex_return_20s,
           CASE WHEN i.index_close>0 AND i.close60>0 THEN i.index_close/i.close60-1 END AS vnindex_return_60s,
           CASE WHEN i.return_count20=20 THEN i.vol20 END AS vnindex_realized_vol20
    FROM sessions s
    LEFT JOIN market_daily_stats m ON m.session_no=s.session_no$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 index context projection was not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    old_text:=$old$    INSERT INTO feat.features_daily
    SELECT * FROM pg_temp.phase2_v3_output;$old$;
    new_text:=$new$    UPDATE pg_temp.phase2_v3_output target
           SET vnindex_return_20s=ml.vnindex_return_20s,
               vnindex_return_60s=ml.vnindex_return_60s,
               vnindex_realized_vol20=ml.vnindex_realized_vol20
          FROM pg_temp.phase2_v3_sessions s
          LEFT JOIN pg_temp.phase2_v3_market_lagged ml ON ml.session_no=s.session_no-1
         WHERE target.trade_date=s.trade_date;

    INSERT INTO feat.features_daily
    SELECT * FROM pg_temp.phase2_v3_output;$new$;
    IF position(new_text IN definition)=0 THEN
        IF position(old_text IN definition)=0 THEN
            RAISE EXCEPTION 'V3 output insertion point was not found';
        END IF;
        definition:=replace(definition,old_text,new_text);
    END IF;

    IF position('vnindex_realized_vol20=ml.vnindex_realized_vol20' IN definition)=0 THEN
        RAISE EXCEPTION 'V3 builder patch did not add lagged VCI inherited fields';
    END IF;
    EXECUTE definition;
END;
$phase2_vci_function_patch$;

-- Keep the historical correction resumable: stage the small session-level
-- index context once, then let the operator commit bounded date ranges. A
-- migration transaction must never rewrite millions of V3 rows in one shot.
CREATE TABLE IF NOT EXISTS ops.phase2_vci_backfill_runs (
    build_id text PRIMARY KEY,
    status text NOT NULL CHECK(status IN ('building','prepared','complete')),
    context_rows bigint NOT NULL DEFAULT 0 CHECK(context_rows>=0),
    context_sha256 text CHECK(context_sha256 IS NULL OR context_sha256 ~ '^[0-9a-f]{64}$'),
    target_from date,
    target_to date,
    chunk_days integer CHECK(chunk_days IS NULL OR chunk_days BETWEEN 1 AND 30),
    expected_chunks integer CHECK(expected_chunks IS NULL OR expected_chunks>0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    prepared_at timestamptz,
    completed_at timestamptz,
    CHECK((status='complete')=(completed_at IS NOT NULL)),
    CHECK(status='building' OR
          (target_from IS NOT NULL AND target_to IS NOT NULL AND target_from<=target_to
           AND chunk_days IS NOT NULL AND expected_chunks IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS ops.phase2_vci_backfill_context (
    build_id text NOT NULL REFERENCES ops.phase2_vci_backfill_runs(build_id),
    trade_date date NOT NULL,
    session_no bigint NOT NULL,
    vnindex_return_20s double precision,
    vnindex_return_60s double precision,
    vnindex_realized_vol20 double precision,
    PRIMARY KEY(build_id,trade_date),
    UNIQUE(build_id,session_no)
);

CREATE TABLE IF NOT EXISTS ops.phase2_vci_backfill_chunks (
    build_id text NOT NULL REFERENCES ops.phase2_vci_backfill_runs(build_id),
    date_from date NOT NULL,
    date_to date NOT NULL,
    status text NOT NULL CHECK(status IN ('pending','running','done','failed')),
    attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
    rows bigint CHECK(rows IS NULL OR rows>=0),
    changed_rows bigint CHECK(changed_rows IS NULL OR changed_rows>=0),
    context_sha256 text NOT NULL CHECK(context_sha256 ~ '^[0-9a-f]{64}$'),
    output_sha256 text CHECK(output_sha256 IS NULL OR output_sha256 ~ '^[0-9a-f]{64}$'),
    started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    finished_at timestamptz,
    error text,
    PRIMARY KEY(build_id,date_from,date_to),
    CHECK(date_from<=date_to),
    CHECK(status IN ('pending','running')=(finished_at IS NULL)),
    CHECK(status<>'done' OR output_sha256 IS NOT NULL)
);

CREATE OR REPLACE FUNCTION ops.prepare_phase2_vci_backfill(
    p_build_id text,p_chunk_days integer DEFAULT 30
)
RETURNS TABLE(context_rows bigint,context_sha256 text,target_from date,target_to date,expected_chunks integer)
LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    v_status text;
    v_rows bigint;
    v_hash text;
    v_from date;
    v_to date;
    v_chunk_days integer;
    v_expected integer;
BEGIN
    IF p_build_id IS NULL OR p_build_id !~ '^[A-Za-z0-9._-]{1,100}$'
       OR p_chunk_days NOT BETWEEN 1 AND 30 THEN
        RAISE EXCEPTION 'invalid VCI backfill build id or chunk size';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('phase2-vci-backfill:'||p_build_id,0));

    INSERT INTO ops.phase2_vci_backfill_runs(build_id,status)
    VALUES(p_build_id,'building')
    ON CONFLICT(build_id) DO NOTHING;
    SELECT r.status,r.context_rows,r.context_sha256,r.target_from,r.target_to,
           r.chunk_days,r.expected_chunks
      INTO v_status,v_rows,v_hash,v_from,v_to,v_chunk_days,v_expected
      FROM ops.phase2_vci_backfill_runs r
     WHERE r.build_id=p_build_id
     FOR UPDATE;
    IF v_status IN ('prepared','complete') THEN
        IF v_chunk_days<>p_chunk_days THEN
            RAISE EXCEPTION 'build % was prepared with %-day chunks, not %',
                p_build_id,v_chunk_days,p_chunk_days;
        END IF;
        RETURN QUERY SELECT v_rows,v_hash,v_from,v_to,v_expected;
        RETURN;
    END IF;

    SELECT min(f.trade_date),max(f.trade_date) INTO v_from,v_to
      FROM feat.features_daily f WHERE f.feature_version='phase2-v3';
    IF v_from IS NULL OR v_to IS NULL THEN
        RAISE EXCEPTION 'no Phase 2 V3 rows exist for the VCI backfill';
    END IF;
    v_expected:=ceil((v_to-v_from+1)::numeric/p_chunk_days)::integer;

    WITH vci AS MATERIALIZED (
        SELECT trade_date,session_no,vnindex_return_20s,vnindex_return_60s,
               vnindex_realized_vol20
        FROM feat.phase2_vci_index_features
    )
    INSERT INTO ops.phase2_vci_backfill_context(
        build_id,trade_date,session_no,vnindex_return_20s,
        vnindex_return_60s,vnindex_realized_vol20
    )
    SELECT p_build_id,cur.trade_date,cur.session_no,
           prior.vnindex_return_20s,prior.vnindex_return_60s,
           prior.vnindex_realized_vol20
      FROM vci cur
      LEFT JOIN vci prior ON prior.session_no=cur.session_no-1;

    SELECT count(*),
           ops.phase2_hash_text(coalesce(string_agg(
               ops.phase2_hash_jsonb(to_jsonb(c)-'build_id'),E'\n' ORDER BY c.trade_date),''))
      INTO v_rows,v_hash
      FROM ops.phase2_vci_backfill_context c
     WHERE c.build_id=p_build_id;
    IF v_rows=0 THEN
        RAISE EXCEPTION 'VCI context staging produced no effective sessions';
    END IF;
    UPDATE ops.phase2_vci_backfill_runs r
       SET status='prepared',context_rows=v_rows,context_sha256=v_hash,
           target_from=v_from,target_to=v_to,chunk_days=p_chunk_days,
           expected_chunks=v_expected,prepared_at=clock_timestamp(),completed_at=NULL
     WHERE r.build_id=p_build_id;
    INSERT INTO ops.phase2_vci_backfill_chunks(
        build_id,date_from,date_to,status,context_sha256
    )
    SELECT p_build_id,d::date,least(d::date+(p_chunk_days-1),v_to),'pending',v_hash
      FROM generate_series(v_from::timestamp,v_to::timestamp,
                           make_interval(days=>p_chunk_days)) d
    ON CONFLICT(build_id,date_from,date_to) DO NOTHING;
    RETURN QUERY SELECT v_rows,v_hash,v_from,v_to,v_expected;
END;
$$;

CREATE OR REPLACE FUNCTION ops.backfill_phase2_vci_chunk(
    p_build_id text,p_date_from date,p_date_to date
)
RETURNS TABLE(rows bigint,changed_rows bigint,output_sha256 text)
LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    v_run_status text;
    v_context_sha text;
    v_rows bigint;
    v_changed bigint;
    v_hash text;
    v_missing bigint;
    v_chunk_status text;
BEGIN
    IF p_build_id IS NULL OR p_date_from IS NULL OR p_date_to IS NULL
       OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid build id and inclusive chunk date range required';
    END IF;
    SELECT r.status,r.context_sha256 INTO v_run_status,v_context_sha
      FROM ops.phase2_vci_backfill_runs r
     WHERE r.build_id=p_build_id
     FOR UPDATE;
    IF v_run_status NOT IN ('prepared','complete') OR v_context_sha IS NULL THEN
        RAISE EXCEPTION 'VCI backfill context must be prepared first';
    END IF;
    SELECT c.status,c.rows,c.changed_rows,c.output_sha256
      INTO v_chunk_status,v_rows,v_changed,v_hash
      FROM ops.phase2_vci_backfill_chunks c
     WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'chunk % through % was not planned for build %',
            p_date_from,p_date_to,p_build_id;
    END IF;
    IF v_chunk_status='done' THEN
        RETURN QUERY SELECT v_rows,v_changed,v_hash;
        RETURN;
    END IF;
    UPDATE ops.phase2_vci_backfill_chunks c
       SET status='running',attempts=c.attempts+1,rows=NULL,changed_rows=NULL,
           output_sha256=NULL,started_at=clock_timestamp(),finished_at=NULL,error=NULL
     WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to;
    /* The planned row is locked by the update above; re-fetch its immutable
       input identity to catch an accidental context replacement. */
    IF NOT EXISTS (
        SELECT 1 FROM ops.phase2_vci_backfill_chunks c
         WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to
           AND c.context_sha256=v_context_sha
    ) THEN
        RAISE EXCEPTION 'planned chunk context hash does not match its prepared run';
    END IF;

    SELECT count(*) INTO v_rows
      FROM feat.features_daily f
     WHERE f.feature_version='phase2-v3'
       AND f.trade_date BETWEEN p_date_from AND p_date_to;
    SELECT count(*) INTO v_missing
      FROM feat.features_daily f
     WHERE f.feature_version='phase2-v3'
       AND f.trade_date BETWEEN p_date_from AND p_date_to
       AND NOT EXISTS (
           SELECT 1 FROM ops.phase2_vci_backfill_context c
            WHERE c.build_id=p_build_id AND c.trade_date=f.trade_date
       );
    IF v_missing>0 THEN
        RAISE EXCEPTION 'VCI context is missing for % V3 feature rows',v_missing;
    END IF;

    UPDATE feat.features_daily f
       SET vnindex_return_20s=c.vnindex_return_20s,
           vnindex_return_60s=c.vnindex_return_60s,
           vnindex_realized_vol20=c.vnindex_realized_vol20,
           feature_set_hash=feat.phase2_feature_set_hash_v3()
      FROM ops.phase2_vci_backfill_context c
     WHERE c.build_id=p_build_id
       AND c.trade_date=f.trade_date
       AND f.feature_version='phase2-v3'
       AND f.trade_date BETWEEN p_date_from AND p_date_to
       AND ROW(f.vnindex_return_20s,f.vnindex_return_60s,
               f.vnindex_realized_vol20,f.feature_set_hash)
           IS DISTINCT FROM
           ROW(c.vnindex_return_20s,c.vnindex_return_60s,
               c.vnindex_realized_vol20,feat.phase2_feature_set_hash_v3());
    GET DIAGNOSTICS v_changed=ROW_COUNT;

    v_hash:=ops.phase2_chunk_output_hash('features',p_date_from,p_date_to);
    UPDATE ops.phase2_vci_backfill_chunks c
       SET status='done',rows=v_rows,changed_rows=v_changed,output_sha256=v_hash,
           finished_at=clock_timestamp(),error=NULL
     WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to;
    UPDATE ops.phase2_vci_backfill_runs r
       SET status=CASE WHEN NOT EXISTS (
               SELECT 1 FROM ops.phase2_vci_backfill_chunks c
                WHERE c.build_id=p_build_id AND c.status<>'done'
           ) AND (SELECT count(*) FROM ops.phase2_vci_backfill_chunks c
                   WHERE c.build_id=p_build_id)=r.expected_chunks
           THEN 'complete' ELSE 'prepared' END,
           completed_at=CASE WHEN NOT EXISTS (
               SELECT 1 FROM ops.phase2_vci_backfill_chunks c
                WHERE c.build_id=p_build_id AND c.status<>'done'
           ) AND (SELECT count(*) FROM ops.phase2_vci_backfill_chunks c
                   WHERE c.build_id=p_build_id)=r.expected_chunks
           THEN clock_timestamp() ELSE NULL END
     WHERE r.build_id=p_build_id;
    RETURN QUERY SELECT v_rows,v_changed,v_hash;
END;
$$;

CREATE OR REPLACE FUNCTION ops.fail_phase2_vci_chunk(
    p_build_id text,p_date_from date,p_date_to date,p_error text
)
RETURNS void LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    v_context_sha text;
    v_chunk_status text;
BEGIN
    SELECT context_sha256 INTO v_context_sha
      FROM ops.phase2_vci_backfill_runs WHERE build_id=p_build_id FOR UPDATE;
    IF v_context_sha IS NULL THEN
        RAISE EXCEPTION 'VCI backfill context is not prepared';
    END IF;
    SELECT status INTO v_chunk_status
      FROM ops.phase2_vci_backfill_chunks
     WHERE build_id=p_build_id AND date_from=p_date_from AND date_to=p_date_to
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'chunk % through % was not planned for build %',
            p_date_from,p_date_to,p_build_id;
    END IF;
    IF v_chunk_status='done' THEN RETURN; END IF;
    UPDATE ops.phase2_vci_backfill_chunks c
       SET status='failed',attempts=c.attempts+1,rows=NULL,changed_rows=NULL,
           output_sha256=NULL,finished_at=clock_timestamp(),
           error=left(coalesce(p_error,'unknown error'),4000)
     WHERE c.build_id=p_build_id AND c.date_from=p_date_from AND c.date_to=p_date_to;
    UPDATE ops.phase2_vci_backfill_runs SET status='prepared',completed_at=NULL
     WHERE build_id=p_build_id;
END;
$$;

COMMENT ON VIEW feat.phase2_vci_index_features IS
    'VCI VNINDEX returns and realized volatility by effective session; stock features consume the prior session values.';
COMMENT ON FUNCTION feat.phase2_feature_set_hash_v3() IS
    'Phase 2 V3 feature contract including lagged VCI VNINDEX context and inherited 20/60-session returns and 20-session volatility.';
COMMENT ON TABLE ops.phase2_vci_backfill_context IS
    'Frozen session-level one-session-lagged VCI context used to repair existing V3 rows in bounded, resumable date chunks.';
COMMENT ON TABLE ops.phase2_vci_backfill_chunks IS
    'Durable attempt, row-count, context-hash, and output-hash evidence for each bounded VCI V3 repair chunk.';

COMMIT;

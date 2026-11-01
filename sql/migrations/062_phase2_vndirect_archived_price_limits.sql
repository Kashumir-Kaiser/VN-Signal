-- Project exact, archive-backed VNDIRECT price limits from the same immutable
-- Finfo rows already linked to daily bars. Historical availability begins at
-- the archive fetch time; no exchange-band percentage is inferred.
BEGIN;

CREATE INDEX IF NOT EXISTS daily_price_limit_observations_symbol_date_source_idx
    ON core.daily_price_limit_observations(symbol_id,trade_date,source,available_at DESC);

CREATE OR REPLACE FUNCTION core.verify_phase2_source_input_lineage()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    landing raw.landings%ROWTYPE;
    expected_symbol text;
    landing_rows jsonb;
    linked_bar boolean;
BEGIN
    SELECT * INTO landing FROM raw.landings WHERE landing_id=NEW.raw_landing_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'source observation raw landing does not exist'; END IF;
    IF NEW.source IS DISTINCT FROM landing.source OR NEW.fetched_at IS DISTINCT FROM landing.fetched_at THEN
        RAISE EXCEPTION 'source observation source/fetched_at must match raw landing';
    END IF;
    IF NEW.available_at < NEW.fetched_at THEN
        RAISE EXCEPTION 'source observation cannot be available before it was fetched';
    END IF;
    IF TG_TABLE_NAME <> 'calendar_event_observations' THEN
        SELECT symbol INTO expected_symbol FROM core.symbols WHERE symbol_id=NEW.symbol_id;
        IF expected_symbol IS DISTINCT FROM upper(landing.symbol) THEN
            RAISE EXCEPTION 'source observation symbol does not match raw landing';
        END IF;
    END IF;

    -- VNDIRECT Finfo history uses a top-level data[] body. Other Phase 2
    -- observation adapters keep the rows[] envelope checked by migration 036.
    IF TG_TABLE_NAME='daily_price_limit_observations'
       AND landing.source='vndirect' AND landing.route='equity_ohlcv' THEN
        landing_rows := landing.payload->'data';
    ELSE
        landing_rows := landing.payload->'rows';
    END IF;
    IF landing_rows IS NULL OR jsonb_typeof(landing_rows) <> 'array' THEN
        RAISE EXCEPTION 'raw landing must contain the expected observation array';
    END IF;
    IF NEW.source_row >= jsonb_array_length(landing_rows) OR
       landing_rows->NEW.source_row IS DISTINCT FROM NEW.row_payload THEN
        RAISE EXCEPTION 'source_row/row_payload do not match raw landing';
    END IF;

    IF TG_TABLE_NAME='daily_price_limit_observations'
       AND landing.source='vndirect' AND landing.route='equity_ohlcv' THEN
        IF NEW.available_at IS DISTINCT FROM landing.fetched_at THEN
            RAISE EXCEPTION 'VNDIRECT archived price-limit availability must equal landing fetched_at';
        END IF;
        IF NEW.row_payload->>'code' IS DISTINCT FROM expected_symbol
           OR NEW.row_payload->>'date' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD') THEN
            RAISE EXCEPTION 'VNDIRECT price-limit row code/date does not match observation key';
        END IF;
        IF jsonb_typeof(NEW.row_payload->'ceilingPrice') IS DISTINCT FROM 'number'
           OR jsonb_typeof(NEW.row_payload->'floorPrice') IS DISTINCT FROM 'number' THEN
            RAISE EXCEPTION 'VNDIRECT price-limit row must contain numeric ceilingPrice/floorPrice';
        END IF;
        IF NEW.limit_up IS DISTINCT FROM (NEW.row_payload->>'ceilingPrice')::numeric
           OR NEW.limit_down IS DISTINCT FROM (NEW.row_payload->>'floorPrice')::numeric THEN
            RAISE EXCEPTION 'VNDIRECT price-limit values must equal the archived source row';
        END IF;
        SELECT EXISTS (
            SELECT 1 FROM core.bars_daily_sources b
             WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
               AND b.source='vndirect' AND b.landing_id=NEW.raw_landing_id
               AND b.source_row=NEW.source_row
        ) INTO linked_bar;
        IF NOT linked_bar THEN
            RAISE EXCEPTION 'VNDIRECT price-limit row must link to its exact daily bar source row';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION core.materialize_vndirect_daily_price_limits(
    p_date_from date,
    p_date_to date,
    p_symbol_ids bigint[]
)
RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_inserted bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to<p_date_from THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF p_date_to-p_date_from>30 THEN
        RAISE EXCEPTION 'price-limit materialization is limited to 31 calendar days per call';
    END IF;
    IF p_symbol_ids IS NULL OR cardinality(p_symbol_ids)=0 OR cardinality(p_symbol_ids)>100 THEN
        RAISE EXCEPTION 'provide 1 to 100 symbol IDs per price-limit materialization call';
    END IF;

    -- Keep this batch's exact source rows available for both the conflict
    -- comparison and insert, without expanding each archived landing twice.
    CREATE TEMP TABLE IF NOT EXISTS phase2_vndirect_price_limit_candidates (
        symbol_id bigint NOT NULL,
        source text NOT NULL,
        trade_date date NOT NULL,
        limit_up numeric(20,6) NOT NULL,
        limit_down numeric(20,6) NOT NULL,
        available_at timestamptz NOT NULL,
        fetched_at timestamptz NOT NULL,
        raw_landing_id bigint NOT NULL,
        source_row integer NOT NULL,
        row_payload jsonb NOT NULL,
        PRIMARY KEY (raw_landing_id,source_row)
    ) ON COMMIT DROP;
    TRUNCATE TABLE pg_temp.phase2_vndirect_price_limit_candidates;

    WITH candidate_landings AS MATERIALIZED (
        SELECT DISTINCT b.landing_id
          FROM core.bars_daily_sources b
         WHERE b.source='vndirect'
           AND b.trade_date BETWEEN p_date_from AND p_date_to
           AND b.symbol_id=ANY(p_symbol_ids)
    ), archived AS MATERIALIZED (
        -- Fetch each candidate archive body once per bounded symbol/date chunk.
        SELECT l.landing_id,l.source,l.route,l.fetched_at,l.symbol,
               l.payload->'data' AS data_rows
          FROM candidate_landings c
          JOIN raw.landings l USING(landing_id)
         WHERE l.source='vndirect' AND l.route='equity_ohlcv'
           AND jsonb_typeof(l.payload->'data')='array'
    ), exact_rows AS MATERIALIZED (
        SELECT b.symbol_id,b.trade_date,b.source,b.landing_id,b.source_row,
               s.symbol,a.fetched_at,a.symbol AS landing_symbol,
               a.data_rows->b.source_row AS row_payload
          FROM core.bars_daily_sources b
          JOIN archived a USING(landing_id)
          JOIN core.symbols s USING(symbol_id)
         WHERE b.source='vndirect'
           AND b.trade_date BETWEEN p_date_from AND p_date_to
           AND b.symbol_id=ANY(p_symbol_ids)
    ), valid_rows AS (
        SELECT symbol_id,trade_date,source,landing_id,source_row,fetched_at,row_payload,
               CASE WHEN jsonb_typeof(row_payload->'ceilingPrice')='number'
                    THEN (row_payload->>'ceilingPrice')::numeric END AS limit_up,
               CASE WHEN jsonb_typeof(row_payload->'floorPrice')='number'
                    THEN (row_payload->>'floorPrice')::numeric END AS limit_down
          FROM exact_rows
         WHERE jsonb_typeof(row_payload)='object'
           AND landing_symbol=upper(symbol)
           AND row_payload->>'code'=symbol
           AND row_payload->>'date'=to_char(trade_date,'YYYY-MM-DD')
           AND jsonb_typeof(row_payload->'ceilingPrice')='number'
           AND jsonb_typeof(row_payload->'floorPrice')='number'
    )
    INSERT INTO pg_temp.phase2_vndirect_price_limit_candidates(
        symbol_id,source,trade_date,limit_up,limit_down,
        available_at,fetched_at,raw_landing_id,source_row,row_payload
    )
    SELECT symbol_id,source,trade_date,limit_up,limit_down,
           fetched_at,fetched_at,landing_id,source_row,row_payload
      FROM valid_rows
     WHERE limit_up>0 AND limit_down>0 AND limit_up>=limit_down;

    IF EXISTS (
        SELECT 1
          FROM pg_temp.phase2_vndirect_price_limit_candidates c
          JOIN core.daily_price_limit_observations o
            USING (raw_landing_id,source_row)
         WHERE ROW(o.symbol_id,o.source,o.trade_date,o.limit_up,o.limit_down,
                   o.available_at,o.fetched_at,o.row_payload)
               IS DISTINCT FROM
               ROW(c.symbol_id,c.source,c.trade_date,c.limit_up,c.limit_down,
                   c.available_at,c.fetched_at,c.row_payload)
    ) THEN
        RAISE EXCEPTION 'existing VNDIRECT price-limit observation conflicts with archived source row';
    END IF;

    -- Equal conflicts are a no-op. If a concurrent writer inserts divergent
    -- content after the comparison above, the append-only update trigger
    -- rejects the attempted conflict update instead of silently hiding it.
    INSERT INTO core.daily_price_limit_observations AS target (
        symbol_id,source,trade_date,limit_up,limit_down,
        available_at,fetched_at,raw_landing_id,source_row,row_payload
    )
    SELECT symbol_id,source,trade_date,limit_up,limit_down,
           available_at,fetched_at,raw_landing_id,source_row,row_payload
      FROM pg_temp.phase2_vndirect_price_limit_candidates
    ON CONFLICT(raw_landing_id,source_row) DO UPDATE
       SET row_payload=EXCLUDED.row_payload
     WHERE ROW(target.symbol_id,target.source,target.trade_date,target.limit_up,target.limit_down,
               target.available_at,target.fetched_at,target.row_payload)
           IS DISTINCT FROM
           ROW(EXCLUDED.symbol_id,EXCLUDED.source,EXCLUDED.trade_date,EXCLUDED.limit_up,EXCLUDED.limit_down,
               EXCLUDED.available_at,EXCLUDED.fetched_at,EXCLUDED.row_payload);

    GET DIAGNOSTICS v_inserted=ROW_COUNT;
    TRUNCATE TABLE pg_temp.phase2_vndirect_price_limit_candidates;
    RETURN v_inserted;
END;
$$;

COMMENT ON FUNCTION core.materialize_vndirect_daily_price_limits(date,date,bigint[]) IS
    'Materializes exact ceilingPrice/floorPrice observations from VNDIRECT Finfo data[] rows linked by core.bars_daily_sources source_row. Each call is bounded to 31 calendar days and at most 100 symbols; available_at is the immutable landing fetched_at. Existing rows are compared across all linked observation fields and divergent conflicts raise an error.';

COMMIT;

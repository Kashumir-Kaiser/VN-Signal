-- Add a strict, retrospective BSC fallback for exact daily price limits.
-- BSC limit values remain separate source evidence and are admitted only when
-- its reported close and matched volume exactly agree with the VNDIRECT bar.
-- These observations are label outcomes and are never feature inputs.
BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

CREATE OR REPLACE FUNCTION core.phase2_bsc_history_cell_text(
    p_row_html text,
    p_cell_index integer
)
RETURNS text
LANGUAGE plpgsql IMMUTABLE STRICT AS $bsc_history_cell_text$
DECLARE
    v_index integer:=0;
    v_search integer:=1;
    v_cell integer;
    v_open_end integer;
    v_close integer;
    v_lower_html text:=lower(p_row_html);
    v_text text;
BEGIN
    IF p_cell_index<0 THEN RETURN NULL; END IF;
    LOOP
        v_cell:=strpos(substring(v_lower_html from v_search),'<td');
        IF v_cell=0 THEN RETURN NULL; END IF;
        v_cell:=v_search+v_cell-1;
        v_open_end:=strpos(substring(p_row_html from v_cell),'>');
        IF v_open_end=0 THEN RETURN NULL; END IF;
        v_open_end:=v_cell+v_open_end-1;
        v_close:=strpos(substring(v_lower_html from v_open_end+1),'</td>');
        IF v_close=0 THEN RETURN NULL; END IF;
        v_close:=v_open_end+v_close;
        IF v_index=p_cell_index THEN
            v_text:=substring(p_row_html from v_open_end+1 for v_close-v_open_end-1);
            v_text:=regexp_replace(v_text,'<[^>]*>','','g');
            v_text:=regexp_replace(v_text,'&nbsp;|&#160;|&#x0*a0;',' ','gi');
            v_text:=replace(v_text,'&amp;','&');
            RETURN btrim(regexp_replace(v_text,'[[:space:]]+',' ','g'));
        END IF;
        v_index:=v_index+1;
        v_search:=v_close+length('</td>');
    END LOOP;
END;
$bsc_history_cell_text$;

CREATE OR REPLACE FUNCTION core.verify_phase2_source_input_lineage()
RETURNS trigger
LANGUAGE plpgsql AS $phase2_source_input_lineage_106$
DECLARE
    landing raw.landings%ROWTYPE;
    expected_symbol text;
    landing_rows jsonb;
    response_html text;
    source_row_html text;
    source_cells jsonb;
    v_close_vnd numeric;
    v_volume numeric;
    v_reference_vnd numeric;
    v_ceiling_vnd numeric;
    v_floor_vnd numeric;
    v_bar_count bigint;
    v_bar_landing_id bigint;
    v_bar_source_row integer;
    v_bar_payload_sha256 text;
    v_bar_row jsonb;
    v_bar_open numeric;
    v_bar_high numeric;
    v_bar_low numeric;
    v_bar_close numeric;
    v_bar_volume numeric;
    v_raw_open numeric;
    v_raw_high numeric;
    v_raw_low numeric;
    v_raw_close numeric;
    v_raw_volume numeric;
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

    -- VNDIRECT Finfo history uses data[]; BSC's captured AJAX source uses a
    -- separate normalized rows[] envelope around the exact archived response.
    IF TG_TABLE_NAME='daily_price_limit_observations'
       AND landing.source='vndirect' AND landing.route='equity_ohlcv' THEN
        landing_rows:=landing.payload->'data';
    ELSE
        landing_rows:=landing.payload->'rows';
    END IF;
    IF landing_rows IS NULL OR jsonb_typeof(landing_rows)<>'array' THEN
        RAISE EXCEPTION 'raw landing must contain the expected observation array';
    END IF;
    IF NEW.source_row>=jsonb_array_length(landing_rows) OR
       landing_rows->NEW.source_row IS DISTINCT FROM NEW.row_payload THEN
        RAISE EXCEPTION 'source_row/row_payload do not match raw landing';
    END IF;

    IF TG_TABLE_NAME='daily_price_limit_observations'
       AND landing.source='bsc' AND landing.route<>'historical_data_ajax' THEN
        RAISE EXCEPTION 'BSC price-limit observations require the exact historical-data AJAX route';
    END IF;
    IF TG_TABLE_NAME='daily_price_limit_observations'
       AND landing.source='bsc' AND landing.route='historical_data_ajax' THEN
        IF NEW.available_at IS DISTINCT FROM landing.fetched_at THEN
            RAISE EXCEPTION 'BSC archived price-limit availability must equal landing fetched_at';
        END IF;
        IF landing.payload_bytes IS NULL OR octet_length(landing.payload_bytes)<2
           OR octet_length(landing.payload_bytes)>10485760
           OR encode(sha256(landing.payload_bytes),'hex')<>lower(landing.payload_sha256) THEN
            RAISE EXCEPTION 'BSC raw response bytes do not match their archived SHA-256';
        END IF;
        IF ops.phase2_try_jsonb_bytes(landing.payload_bytes)
           IS DISTINCT FROM landing.payload->'response' THEN
            RAISE EXCEPTION 'BSC parsed source response does not match its exact archived bytes';
        END IF;
        IF landing.payload->'request'->>'action' IS DISTINCT FROM 'filter_du_lieu_lich_su'
           OR landing.payload->'request'->>'mck' IS DISTINCT FROM expected_symbol
           OR landing.payload->'request'->>'fromdate' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD')
           OR landing.payload->'request'->>'todate' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD')
           OR landing.payload->'request'->>'type_form' IS DISTINCT FROM 'history'
           OR (landing.payload->'request' ? 'security')
           OR landing.payload->>'request_url' IS DISTINCT FROM 'https://www.bsc.com.vn/wp-admin/admin-ajax.php'
           OR landing.payload->>'source_page_url' IS DISTINCT FROM
              'https://www.bsc.com.vn/en/historical-data/?mck='||expected_symbol THEN
            RAISE EXCEPTION 'BSC source request metadata does not match the symbol/date or contains a nonce';
        END IF;
        IF jsonb_typeof(landing.payload->'response') IS DISTINCT FROM 'object'
           OR landing.payload->'response'->'success' IS DISTINCT FROM 'true'::jsonb
           OR jsonb_typeof(landing.payload->'response'->'data'->'html') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'BSC source response is not a successful historical table response';
        END IF;
        IF jsonb_array_length(landing_rows)<>1 OR NEW.source_row<>0 THEN
            RAISE EXCEPTION 'BSC exact-date response must contain exactly one source row at ordinal zero';
        END IF;

        source_row_html:=NEW.row_payload->>'source_row_html';
        source_cells:=NEW.row_payload->'source_cells';
        response_html:=landing.payload->'response'->'data'->>'html';
        IF source_row_html IS NULL OR source_row_html=''
           OR position(source_row_html IN response_html)=0 THEN
            RAISE EXCEPTION 'BSC normalized source row is not present in the archived response HTML';
        END IF;
        IF jsonb_typeof(source_cells) IS DISTINCT FROM 'array' THEN
            RAISE EXCEPTION 'BSC normalized source row must retain all ten source cells';
        END IF;
        IF jsonb_array_length(source_cells)<>10 THEN
            RAISE EXCEPTION 'BSC historical source row must contain exactly ten cells';
        END IF;
        IF NEW.row_payload->>'code' IS DISTINCT FROM expected_symbol
           OR NEW.row_payload->>'trade_date' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD')
           OR core.phase2_bsc_history_cell_text(source_row_html,0)
                IS DISTINCT FROM to_char(NEW.trade_date,'DD/MM/YYYY') THEN
            RAISE EXCEPTION 'BSC historical row symbol/date does not match its observation key';
        END IF;

        v_close_vnd:=(NEW.row_payload->>'close_price_vnd')::numeric;
        v_volume:=(NEW.row_payload->>'matched_volume_shares')::numeric;
        v_reference_vnd:=(NEW.row_payload->>'reference_price_vnd')::numeric;
        v_ceiling_vnd:=(NEW.row_payload->>'ceiling_price_vnd')::numeric;
        v_floor_vnd:=(NEW.row_payload->>'floor_price_vnd')::numeric;
        IF v_close_vnd<=0 OR v_volume<0 OR v_reference_vnd<=0
           OR v_ceiling_vnd<=0 OR v_floor_vnd<=0 OR v_ceiling_vnd<v_floor_vnd
           OR NEW.limit_up IS DISTINCT FROM v_ceiling_vnd/1000
           OR NEW.limit_down IS DISTINCT FROM v_floor_vnd/1000 THEN
            RAISE EXCEPTION 'BSC price-limit values must equal the source-reported bounds in VND per share';
        END IF;
        IF regexp_replace(core.phase2_bsc_history_cell_text(source_row_html,1),'[,[:space:]]','','g')::numeric
                IS DISTINCT FROM v_close_vnd
           OR regexp_replace(core.phase2_bsc_history_cell_text(source_row_html,3),'[,[:space:]]','','g')::numeric
                IS DISTINCT FROM v_volume
           OR regexp_replace(core.phase2_bsc_history_cell_text(source_row_html,7),'[,[:space:]]','','g')::numeric
                IS DISTINCT FROM v_reference_vnd
           OR regexp_replace(core.phase2_bsc_history_cell_text(source_row_html,8),'[,[:space:]]','','g')::numeric
                IS DISTINCT FROM v_ceiling_vnd
           OR regexp_replace(core.phase2_bsc_history_cell_text(source_row_html,9),'[,[:space:]]','','g')::numeric
                IS DISTINCT FROM v_floor_vnd THEN
            RAISE EXCEPTION 'BSC normalized close, volume, reference, or limits differ from the exact source-row HTML';
        END IF;
        IF source_cells->>0 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,0)
           OR source_cells->>1 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,1)
           OR source_cells->>3 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,3)
           OR source_cells->>7 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,7)
           OR source_cells->>8 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,8)
           OR source_cells->>9 IS DISTINCT FROM core.phase2_bsc_history_cell_text(source_row_html,9) THEN
            RAISE EXCEPTION 'BSC retained source cells differ from the exact archived HTML row';
        END IF;

        IF EXISTS (
            SELECT 1 FROM core.daily_price_limit_observations prior
             WHERE prior.symbol_id=NEW.symbol_id AND prior.trade_date=NEW.trade_date
               AND prior.source='vndirect'
        ) THEN
            RAISE EXCEPTION 'BSC fallback is not admitted when any VNDIRECT limit observation exists';
        END IF;

        IF coalesce(landing.payload->'validation'->>'vndirect_landing_id','') !~ '^[0-9]+$'
           OR coalesce(landing.payload->'validation'->>'vndirect_source_row','') !~ '^[0-9]+$'
           OR coalesce(landing.payload->'validation'->>'vndirect_payload_sha256','') !~ '^[0-9a-f]{64}$' THEN
            RAISE EXCEPTION 'BSC capture does not retain its VNDIRECT bar-lineage keys';
        END IF;
        SELECT count(*) INTO v_bar_count
          FROM core.bars_daily_sources_ml_eligible b
          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
         WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
           AND b.source='vndirect' AND b.adj_basis='unadjusted'
           AND b.landing_id=(landing.payload->'validation'->>'vndirect_landing_id')::bigint
           AND b.source_row=(landing.payload->'validation'->>'vndirect_source_row')::integer
           AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
           AND bar_l.payload_sha256=(landing.payload->'validation'->>'vndirect_payload_sha256')
           AND bar_l.payload_sha256 ~ '^[0-9a-f]{64}$'
           AND bar_l.payload_bytes IS NOT NULL
           AND encode(sha256(bar_l.payload_bytes),'hex')=lower(bar_l.payload_sha256)
           AND ops.phase2_try_jsonb_bytes(bar_l.payload_bytes)=bar_l.payload
           AND jsonb_typeof(bar_l.payload->'data')='array';
        IF v_bar_count<>1 THEN
            RAISE EXCEPTION 'BSC row does not reference exactly one eligible unadjusted VNDIRECT bar';
        END IF;
        SELECT bar_l.payload->'data'->b.source_row,b.landing_id,b.source_row,
               bar_l.payload_sha256,b.o::numeric,b.h::numeric,b.l::numeric,b.c::numeric,b.v::numeric
          INTO v_bar_row,v_bar_landing_id,v_bar_source_row,v_bar_payload_sha256,
               v_bar_open,v_bar_high,v_bar_low,v_bar_close,v_bar_volume
          FROM core.bars_daily_sources_ml_eligible b
          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
         WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
           AND b.source='vndirect' AND b.adj_basis='unadjusted'
           AND b.landing_id=(landing.payload->'validation'->>'vndirect_landing_id')::bigint
           AND b.source_row=(landing.payload->'validation'->>'vndirect_source_row')::integer
           AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
         LIMIT 1;
        v_raw_open:=(v_bar_row->>'open')::numeric;
        v_raw_high:=(v_bar_row->>'high')::numeric;
        v_raw_low:=(v_bar_row->>'low')::numeric;
        v_raw_close:=(v_bar_row->>'close')::numeric;
        v_raw_volume:=(v_bar_row->>'nmVolume')::numeric;
        IF v_bar_row->>'code' IS DISTINCT FROM expected_symbol
           OR v_bar_row->>'date' IS DISTINCT FROM to_char(NEW.trade_date,'YYYY-MM-DD')
           OR v_bar_payload_sha256 IS DISTINCT FROM landing.payload->'validation'->>'vndirect_payload_sha256'
           OR v_raw_close*1000 IS DISTINCT FROM v_close_vnd
           OR v_raw_volume IS DISTINCT FROM v_volume
           OR v_bar_close IS DISTINCT FROM v_raw_close
           OR v_bar_open IS DISTINCT FROM v_raw_open
           OR v_bar_high IS DISTINCT FROM v_raw_high
           OR v_bar_low IS DISTINCT FROM v_raw_low THEN
            RAISE EXCEPTION 'BSC close/matched volume does not exactly reconcile to its VNDIRECT raw bar row';
        END IF;
        IF v_raw_close IS NULL OR v_raw_open IS NULL OR v_raw_high IS NULL OR v_raw_low IS NULL
           OR v_raw_volume IS NULL OR v_bar_open<=0 OR v_bar_high<=0 OR v_bar_low<=0 OR v_bar_close<=0
           OR v_bar_volume IS DISTINCT FROM v_volume THEN
            RAISE EXCEPTION 'BSC matched VNDIRECT bar does not contain exact positive OHLC and matching volume';
        END IF;
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
        IF NOT EXISTS (
            SELECT 1 FROM core.bars_daily_sources b
             WHERE b.symbol_id=NEW.symbol_id AND b.trade_date=NEW.trade_date
               AND b.source='vndirect' AND b.landing_id=NEW.raw_landing_id
               AND b.source_row=NEW.source_row
        ) THEN
            RAISE EXCEPTION 'VNDIRECT price-limit row must link to its exact daily bar source row';
        END IF;
    END IF;
    RETURN NEW;
END;
$phase2_source_input_lineage_106$;

CREATE OR REPLACE FUNCTION core.materialize_bsc_daily_price_limits(
    p_date_from date,
    p_date_to date,
    p_symbol_ids bigint[]
)
RETURNS bigint
LANGUAGE plpgsql AS $materialize_bsc_daily_price_limits$
DECLARE
    v_inserted bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_to<p_date_from THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF p_date_to-p_date_from>30 THEN
        RAISE EXCEPTION 'BSC price-limit materialization is limited to 31 calendar days per call';
    END IF;
    IF p_symbol_ids IS NULL OR cardinality(p_symbol_ids)=0 OR cardinality(p_symbol_ids)>100
       OR array_position(p_symbol_ids,NULL) IS NOT NULL THEN
        RAISE EXCEPTION 'provide 1 to 100 non-null symbol IDs per BSC materialization call';
    END IF;

    DROP TABLE IF EXISTS pg_temp.phase2_bsc_price_limit_candidates_106;
    CREATE TEMP TABLE phase2_bsc_price_limit_candidates_106 (
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
        PRIMARY KEY(raw_landing_id,source_row),
        UNIQUE(symbol_id,trade_date)
    ) ON COMMIT DROP;

    INSERT INTO pg_temp.phase2_bsc_price_limit_candidates_106(
        symbol_id,source,trade_date,limit_up,limit_down,
        available_at,fetched_at,raw_landing_id,source_row,row_payload
    )
    SELECT s.symbol_id,'bsc',(r.row_payload->>'trade_date')::date,
           ((r.row_payload->>'ceiling_price_vnd')::numeric/1000)::numeric(20,6),
           ((r.row_payload->>'floor_price_vnd')::numeric/1000)::numeric(20,6),
           l.fetched_at,l.fetched_at,l.landing_id,(r.ordinality-1)::integer,r.row_payload
      FROM raw.landings l
      JOIN core.symbols s ON s.symbol=upper(l.symbol)
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') WITH ORDINALITY AS r(row_payload,ordinality)
     WHERE l.source='bsc' AND l.route='historical_data_ajax'
       AND s.symbol_id=ANY(p_symbol_ids)
       AND (l.payload->'request'->>'fromdate')::date BETWEEN p_date_from AND p_date_to
       AND (l.payload->'request'->>'todate')::date BETWEEN p_date_from AND p_date_to;

    IF EXISTS (
        SELECT 1
          FROM pg_temp.phase2_bsc_price_limit_candidates_106 c
          JOIN core.daily_price_limit_observations o USING(raw_landing_id,source_row)
         WHERE ROW(o.symbol_id,o.source,o.trade_date,o.limit_up,o.limit_down,
                   o.available_at,o.fetched_at,o.row_payload)
               IS DISTINCT FROM
               ROW(c.symbol_id,c.source,c.trade_date,c.limit_up,c.limit_down,
                   c.available_at,c.fetched_at,c.row_payload)
    ) THEN
        RAISE EXCEPTION 'existing BSC price-limit observation conflicts with its archived source row';
    END IF;

    INSERT INTO core.daily_price_limit_observations(
        symbol_id,source,trade_date,limit_up,limit_down,
        available_at,fetched_at,raw_landing_id,source_row,row_payload
    )
    SELECT symbol_id,source,trade_date,limit_up,limit_down,
           available_at,fetched_at,raw_landing_id,source_row,row_payload
      FROM pg_temp.phase2_bsc_price_limit_candidates_106
    ON CONFLICT(raw_landing_id,source_row) DO NOTHING;
    GET DIAGNOSTICS v_inserted=ROW_COUNT;
    RETURN v_inserted;
END;
$materialize_bsc_daily_price_limits$;

COMMENT ON FUNCTION core.materialize_bsc_daily_price_limits(date,date,bigint[]) IS
    'Materializes source-reported BSC ceiling/floor fields after exact row, hash, timestamp, close, matched-volume, and VNDIRECT bar-lineage checks. Bounded to 31 calendar days and 100 symbols per call; BSC remains a separate retrospective label-evidence source.';

CREATE INDEX IF NOT EXISTS daily_price_limit_observations_symbol_date_source_idx
    ON core.daily_price_limit_observations(symbol_id,trade_date,source);

CREATE OR REPLACE FUNCTION core.phase2_execution_limit_evidence_for_day(
    p_symbol_id bigint,
    p_trade_date date
)
RETURNS TABLE (
    observation_id bigint,
    symbol_id bigint,
    trade_date date,
    source text,
    limit_up numeric,
    limit_down numeric,
    available_at timestamptz,
    fetched_at timestamptz,
    evidence_landing_id bigint,
    evidence_source_row integer,
    evidence_row_payload jsonb,
    evidence_payload_sha256 text,
    bar_landing_id bigint,
    bar_source_row integer,
    bar_payload_sha256 text,
    raw_bar_row jsonb,
    bar_open double precision,
    bar_high double precision,
    bar_low double precision,
    bar_close double precision,
    bar_volume double precision
)
LANGUAGE sql STABLE AS $phase2_execution_limit_evidence_for_day_106$
WITH vndirect AS (
    SELECT p.observation_id,p.symbol_id,p.trade_date,p.source,p.limit_up,p.limit_down,
           p.available_at,p.fetched_at,p.raw_landing_id AS evidence_landing_id,
           p.source_row AS evidence_source_row,p.row_payload AS evidence_row_payload,
           limits_l.payload_sha256 AS evidence_payload_sha256,
           b.landing_id AS bar_landing_id,b.source_row AS bar_source_row,
           bar_l.payload_sha256 AS bar_payload_sha256,
           bar_l.payload->'data'->b.source_row AS raw_bar_row,
           b.o AS bar_open,b.h AS bar_high,b.l AS bar_low,b.c AS bar_close,b.v AS bar_volume
      FROM core.daily_price_limit_observations p
      JOIN core.bars_daily_sources_ml_eligible b
        ON b.symbol_id=p.symbol_id AND b.trade_date=p.trade_date
       AND b.source='vndirect' AND b.adj_basis='unadjusted'
       AND b.landing_id=p.raw_landing_id AND b.source_row=p.source_row
      JOIN raw.landings limits_l ON limits_l.landing_id=p.raw_landing_id
      JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
     WHERE p.symbol_id=p_symbol_id AND p.trade_date=p_trade_date
       AND p.source='vndirect' AND limits_l.source='vndirect'
       AND limits_l.route='equity_ohlcv'
       AND p.available_at=p.fetched_at AND p.fetched_at=limits_l.fetched_at
       AND p.limit_up>0 AND p.limit_down>0 AND p.limit_up>=p.limit_down
       AND p.row_payload=limits_l.payload->'data'->p.source_row
       AND p.row_payload->>'code'=upper(limits_l.symbol)
       AND p.row_payload->>'date'=to_char(p.trade_date,'YYYY-MM-DD')
       AND p.limit_up=(p.row_payload->>'ceilingPrice')::numeric
       AND p.limit_down=(p.row_payload->>'floorPrice')::numeric
       AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
       AND bar_l.payload_sha256 ~ '^[0-9a-f]{64}$'
       AND bar_l.payload_bytes IS NOT NULL
       AND encode(sha256(bar_l.payload_bytes),'hex')=lower(bar_l.payload_sha256)
       AND ops.phase2_try_jsonb_bytes(bar_l.payload_bytes)=bar_l.payload
       AND jsonb_typeof(bar_l.payload->'data'->b.source_row)='object'
), bsc AS (
    SELECT p.observation_id,p.symbol_id,p.trade_date,p.source,p.limit_up,p.limit_down,
           p.available_at,p.fetched_at,p.raw_landing_id AS evidence_landing_id,
           p.source_row AS evidence_source_row,p.row_payload AS evidence_row_payload,
           bsc_l.payload_sha256 AS evidence_payload_sha256,
           b.landing_id AS bar_landing_id,b.source_row AS bar_source_row,
           bar_l.payload_sha256 AS bar_payload_sha256,
           bar_l.payload->'data'->b.source_row AS raw_bar_row,
           b.o AS bar_open,b.h AS bar_high,b.l AS bar_low,b.c AS bar_close,b.v AS bar_volume
      FROM core.daily_price_limit_observations p
      JOIN raw.landings bsc_l ON bsc_l.landing_id=p.raw_landing_id
      JOIN core.bars_daily_sources_ml_eligible b
        ON b.symbol_id=p.symbol_id AND b.trade_date=p.trade_date
       AND b.source='vndirect' AND b.adj_basis='unadjusted'
      JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
      CROSS JOIN LATERAL (SELECT bar_l.payload->'data'->b.source_row AS bar_row) raw_bar
     WHERE p.symbol_id=p_symbol_id AND p.trade_date=p_trade_date
       AND p.source='bsc' AND bsc_l.source='bsc'
       AND bsc_l.route='historical_data_ajax'
       AND p.available_at=p.fetched_at AND p.fetched_at=bsc_l.fetched_at
       AND p.limit_up>0 AND p.limit_down>0 AND p.limit_up>=p.limit_down
       AND p.row_payload=bsc_l.payload->'rows'->p.source_row
       AND encode(sha256(bsc_l.payload_bytes),'hex')=lower(bsc_l.payload_sha256)
       AND ops.phase2_try_jsonb_bytes(bsc_l.payload_bytes)=bsc_l.payload->'response'
       AND bsc_l.payload->'request'->>'mck'=upper(bsc_l.symbol)
       AND bsc_l.payload->'request'->>'fromdate'=to_char(p.trade_date,'YYYY-MM-DD')
       AND bsc_l.payload->'request'->>'todate'=to_char(p.trade_date,'YYYY-MM-DD')
       AND (bsc_l.payload->'request' ? 'security') IS FALSE
       AND p.row_payload->>'code'=upper(bsc_l.symbol)
       AND p.row_payload->>'trade_date'=to_char(p.trade_date,'YYYY-MM-DD')
       AND p.limit_up=(p.row_payload->>'ceiling_price_vnd')::numeric/1000
       AND p.limit_down=(p.row_payload->>'floor_price_vnd')::numeric/1000
       AND position(p.row_payload->>'source_row_html'
                    IN bsc_l.payload->'response'->'data'->>'html')>0
       AND bsc_l.payload->'validation'->>'vndirect_landing_id'=b.landing_id::text
       AND bsc_l.payload->'validation'->>'vndirect_source_row'=b.source_row::text
       AND bsc_l.payload->'validation'->>'vndirect_payload_sha256'=bar_l.payload_sha256
       AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
       AND bar_l.payload_sha256 ~ '^[0-9a-f]{64}$'
       AND bar_l.payload_bytes IS NOT NULL
       AND encode(sha256(bar_l.payload_bytes),'hex')=lower(bar_l.payload_sha256)
       AND ops.phase2_try_jsonb_bytes(bar_l.payload_bytes)=bar_l.payload
       AND raw_bar.bar_row->>'code'=upper(bsc_l.symbol)
       AND raw_bar.bar_row->>'date'=to_char(p.trade_date,'YYYY-MM-DD')
       AND (raw_bar.bar_row->>'close')::numeric*1000=(p.row_payload->>'close_price_vnd')::numeric
       AND (raw_bar.bar_row->>'nmVolume')::numeric=(p.row_payload->>'matched_volume_shares')::numeric
       AND b.c::numeric=(raw_bar.bar_row->>'close')::numeric
       AND b.v::numeric=(raw_bar.bar_row->>'nmVolume')::numeric
       AND NOT EXISTS (
           SELECT 1 FROM core.daily_price_limit_observations direct
            WHERE direct.symbol_id=p.symbol_id AND direct.trade_date=p.trade_date
              AND direct.source='vndirect'
       )
       AND 1=(SELECT count(*) FROM core.daily_price_limit_observations same_day
              WHERE same_day.symbol_id=p.symbol_id AND same_day.trade_date=p.trade_date
                AND same_day.source='bsc')
)
SELECT * FROM vndirect
UNION ALL
SELECT * FROM bsc
$phase2_execution_limit_evidence_for_day_106$;

CREATE OR REPLACE VIEW core.phase2_execution_limit_evidence AS
SELECT evidence.observation_id,evidence.symbol_id,evidence.trade_date,
       evidence.source,evidence.limit_up::numeric(20,6) AS limit_up,
       evidence.limit_down::numeric(20,6) AS limit_down,
       evidence.available_at,evidence.fetched_at,evidence.evidence_landing_id,
       evidence.evidence_source_row,evidence.evidence_row_payload,
       evidence.evidence_payload_sha256,evidence.bar_landing_id,
       evidence.bar_source_row,evidence.bar_payload_sha256,evidence.raw_bar_row,
       evidence.bar_open,evidence.bar_high,evidence.bar_low,evidence.bar_close,
       evidence.bar_volume
  FROM (
      SELECT DISTINCT p.symbol_id,p.trade_date
        FROM core.daily_price_limit_observations p
  ) keys
  CROSS JOIN LATERAL core.phase2_execution_limit_evidence_for_day(
      keys.symbol_id,keys.trade_date
  ) evidence;

COMMENT ON VIEW core.phase2_execution_limit_evidence IS
    'Exact label-only daily limit evidence. VNDIRECT same-row limits take precedence; BSC is a separately hashed, source-reported fallback only when no VNDIRECT observation exists and its close/volume match the unadjusted VNDIRECT bar.';
COMMENT ON FUNCTION core.phase2_execution_limit_evidence_for_day(bigint,date) IS
    'Returns exact limit evidence for one symbol and session only. Scalar and staged label refreshes use this bounded lookup; the global view is diagnostic.';

CREATE OR REPLACE FUNCTION feat.phase2_exact_execution_weight(
    p_symbol_id bigint,
    p_entry_date date,
    p_exit_date date
)
RETURNS double precision
LANGUAGE sql STABLE AS $phase2_exact_execution_weight_106$
    WITH expected AS MATERIALIZED (
        SELECT trade_date
          FROM core.effective_trading_sessions
         WHERE is_session AND trade_date BETWEEN p_entry_date AND p_exit_date
    ), evidence AS MATERIALIZED (
        SELECT s.trade_date,l.limit_up,l.limit_down,
               CASE WHEN jsonb_typeof(l.raw_bar_row->'open')='number'
                    THEN (l.raw_bar_row->>'open')::numeric END AS raw_open,
               CASE WHEN jsonb_typeof(l.raw_bar_row->'high')='number'
                    THEN (l.raw_bar_row->>'high')::numeric END AS raw_high,
               CASE WHEN jsonb_typeof(l.raw_bar_row->'low')='number'
                    THEN (l.raw_bar_row->>'low')::numeric END AS raw_low,
               CASE WHEN jsonb_typeof(l.raw_bar_row->'close')='number'
                    THEN (l.raw_bar_row->>'close')::numeric END AS raw_close,
               l.bar_open,l.bar_high,l.bar_low,l.bar_close
          FROM expected s
          CROSS JOIN LATERAL core.phase2_execution_limit_evidence_for_day(
              p_symbol_id,s.trade_date
          ) l
    ), counts AS (
        SELECT (SELECT count(*) FROM expected) AS expected_count,
               count(*) AS evidenced_count,
               count(*) FILTER (
                   WHERE (raw_open=limit_up AND raw_high=limit_up
                          AND raw_low=limit_up AND raw_close=limit_up)
                      OR (raw_open=limit_down AND raw_high=limit_down
                          AND raw_low=limit_down AND raw_close=limit_down)
               ) AS locked_count,
               max(raw_open) FILTER(WHERE trade_date=p_entry_date) AS entry_open,
               max(limit_up) FILTER(WHERE trade_date=p_entry_date) AS entry_limit_up
          FROM evidence
         WHERE raw_open IS NOT NULL AND raw_high IS NOT NULL
           AND raw_low IS NOT NULL AND raw_close IS NOT NULL
           AND limit_up IS NOT NULL AND limit_down IS NOT NULL
           AND bar_open=raw_open AND bar_high=raw_high
           AND bar_low=raw_low AND bar_close=raw_close
    )
    SELECT feat.phase2_execution_weight_decision(
               expected_count>0 AND evidenced_count=expected_count,
               entry_open,entry_limit_up,locked_count::integer
           )
      FROM counts
$phase2_exact_execution_weight_106$;

CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date,
    p_evidence_trade_date date,
    p_symbol_ids bigint[]
)
RETURNS bigint
LANGUAGE plpgsql AS $phase2_staged_execution_weights_106$
DECLARE
    v_rows bigint;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;
    IF (SELECT count(*) FROM core.effective_trading_sessions
         WHERE is_session AND trade_date BETWEEN p_date_from AND p_date_to)>300 THEN
        RAISE EXCEPTION 'execution-weight chunks are limited to 300 sessions';
    END IF;

    DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_counts_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_evidence_days_106;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_verified_vndirect_landings_106;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_eligible_bars_106;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_unique_sessions_106;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_counts_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_expected_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_sessions_102;
    DROP TABLE IF EXISTS pg_temp.phase2_weight_windows_102;

    CREATE TEMP TABLE phase2_weight_windows_102 ON COMMIT DROP AS
    SELECT DISTINCT t.symbol_id,l.entry_date,l.exit_date
      FROM feat.phase2_label_targets_v3 t
      JOIN feat.labels_daily l
        ON l.symbol_id=t.symbol_id AND l.signal_date=t.signal_date
       AND l.horizon_sessions=t.horizon_sessions AND l.label_version=t.label_version
       AND l.feature_set_hash=t.feature_set_hash
     WHERE t.signal_date BETWEEN p_date_from AND p_date_to
       AND (p_symbol_ids IS NULL OR t.symbol_id=ANY(p_symbol_ids))
       AND (p_evidence_trade_date IS NULL
            OR (
                l.entry_date<=p_evidence_trade_date AND l.exit_date>=p_evidence_trade_date
                AND EXISTS (
                    SELECT 1 FROM core.daily_price_limit_observations changed_limit
                     WHERE changed_limit.symbol_id=t.symbol_id
                       AND changed_limit.trade_date=p_evidence_trade_date
                       AND changed_limit.source IN ('vndirect','bsc')
                )
            ))
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;
    CREATE UNIQUE INDEX phase2_weight_windows_102_pk
        ON pg_temp.phase2_weight_windows_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_windows_102;

    CREATE TEMP TABLE phase2_weight_sessions_102 ON COMMIT DROP AS
    SELECT trade_date FROM core.effective_trading_sessions WHERE is_session;
    CREATE UNIQUE INDEX phase2_weight_sessions_102_pk
        ON pg_temp.phase2_weight_sessions_102(trade_date);
    ANALYZE pg_temp.phase2_weight_sessions_102;

    CREATE TEMP TABLE phase2_weight_expected_102 ON COMMIT DROP AS
    SELECT w.symbol_id,w.entry_date,w.exit_date,s.trade_date
      FROM pg_temp.phase2_weight_windows_102 w
      CROSS JOIN LATERAL (
          SELECT s.trade_date
            FROM pg_temp.phase2_weight_sessions_102 s
           WHERE s.trade_date BETWEEN w.entry_date AND w.exit_date
           OFFSET 0
      ) s;
    CREATE UNIQUE INDEX phase2_weight_expected_102_pk
        ON pg_temp.phase2_weight_expected_102(symbol_id,entry_date,exit_date,trade_date);
    CREATE INDEX phase2_weight_expected_102_bar_lookup_idx
        ON pg_temp.phase2_weight_expected_102(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_weight_expected_102;

    CREATE TEMP TABLE phase2_weight_expected_counts_102 ON COMMIT DROP AS
    SELECT symbol_id,entry_date,exit_date,count(*)::bigint AS expected_count
      FROM pg_temp.phase2_weight_expected_102
     GROUP BY symbol_id,entry_date,exit_date;
    CREATE UNIQUE INDEX phase2_weight_expected_counts_102_pk
        ON pg_temp.phase2_weight_expected_counts_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_expected_counts_102;

    CREATE TEMP TABLE phase2_weight_unique_sessions_106 ON COMMIT DROP AS
    SELECT DISTINCT symbol_id,trade_date
      FROM pg_temp.phase2_weight_expected_102;
    CREATE UNIQUE INDEX phase2_weight_unique_sessions_106_pk
        ON pg_temp.phase2_weight_unique_sessions_106(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_weight_unique_sessions_106;

    CREATE TEMP TABLE phase2_weight_eligible_bars_106 ON COMMIT DROP AS
    WITH latest AS MATERIALIZED (
        SELECT DISTINCT ON (ev.source,ev.symbol_id,ev.trade_date)
               ev.source,ev.symbol_id,ev.trade_date,ev.event_id,ev.decision
          FROM pg_temp.phase2_weight_unique_sessions_106 e
          JOIN ops.ml_bar_eligibility_events ev
            ON ev.source='vndirect' AND ev.symbol_id=e.symbol_id
           AND ev.trade_date=e.trade_date
         ORDER BY ev.source,ev.symbol_id,ev.trade_date,
                  ev.recorded_at DESC,ev.event_id DESC
    )
    SELECT b.symbol_id,b.trade_date,b.o,b.h,b.l,b.c,b.v,
           b.landing_id,b.source_row
      FROM pg_temp.phase2_weight_unique_sessions_106 e
      JOIN core.bars_daily_sources b
        ON b.symbol_id=e.symbol_id AND b.trade_date=e.trade_date
       AND b.source='vndirect' AND b.adj_basis='unadjusted'
      LEFT JOIN latest eligibility
        ON eligibility.source=b.source AND eligibility.symbol_id=b.symbol_id
       AND eligibility.trade_date=b.trade_date
     WHERE eligibility.event_id IS NULL OR eligibility.decision<>'EXCLUDE';
    CREATE UNIQUE INDEX phase2_weight_eligible_bars_106_pk
        ON pg_temp.phase2_weight_eligible_bars_106(symbol_id,trade_date);
    CREATE INDEX phase2_weight_eligible_bars_106_landing_idx
        ON pg_temp.phase2_weight_eligible_bars_106(landing_id);
    ANALYZE pg_temp.phase2_weight_eligible_bars_106;

    CREATE TEMP TABLE phase2_weight_verified_vndirect_landings_106 ON COMMIT DROP AS
    SELECT l.landing_id
      FROM (
          SELECT DISTINCT landing_id
            FROM pg_temp.phase2_weight_eligible_bars_106
      ) candidates
      JOIN raw.landings l ON l.landing_id=candidates.landing_id
     WHERE l.source='vndirect' AND l.route='equity_ohlcv'
       AND l.payload_sha256 ~ '^[0-9a-f]{64}$'
       AND l.payload_bytes IS NOT NULL
       AND encode(sha256(l.payload_bytes),'hex')=lower(l.payload_sha256)
       AND ops.phase2_try_jsonb_bytes(l.payload_bytes)=l.payload;
    CREATE UNIQUE INDEX phase2_weight_verified_vndirect_landings_106_pk
        ON pg_temp.phase2_weight_verified_vndirect_landings_106(landing_id);
    ANALYZE pg_temp.phase2_weight_verified_vndirect_landings_106;

    CREATE TEMP TABLE phase2_weight_evidence_days_106 ON COMMIT DROP AS
    WITH vndirect AS (
        SELECT e.symbol_id,e.trade_date,p.limit_up,p.limit_down,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'open')='number'
                    THEN (raw_bar.bar_row->>'open')::numeric END AS raw_open,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'high')='number'
                    THEN (raw_bar.bar_row->>'high')::numeric END AS raw_high,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'low')='number'
                    THEN (raw_bar.bar_row->>'low')::numeric END AS raw_low,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'close')='number'
                    THEN (raw_bar.bar_row->>'close')::numeric END AS raw_close,
               b.o AS bar_open,b.h AS bar_high,b.l AS bar_low,b.c AS bar_close
          FROM pg_temp.phase2_weight_unique_sessions_106 e
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=e.symbol_id AND p.trade_date=e.trade_date
           AND p.source='vndirect'
          JOIN pg_temp.phase2_weight_eligible_bars_106 b
            ON b.symbol_id=p.symbol_id AND b.trade_date=p.trade_date
           AND b.landing_id=p.raw_landing_id AND b.source_row=p.source_row
          JOIN pg_temp.phase2_weight_verified_vndirect_landings_106 verified
            ON verified.landing_id=b.landing_id
          JOIN raw.landings limits_l ON limits_l.landing_id=p.raw_landing_id
          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
          CROSS JOIN LATERAL (
              SELECT bar_l.payload->'data'->b.source_row AS bar_row
          ) raw_bar
         WHERE limits_l.source='vndirect' AND limits_l.route='equity_ohlcv'
           AND p.available_at=p.fetched_at AND p.fetched_at=limits_l.fetched_at
           AND p.limit_up>0 AND p.limit_down>0 AND p.limit_up>=p.limit_down
           AND p.row_payload=limits_l.payload->'data'->p.source_row
           AND p.row_payload->>'code'=upper(limits_l.symbol)
           AND p.row_payload->>'date'=to_char(p.trade_date,'YYYY-MM-DD')
           AND p.limit_up=(p.row_payload->>'ceilingPrice')::numeric
           AND p.limit_down=(p.row_payload->>'floorPrice')::numeric
           AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
           AND jsonb_typeof(bar_l.payload->'data'->b.source_row)='object'
    ), bsc AS (
        SELECT e.symbol_id,e.trade_date,p.limit_up,p.limit_down,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'open')='number'
                    THEN (raw_bar.bar_row->>'open')::numeric END AS raw_open,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'high')='number'
                    THEN (raw_bar.bar_row->>'high')::numeric END AS raw_high,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'low')='number'
                    THEN (raw_bar.bar_row->>'low')::numeric END AS raw_low,
               CASE WHEN jsonb_typeof(raw_bar.bar_row->'close')='number'
                    THEN (raw_bar.bar_row->>'close')::numeric END AS raw_close,
               b.o AS bar_open,b.h AS bar_high,b.l AS bar_low,b.c AS bar_close
          FROM pg_temp.phase2_weight_unique_sessions_106 e
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=e.symbol_id AND p.trade_date=e.trade_date
           AND p.source='bsc'
          JOIN raw.landings bsc_l ON bsc_l.landing_id=p.raw_landing_id
          JOIN pg_temp.phase2_weight_eligible_bars_106 b
            ON b.symbol_id=p.symbol_id AND b.trade_date=p.trade_date
          JOIN pg_temp.phase2_weight_verified_vndirect_landings_106 verified
            ON verified.landing_id=b.landing_id
          JOIN raw.landings bar_l ON bar_l.landing_id=b.landing_id
          CROSS JOIN LATERAL (
              SELECT bar_l.payload->'data'->b.source_row AS bar_row
          ) raw_bar
         WHERE bsc_l.source='bsc' AND bsc_l.route='historical_data_ajax'
           AND p.available_at=p.fetched_at AND p.fetched_at=bsc_l.fetched_at
           AND p.limit_up>0 AND p.limit_down>0 AND p.limit_up>=p.limit_down
           AND p.row_payload=bsc_l.payload->'rows'->p.source_row
           AND encode(sha256(bsc_l.payload_bytes),'hex')=lower(bsc_l.payload_sha256)
           AND ops.phase2_try_jsonb_bytes(bsc_l.payload_bytes)=bsc_l.payload->'response'
           AND bsc_l.payload->'request'->>'mck'=upper(bsc_l.symbol)
           AND bsc_l.payload->'request'->>'fromdate'=to_char(p.trade_date,'YYYY-MM-DD')
           AND bsc_l.payload->'request'->>'todate'=to_char(p.trade_date,'YYYY-MM-DD')
           AND (bsc_l.payload->'request' ? 'security') IS FALSE
           AND p.row_payload->>'code'=upper(bsc_l.symbol)
           AND p.row_payload->>'trade_date'=to_char(p.trade_date,'YYYY-MM-DD')
           AND p.limit_up=(p.row_payload->>'ceiling_price_vnd')::numeric/1000
           AND p.limit_down=(p.row_payload->>'floor_price_vnd')::numeric/1000
           AND position(p.row_payload->>'source_row_html'
                        IN bsc_l.payload->'response'->'data'->>'html')>0
           AND bsc_l.payload->'validation'->>'vndirect_landing_id'=b.landing_id::text
           AND bsc_l.payload->'validation'->>'vndirect_source_row'=b.source_row::text
           AND bsc_l.payload->'validation'->>'vndirect_payload_sha256'=bar_l.payload_sha256
           AND bar_l.source='vndirect' AND bar_l.route='equity_ohlcv'
           AND raw_bar.bar_row->>'code'=upper(bsc_l.symbol)
           AND raw_bar.bar_row->>'date'=to_char(p.trade_date,'YYYY-MM-DD')
           AND (raw_bar.bar_row->>'close')::numeric*1000=(p.row_payload->>'close_price_vnd')::numeric
           AND (raw_bar.bar_row->>'nmVolume')::numeric=(p.row_payload->>'matched_volume_shares')::numeric
           AND b.c::numeric=(raw_bar.bar_row->>'close')::numeric
           AND b.v::numeric=(raw_bar.bar_row->>'nmVolume')::numeric
           AND NOT EXISTS (
               SELECT 1 FROM core.daily_price_limit_observations direct
                WHERE direct.symbol_id=p.symbol_id AND direct.trade_date=p.trade_date
                  AND direct.source='vndirect'
           )
           AND 1=(SELECT count(*) FROM core.daily_price_limit_observations same_day
                  WHERE same_day.symbol_id=p.symbol_id AND same_day.trade_date=p.trade_date
                    AND same_day.source='bsc')
    )
    SELECT * FROM vndirect
    UNION ALL
    SELECT * FROM bsc;
    CREATE INDEX phase2_weight_evidence_days_106_lookup_idx
        ON pg_temp.phase2_weight_evidence_days_106(symbol_id,trade_date);
    ANALYZE pg_temp.phase2_weight_evidence_days_106;

    CREATE TEMP TABLE phase2_weight_evidence_102 ON COMMIT DROP AS
    SELECT e.symbol_id,e.entry_date,e.exit_date,e.trade_date,
           p.limit_up,p.limit_down,p.raw_open,p.raw_high,p.raw_low,p.raw_close
      FROM pg_temp.phase2_weight_expected_102 e
      JOIN pg_temp.phase2_weight_evidence_days_106 p
        ON p.symbol_id=e.symbol_id AND p.trade_date=e.trade_date
     WHERE p.raw_open IS NOT NULL AND p.raw_high IS NOT NULL
       AND p.raw_low IS NOT NULL AND p.raw_close IS NOT NULL
       AND p.limit_up IS NOT NULL AND p.limit_down IS NOT NULL
       AND p.bar_open=p.raw_open AND p.bar_high=p.raw_high
       AND p.bar_low=p.raw_low AND p.bar_close=p.raw_close;
    CREATE INDEX phase2_weight_evidence_102_window_idx
        ON pg_temp.phase2_weight_evidence_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_evidence_102;

    CREATE TEMP TABLE phase2_weight_evidence_counts_102 ON COMMIT DROP AS
    SELECT symbol_id,entry_date,exit_date,
           count(*)::bigint AS evidenced_count,
           count(*) FILTER (
               WHERE (raw_open=limit_up AND raw_high=limit_up
                      AND raw_low=limit_up AND raw_close=limit_up)
                  OR (raw_open=limit_down AND raw_high=limit_down
                      AND raw_low=limit_down AND raw_close=limit_down)
           )::bigint AS locked_count,
           max(raw_open) FILTER (WHERE trade_date=entry_date) AS entry_open,
           max(limit_up) FILTER (WHERE trade_date=entry_date) AS entry_limit_up
      FROM pg_temp.phase2_weight_evidence_102
     GROUP BY symbol_id,entry_date,exit_date;
    CREATE UNIQUE INDEX phase2_weight_evidence_counts_102_pk
        ON pg_temp.phase2_weight_evidence_counts_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_evidence_counts_102;

    CREATE TEMP TABLE phase2_weight_values_102 ON COMMIT DROP AS
    SELECT w.symbol_id,w.entry_date,w.exit_date,
           feat.phase2_execution_weight_decision(
               coalesce(ec.expected_count,0)>0
                   AND coalesce(vc.evidenced_count,0)=coalesce(ec.expected_count,0),
               vc.entry_open,vc.entry_limit_up,coalesce(vc.locked_count,0)::integer
           ) AS execution_weight
      FROM pg_temp.phase2_weight_windows_102 w
      LEFT JOIN pg_temp.phase2_weight_expected_counts_102 ec
        ON ec.symbol_id=w.symbol_id AND ec.entry_date=w.entry_date AND ec.exit_date=w.exit_date
      LEFT JOIN pg_temp.phase2_weight_evidence_counts_102 vc
        ON vc.symbol_id=w.symbol_id AND vc.entry_date=w.entry_date AND vc.exit_date=w.exit_date;
    CREATE UNIQUE INDEX phase2_weight_values_102_pk
        ON pg_temp.phase2_weight_values_102(symbol_id,entry_date,exit_date);
    ANALYZE pg_temp.phase2_weight_values_102;

    UPDATE feat.phase2_label_targets_v3 t
       SET execution_weight=w.execution_weight
      FROM feat.labels_daily l
      JOIN pg_temp.phase2_weight_values_102 w
        ON w.symbol_id=l.symbol_id AND w.entry_date=l.entry_date AND w.exit_date=l.exit_date
     WHERE t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
       AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
       AND t.feature_set_hash=l.feature_set_hash
       AND t.signal_date BETWEEN p_date_from AND p_date_to
       AND l.label_status='READY' AND l.entry_date IS NOT NULL AND l.exit_date IS NOT NULL;

    GET DIAGNOSTICS v_rows=ROW_COUNT;
    RETURN v_rows;
END;
$phase2_staged_execution_weights_106$;

CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date,
    p_evidence_trade_date date
)
RETURNS bigint
LANGUAGE sql AS $phase2_staged_execution_weights_date_wrapper_106$
    SELECT feat.refresh_phase2_execution_weights(
        p_date_from,p_date_to,p_evidence_trade_date,NULL::bigint[]
    )
$phase2_staged_execution_weights_date_wrapper_106$;

CREATE OR REPLACE FUNCTION feat.refresh_phase2_execution_weights(
    p_date_from date,
    p_date_to date
)
RETURNS bigint
LANGUAGE sql AS $phase2_staged_execution_weights_wrapper_106$
    SELECT feat.refresh_phase2_execution_weights(
        p_date_from,p_date_to,NULL::date,NULL::bigint[]
    )
$phase2_staged_execution_weights_wrapper_106$;

DO $phase2_bsc_label_hash_patch$
DECLARE
    v_definition text:=pg_get_functiondef(
        'ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure
    );
    v_anchor constant text:='WHERE p.symbol_id=w.symbol_id AND p.source=''vndirect''';
    v_replacement constant text:='WHERE p.symbol_id=w.symbol_id AND p.source IN (''vndirect'',''bsc'')';
BEGIN
    IF position(v_replacement IN v_definition)>0 THEN
        RETURN;
    END IF;
    IF length(v_definition)-length(replace(v_definition,v_anchor,''))<>length(v_anchor) THEN
        RAISE EXCEPTION 'unexpected label input-hash price-limit source filter';
    END IF;
    EXECUTE replace(v_definition,v_anchor,v_replacement);
END;
$phase2_bsc_label_hash_patch$;

COMMENT ON FUNCTION feat.phase2_exact_execution_weight(bigint,date,date) IS
    'Computes exact execution-label weights from complete expected-session VNDIRECT OHLC and source-row-linked limits. Exact VNDIRECT limits take precedence; separately archived BSC limits are allowed only after exact close/volume match and only when no VNDIRECT limit observation exists. BSC evidence is never a feature input.';

COMMENT ON FUNCTION feat.refresh_phase2_execution_weights(date,date) IS
    'Refreshes every READY label target in the signal-date range through the staged exact-evidence implementation.';

COMMENT ON FUNCTION feat.refresh_phase2_execution_weights(date,date,date) IS
    'Refreshes READY label targets in the signal-date range, optionally limited to windows containing one changed evidence session. Uses distinct symbol/session evidence, latest bar eligibility, and one raw VNDIRECT landing hash verification per distinct landing; BSC is a label-only fallback.';

COMMENT ON FUNCTION feat.refresh_phase2_execution_weights(date,date,date,bigint[]) IS
    'Refreshes READY label targets in the signal-date range, optionally limited to windows containing one changed evidence session and an explicit symbol batch. Uses distinct symbol/session evidence, latest bar eligibility, and one raw VNDIRECT landing hash verification per distinct landing; BSC is a label-only fallback.';

COMMENT ON FUNCTION ops.phase2_label_target_chunk_input_hash(date,date) IS
    'Exact label input manifest including base features, execution-weight policy, and all VNDIRECT/BSC limit observations within each READY label window; BSC rows remain retrospective label-only evidence.';

DO $phase2_bsc_migration_assertions$
DECLARE
    v_scalar text:=pg_get_functiondef('feat.phase2_exact_execution_weight(bigint,date,date)'::regprocedure);
    v_batch text:=pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date)'::regprocedure);
    v_batch_date text:=pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date)'::regprocedure);
    v_batch_impl text:=pg_get_functiondef('feat.refresh_phase2_execution_weights(date,date,date,bigint[])'::regprocedure);
    v_hash text:=pg_get_functiondef('ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure);
    v_evidence text:=pg_get_functiondef('core.phase2_execution_limit_evidence_for_day(bigint,date)'::regprocedure);
BEGIN
    IF position('core.phase2_execution_limit_evidence_for_day' IN v_scalar)=0
       OR position('feat.refresh_phase2_execution_weights' IN v_batch)=0
       OR position('feat.refresh_phase2_execution_weights' IN v_batch_date)=0
       OR position('p_evidence_trade_date' IN v_batch_impl)=0
       OR position('p_symbol_ids' IN v_batch_impl)=0
       OR position('changed_limit' IN v_batch_impl)=0
       OR position('phase2_weight_windows_102' IN v_batch_impl)=0
       OR position('phase2_weight_unique_sessions_106' IN v_batch_impl)=0
       OR position('phase2_weight_eligible_bars_106' IN v_batch_impl)=0
       OR position('phase2_weight_verified_vndirect_landings_106' IN v_batch_impl)=0
       OR position('phase2_weight_evidence_days_106' IN v_batch_impl)=0
       OR position('ops.ml_bar_eligibility_events' IN v_batch_impl)=0
       OR position('EXCLUDE' IN v_batch_impl)=0
       OR position('core.daily_price_limit_observations' IN v_batch_impl)=0
       OR position('source=''bsc''' IN v_batch_impl)=0
       OR position('payload_bytes' IN v_batch_impl)=0
       OR position('NOT EXISTS' IN v_batch_impl)=0
       OR position('DROP TABLE IF EXISTS pg_temp.phase2_weight_values_102' IN v_batch_impl)=0
       OR position('source=''bsc''' IN v_evidence)=0
       OR position('bsc' IN lower(v_hash))=0
       OR to_regprocedure('core.materialize_bsc_daily_price_limits(date,date,bigint[])') IS NULL
       OR to_regclass('core.phase2_execution_limit_evidence') IS NULL THEN
        RAISE EXCEPTION 'BSC exact-label fallback is not consistently wired into scalar, batch, and input-hash paths';
    END IF;
END;
$phase2_bsc_migration_assertions$;

COMMIT;

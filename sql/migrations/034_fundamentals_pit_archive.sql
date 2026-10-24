-- Versioned, point-in-time archive for normalized level-1 financial statement rows.
-- Existing core.fundamentals_pit rows are retained as legacy rows; new archive
-- requirements apply only to rows written through core.archive_fundamental_rows.
BEGIN;

ALTER TABLE core.fundamentals_pit
    ADD COLUMN IF NOT EXISTS statement_type text,
    ADD COLUMN IF NOT EXISTS ingest_id uuid,
    ADD COLUMN IF NOT EXISTS fetched_at timestamptz,
    ADD COLUMN IF NOT EXISTS row_id text,
    ADD COLUMN IF NOT EXISTS line_name text,
    ADD COLUMN IF NOT EXISTS line_order integer,
    ADD COLUMN IF NOT EXISTS line_level smallint,
    ADD COLUMN IF NOT EXISTS unit text,
    ADD COLUMN IF NOT EXISTS availability_basis text,
    ADD COLUMN IF NOT EXISTS availability_is_assumed boolean,
    ADD COLUMN IF NOT EXISTS raw_landing_id bigint,
    ADD COLUMN IF NOT EXISTS source_row integer,
    ADD COLUMN IF NOT EXISTS row_payload jsonb,
    ADD COLUMN IF NOT EXISTS archive_managed boolean NOT NULL DEFAULT false;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fundamentals_pit_raw_landing_fk') THEN
        ALTER TABLE core.fundamentals_pit ADD CONSTRAINT fundamentals_pit_raw_landing_fk
            FOREIGN KEY(raw_landing_id) REFERENCES raw.landings(landing_id) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='fundamentals_pit_archive_shape') THEN
        ALTER TABLE core.fundamentals_pit ADD CONSTRAINT fundamentals_pit_archive_shape CHECK (
            NOT archive_managed OR (
                statement_type IN ('income_statement','balance_sheet','cash_flow') AND
                ingest_id IS NOT NULL AND fetched_at IS NOT NULL AND row_id IS NOT NULL AND row_id <> '' AND
                line_name IS NOT NULL AND line_name <> '' AND line_order IS NOT NULL AND line_level = 1 AND
                availability_basis IN ('assumed_backfill_lag','observed_ingestion') AND
                availability_is_assumed = (availability_basis = 'assumed_backfill_lag') AND
                raw_landing_id IS NOT NULL AND row_payload IS NOT NULL AND
                source_row IS NOT NULL AND source_row >= 0 AND
                first_seen_at = fetched_at AND last_seen_at IS NOT NULL AND last_seen_at >= first_seen_at AND
                ((availability_basis = 'assumed_backfill_lag' AND
                  available_at = ((period_end + CASE period_type WHEN 'quarter' THEN 45 ELSE 100 END)::timestamp
                                  AT TIME ZONE 'Asia/Ho_Chi_Minh')) OR
                 (availability_basis = 'observed_ingestion' AND available_at = fetched_at))
            )
        ) NOT VALID;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS fundamentals_pit_version_lookup
    ON core.fundamentals_pit(symbol_id,source,statement_type,period_type,period_end,row_id,available_at DESC)
    WHERE archive_managed;

-- Every successful observation, including an unchanged repeat, remains linked
-- to its immutable raw response and source-row ordinal.
CREATE TABLE IF NOT EXISTS core.fundamentals_pit_observations (
    observation_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_id bigint NOT NULL REFERENCES core.fundamentals_pit(snapshot_id),
    raw_landing_id bigint NOT NULL REFERENCES raw.landings(landing_id),
    source text NOT NULL,
    ingest_id uuid NOT NULL,
    fetched_at timestamptz NOT NULL,
    source_row integer NOT NULL CHECK(source_row >= 0),
    row_payload jsonb NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(raw_landing_id,source_row)
);
CREATE INDEX IF NOT EXISTS fundamentals_pit_observations_snapshot_idx
    ON core.fundamentals_pit_observations(snapshot_id,fetched_at);

CREATE OR REPLACE FUNCTION core.reject_fundamental_observation_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'fundamental observations are append-only; % is forbidden', TG_OP;
END;
$$;
DROP TRIGGER IF EXISTS fundamentals_pit_observations_no_update_delete ON core.fundamentals_pit_observations;
CREATE TRIGGER fundamentals_pit_observations_no_update_delete
BEFORE UPDATE OR DELETE ON core.fundamentals_pit_observations
FOR EACH ROW EXECUTE FUNCTION core.reject_fundamental_observation_mutation();
DROP TRIGGER IF EXISTS fundamentals_pit_observations_no_truncate ON core.fundamentals_pit_observations;
CREATE TRIGGER fundamentals_pit_observations_no_truncate
BEFORE TRUNCATE ON core.fundamentals_pit_observations
FOR EACH STATEMENT EXECUTE FUNCTION core.reject_fundamental_observation_mutation();

CREATE OR REPLACE FUNCTION core.guard_fundamental_archive_version()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.archive_managed THEN
            RAISE EXCEPTION 'archived fundamental versions are append-only';
        END IF;
        RETURN OLD;
    END IF;
    IF OLD.archive_managed AND
       (to_jsonb(NEW) - 'last_seen_at') IS DISTINCT FROM (to_jsonb(OLD) - 'last_seen_at') THEN
        RAISE EXCEPTION 'archived fundamental versions are immutable';
    END IF;
    IF OLD.archive_managed AND NEW.last_seen_at < OLD.last_seen_at THEN
        RAISE EXCEPTION 'last_seen_at cannot move backward';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS fundamentals_pit_archive_immutable ON core.fundamentals_pit;
CREATE TRIGGER fundamentals_pit_archive_immutable
BEFORE UPDATE OR DELETE ON core.fundamentals_pit
FOR EACH ROW EXECUTE FUNCTION core.guard_fundamental_archive_version();

-- DB ingestion boundary. The registered compact route probe records a `period`
-- column and an eight-period cap, but no period-label samples. This API therefore
-- accepts only the explicit canonical labels YYYY-Q1..YYYY-Q4 and YYYY; unfamiliar
-- vendor labels fail closed until separately reviewed and added deliberately.
-- A backfill timestamp is an explicit conservative assumption, never a claimed
-- historical publication timestamp. A later changed version is available only
-- when the change was first observed by this archive.
CREATE OR REPLACE FUNCTION core.archive_fundamental_rows(
    p_raw_landing_id bigint,
    p_symbol_id bigint,
    p_statement_type text,
    p_period_type text,
    p_period_end date,
    p_period_key text,
    p_rows jsonb,
    p_mode text DEFAULT 'observed'
) RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    landing raw.landings%ROWTYPE;
    symbol_name text;
    frame_symbol text;
    expected_route text;
    row_doc jsonb;
    row_no integer := 0;
    row_id_value text;
    row_name_value text;
    row_order_value integer;
    row_level_value smallint;
    row_unit_value text;
    row_value numeric;
    prior core.fundamentals_pit%ROWTYPE;
    sid bigint;
    seen_at timestamptz;
    avail_at timestamptz;
    avail_basis text;
    is_revision boolean;
    source_row_no integer;
    period_year integer;
    period_quarter integer;
    expected_period_end date;
    frame_row jsonb;
    inserted_count integer := 0;
BEGIN
    IF p_statement_type IS NULL OR p_period_type IS NULL OR p_mode IS NULL THEN
        RAISE EXCEPTION 'statement_type, period_type, and mode are required';
    END IF;
    IF p_statement_type NOT IN ('income_statement','balance_sheet','cash_flow') THEN
        RAISE EXCEPTION 'unsupported statement_type';
    END IF;
    IF p_period_type NOT IN ('quarter','year') THEN RAISE EXCEPTION 'invalid period_type'; END IF;
    IF p_mode NOT IN ('backfill','observed') THEN RAISE EXCEPTION 'invalid availability mode'; END IF;
    IF p_period_end IS NULL OR p_period_key IS NULL OR p_rows IS NULL OR
       jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows)=0 THEN
        RAISE EXCEPTION 'period key, period_end, and a non-empty rows array are required';
    END IF;
    IF p_period_type='quarter' AND p_period_key ~ '^([0-9]{4})-Q([1-4])$' THEN
        period_year := substring(p_period_key from 1 for 4)::integer;
        period_quarter := substring(p_period_key from 7 for 1)::integer;
        expected_period_end := (make_date(period_year,period_quarter*3,1) + interval '1 month')::date - 1;
    ELSIF p_period_type='year' AND p_period_key ~ '^[0-9]{4}$' THEN
        period_year := p_period_key::integer;
        expected_period_end := make_date(period_year,12,31);
    ELSE
        RAISE EXCEPTION 'unrecognized period key for period_type; accepted examples are 2024-Q1 and 2024';
    END IF;
    IF expected_period_end IS DISTINCT FROM p_period_end THEN
        RAISE EXCEPTION 'period key does not match canonical period_type/period_end';
    END IF;
    expected_route := 'fundamental.equity.' || p_statement_type;
    SELECT * INTO landing FROM raw.landings WHERE landing_id=p_raw_landing_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'raw landing not found'; END IF;
    IF landing.route NOT IN (expected_route,p_statement_type) THEN RAISE EXCEPTION 'landing route does not match statement_type'; END IF;
    IF landing.symbol IS NULL THEN RAISE EXCEPTION 'raw landing has no symbol'; END IF;
    frame_symbol := landing.payload #>> '{attributes,symbol}';
    IF upper(btrim(frame_symbol)) IS DISTINCT FROM upper(btrim(landing.symbol)) THEN
        RAISE EXCEPTION 'fundamental frame symbol does not match raw landing symbol';
    END IF;
    IF jsonb_typeof(landing.payload->'rows') <> 'array' OR landing.payload->'rows' IS DISTINCT FROM p_rows THEN
        RAISE EXCEPTION 'p_rows must be the complete rows array from the immutable raw landing';
    END IF;
    SELECT symbol INTO symbol_name FROM core.symbols WHERE symbol_id=p_symbol_id;
    IF NOT FOUND OR symbol_name <> upper(landing.symbol) THEN RAISE EXCEPTION 'landing symbol does not match symbol_id'; END IF;
    seen_at := landing.fetched_at;

    -- Validate every label in the full frame, not just the selected slice, so
    -- an unfamiliar label cannot silently disappear from an archive pass.
    FOR frame_row IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
        IF jsonb_typeof(frame_row->'period') IS DISTINCT FROM 'string' THEN
            RAISE EXCEPTION 'statement frame row has a missing or non-string period label';
        ELSIF frame_row->>'period' !~ '^([0-9]{4})-Q([1-4])$' AND
              frame_row->>'period' !~ '^[0-9]{4}$' THEN
            RAISE EXCEPTION 'unrecognized statement period label: %', frame_row->>'period';
        END IF;
    END LOOP;

    -- Long-format frames repeat line IDs across periods. Reject duplicates only
    -- within the selected period group; preserve each original zero-based row.
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_rows) AS src(value)
         WHERE src.value->>'period'=p_period_key
        GROUP BY src.value->>'id'
        HAVING src.value->>'id' IS NULL OR src.value->>'id'='' OR count(*) > 1
    ) THEN RAISE EXCEPTION 'rows contain null, empty, or duplicate line ids'; END IF;

    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) AS src(value) WHERE src.value->>'period'=p_period_key) THEN
        RAISE EXCEPTION 'raw frame contains no rows for requested period key';
    END IF;
    FOR row_doc,source_row_no IN
        SELECT src.value,(src.ordinality-1)::integer
          FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS src(value,ordinality)
         WHERE src.value->>'period'=p_period_key
         ORDER BY src.ordinality
    LOOP
        row_no := row_no + 1;
        IF jsonb_typeof(row_doc) <> 'object' OR
           jsonb_typeof(row_doc->'period') IS DISTINCT FROM 'string' OR row_doc->>'period' IS DISTINCT FROM p_period_key OR
           jsonb_typeof(row_doc->'id') <> 'string' OR coalesce(row_doc->>'id','')='' OR
           jsonb_typeof(row_doc->'name') <> 'string' OR coalesce(row_doc->>'name','')='' OR
           jsonb_typeof(row_doc->'order') <> 'number' OR
           jsonb_typeof(row_doc->'level') <> 'number' THEN
            RAISE EXCEPTION 'row % must match the selected period and have non-null id, name, order, and level', row_no-1;
        END IF;
        row_id_value := row_doc->>'id';
        row_name_value := row_doc->>'name';
        IF (row_doc->>'order')::numeric <> trunc((row_doc->>'order')::numeric) OR
           (row_doc->>'level')::numeric <> trunc((row_doc->>'level')::numeric) THEN
            RAISE EXCEPTION 'row % order and level must be integers', row_no-1;
        END IF;
        row_order_value := (row_doc->>'order')::integer;
        row_level_value := (row_doc->>'level')::smallint;
        IF row_level_value <> 1 THEN RAISE EXCEPTION 'row % is not a level-1 line item', row_no-1; END IF;
        IF row_doc ? 'value' AND jsonb_typeof(row_doc->'value') NOT IN ('number','null') THEN
            RAISE EXCEPTION 'row % value must be numeric or null', row_no-1;
        END IF;
        row_value := CASE WHEN jsonb_typeof(row_doc->'value')='number' THEN (row_doc->>'value')::numeric ELSE NULL END;
        row_unit_value := CASE WHEN jsonb_typeof(row_doc->'unit')='string' THEN row_doc->>'unit' ELSE NULL END;

        PERFORM pg_advisory_xact_lock(hashtextextended(
            p_symbol_id::text || '|' || landing.source || '|' || p_statement_type || '|' ||
            p_period_type || '|' || p_period_end::text || '|' || row_id_value,0));
        SELECT * INTO prior FROM core.fundamentals_pit f
         WHERE f.archive_managed AND f.symbol_id=p_symbol_id AND f.source=landing.source
           AND f.statement_type=p_statement_type AND f.period_type=p_period_type
           AND f.period_end=p_period_end AND f.row_id=row_id_value
         ORDER BY f.first_seen_at DESC,f.snapshot_id DESC LIMIT 1 FOR UPDATE;

        is_revision := FOUND AND (
            prior.line_name IS DISTINCT FROM row_name_value OR prior.line_order IS DISTINCT FROM row_order_value OR
            prior.line_level IS DISTINCT FROM row_level_value OR prior.unit IS DISTINCT FROM row_unit_value OR
            prior.value IS DISTINCT FROM row_value OR
            (prior.row_payload - 'value') IS DISTINCT FROM (row_doc - 'value')
        );
        IF FOUND AND NOT is_revision THEN
            UPDATE core.fundamentals_pit SET last_seen_at=greatest(last_seen_at,seen_at)
             WHERE snapshot_id=prior.snapshot_id;
            sid := prior.snapshot_id;
        ELSE
            IF is_revision THEN
                avail_at := seen_at;
                avail_basis := 'observed_ingestion';
            ELSIF p_mode='backfill' THEN
                avail_at := ((p_period_end + CASE p_period_type WHEN 'quarter' THEN 45 ELSE 100 END)::timestamp
                             AT TIME ZONE 'Asia/Ho_Chi_Minh');
                avail_basis := 'assumed_backfill_lag';
            ELSE
                avail_at := seen_at;
                avail_basis := 'observed_ingestion';
            END IF;
            INSERT INTO core.fundamentals_pit
                (symbol_id,line_item,period_end,period_type,value,source,payload,
                 first_seen_at,available_at,last_seen_at,restated,statement_type,ingest_id,fetched_at,
                 row_id,line_name,line_order,line_level,unit,availability_basis,availability_is_assumed,source_row,
                 raw_landing_id,row_payload,archive_managed)
            VALUES
                (p_symbol_id,row_id_value,p_period_end,p_period_type,row_value,landing.source,row_doc,
                 seen_at,avail_at,seen_at,is_revision,p_statement_type,landing.ingest_id,seen_at,
                 row_id_value,row_name_value,row_order_value,row_level_value,row_unit_value,avail_basis,
                 avail_basis='assumed_backfill_lag',source_row_no,p_raw_landing_id,row_doc,true)
            RETURNING snapshot_id INTO sid;
            inserted_count := inserted_count + 1;
        END IF;

        INSERT INTO core.fundamentals_pit_observations
            (snapshot_id,raw_landing_id,source,ingest_id,fetched_at,source_row,row_payload)
        VALUES(sid,p_raw_landing_id,landing.source,landing.ingest_id,seen_at,source_row_no,row_doc);
    END LOOP;
    RETURN inserted_count;
END;
$$;

-- Select the latest version of each source/line that was actually available at
-- the requested instant. Later revisions remain invisible to earlier lookups.
CREATE OR REPLACE FUNCTION core.fundamentals_pit_asof(
    p_symbol_id bigint,
    p_statement_type text,
    p_as_of timestamptz,
    p_source text DEFAULT NULL
) RETURNS SETOF core.fundamentals_pit
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT ON (f.source,f.period_type,f.period_end,f.row_id) f.*
      FROM core.fundamentals_pit f
     WHERE f.archive_managed
       AND f.symbol_id=p_symbol_id
       AND f.statement_type=p_statement_type
       AND f.available_at <= p_as_of
       AND (p_source IS NULL OR f.source=p_source)
     ORDER BY f.source,f.period_type,f.period_end,f.row_id,
              f.available_at DESC,f.first_seen_at DESC,f.snapshot_id DESC
$$;

COMMIT;

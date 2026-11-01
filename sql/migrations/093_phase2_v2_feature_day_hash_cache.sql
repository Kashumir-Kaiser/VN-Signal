BEGIN;

-- Cache the exact per-session V2 digest used by the V3 input manifest. The
-- feature row is wide, so hashing the year-to-date V2 panel for every monthly
-- chunk repeats large scans and sorts. This cache keeps the same digest
-- contract while refreshing only missing or source-invalidated sessions.
CREATE TABLE IF NOT EXISTS ops.phase2_v2_feature_day_hash_cache (
    trade_date date PRIMARY KEY,
    row_count bigint NOT NULL DEFAULT 0 CHECK (row_count>=0),
    day_sha256 text CHECK (day_sha256 IS NULL OR day_sha256 ~ '^[0-9a-f]{64}$'),
    is_dirty boolean NOT NULL DEFAULT true,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    CHECK (is_dirty OR
           (row_count=0 AND day_sha256 IS NULL) OR
           (row_count>0 AND day_sha256 IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS ops.phase2_v2_feature_day_hash_state (
    singleton integer PRIMARY KEY CHECK (singleton=1),
    catalog_seeded boolean NOT NULL DEFAULT false,
    schema_signature text,
    hash_contract text
);

INSERT INTO ops.phase2_v2_feature_day_hash_state(singleton,catalog_seeded)
VALUES(1,false)
ON CONFLICT(singleton) DO NOTHING;

COMMENT ON TABLE ops.phase2_v2_feature_day_hash_cache IS
    'Exact per-trade-date SHA-256 digests of phase2-v2 feat.features_daily rows; dirty dates are recomputed before a V3 input manifest uses them.';
COMMENT ON TABLE ops.phase2_v2_feature_day_hash_state IS
    'Tracks one-time V2 date-catalog seeding and the row-shape/hash contract used by the Phase 2 V3 input-hash cache.';

CREATE OR REPLACE FUNCTION ops.phase2_v2_feature_day_hash_lock()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Acquire before row locks so competing feature writes cannot deadlock
    -- with a manifest refresh that holds this lock while it reads V2 rows.
    PERFORM pg_advisory_xact_lock(hashtextextended('VN-Signal:phase2-v2-feature-day-hash',0));
    RETURN NULL;
END
$$;

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_write_lock ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_write_lock
BEFORE INSERT OR UPDATE OR DELETE ON feat.features_daily
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_v2_feature_day_hash_lock();

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_truncate_lock ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_truncate_lock
BEFORE TRUNCATE ON feat.features_daily
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_v2_feature_day_hash_lock();

CREATE OR REPLACE FUNCTION ops.phase2_mark_v2_feature_days_dirty()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP='TRUNCATE' THEN
        TRUNCATE TABLE ops.phase2_v2_feature_day_hash_cache;
        UPDATE ops.phase2_v2_feature_day_hash_state
           SET catalog_seeded=false
         WHERE singleton=1;
        RETURN NULL;
    ELSIF TG_OP='INSERT' THEN
        INSERT INTO ops.phase2_v2_feature_day_hash_cache(trade_date,is_dirty)
        SELECT DISTINCT n.trade_date,true
          FROM new_rows n
         WHERE n.feature_version='phase2-v2'
        ON CONFLICT(trade_date) DO UPDATE
            SET is_dirty=true,updated_at=clock_timestamp();
    ELSIF TG_OP='UPDATE' THEN
        WITH affected_days AS (
            SELECT o.trade_date FROM old_rows o WHERE o.feature_version='phase2-v2'
            UNION
            SELECT n.trade_date FROM new_rows n WHERE n.feature_version='phase2-v2'
        )
        INSERT INTO ops.phase2_v2_feature_day_hash_cache(trade_date,is_dirty)
        SELECT d.trade_date,true FROM affected_days d
        ON CONFLICT(trade_date) DO UPDATE
            SET is_dirty=true,updated_at=clock_timestamp();
    ELSIF TG_OP='DELETE' THEN
        INSERT INTO ops.phase2_v2_feature_day_hash_cache(trade_date,is_dirty)
        SELECT DISTINCT o.trade_date,true
          FROM old_rows o
         WHERE o.feature_version='phase2-v2'
        ON CONFLICT(trade_date) DO UPDATE
            SET is_dirty=true,updated_at=clock_timestamp();
    ELSE
        RAISE EXCEPTION 'unexpected feature-day hash invalidation event: %',TG_OP;
    END IF;
    RETURN NULL;
END
$$;

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_insert ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_insert
AFTER INSERT ON feat.features_daily
REFERENCING NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_mark_v2_feature_days_dirty();

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_update ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_update
AFTER UPDATE ON feat.features_daily
REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_mark_v2_feature_days_dirty();

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_delete ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_delete
AFTER DELETE ON feat.features_daily
REFERENCING OLD TABLE AS old_rows
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_mark_v2_feature_days_dirty();

DROP TRIGGER IF EXISTS phase2_features_daily_v2_hash_truncate ON feat.features_daily;
CREATE TRIGGER phase2_features_daily_v2_hash_truncate
AFTER TRUNCATE ON feat.features_daily
FOR EACH STATEMENT EXECUTE FUNCTION ops.phase2_mark_v2_feature_days_dirty();

CREATE OR REPLACE FUNCTION ops.phase2_refresh_v2_feature_day_hashes(p_date_from date,p_date_to date)
RETURNS void LANGUAGE plpgsql SET TimeZone TO 'UTC' AS $$
DECLARE
    v_catalog_seeded boolean;
    v_invalidate_cache boolean;
    v_schema_signature text;
    v_old_enable_seqscan text;
    v_old_enable_bitmapscan text;
    v_trade_date date;
    v_row_count bigint;
    v_day_sha256 text;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required for V2 feature-day hash refresh';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('VN-Signal:phase2-v2-feature-day-hash',0));

    SELECT ops.phase2_hash_text(coalesce(string_agg(
               a.attnum::text||':'||a.attname||':'||a.atttypid::text||':'||
               a.atttypmod::text||':'||a.attcollation::text||':'||a.attnotnull::text||':'||
               coalesce(a.attgenerated::text,'')||':'||coalesce(a.attidentity::text,''),
               '|' ORDER BY a.attnum),''))
      INTO v_schema_signature
      FROM pg_attribute a
     WHERE a.attrelid='feat.features_daily'::regclass
       AND a.attnum>0 AND NOT a.attisdropped;

    SELECT catalog_seeded INTO STRICT v_catalog_seeded
      FROM ops.phase2_v2_feature_day_hash_state
     WHERE singleton=1;

    SELECT schema_signature IS DISTINCT FROM v_schema_signature OR
           hash_contract IS DISTINCT FROM 'phase2-v2-day-sha256-v1'
      INTO v_invalidate_cache
      FROM ops.phase2_v2_feature_day_hash_state
     WHERE singleton=1;

    IF v_invalidate_cache THEN
        UPDATE ops.phase2_v2_feature_day_hash_cache SET is_dirty=true;
        UPDATE ops.phase2_v2_feature_day_hash_state
           SET schema_signature=v_schema_signature,
               hash_contract='phase2-v2-day-sha256-v1'
         WHERE singleton=1;
    END IF;

    IF NOT v_catalog_seeded THEN
        -- The feature-version/date index is covering for this date-only seed.
        -- Avoid a wide heap scan while bootstrapping the small date catalog.
        v_old_enable_seqscan:=current_setting('enable_seqscan');
        v_old_enable_bitmapscan:=current_setting('enable_bitmapscan');
        PERFORM set_config('enable_seqscan','off',true);
        PERFORM set_config('enable_bitmapscan','off',true);

        INSERT INTO ops.phase2_v2_feature_day_hash_cache(trade_date,is_dirty)
        SELECT DISTINCT f.trade_date,true
          FROM feat.features_daily f
         WHERE f.feature_version='phase2-v2'
        ON CONFLICT(trade_date) DO NOTHING;

        UPDATE ops.phase2_v2_feature_day_hash_state
           SET catalog_seeded=true
         WHERE singleton=1;
        PERFORM set_config('enable_bitmapscan',v_old_enable_bitmapscan,true);
        PERFORM set_config('enable_seqscan',v_old_enable_seqscan,true);
    END IF;

    FOR v_trade_date IN
        SELECT c.trade_date
          FROM ops.phase2_v2_feature_day_hash_cache c
         WHERE c.is_dirty AND c.trade_date BETWEEN p_date_from AND p_date_to
         ORDER BY c.trade_date
    LOOP
        SELECT count(*),
               CASE WHEN count(*)=0 THEN NULL
                    ELSE ops.phase2_hash_text(string_agg(
                             ops.phase2_hash_jsonb(to_jsonb(f)),''
                             ORDER BY f.symbol_id,f.trade_date))
               END
          INTO v_row_count,v_day_sha256
          FROM feat.features_daily f
         WHERE f.feature_version='phase2-v2'
           AND f.trade_date=v_trade_date;

        UPDATE ops.phase2_v2_feature_day_hash_cache
           SET row_count=v_row_count,
               day_sha256=v_day_sha256,
               is_dirty=false,
               updated_at=clock_timestamp()
         WHERE trade_date=v_trade_date;
    END LOOP;

    IF EXISTS (
        SELECT 1 FROM ops.phase2_v2_feature_day_hash_cache c
         WHERE c.trade_date BETWEEN p_date_from AND p_date_to AND c.is_dirty
    ) THEN
        RAISE EXCEPTION 'dirty V2 feature-day hashes remain in requested range % through %',p_date_from,p_date_to;
    END IF;
END
$$;

DO $phase2_v2_feature_day_hash_patch$
DECLARE
    definition text:=replace(
        pg_get_functiondef('ops.phase2_chunk_input_hash(text,date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    old_block text;
    new_block text;
BEGIN
    IF position('phase2_v2_feature_day_hash_cache c' IN definition)>0 THEN
        RETURN;
    END IF;

    old_block:=$old$
        SELECT coalesce(string_agg(trade_date::text||':'||day_sha256,'' ORDER BY trade_date),'')
          INTO v_piece
          FROM (
              SELECT f.trade_date,
                     ops.phase2_hash_text(string_agg(ops.phase2_hash_jsonb(to_jsonb(f)),''
                                                      ORDER BY f.symbol_id,f.trade_date)) AS day_sha256
                FROM feat.features_daily f
               WHERE f.feature_version='phase2-v2'
                 AND f.trade_date BETWEEN v_year_anchor AND p_date_to
               GROUP BY f.trade_date
          ) v2_days;
$old$;
    new_block:=$new$
        PERFORM ops.phase2_refresh_v2_feature_day_hashes(v_year_anchor,p_date_to);
        SELECT coalesce(string_agg(c.trade_date::text||':'||c.day_sha256,'' ORDER BY c.trade_date),'')
          INTO v_piece
          FROM ops.phase2_v2_feature_day_hash_cache c
         WHERE c.trade_date BETWEEN v_year_anchor AND p_date_to
           AND NOT c.is_dirty AND c.row_count>0;
$new$;

    IF length(definition)-length(replace(definition,old_block,''))<>length(old_block) THEN
        RAISE EXCEPTION 'expected exactly one year-anchored V2 digest block in Phase 2 input hash';
    END IF;
    definition:=replace(definition,old_block,new_block);
    EXECUTE definition;
END
$phase2_v2_feature_day_hash_patch$;

COMMENT ON FUNCTION ops.phase2_chunk_input_hash(text,date,date) IS
    'Deterministic Phase 2 input manifest. Feature hashes cover the V3 calendar-year anchor plus its preceding 1,000 effective sessions; V2 feature context begins at the year anchor and uses exact trigger-invalidated per-day SHA-256 digests.';

COMMIT;

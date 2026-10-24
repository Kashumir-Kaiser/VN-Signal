\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='180000';
SET LOCAL lock_timeout='5000';

-- Each independent builder pass gets the same 180-second statement budget.
-- Keep all passes in this transaction so row-byte comparisons retain the same
-- transaction timestamp and fixtures, with every original assertion intact.
CREATE TEMP TABLE phase2_shared_test_context (
    symbol_ids bigint[],date_from date,date_to date
) ON COMMIT DROP;

DO $phase2_shared_builder_assertions$
DECLARE
    symbol_ids bigint[];
    date_from date;
    date_to date;
    previous_path text;
    feature_count bigint;
    label_count bigint;
    mismatch_symbol bigint;
    mismatch_date date;
    mismatch_version text;
    mismatch_fields text;
    old_image jsonb;
    rebuilt_image jsonb;
    invalid_schema_rejected boolean:=false;
    canonical_output_rejected boolean:=false;
BEGIN
    IF to_regprocedure('feat.build_features_v2_shared(date,date,bigint[])') IS NULL
       OR to_regprocedure('feat.build_price_features_v3_shared(date,date,bigint[])') IS NULL
       OR to_regprocedure('feat.build_labels_set_based_shared(date,date,bigint[])') IS NULL
       OR to_regprocedure('feat.build_features_and_labels(date,date)') IS NULL
       OR to_regprocedure('feat.build_features_and_labels_scoped(date,date,text,text,text,bigint[])') IS NULL THEN
        RAISE EXCEPTION 'Phase 2 public or shared builder signatures are missing';
    END IF;

    SELECT array_agg(symbol_id ORDER BY symbol_id) INTO symbol_ids
      FROM core.symbols
     WHERE symbol IN ('P2READY','P2STOCH');
    SELECT min(trade_date),max(trade_date) INTO date_from,date_to
      FROM core.calendar WHERE source='phase2_test_fixture';
    IF cardinality(symbol_ids)<>2 OR date_from IS NULL OR date_to IS NULL THEN
        RAISE EXCEPTION 'synthetic Phase 2 symbols or dates are unavailable';
    END IF;
    INSERT INTO phase2_shared_test_context VALUES(symbol_ids,date_from,date_to);

    -- Capture the legacy production API output, then rebuild via the generated
    -- shared SQL with a NULL scope. `record_send` compares every stored field,
    -- including float8 wire bytes and transaction-stable timestamps.
    PERFORM feat.build_features_and_labels(date_from,date_to);
    CREATE TEMP TABLE phase2_shared_legacy_features ON COMMIT DROP AS
    SELECT f.symbol_id,f.trade_date,f.feature_version,
           md5(encode(pg_catalog.record_send(f),'hex')) AS row_sha256
      FROM feat.features_daily f
     WHERE f.trade_date BETWEEN date_from AND date_to
       AND f.feature_version IN ('phase2-v2','phase2-v3');
    CREATE TEMP TABLE phase2_shared_legacy_labels ON COMMIT DROP AS
    SELECT l.symbol_id,l.signal_date,l.horizon_sessions,
           md5(encode(pg_catalog.record_send(l),'hex')) AS row_sha256
      FROM feat.labels_daily l
     WHERE l.signal_date BETWEEN date_from AND date_to
       AND l.label_version='close-next-open-v1';

END;
$phase2_shared_builder_assertions$;

DO $phase2_shared_full_assertions$
DECLARE
    symbol_ids bigint[];
    date_from date;
    date_to date;
    previous_path text;
BEGIN
    SELECT c.symbol_ids,c.date_from,c.date_to INTO symbol_ids,date_from,date_to
      FROM pg_temp.phase2_shared_test_context c;
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    PERFORM feat.build_features_v2_shared(date_from,date_to,NULL);
    PERFORM feat.build_price_features_v3_shared(date_from,date_to,NULL);
    PERFORM feat.build_labels_set_based_shared(date_from,date_to,NULL);
    PERFORM feat.phase2_builder_restore_context(previous_path);

    IF EXISTS (
        SELECT 1 FROM phase2_shared_legacy_features old
        FULL JOIN (
            SELECT f.symbol_id,f.trade_date,f.feature_version,
                   md5(encode(pg_catalog.record_send(f),'hex')) AS row_sha256
              FROM feat.features_daily f
             WHERE f.trade_date BETWEEN date_from AND date_to
               AND f.feature_version IN ('phase2-v2','phase2-v3')
        ) rebuilt USING(symbol_id,trade_date,feature_version)
        WHERE old.symbol_id IS NULL OR rebuilt.symbol_id IS NULL
           OR old.row_sha256 IS DISTINCT FROM rebuilt.row_sha256
    ) THEN
        RAISE EXCEPTION 'legacy full-universe builder output differs from the NULL-scope shared SQL';
    END IF;
    IF EXISTS (
        SELECT 1 FROM phase2_shared_legacy_labels old
        FULL JOIN (
            SELECT l.symbol_id,l.signal_date,l.horizon_sessions,
                   md5(encode(pg_catalog.record_send(l),'hex')) AS row_sha256
              FROM feat.labels_daily l
             WHERE l.signal_date BETWEEN date_from AND date_to
               AND l.label_version='close-next-open-v1'
        ) rebuilt USING(symbol_id,signal_date,horizon_sessions)
        WHERE old.symbol_id IS NULL OR rebuilt.symbol_id IS NULL
           OR old.row_sha256 IS DISTINCT FROM rebuilt.row_sha256
    ) THEN
        RAISE EXCEPTION 'legacy label output differs from the NULL-scope shared SQL';
    END IF;

    -- Assert the production label boundary convention directly: signal at
    -- session t enters at t+1 and exits at t+6 / t+21 for 5 / 20 sessions.
    CREATE TEMP TABLE phase2_expected_label_boundaries ON COMMIT DROP AS
    WITH calendar_axis AS MATERIALIZED (
        SELECT trade_date,
               lead(trade_date,1) OVER (ORDER BY trade_date) AS entry_date,
               lead(trade_date,6) OVER (ORDER BY trade_date) AS exit_5_date,
               lead(trade_date,21) OVER (ORDER BY trade_date) AS exit_20_date
          FROM core.effective_trading_sessions
         WHERE is_session
    )
    SELECT f.symbol_id,c.trade_date AS signal_date,h.horizon_sessions,
           c.entry_date,
           CASE h.horizon_sessions WHEN 5 THEN c.exit_5_date ELSE c.exit_20_date END AS exit_date
      FROM calendar_axis c
      JOIN feat.features_daily f
        ON f.trade_date=c.trade_date AND f.feature_version='phase2-v3'
       AND f.symbol_id=ANY(symbol_ids)
      CROSS JOIN (VALUES (5::smallint),(20::smallint)) h(horizon_sessions)
     WHERE c.trade_date BETWEEN date_from AND date_to;
    IF EXISTS (
        SELECT 1
          FROM phase2_expected_label_boundaries e
          FULL JOIN (
              SELECT * FROM feat.labels_daily
               WHERE signal_date BETWEEN date_from AND date_to
                 AND label_version='close-next-open-v1'
                 AND symbol_id=ANY(symbol_ids)
          ) l
            ON l.symbol_id=e.symbol_id AND l.signal_date=e.signal_date
           AND l.horizon_sessions=e.horizon_sessions
           AND l.label_version='close-next-open-v1'
         WHERE e.symbol_id IS NULL OR l.symbol_id IS NULL
            OR l.entry_date IS DISTINCT FROM e.entry_date
            OR l.exit_date IS DISTINCT FROM e.exit_date
    ) THEN
        RAISE EXCEPTION 'label entry/exit dates do not match next-session and +6/+21-session boundaries';
    END IF;

    -- Create isolated schema copies of the exact builder inputs and outputs.
    CREATE SCHEMA phase2_shared_input;
    CREATE SCHEMA phase2_shared_output;
    CREATE SCHEMA phase2_shared_ops;
    CREATE TABLE phase2_shared_input.effective_trading_sessions AS
        SELECT trade_date,is_session FROM core.effective_trading_sessions;
    CREATE TABLE phase2_shared_input.symbols AS
        SELECT symbol_id,exchange FROM core.symbols WHERE symbol_id=ANY(symbol_ids);
    CREATE TABLE phase2_shared_input.index_bars AS SELECT * FROM core.index_bars;
    CREATE TABLE phase2_shared_input.phase2_vci_index_features AS
        SELECT * FROM feat.phase2_vci_index_features;
    CREATE TABLE phase2_shared_input.phase2_adjustment_rows AS
        SELECT r.symbol_id,r.trade_date,r.source,r.v,r.is_traded,
               r.reference_adjustment_ratio,r.episode_start_date,
               r.model_o,r.model_h,r.model_l,r.model_c,
               r.adjustment_vintage_at,r.landing_id,r.source_row,r.fetched_at
          FROM core.vndirect_reference_adjustment_details r
         WHERE r.source='vndirect' AND r.symbol_id=ANY(symbol_ids);
    CREATE TABLE phase2_shared_ops.ml_symbol_scope AS
        SELECT symbol_id,scope_status FROM ops.ml_symbol_scope
         WHERE symbol_id=ANY(symbol_ids);
    CREATE TABLE phase2_shared_output.features_daily
        (LIKE feat.features_daily INCLUDING ALL);
    CREATE TABLE phase2_shared_output.labels_daily
        (LIKE feat.labels_daily INCLUDING ALL);
    CREATE TEMP TABLE phase2_market_features_daily ON COMMIT DROP AS
    SELECT symbol_id,trade_date,feature_version,ret_1,
           distance_52w_high,distance_52w_low,turnover_proxy_vnd
      FROM feat.features_daily
     WHERE feature_version='phase2-v2';
    CREATE INDEX phase2_market_features_daily_date_symbol_idx
        ON phase2_market_features_daily(trade_date,symbol_id);
    ANALYZE phase2_market_features_daily;

END;
$phase2_shared_full_assertions$;

DO $phase2_shared_scoped_assertions$
DECLARE
    symbol_ids bigint[];
    date_from date;
    date_to date;
    previous_path text;
BEGIN
    SELECT c.symbol_ids,c.date_from,c.date_to INTO symbol_ids,date_from,date_to
      FROM pg_temp.phase2_shared_test_context c;
    -- Rebuild the same two-symbol cohort inside isolated schemas. Compare its
    -- complete row bytes against the scoped shared implementation in `core` /
    -- `feat` so schema routing cannot change calculations or ranks.
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    PERFORM feat.build_features_v2_shared(date_from,date_to,symbol_ids);
    PERFORM feat.build_price_features_v3_shared(date_from,date_to,symbol_ids);
    PERFORM feat.build_labels_set_based_shared(date_from,date_to,symbol_ids);
    PERFORM feat.phase2_builder_restore_context(previous_path);

    CREATE TEMP TABLE phase2_shared_scoped_features ON COMMIT DROP AS
    SELECT f.symbol_id,f.trade_date,f.feature_version,
           to_jsonb(f) AS row_image,
           md5(encode(pg_catalog.record_send(f),'hex')) AS row_sha256
      FROM feat.features_daily f
     WHERE f.trade_date BETWEEN date_from AND date_to
       AND f.symbol_id=ANY(symbol_ids)
       AND f.feature_version IN ('phase2-v2','phase2-v3');
    CREATE TEMP TABLE phase2_shared_scoped_labels ON COMMIT DROP AS
    SELECT l.symbol_id,l.signal_date,l.horizon_sessions,
           to_jsonb(l) AS row_image,
           md5(encode(pg_catalog.record_send(l),'hex')) AS row_sha256
      FROM feat.labels_daily l
     WHERE l.signal_date BETWEEN date_from AND date_to
       AND l.symbol_id=ANY(symbol_ids)
       AND l.label_version='close-next-open-v1';

END;
$phase2_shared_scoped_assertions$;

DO $phase2_shared_isolated_assertions$
DECLARE
    symbol_ids bigint[];
    date_from date;
    date_to date;
    feature_count bigint;
    label_count bigint;
    mismatch_symbol bigint;
    mismatch_date date;
    mismatch_version text;
    mismatch_fields text;
    old_image jsonb;
    rebuilt_image jsonb;
    invalid_schema_rejected boolean:=false;
    canonical_output_rejected boolean:=false;
BEGIN
    SELECT c.symbol_ids,c.date_from,c.date_to INTO symbol_ids,date_from,date_to
      FROM pg_temp.phase2_shared_test_context c;
    SELECT b.feature_rows,b.label_rows INTO feature_count,label_count
      FROM feat.build_features_and_labels_scoped(
          date_from,date_to,'phase2_shared_input','phase2_shared_output',
          'phase2_shared_ops',symbol_ids
      ) b;
    IF feature_count=0 OR label_count=0 THEN
        RAISE EXCEPTION 'isolated shared builder returned no feature or label rows';
    END IF;
    IF EXISTS (
        SELECT symbol_id FROM unnest(symbol_ids) AS selected(symbol_id)
        EXCEPT
        SELECT DISTINCT symbol_id FROM phase2_shared_scoped_features
    ) THEN
        RAISE EXCEPTION 'scoped shared output omitted a selected cohort symbol';
    END IF;
    IF EXISTS (
        SELECT symbol_id FROM unnest(symbol_ids) AS selected(symbol_id)
        EXCEPT
        SELECT DISTINCT f.symbol_id
          FROM phase2_shared_output.features_daily f
         WHERE f.trade_date BETWEEN date_from AND date_to
           AND f.feature_version IN ('phase2-v2','phase2-v3')
    ) THEN
        RAISE EXCEPTION 'isolated shared output omitted a selected cohort symbol';
    END IF;
    IF EXISTS (
        SELECT 1 FROM phase2_shared_scoped_features old
        FULL JOIN (
            SELECT f.symbol_id,f.trade_date,f.feature_version,
                   md5(encode(pg_catalog.record_send(f),'hex')) AS row_sha256
              FROM phase2_shared_output.features_daily f
             WHERE f.trade_date BETWEEN date_from AND date_to
               AND f.symbol_id=ANY(symbol_ids)
               AND f.feature_version IN ('phase2-v2','phase2-v3')
        ) rebuilt USING(symbol_id,trade_date,feature_version)
        WHERE old.symbol_id IS NULL OR rebuilt.symbol_id IS NULL
           OR old.row_sha256 IS DISTINCT FROM rebuilt.row_sha256
    ) THEN
        SELECT coalesce(old.symbol_id,rebuilt.symbol_id),
               coalesce(old.trade_date,rebuilt.trade_date),
               coalesce(old.feature_version,rebuilt.feature_version)
          INTO mismatch_symbol,mismatch_date,mismatch_version
          FROM phase2_shared_scoped_features old
          FULL JOIN (
              SELECT f.symbol_id,f.trade_date,f.feature_version,
                     md5(encode(pg_catalog.record_send(f),'hex')) AS row_sha256
                FROM phase2_shared_output.features_daily f
               WHERE f.trade_date BETWEEN date_from AND date_to
                 AND f.symbol_id=ANY(symbol_ids)
                 AND f.feature_version IN ('phase2-v2','phase2-v3')
          ) rebuilt USING(symbol_id,trade_date,feature_version)
         WHERE old.symbol_id IS NULL OR rebuilt.symbol_id IS NULL
            OR old.row_sha256 IS DISTINCT FROM rebuilt.row_sha256
         ORDER BY coalesce(old.trade_date,rebuilt.trade_date),
                  coalesce(old.symbol_id,rebuilt.symbol_id),
                  coalesce(old.feature_version,rebuilt.feature_version)
         LIMIT 1;
        SELECT old.row_image,to_jsonb(rebuilt)
          INTO old_image,rebuilt_image
          FROM phase2_shared_scoped_features old
          JOIN phase2_shared_output.features_daily rebuilt
            USING(symbol_id,trade_date,feature_version)
         WHERE old.symbol_id=mismatch_symbol AND old.trade_date=mismatch_date
           AND old.feature_version=mismatch_version;
        IF old_image IS NOT NULL AND rebuilt_image IS NOT NULL THEN
            SELECT string_agg(k.key,',' ORDER BY k.key) INTO mismatch_fields
              FROM jsonb_object_keys(old_image) AS k(key)
             WHERE old_image->k.key IS DISTINCT FROM rebuilt_image->k.key;
        ELSE
            mismatch_fields:='row missing in one output';
        END IF;
        RAISE EXCEPTION 'isolated schema feature rows differ from scoped shared SQL at symbol %, date %, version %, fields %',
            mismatch_symbol,mismatch_date,mismatch_version,mismatch_fields;
    END IF;
    IF EXISTS (
        SELECT 1 FROM phase2_shared_scoped_labels old
        FULL JOIN (
            SELECT l.symbol_id,l.signal_date,l.horizon_sessions,
                   md5(encode(pg_catalog.record_send(l),'hex')) AS row_sha256
              FROM phase2_shared_output.labels_daily l
             WHERE l.signal_date BETWEEN date_from AND date_to
               AND l.symbol_id=ANY(symbol_ids)
               AND l.label_version='close-next-open-v1'
        ) rebuilt USING(symbol_id,signal_date,horizon_sessions)
        WHERE old.symbol_id IS NULL OR rebuilt.symbol_id IS NULL
           OR old.row_sha256 IS DISTINCT FROM rebuilt.row_sha256
    ) THEN
        RAISE EXCEPTION 'isolated schema label rows differ from scoped shared SQL';
    END IF;

    BEGIN
        PERFORM 1 FROM feat.build_features_and_labels_scoped(
            date_from,date_to,'phase2_shared_input','feat','phase2_shared_ops',symbol_ids
        );
    EXCEPTION WHEN OTHERS THEN
        canonical_output_rejected:=position(
            'scoped Phase 2 builders require isolated output and ops schemas' IN SQLERRM
        )>0;
    END;
    IF NOT canonical_output_rejected THEN
        RAISE EXCEPTION 'scoped builder did not reject canonical production output schema before writing';
    END IF;

    BEGIN
        PERFORM 1 FROM feat.build_features_and_labels_scoped(
            date_from,date_to,'phase2_shared_input;DROP SCHEMA core',
            'phase2_shared_output','phase2_shared_ops',symbol_ids
        );
    EXCEPTION WHEN OTHERS THEN
        invalid_schema_rejected:=position('invalid Phase 2 schema identifier' IN SQLERRM)>0;
    END;
    IF NOT invalid_schema_rejected THEN
        RAISE EXCEPTION 'scoped builder accepted an injected schema identifier';
    END IF;
END;
$phase2_shared_isolated_assertions$;

ROLLBACK;

BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Reuse the session first-date cache for the liquidity-series spine as well as
-- the prior-membership checkpoint. The p_date_to cutoff is equivalent to the
-- original per-symbol min(trade_date) filtered to dates through p_date_to.
DO $phase2_label_series_start_cache$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_init constant text := $old_init$
    IF v_first_signal IS NULL THEN
        DELETE FROM feat.phase2_label_targets_v3
         WHERE signal_date BETWEEN p_date_from AND p_date_to;
        RETURN 0;
    END IF;

    SELECT max(trade_date) INTO v_prior_session
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date<v_first_signal;
$old_init$;
    v_new_init constant text := $new_init$
    IF v_first_signal IS NULL THEN
        DELETE FROM feat.phase2_label_targets_v3
         WHERE signal_date BETWEEN p_date_from AND p_date_to;
        RETURN 0;
    END IF;

    IF to_regclass('pg_temp.phase2_label_feature_first_dates') IS NULL THEN
        CREATE TEMP TABLE phase2_label_feature_first_dates (
            feature_set_hash text NOT NULL,
            symbol_id bigint NOT NULL,
            first_date date NOT NULL,
            PRIMARY KEY(feature_set_hash,symbol_id)
        ) ON COMMIT PRESERVE ROWS;
        CREATE INDEX phase2_label_feature_first_dates_cutoff_idx
            ON pg_temp.phase2_label_feature_first_dates(feature_set_hash,first_date);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_temp.phase2_label_feature_first_dates
         WHERE feature_set_hash=v_hash
    ) THEN
        INSERT INTO pg_temp.phase2_label_feature_first_dates(feature_set_hash,symbol_id,first_date)
        SELECT v_hash,symbol_id,min(trade_date)
          FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash
         GROUP BY symbol_id;
        ANALYZE pg_temp.phase2_label_feature_first_dates;
    END IF;

    SELECT max(trade_date) INTO v_prior_session
      FROM core.effective_trading_sessions
     WHERE is_session AND trade_date<v_first_signal;
$new_init$;
    v_old_series constant text := $old_series$
    WITH symbol_start AS MATERIALIZED (
        SELECT symbol_id,min(trade_date) AS first_date
          FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash AND trade_date<=p_date_to
         GROUP BY symbol_id
    ), series AS MATERIALIZED (
$old_series$;
    v_new_series constant text := $new_series$
    WITH symbol_start AS MATERIALIZED (
        SELECT symbol_id,first_date
          FROM pg_temp.phase2_label_feature_first_dates
         WHERE feature_set_hash=v_hash AND first_date<=p_date_to
    ), series AS MATERIALIZED (
$new_series$;
BEGIN
    IF position(v_new_init IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_init,''))<>length(v_new_init)
           OR position(v_old_init IN v_definition)>0 THEN
            RAISE EXCEPTION 'session cache initialization hook is duplicated or conflicts with the old function';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_init,''))<>length(v_old_init) THEN
            RAISE EXCEPTION 'expected exactly one label builder empty-range/previous-session anchor';
        END IF;
        v_definition:=replace(v_definition,v_old_init,v_new_init);
    END IF;

    IF position(v_new_series IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_series,''))<>length(v_new_series)
           OR position(v_old_series IN v_definition)>0 THEN
            RAISE EXCEPTION 'cached liquidity-series start is duplicated or conflicts with the old query';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_series,''))<>length(v_old_series) THEN
            RAISE EXCEPTION 'expected exactly one feature-table symbol-start CTE';
        END IF;
        v_definition:=replace(v_definition,v_old_series,v_new_series);
    END IF;

    EXECUTE v_definition;
END;
$phase2_label_series_start_cache$;

DO $phase2_label_series_start_cache_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
BEGIN
    IF position('phase2_label_feature_first_dates' IN v_definition)=0
       OR position('ON COMMIT PRESERVE ROWS' IN v_definition)=0
       OR position('WHERE feature_set_hash=v_hash AND first_date<=p_date_to' IN v_definition)=0
       OR position('FROM feat.features_daily' IN v_definition)=0
       OR position('NULLIF(current_setting(' IN v_definition)=0
       OR position('ORDER BY volatility_scaled_score ASC,symbol_id' IN v_definition)=0 THEN
        RAISE EXCEPTION 'label series cache is missing or prior label-build hooks were lost';
    END IF;
END;
$phase2_label_series_start_cache_assertions$;

COMMIT;

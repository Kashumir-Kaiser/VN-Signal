BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- The derived-label runner processes monthly chunks in one PostgreSQL session.
-- Cache the exact first-feature date for each symbol/hash in a temporary table
-- that survives chunk commits, avoiding one wide-table GROUP BY per month.
DO $phase2_label_checkpoint_session_cache$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_anchor constant text := $old$
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
$old$;
    v_new_anchor constant text := $new$
    IF v_prior_session IS NOT NULL AND v_first_signal>coalesce(v_first_feature,v_first_signal) THEN
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
        IF NOT EXISTS (
            SELECT 1 FROM feat.phase2_liquidity_tiers_v3
             WHERE trade_date=v_prior_session AND feature_set_hash=v_hash
             GROUP BY trade_date
             HAVING count(*)=(SELECT count(*)
                                FROM pg_temp.phase2_label_feature_first_dates
                               WHERE feature_set_hash=v_hash AND first_date<=v_prior_session)
        ) THEN
            RAISE EXCEPTION 'liquidity membership checkpoint missing before chunk start %',v_first_signal;
        END IF;
    END IF;
$new$;
BEGIN
    IF position(v_new_anchor IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_anchor,''))<>length(v_new_anchor)
           OR position(v_old_anchor IN v_definition)>0 THEN
            RAISE EXCEPTION 'session first-date cache hook is duplicated or conflicts with the old checkpoint guard';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_anchor,''))<>length(v_old_anchor) THEN
            RAISE EXCEPTION 'expected exactly one old full-table label checkpoint guard';
        END IF;
        v_definition:=replace(v_definition,v_old_anchor,v_new_anchor);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_checkpoint_session_cache$;

DO $phase2_label_checkpoint_session_cache_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
BEGIN
    IF position('phase2_label_feature_first_dates' IN v_definition)=0
       OR position('ON COMMIT PRESERVE ROWS' IN v_definition)=0
       OR position('NULLIF(current_setting(' IN v_definition)=0
       OR position('ORDER BY volatility_scaled_score ASC,symbol_id' IN v_definition)=0 THEN
        RAISE EXCEPTION 'session label cache is missing or prior 090/094 label hooks were lost';
    END IF;
END;
$phase2_label_checkpoint_session_cache_assertions$;

COMMIT;

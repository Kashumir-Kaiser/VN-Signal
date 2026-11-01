BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Use the existing V3 index to fetch each symbol's first feature date. The
-- previous grouped scan read the 4.8 GiB wide feature table and timed out on
-- the low-memory report clone before it could seed the session cache.
DO $phase2_label_first_date_index_lookup$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_query constant text := $old$
            INSERT INTO pg_temp.phase2_label_feature_first_dates(feature_set_hash,symbol_id,first_date)
            SELECT v_hash,symbol_id,min(trade_date)
              FROM feat.features_daily
             WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash
             GROUP BY symbol_id;
$old$;
    v_new_query constant text := $new$
            INSERT INTO pg_temp.phase2_label_feature_first_dates(feature_set_hash,symbol_id,first_date)
            SELECT v_hash,s.symbol_id,f.first_date
              FROM core.symbols s
              CROSS JOIN LATERAL (
                  SELECT fd.trade_date AS first_date
                    FROM feat.features_daily fd
                   WHERE fd.feature_version='phase2-v3'
                     AND fd.feature_set_hash=v_hash
                     AND fd.symbol_id=s.symbol_id
                   ORDER BY fd.trade_date
                   LIMIT 1
              ) f;
$new$;
BEGIN
    IF position(v_new_query IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_query,''))<>length(v_new_query)
           OR position(v_old_query IN v_definition)>0 THEN
            RAISE EXCEPTION 'indexed first-date lookup is duplicated or conflicts with the old grouped scan';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_query,''))<>length(v_old_query) THEN
            RAISE EXCEPTION 'expected exactly one old session-cache grouped first-date lookup';
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM pg_constraint c
             WHERE c.conrelid='feat.features_daily'::regclass
               AND c.confrelid='core.symbols'::regclass
               AND c.contype='f'
               AND c.convalidated
        ) THEN
            RAISE EXCEPTION 'indexed first-date lookup requires the validated features_daily symbol foreign key';
        END IF;
        v_definition:=replace(v_definition,v_old_query,v_new_query);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_first_date_index_lookup$;

DO $phase2_label_first_date_index_lookup_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
BEGIN
    IF position('FROM core.symbols s' IN v_definition)=0
       OR position('CROSS JOIN LATERAL' IN v_definition)=0
       OR position('ORDER BY fd.trade_date' IN v_definition)=0
       OR position('LIMIT 1' IN v_definition)=0
       OR position('AND fd.feature_set_hash=v_hash' IN v_definition)=0 THEN
        RAISE EXCEPTION 'label cache no longer uses indexed per-symbol first-date lookups';
    END IF;
END;
$phase2_label_first_date_index_lookup_assertions$;

COMMIT;

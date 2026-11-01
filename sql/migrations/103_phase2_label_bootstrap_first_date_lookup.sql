BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Migration 097 added an early cache bootstrap with the old grouped scan.
-- Migration 099 optimized the later liquidity-check bootstrap but left this
-- separate first-date seed intact. Replace that exact remaining call site.
DO $phase2_label_bootstrap_first_date_lookup$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('feat.build_phase2_label_targets_v3(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_seed constant text := $old$
        INSERT INTO pg_temp.phase2_label_feature_first_dates(feature_set_hash,symbol_id,first_date)
        SELECT v_hash,symbol_id,min(trade_date)
          FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND feature_set_hash=v_hash
         GROUP BY symbol_id;
$old$;
    v_new_seed constant text := $new$
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
    v_old_marker constant text := 'SELECT v_hash,symbol_id,min(trade_date)';
    v_new_marker constant text := 'SELECT v_hash,s.symbol_id,f.first_date';
    v_old_count integer;
    v_new_count integer;
BEGIN
    v_old_count := (length(v_definition)-length(replace(v_definition,v_old_marker,'')))
                   / length(v_old_marker);
    v_new_count := (length(v_definition)-length(replace(v_definition,v_new_marker,'')))
                   / length(v_new_marker);

    IF v_old_count=1 AND v_new_count=1 THEN
        IF NOT EXISTS (
            SELECT 1
              FROM pg_constraint c
             WHERE c.conrelid='feat.features_daily'::regclass
               AND c.confrelid='core.symbols'::regclass
               AND c.contype='f'
               AND c.convalidated
        ) THEN
            RAISE EXCEPTION 'indexed first-date seed requires the validated features_daily symbol foreign key';
        END IF;
        v_definition := replace(v_definition,v_old_seed,v_new_seed);
        IF position(v_old_seed IN v_definition)>0 THEN
            RAISE EXCEPTION 'grouped bootstrap seed remains after indexed replacement';
        END IF;
        EXECUTE v_definition;
    ELSIF v_old_count=0 AND v_new_count=2 THEN
        -- Idempotent replay after both cache-seeding call sites are indexed.
        NULL;
    ELSE
        RAISE EXCEPTION 'expected one grouped bootstrap seed and one indexed liquidity seed; found old %, indexed %',
            v_old_count,v_new_count;
    END IF;
END;
$phase2_label_bootstrap_first_date_lookup$;

DO $phase2_label_bootstrap_first_date_lookup_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_phase2_label_targets_v3(date,date)'::regprocedure
    );
    v_old_marker constant text := 'SELECT v_hash,symbol_id,min(trade_date)';
    v_new_marker constant text := 'SELECT v_hash,s.symbol_id,f.first_date';
BEGIN
    IF position(v_old_marker IN v_definition)>0
       OR (length(v_definition)-length(replace(v_definition,v_new_marker,'')))<>2*length(v_new_marker)
       OR position('ORDER BY fd.trade_date' IN v_definition)=0
       OR position('LIMIT 1' IN v_definition)=0 THEN
        RAISE EXCEPTION 'both label first-date cache seeds must use indexed per-symbol lookups';
    END IF;
END;
$phase2_label_bootstrap_first_date_lookup_assertions$;

COMMIT;

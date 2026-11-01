BEGIN;

SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30min';

-- Keep the exact linked price-limit set, but probe the existing
-- (symbol_id,trade_date,source) index once per relevant label window instead
-- of scanning all price-limit observations and expanding a merge join.
DO $phase2_label_limit_hash_window_index$
DECLARE
    v_definition text := replace(
        pg_get_functiondef('ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    v_old_join constant text := $old$
          FROM relevant_windows w
          JOIN core.daily_price_limit_observations p
            ON p.symbol_id=w.symbol_id AND p.source='vndirect'
           AND p.trade_date BETWEEN w.entry_date AND w.exit_date
          JOIN raw.landings rl ON rl.landing_id=p.raw_landing_id
$old$;
    v_new_join constant text := $new$
          FROM relevant_windows w
          CROSS JOIN LATERAL (
              SELECT p.observation_id,p.symbol_id,p.source,p.trade_date,
                     p.limit_up,p.limit_down,p.available_at,p.fetched_at,
                     p.raw_landing_id,p.source_row,p.row_payload
                FROM core.daily_price_limit_observations p
               WHERE p.symbol_id=w.symbol_id AND p.source='vndirect'
                 AND p.trade_date BETWEEN w.entry_date AND w.exit_date
               OFFSET 0
          ) p
          JOIN raw.landings rl ON rl.landing_id=p.raw_landing_id
$new$;
BEGIN
    IF position(v_new_join IN v_definition)>0 THEN
        IF length(v_definition)-length(replace(v_definition,v_new_join,''))<>length(v_new_join)
           OR position(v_old_join IN v_definition)>0 THEN
            RAISE EXCEPTION 'indexed price-limit window lookup is duplicated or conflicts with the old join';
        END IF;
    ELSE
        IF length(v_definition)-length(replace(v_definition,v_old_join,''))<>length(v_old_join) THEN
            RAISE EXCEPTION 'expected exactly one original price-limit window join';
        END IF;
        IF NOT EXISTS (
            SELECT 1
              FROM pg_index i
             WHERE i.indexrelid='core.daily_price_limit_observations_symbol_date_source_idx'::regclass
               AND i.indisvalid AND i.indisready
        ) THEN
            RAISE EXCEPTION 'indexed price-limit lookup requires the valid symbol/date/source index';
        END IF;
        v_definition:=replace(v_definition,v_old_join,v_new_join);
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_limit_hash_window_index$;

DO $phase2_label_limit_hash_window_index_assertions$
DECLARE
    v_definition text := pg_get_functiondef(
        'ops.phase2_label_target_chunk_input_hash(date,date)'::regprocedure
    );
BEGIN
    IF position('CROSS JOIN LATERAL' IN v_definition)=0
       OR position('OFFSET 0' IN v_definition)=0
       OR position('daily_price_limit_observations' IN v_definition)=0
       OR position('p.trade_date BETWEEN w.entry_date AND w.exit_date' IN v_definition)=0
       OR position('JOIN raw.landings rl ON rl.landing_id=p.raw_landing_id' IN v_definition)=0 THEN
        RAISE EXCEPTION 'exact price-limit input hash lost its indexed per-window observation lookup';
    END IF;
END;
$phase2_label_limit_hash_window_index_assertions$;

COMMIT;

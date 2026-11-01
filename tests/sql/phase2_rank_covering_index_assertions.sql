\set ON_ERROR_STOP on
BEGIN READ ONLY;
DO $$
DECLARE
    v_index oid:=to_regclass('feat.features_daily_v2_rank_inputs_cover_idx');
    v_definition text;
    v_key_columns smallint;
    v_total_columns smallint;
BEGIN
    IF v_index IS NULL THEN
        RAISE EXCEPTION 'V2 rank-input covering index is missing';
    END IF;
    SELECT lower(pg_get_indexdef(v_index)),i.indnkeyatts,i.indnatts
      INTO v_definition,v_key_columns,v_total_columns
      FROM pg_index i WHERE i.indexrelid=v_index;
    IF v_key_columns<>2 OR v_total_columns<>5
       OR position('on feat.features_daily using btree (trade_date, symbol_id)' IN v_definition)=0
       OR position('include (return_20s, turnover_proxy_vnd, realized_vol20)' IN v_definition)=0
       OR position('where (feature_version = ''phase2-v2''::text)' IN v_definition)=0 THEN
        RAISE EXCEPTION 'V2 rank-input index does not cover the exact narrow rank source: %',v_definition;
    END IF;
END $$;
ROLLBACK;

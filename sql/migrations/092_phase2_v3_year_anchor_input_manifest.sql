-- The V3 builder starts each calendar-year calculation at January 1 and uses
-- the preceding 1,000 effective sessions as recursive warmup. The chunk input
-- manifest must cover that same input window so resumable builds cannot reuse
-- chunks after an omitted warmup or early-year V2 input changes.
BEGIN;

DO $phase2_v3_input_manifest$
DECLARE
    definition text:=replace(
        pg_get_functiondef('ops.phase2_chunk_input_hash(text,date,date)'::regprocedure),
        E'\r\n',E'\n'
    );
    anchor text;
    replacement text;
    feature_start integer;
    labels_start integer;
    feature_block text;
BEGIN
    IF position('|v3_year_anchor=' IN definition)>0 THEN
        RETURN;
    END IF;

    anchor:='    v_history_from date;';
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected Phase 2 input-hash history declaration';
    END IF;
    definition:=replace(definition,anchor,anchor||E'\n    v_year_anchor date;');

    anchor:='    v_manifest:=''phase2-input-v2|stage=''||p_stage||''|from=''||p_date_from||''|to=''||p_date_to;';
    replacement:=$manifest$
    v_manifest:='phase2-input-v'||CASE WHEN p_stage IN ('features','labels') THEN '3' ELSE '2' END||
                 '|stage='||p_stage||'|from='||p_date_from||'|to='||p_date_to;
$manifest$;
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected Phase 2 input-hash manifest-version anchor';
    END IF;
    definition:=replace(definition,anchor,replacement);

    anchor:=$history$
        SELECT coalesce(min(trade_date),p_date_from) INTO v_history_from
          FROM (SELECT trade_date
                  FROM core.effective_trading_sessions
                 WHERE is_session AND trade_date<p_date_from
                 ORDER BY trade_date DESC LIMIT 1000) warmup;
$history$;
    replacement:=$history$
        v_year_anchor:=date_trunc('year',p_date_from)::date;
        SELECT coalesce(min(trade_date),v_year_anchor) INTO v_history_from
          FROM (SELECT trade_date
                  FROM core.effective_trading_sessions
                 WHERE is_session AND trade_date<v_year_anchor
                 ORDER BY trade_date DESC LIMIT 1000) warmup;
        v_manifest:=v_manifest||'|v3_year_anchor='||v_year_anchor||'|v3_history_from='||v_history_from;
$history$;
    IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'unexpected Phase 2 V3 history-window anchor';
    END IF;
    definition:=replace(definition,anchor,replacement);

    feature_start:=position('    IF p_stage=''features'' THEN' IN definition);
    labels_start:=position('    ELSIF p_stage=''labels'' THEN' IN definition);
    IF feature_start=0 OR labels_start<=feature_start THEN
        RAISE EXCEPTION 'Phase 2 feature/label manifest branches are missing or reordered';
    END IF;
    feature_block:=substring(definition FROM feature_start FOR labels_start-feature_start);

    anchor:='                 AND f.trade_date BETWEEN p_date_from AND p_date_to';
    replacement:='                 AND f.trade_date BETWEEN v_year_anchor AND p_date_to';
    IF length(feature_block)-length(replace(feature_block,anchor,''))<>length(anchor) THEN
        RAISE EXCEPTION 'expected exactly one V2 feature range in the feature manifest';
    END IF;
    feature_block:=replace(feature_block,anchor,replacement);
    definition:=substring(definition FROM 1 FOR feature_start-1)||
                feature_block||substring(definition FROM labels_start);

    IF position('trade_date<v_year_anchor' IN definition)=0
       OR position('v3_year_anchor=' IN definition)=0
       OR position('trade_date BETWEEN v_year_anchor AND p_date_to' IN definition)=0
       OR position('THEN ''3'' ELSE ''2'' END' IN definition)=0 THEN
        RAISE EXCEPTION 'Phase 2 V3 input manifest transformation is incomplete';
    END IF;
    EXECUTE definition;
END
$phase2_v3_input_manifest$;

COMMENT ON FUNCTION ops.phase2_chunk_input_hash(text,date,date) IS
    'Deterministic Phase 2 input manifest. Feature hashes cover the V3 calendar-year anchor plus its preceding 1,000 effective sessions; V2 feature context begins at the year anchor. Feature and label manifest domains are v3.';

COMMIT;

-- A refill or new cache generation invalidates hashes of the old cache.
BEGIN;
CREATE OR REPLACE FUNCTION feat.invalidate_phase2_price_cache_hashes()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE item record; relation oid;
BEGIN
 FOR item IN SELECT * FROM (VALUES
   ('phase2_price_day_hashes','VN-Signal Phase 2 deterministic price-day hashes'),
   ('phase2_price_day_hash_coverage','VN-Signal Phase 2 deterministic price-hash date coverage')
 ) expected(name,description) LOOP
  relation:=to_regclass(format('pg_temp.%I',item.name));
  IF relation IS NOT NULL THEN
   IF obj_description(relation,'pg_class') IS DISTINCT FROM item.description THEN
    RAISE EXCEPTION 'temporary relation % is reserved by the Phase 2 builder',item.name;
   END IF;
   EXECUTE format('TRUNCATE TABLE pg_temp.%I',item.name);
  END IF;
 END LOOP;
END;
$$;

DO $invalidate_cache$
DECLARE
 definition text;
 anchor text;
 addition text;
BEGIN
 definition:=pg_get_functiondef('feat.begin_phase2_adjustment_rows(integer,integer)'::regprocedure);
 anchor:='    v_cache_relation:=to_regclass(''pg_temp.phase2_adjustment_rows'');';
 addition:=$body$
    PERFORM feat.invalidate_phase2_price_cache_hashes();
    IF to_regclass('pg_temp.phase2_adjustment_batch_dates') IS NOT NULL THEN
        IF obj_description(to_regclass('pg_temp.phase2_adjustment_batch_dates'),'pg_class') IS DISTINCT FROM
           'VN-Signal Phase 2 session-local adjustment-cache batch dates' THEN
            RAISE EXCEPTION 'temporary relation phase2_adjustment_batch_dates is reserved by the Phase 2 builder';
        END IF;
        TRUNCATE TABLE pg_temp.phase2_adjustment_batch_dates;
    END IF;
$body$;
 IF position('PERFORM feat.invalidate_phase2_price_cache_hashes();' IN definition)=0 THEN
  IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'cache initialization invalidation anchor missing'; END IF;
  EXECUTE replace(definition,anchor,addition||anchor);
 END IF;
 definition:=pg_get_functiondef('feat.populate_phase2_adjustment_rows(integer)'::regprocedure);
 anchor:='    v_date_manifest:=to_regclass(''pg_temp.phase2_adjustment_batch_dates'');';
 IF position('PERFORM feat.invalidate_phase2_price_cache_hashes();' IN definition)=0 THEN
  IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'cache refill invalidation anchor missing'; END IF;
  EXECUTE replace(definition,anchor,'    PERFORM feat.invalidate_phase2_price_cache_hashes();'||chr(10)||anchor);
 END IF;
END;
$invalidate_cache$;
COMMIT;

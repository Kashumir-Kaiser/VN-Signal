BEGIN;
CREATE INDEX IF NOT EXISTS security_observations_industry_pit_idx
 ON core.security_observations(security_id,observed_at DESC,observed_on);
CREATE OR REPLACE FUNCTION core.industry_as_of(p_symbol bigint,p_signal date)
RETURNS TABLE(industry text,observation_ids bigint[],landing_ids bigint[],available_at timestamptz)
LANGUAGE sql STABLE AS $$
 WITH identity AS (
  SELECT m.security_id FROM core.security_master m JOIN core.symbols s ON s.symbol=m.symbol WHERE s.symbol_id=p_symbol
 ), latest AS (
  SELECT max(o.observed_at) AS at FROM core.security_observations o JOIN identity i USING(security_id)
   WHERE o.observed_on<=p_signal AND o.observed_at<=((p_signal::timestamp+time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')
 ), observations AS (
  SELECT o.* FROM core.security_observations o JOIN identity i USING(security_id) JOIN latest l ON l.at=o.observed_at
   WHERE o.observed_on<=p_signal
 )
 SELECT CASE WHEN count(DISTINCT jsonb_build_array(category,exchange,icb_lv2))=1
                   AND bool_and(category='EXCHANGE_LISTED') THEN min(icb_lv2) END,
  coalesce(array_agg(observation_id ORDER BY observation_id),'{}'::bigint[]),
  coalesce(array_agg(DISTINCT landing_id ORDER BY landing_id),'{}'::bigint[]),max(observed_at)
 FROM observations
$$;
ALTER TABLE feat.fundamental_features_daily
 ADD COLUMN IF NOT EXISTS industry_observation_ids bigint[] NOT NULL DEFAULT '{}',
 ADD COLUMN IF NOT EXISTS industry_available_at timestamptz;
DO $industry_overlay$
DECLARE d text:=replace(pg_get_functiondef('feat.build_fundamental_features(date,date)'::regprocedure),E'\r\n',E'\n');
 a text; patch record;
BEGIN
 IF position('|industry_observations=v1' IN d)>0 THEN RETURN; END IF;
 a:='          LEFT JOIN LATERAL (
              SELECT l.industry FROM core.listing_snapshots l
               WHERE l.symbol_id=f.symbol_id AND l.snapshot_date<=f.trade_date
               ORDER BY l.snapshot_date DESC LIMIT 1
          ) ind ON true';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'industry snapshot lookup anchor missing'; END IF;
 d:=replace(d,a,'          LEFT JOIN LATERAL core.industry_as_of(f.symbol_id,f.trade_date) ind ON true');
 FOR patch IN SELECT * FROM (VALUES
  ('|valuation=parent-v1','|industry_observations=v1|valuation=parent-v1'),
  ('ind.industry,','ind.industry,ind.observation_ids AS industry_observation_ids,ind.available_at AS industry_available_at,ind.landing_ids AS industry_landing_ids,'),
  ('SELECT s.symbol_id,s.trade_date,s.industry,f.latest_quarter_end,','SELECT s.symbol_id,s.trade_date,s.industry,s.industry_observation_ids,s.industry_available_at,f.latest_quarter_end,'),
  ('coalesce(f.pit_landing_ids,''{}''::bigint[]) ||','coalesce(f.pit_landing_ids,''{}''::bigint[]) || s.industry_landing_ids ||'),
  ('symbol_id,trade_date,mapping_hash,source,industry,latest_quarter_end,','symbol_id,trade_date,mapping_hash,source,industry,industry_observation_ids,industry_available_at,latest_quarter_end,'),
  ('v_mapping_hash,''vci'',industry,latest_quarter_end,','v_mapping_hash,''vci'',industry,industry_observation_ids,industry_available_at,latest_quarter_end,')
 ) AS patches(anchor,replacement) LOOP
  IF position(patch.anchor IN d)=0 THEN RAISE EXCEPTION 'industry projection anchor missing: %',patch.anchor; END IF;
  d:=replace(d,patch.anchor,patch.replacement);
 END LOOP;
 EXECUTE d;
END $industry_overlay$;
DO $industry_manifest$
DECLARE d text:=replace(pg_get_functiondef('ops.phase2_chunk_input_hash(text,date,date)'::regprocedure),E'\r\n',E'\n'); a text;
BEGIN
 IF position('|industry_observations=v1|' IN d)>0 THEN RETURN; END IF;
 a:='        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(l)),''''
                                   ORDER BY l.symbol_id,l.snapshot_date),'''')
          INTO v_piece FROM core.listing_snapshots l
         WHERE l.snapshot_date<=p_date_to AND l.symbol_id=ANY(v_symbols);
        v_manifest:=v_manifest||''|listings=''||v_piece;';
 IF position(a IN d)=0 THEN RAISE EXCEPTION 'industry manifest snapshot anchor missing'; END IF;
 d:=replace(d,a,'        SELECT coalesce(string_agg(ops.phase2_hash_jsonb(to_jsonb(o)),'''' ORDER BY o.security_id,o.observed_at,o.observation_id),'''')
          INTO v_piece FROM core.security_observations o
          JOIN core.security_master m USING(security_id) JOIN core.symbols s ON s.symbol=m.symbol
         WHERE o.observed_on<=p_date_to AND o.observed_at<=((p_date_to::timestamp+time ''15:00'') AT TIME ZONE ''Asia/Ho_Chi_Minh'') AND s.symbol_id=ANY(v_symbols);
        v_manifest:=v_manifest||''|industry_observations=v1|''||v_piece;');
 EXECUTE d;
END $industry_manifest$;
COMMENT ON FUNCTION core.industry_as_of(bigint,date) IS
 'Latest timestamped security observation visible by the local 15:00 cutoff. Conflicting latest classifications, delisted categories and unknown industry return NULL. Date-only listing snapshots never supply PIT classification. Source observation IDs and raw landings are retained.';
COMMIT;

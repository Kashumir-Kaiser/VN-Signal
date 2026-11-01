BEGIN;
-- Overlay membership follows the current price feature population. An unknown
-- industry is not a peer group and must never receive an industry-relative rank.
DO $overlay_v3_cohort$
DECLARE
 definition text:=pg_get_functiondef('feat.build_fundamental_features(date,date)'::regprocedure);
 anchor text; replacement text; rank_start integer; rank_body text;
BEGIN
 IF position('|price_features=' IN definition)>0 THEN RETURN; END IF;
 anchor:='f.feature_version=''phase2-v2''';
 IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN
  RAISE EXCEPTION 'unexpected fundamental price cohort predicates';
 END IF;
 definition:=replace(definition,anchor,
  'f.feature_version=''phase2-v3'' AND f.feature_set_hash=feat.phase2_feature_set_hash_v3()');
 anchor:='FROM feat.fundamental_industry_class_map),'''') AS definition) x;';
 replacement:='FROM feat.fundamental_industry_class_map),'''') || ''|price_features='' || feat.phase2_feature_set_hash_v3() AS definition) x;';
 IF position(anchor IN definition)=0 THEN RAISE EXCEPTION 'fundamental mapping hash anchor missing'; END IF;
 definition:=replace(definition,anchor,replacement);
 rank_start:=position('    ranked AS (' IN definition);
 IF rank_start=0 THEN RAISE EXCEPTION 'fundamental industry ranking stage missing'; END IF;
 rank_body:=substring(definition FROM rank_start);
 anchor:='CASE WHEN count(';
 IF (length(rank_body)-length(replace(rank_body,anchor,'')))/length(anchor)<>7 THEN
  RAISE EXCEPTION 'unexpected fundamental industry rank conditions';
 END IF;
 definition:=left(definition,rank_start-1)||replace(rank_body,anchor,'CASE WHEN industry IS NOT NULL AND count(');
 EXECUTE definition;
END;
$overlay_v3_cohort$;
COMMENT ON FUNCTION feat.build_fundamental_features(date,date) IS
 'Separate PIT fundamental overlay for the current-hash V3 price cohort. Mapping identity includes the V3 feature hash. Unknown industries have no industry rank. No provider item maps are inferred.';
COMMIT;

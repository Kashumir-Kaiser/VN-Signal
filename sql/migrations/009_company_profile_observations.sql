-- Profile dates are provider-reported metadata, NOT first-ever public trades.
-- Phase 1 source ingestion; do not populate authoritative lifecycle intervals.
BEGIN;
CREATE TABLE IF NOT EXISTS core.company_profile_observations (
    profile_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    security_id bigint NOT NULL REFERENCES core.security_master(security_id),
    landing_id bigint NOT NULL UNIQUE REFERENCES raw.landings(landing_id),
    observed_at timestamptz NOT NULL,
    source text NOT NULL CHECK(source='vci'),
    reported_listing_date date,
    listing_date_interpretation text NOT NULL DEFAULT 'PROVIDER_CURRENT_PROFILE_UNVERIFIED'
       CHECK(listing_date_interpretation='PROVIDER_CURRENT_PROFILE_UNVERIFIED')
);
CREATE INDEX IF NOT EXISTS profile_security_date_idx
ON core.company_profile_observations(security_id,observed_at);
CREATE OR REPLACE FUNCTION core.verify_company_profile_landing() RETURNS trigger
LANGUAGE plpgsql AS $profileverify$
DECLARE existing_raw bytea; existing_sha text; existing_route text; existing_source text; existing_symbol text; ticker text;
BEGIN
   SELECT m.symbol INTO ticker FROM core.security_master m WHERE m.security_id=NEW.security_id;
   SELECT l.payload_bytes,l.payload_sha256,l.route,l.source,l.symbol
     INTO existing_raw,existing_sha,existing_route,existing_source,existing_symbol
     FROM raw.landings l WHERE l.landing_id=NEW.landing_id;
   IF existing_raw IS NULL OR encode(sha256(existing_raw),'hex')<>lower(existing_sha)
      OR existing_route<>'company_info' OR existing_source<>'vci'
      OR existing_symbol IS DISTINCT FROM ticker THEN
      RAISE EXCEPTION 'profile source must be original matching vci company_info bytes';
   END IF;
   RETURN NEW;
END;
$profileverify$;
DROP TRIGGER IF EXISTS profile_source_verify ON core.company_profile_observations;
CREATE TRIGGER profile_source_verify BEFORE INSERT ON core.company_profile_observations
FOR EACH ROW EXECUTE FUNCTION core.verify_company_profile_landing();

CREATE OR REPLACE FUNCTION core.reject_company_profile_mutation() RETURNS trigger
LANGUAGE plpgsql AS $profileimmutable$
BEGIN
    RAISE EXCEPTION 'company profile observations are append-only';
END;
$profileimmutable$;
DROP TRIGGER IF EXISTS profile_append_only ON core.company_profile_observations;
CREATE TRIGGER profile_append_only BEFORE UPDATE OR DELETE ON core.company_profile_observations
FOR EACH ROW EXECUTE FUNCTION core.reject_company_profile_mutation();

CREATE OR REPLACE VIEW core.company_profile_listing_evidence AS
SELECT m.symbol,p.observed_at,p.reported_listing_date,p.listing_date_interpretation,
       p.landing_id
FROM core.company_profile_observations p
JOIN core.security_master m USING(security_id);
COMMIT;

-- Bind lifecycle evidence to the security named by its archived source.
BEGIN;

CREATE OR REPLACE FUNCTION core.verify_lifecycle_evidence_source() RETURNS trigger
LANGUAGE plpgsql AS $verifylifecycle$
DECLARE
    original bytea;
    recorded_sha text;
    original_route text;
    landing_symbol text;
    evidence_symbol text;
BEGIN
    SELECT symbol INTO evidence_symbol
      FROM core.symbols WHERE symbol_id=NEW.symbol_id;
    SELECT payload_bytes,payload_sha256,route,symbol
      INTO original,recorded_sha,original_route,landing_symbol
      FROM raw.landings WHERE landing_id=NEW.source_landing_id;

    IF original IS NULL OR length(original)<2
       OR original_route<>'security_lifecycle_notice'
       OR landing_symbol IS DISTINCT FROM evidence_symbol
       OR encode(sha256(original),'hex')<>lower(recorded_sha) THEN
        RAISE EXCEPTION 'lifecycle evidence must cite an intact notice for the same security';
    END IF;
    RETURN NEW;
END;
$verifylifecycle$;

DROP TRIGGER IF EXISTS security_lifecycle_verify_source ON core.security_lifecycle_evidence;
CREATE TRIGGER security_lifecycle_verify_source
BEFORE INSERT ON core.security_lifecycle_evidence
FOR EACH ROW EXECUTE FUNCTION core.verify_lifecycle_evidence_source();

COMMIT;

-- Raw source frames are the immutable evidence used to rebuild every projection.
BEGIN;

CREATE OR REPLACE FUNCTION raw.reject_landing_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'raw.landings is append-only; % is forbidden', TG_OP
        USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS raw_landings_no_row_mutation ON raw.landings;
CREATE TRIGGER raw_landings_no_row_mutation
BEFORE UPDATE OR DELETE ON raw.landings
FOR EACH ROW EXECUTE FUNCTION raw.reject_landing_mutation();

DROP TRIGGER IF EXISTS raw_landings_no_truncate ON raw.landings;
CREATE TRIGGER raw_landings_no_truncate
BEFORE TRUNCATE ON raw.landings
FOR EACH STATEMENT EXECUTE FUNCTION raw.reject_landing_mutation();

COMMIT;

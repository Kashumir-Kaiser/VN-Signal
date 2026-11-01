\set ON_ERROR_STOP on
BEGIN;
\ir fundamental_industry_helpers.sql
SELECT pg_temp.synthetic_industry_observation('Synthetic Finance','2098-01-02 12:00+07');
COMMIT;

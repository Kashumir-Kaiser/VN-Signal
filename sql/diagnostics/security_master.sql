-- Read-only local inspection of observed provider securities.
-- Snapshot dates are observation days, NOT backfilled historical membership.
\pset pager off
SELECT observed_on,category,coalesce(exchange,'NOT_REPORTED') AS venue,
       count(*) AS securities
FROM core.security_observed_sessions
GROUP BY observed_on,category,exchange
ORDER BY observed_on,category,venue;
SELECT count(DISTINCT symbol) AS unique_symbols,
       count(*) FILTER (WHERE observation_status='PROVIDER_DELISTED_UNDATED') AS provider_delisted_observation_days,
       count(*) FILTER (WHERE observation_status='CONFLICTING_OBSERVATIONS') AS conflicts
FROM core.security_observed_days;

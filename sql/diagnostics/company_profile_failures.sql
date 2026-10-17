-- Read-only failure distribution from source-backed company profile runs.
-- An unknown outcome is not evidence of a missing/delisted security.
-- Safe error categories only; never expose vendor exception text or tokens.
SELECT j.state,coalesce(j.last_error_type,'NONE') AS last_error_type,
       count(*) AS securities
FROM ops.company_profile_jobs j
GROUP BY j.state,j.last_error_type
ORDER BY securities DESC,j.state,j.last_error_type;

SELECT a.attempt_id,m.symbol,a.status,coalesce(a.error_type,'NONE') AS error_type,
       a.reserved_at,a.finished_at,
       round(extract(epoch FROM (a.finished_at-a.reserved_at))::numeric,1) AS elapsed_seconds
FROM ops.company_profile_attempts a
JOIN core.security_master m USING(security_id)
WHERE a.status IN ('UNKNOWN','ERROR')
ORDER BY a.attempt_id DESC
LIMIT 80;

SELECT batch_id,max_calls,attempted,imported,missing_date,errors,
       skipped_existing,skipped_errors,skipped_unknown,deferred,
       last_error_type,started_at,finished_at
FROM ops.company_profile_batch_runs
ORDER BY batch_id DESC LIMIT 10;

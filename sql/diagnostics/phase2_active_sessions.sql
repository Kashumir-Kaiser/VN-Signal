-- Read-only session status for the disposable Phase 2 report clone.
SELECT pid, application_name, client_port, backend_start, query_start,
       state, wait_event_type, wait_event,
       clock_timestamp()-query_start AS query_age,
       pg_blocking_pids(pid) AS blockers,
       left(query, 400) AS query
FROM pg_stat_activity
WHERE datname='vnsignal_phase2_report_20261019'
  AND pid<>pg_backend_pid()
ORDER BY query_start NULLS LAST, pid;

SELECT datname, temp_files, temp_bytes
FROM pg_stat_database
WHERE datname='vnsignal_phase2_report_20261019';

SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('jit','jit_above_cost','work_mem','max_parallel_workers_per_gather')
ORDER BY name;

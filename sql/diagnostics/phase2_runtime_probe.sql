-- Read-only runtime facts for investigating a Phase 2 build on a disposable clone.
BEGIN TRANSACTION READ ONLY;
SET LOCAL statement_timeout = '30s';
LOAD 'auto_explain';
SET LOCAL auto_explain.log_min_duration = '0';
SET LOCAL auto_explain.log_analyze = on;
SET LOCAL auto_explain.log_buffers = on;
SET LOCAL client_min_messages = log;

SELECT current_database() AS database_name, current_user AS database_role;
SELECT count(*) AS calendar_rows FROM core.effective_trading_sessions;
SELECT name, installed_version
FROM pg_available_extensions
WHERE name IN ('auto_explain', 'pg_stat_statements')
ORDER BY name;
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('auto_explain', 'pg_stat_statements')
ORDER BY extname;
SELECT pid, state, wait_event_type, wait_event, left(query, 160) AS query
FROM pg_stat_activity
WHERE datname = current_database() AND pid <> pg_backend_pid()
ORDER BY pid;

ROLLBACK;

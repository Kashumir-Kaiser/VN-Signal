#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL required}"
export PGOPTIONS='-c TimeZone=UTC'
for pass in 1 2; do
    for migration in sql/migrations/[0-9]*.sql; do
        psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$migration"
    done
done
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f tests/sql/schema_assertions.sql
if psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TABLE ops.fault_rollback(id integer);
SELECT 1/0;
COMMIT;
SQL
then
    echo 'fault injection unexpectedly succeeded' >&2
    exit 1
fi
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -Atc "SELECT CASE WHEN to_regclass('ops.fault_rollback') IS NULL THEN 'rollback-ok' ELSE 'bad' END" | grep -qx rollback-ok
# A connection failure must be detected rather than silently regarded as migrated.
if PGCONNECT_TIMEOUT=1 psql 'postgresql://127.0.0.1:1/nonexistent' -X -v ON_ERROR_STOP=1 -c 'SELECT 1' >/dev/null 2>&1; then
    echo 'unreachable Postgres unexpectedly passed' >&2
    exit 1
fi

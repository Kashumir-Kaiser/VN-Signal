#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL required}"
: "${VNPIPE_TEST_DATABASE_NAME:?Set VNPIPE_TEST_DATABASE_NAME to the exact disposable database name before running this destructive migration harness}"
export PGOPTIONS='-c TimeZone=UTC'

# This harness replays every migration and commits fixture rows. Require both an
# exact database-name acknowledgement and a test-only suffix before connecting.
actual_database_name=$(psql -X -v ON_ERROR_STOP=1 -Atqc 'SELECT current_database()' "$DATABASE_URL")
if [[ "$actual_database_name" != "$VNPIPE_TEST_DATABASE_NAME" ]]; then
    echo "refusing migration harness: DATABASE_URL selects '$actual_database_name', expected '$VNPIPE_TEST_DATABASE_NAME'" >&2
    exit 1
fi
case "$actual_database_name" in
    *_test|*_ci|*_ci_*|*_disposable) ;;
    *)
        echo "refusing migration harness: database '$actual_database_name' does not have a test-only suffix (_test, _ci, or _disposable)" >&2
        exit 1
        ;;
esac
case "$actual_database_name" in
    vnsignal|postgres|template0|template1)
        echo "refusing migration harness: '$actual_database_name' is a protected database name" >&2
        exit 1
        ;;
esac

for pass in 1 2; do
    for migration in sql/migrations/[0-9]*.sql; do
        if [[ "$pass" == 1 && "$migration" == "sql/migrations/026_vndirect_adjusted_prices.sql" ]]; then
            psql -X -v ON_ERROR_STOP=1 -f tests/sql/vndirect_adjustment_backfill_fixture.sql "$DATABASE_URL"
        fi
        if [[ "$pass" == 1 && "$migration" == "sql/migrations/033_vndirect_close_tick_price_corrections.sql" ]]; then
            psql -X -v ON_ERROR_STOP=1 -f tests/sql/vndirect_close_tick_fixture.sql "$DATABASE_URL"
        fi
        if [[ "$pass" == 1 && "$migration" == "sql/migrations/034_fundamentals_pit_archive.sql" ]]; then
            psql -X -v ON_ERROR_STOP=1 -f tests/sql/fundamentals_pit_fixture.sql "$DATABASE_URL"
        fi
        psql -X -v ON_ERROR_STOP=1 -f "$migration" "$DATABASE_URL"
    done
done
psql -X -v ON_ERROR_STOP=1 -f tests/sql/schema_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_moving_window_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/vndirect_adjustment_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/vndirect_close_tick_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/fundamentals_pit_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_feature_fixture.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_recursive_builder_golden.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_session_cache_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/fundamental_features_fixture.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/fundamental_industry_fixture.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_feature_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -c "SELECT feat.build_features((SELECT min(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'), (SELECT max(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'))" "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_vci_backfill_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -c "SELECT feat.build_labels((SELECT min(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'), (SELECT max(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'))" "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_label_outputs_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_execution_policy_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/fundamental_features_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_industry_availability_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -c "SELECT feat.build_fundamental_features((SELECT min(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'), (SELECT max(trade_date) FROM core.bars_daily_sources WHERE source='vndirect'))" "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_leakage_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_shared_builder_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_market_projection_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_rank_population_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_source_inputs_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_chunk_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_cache_probe_strategy_assertions.sql "$DATABASE_URL"
if psql -X -v ON_ERROR_STOP=1 "$DATABASE_URL" <<'SQL'
BEGIN;
CREATE TABLE ops.fault_rollback(id integer);
SELECT 1/0;
COMMIT;
SQL
then
    echo 'fault injection unexpectedly succeeded' >&2
    exit 1
fi
psql -X -v ON_ERROR_STOP=1 "$DATABASE_URL" <<'SQL'
DO $$
BEGIN
    IF to_regclass('ops.fault_rollback') IS NOT NULL THEN
        RAISE EXCEPTION 'fault-injection rollback check failed';
    END IF;
END
$$;
SQL
# A connection failure must be detected rather than silently regarded as migrated.
if PGCONNECT_TIMEOUT=1 psql -X -v ON_ERROR_STOP=1 -c 'SELECT 1' 'postgresql://127.0.0.1:1/nonexistent' >/dev/null 2>&1; then
    echo 'unreachable Postgres unexpectedly passed' >&2
    exit 1
fi
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_cache_projection_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_cache_first_load_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_cache_replicate_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_cache_reset_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_vci_lineage_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_vci_recovery_lineage_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_listing_tenure_assertions.sql "$DATABASE_URL"
psql -X -v ON_ERROR_STOP=1 -f tests/sql/phase2_public_execution_assertions.sql "$DATABASE_URL"
echo 'Phase 2 SQL migration harness passed.'

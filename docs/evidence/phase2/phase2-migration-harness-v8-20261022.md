# PostgreSQL migration harness v8 — V3 selected-symbol CTE fix

- Fresh disposable database: `vnsignal_phase2_ci_20261022_v8_test` on local PostgreSQL 18.3.
- Ran `tests/sql/test_migration.sh` after adding migration 046 and the selected-symbol CTE regression assertion. The harness applied the migration sequence twice, ran schema, adjustment, fundamentals, feature, cache, VCI backfill, batch-parity, leakage, source-input, and chunk assertions, and exited with the final marker `Phase 2 SQL migration harness passed.`
- The specific regression assertion verifies that `selected_symbols` reads `eligible_symbols` and that no stale `FROM symbols` reference remains. The harness's actual synthetic V3 build also completed with the migration sequence.
- This is synthetic fixture evidence only. It does not establish real-data feature/label completion or E1–E5 acceptance.
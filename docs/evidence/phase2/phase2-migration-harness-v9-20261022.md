# Phase 2 PostgreSQL migration harness v9 — 2026-10-22

**Result: PASS.** `tests/sql/test_migration.sh` completed successfully against
fresh disposable PostgreSQL 18.3 database
`vnsignal_phase2_ci_20261022_v9_test`. The captured log ends with
`Phase 2 SQL migration harness passed.`

The two-pass harness replayed the migration set and ran the synthetic feature,
label, leakage, source-input, chunk, and migration assertions, including the
expected rollback fault case. It exercises fixtures only; it is not real-data
E2 leakage, E3 reference parity, E4 full-history integrity, or hosted CI.

See [`captured harness log`](phase2-migration-harness-v9-20261022.log). No
vnstock market-data route or account quota was used.

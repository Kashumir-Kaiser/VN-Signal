# Build status — 2026-10-16

**State: INCOMPLETE, no trading recommendations are enabled.** This is an initial checked-in foundation, not a complete implementation of the master prompt.

| Phase | Status | Evidence | Unfinished exit criteria |
| --- | --- | --- | --- |
| 0: probe/schema/config | PARTIAL | `vnpipe probe`, Python worker, SQL migrations and tests | Live `vnstock` probe report, apply migrations against PostgreSQL 16, validate real data shapes |
| 1: ingestion/backfill | PARTIAL | quota math/rate governor, checkpoint/quality gate libraries | PostgreSQL `pgx` bulk loader, incremental ingestion, durable API ledger, full quota-safe backfill |
| 2: features/PIT | NOT STARTED | contract describes the required rules | features, PIT archive, leakage and parity tests |
| 3: models/backtest | NOT STARTED | architecture specified | real Rust training, 36+ monthly OOS folds, calibration, backtest |
| 4: serving/portfolio | NOT STARTED | architecture specified | atomic SQLite export, parity, optimisation |
| 5: desktop UI | NOT STARTED | architecture specified | Tauri/Svelte views and performance evidence |
| 6: daemon/operations | NOT STARTED | no cron coupling in foundation | scheduler, installer, backups, seven unattended trading-day runs |

**No mock or fabricated price history, quota report, test performance, expected return, or model confidence is presented as genuine.** CI is deliberately offline and may not consume a user's vnstock account/device quota.

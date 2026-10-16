# Build status — 2026-10-16

**State: INCOMPLETE, no trading recommendations are enabled. P0 offline hardening implemented; PostgreSQL CI and live probe not yet observed.** This is an initial checked-in foundation, not a complete implementation of the master prompt.

| Phase | Status | Evidence | Unfinished exit criteria |
| --- | --- | --- | --- |
| 0: probe/schema/config | PARTIAL | Strict Python/Go JSONL tests, passive probe, metered active probe gateway, validated Go config, PostgreSQL 16 service test defined in CI | Observe CI PostgreSQL results and live probe on user's registered device, validate real data shapes |
| 1: ingestion/backfill | PARTIAL | Fail-closed quota parsing and metered call gateway with wait tests, fault-injected checkpoint persistence, DQ blocking gates, worker-process concurrency bound | PostgreSQL `pgx` loader, incremental ingestion, real durable API-call ledger and full quota-safe backfill; can't certify every future call yet |
| 2: features/PIT | NOT STARTED | contract describes the required rules | features, PIT archive, leakage and parity tests |
| 3: models/backtest | NOT STARTED | architecture specified | real Rust training, 36+ monthly OOS folds, calibration, backtest |
| 4: serving/portfolio | NOT STARTED | architecture specified | atomic SQLite export, parity, optimisation |
| 5: desktop UI | NOT STARTED | architecture specified | Tauri/Svelte views and performance evidence |
| 6: daemon/operations | NOT STARTED | no cron coupling in foundation | scheduler, installer, backups, seven unattended trading-day runs |

**No mock or fabricated price history, quota report, test performance, expected return, or model confidence is presented as genuine.** CI is deliberately offline and may not consume a user's vnstock account/device quota.

## 2026-10-16 P0 hardening evidence

- `go -C go test ./...`, `go -C go test -race ./...`, `go -C go vet ./...`: passed locally.
- `VNPIPE_DISABLE_LIVE=1 python -m unittest discover -s tests -v`: 15 offline tests passed locally, including JSONL main(), oversized input, broken pipe, vendored stdout print, CLI errors and route exceptions.
- `tests/sql/test_migration.sh`: checked into CI, runs migration twice and tests constraints, trigger canonicalization, PIT dates, rollback and connection failure against PostgreSQL 16. **Not run locally (PostgreSQL unavailable). Do not claim green CI until the hosted run completes.**
- `VNPIPE_DISABLE_LIVE=1` is enforced by both the Go quota gateway and Python adapter in CI. The active probe is now a Go-only metered sequence; direct Python `probe(active=True)` fails closed.
- Default config is validated on CLI probes/budget requests; invalid risk cap, timezone, unknown keys and exchange limits are rejected.
- The current CLI has no scheduler, SQLite serving, training or backfill execution, so those failure paths cannot be signed off yet. The quota gateway is the required integration point for all future market-data calls; verify that production ingestion uses it before Phase 1 exit.
- Live quota usage API shapes, account entitlements, Postgres outage during migrations, and cross-source real-price data were not exercised. No actual API/device quota was consumed by tests.

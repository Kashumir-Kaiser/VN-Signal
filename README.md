# VN-Signal

**Single-user Vietnamese equity research system (in development).** Proprietary: copyright (c) 2026 Kashumir-Kaiser; see [LICENSE](LICENSE).

VN-Signal is designed around the **vnstock v5 free tier**. It must not claim that model predictions are investment advice. The system is deliberately **fail-closed**: unknown quota limits prevent scheduled ingestion; an unverified data source cannot produce recommendations.

## Current implementation

Phase 0 foundation and a portion of Phase 1: a Go 1.23 CLI with offline OHLCV frame normalization and quota-aware backfill previews; supervised JSON-lines Python 3.12 vnstock adapter; status/usage/capability probes; fail-closed quota reservations and single-worker process bound; bar quality/publishing gates; crash-aware checkpoints; checked configuration; PostgreSQL schemas and transactional ingestion store with durable quota audit; tagged PostgreSQL driver and migration tooling; integration tests and CI. **No trained model, portfolio recommendations, usable desktop app, full backfill, or deployed scheduler yet.** See [Build status](docs/BUILD_STATUS.md).

## Prerequisites

- Python **3.12**, [`uv`](https://docs.astral.sh/uv/), Go **1.23+**. PostgreSQL 16+ is required for migrations and future ingestion.
- On your **local machine only**, install vnstock v5 and register your Community (free) key. The key is never written into this repository.

```powershell
uv venv --python 3.12 .venv
uv pip install --python .venv/Scripts/python.exe --extra-index-url https://vnstocks.com/api/packages "vnstock==5.0.1"
.venv\Scripts\vnstock.exe register
go -C go test ./...
go -C go run ./cmd/vnpipe --help
```

On Linux, replace `.venv/Scripts/python.exe` with `.venv/bin/python`, and `.venv\\Scripts\\vnstock.exe` with `.venv/bin/vnstock`. For Python code on Windows, `py -3.12` can be used; the CLI invokes the configured interpreter directly.

```powershell
$env:VNPIPE_PYTHON = ".venv/Scripts/python.exe"
go -C go run ./cmd/vnpipe probe
# Active probe consumes your *local* free-tier allowance, opt in explicitly:
go -C go run ./cmd/vnpipe probe --active --trading-days 12
# Replace 12 with actual remaining trading sessions; never guess account quotas.
```

`probe` writes a date-stamped report to `docs/probe/` locally. Without `--active`, it checks the installed tier and quotas but does not request market data. The active probe checks a minimal symbol/bar/calendar sample, records actual columns and limitations and never treats missing data as success. **It refuses to send any live request unless `vnstock status --json` exposes a recognized free-tier name and `vnstock usage --json` reports absolute integer `daily_remaining` and `monthly_remaining`.** Percent-only or unavailable usage fails closed; do not manufacture quotas. This protects quota/device usage. A durable API reservation ledger is now implemented for the explicit backfill command, but real account quotas and database transactions still require CI and local verification. **Do not use GitHub-hosted runners for live vnstock calls.**

## Next gates

Read [Runbook](docs/RUNBOOK.md), [Data contract](docs/DATA_CONTRACT.md), and [Decisions](docs/DECISIONS.md). Nothing is presented as a validated market signal until historical point-in-time checks, walk-forward testing, cross-language parity, and paper-trading checks pass.

Attribution: [Vnstock](https://vnstocks.com/docs/vnstock) provides the source API and its own licensing and tier rules; this repository does **not** license Vnstock or redistribute its data.

## Offline hardening checks

From the repository root (Go must be installed):

```powershell
go -C go test -race ./...
go -C go vet ./...
py -3.12 -m unittest discover -s tests -v
```

CI sets `VNPIPE_DISABLE_LIVE=1` and never registers vnstock or queries market data. Its PostgreSQL 16 service runs migration and SQL assertions including transaction rollback. Run locally against a disposable PostgreSQL database with `DATABASE_URL` set: `bash tests/sql/test_migration.sh`. Do not point fault-injection tests at a valuable database.

The SQL migration CI check is **not evidence of a successful local historical backfill**. Tests requiring valid vnstock quota data, real histories, a deployed scheduler, or a serving SQLite snapshot remain incomplete until those components exist.

## Phase 1 offline ingestion checks

A saved successful worker `data` frame can be validated **without making a market-data request**:

```powershell
go -C go run ./cmd/vnpipe validate-bars --input saved-data.json --symbol FPT
```

The validator rejects missing/extra schema columns, mismatched counts, duplicated or non-chronological dates, null/nonfinite numeric values, and invalid OHLCV. It prints counts and dates only, never prices. `saved-data.json` contains the `data` object of the worker's JSONL response, not the outer `{id,ok,data}` envelope.

Given a *locally recorded* successful active probe and a JSON array of real symbols, you can preview a deterministic, capped backfill plan:

```powershell
go -C go run ./cmd/vnpipe preview-backfill --probe docs/probe/2026-10-16.json --symbols symbols.json --from 2018-10-01 --to 2026-10-16 --days 10
```

This is **preview-only**. It does not reserve quota, fetch symbols, backfill, or import PostgreSQL rows. A dated capability probe does not authorize live execution; the real backfill command refreshes *absolute* account usage before beginning, persists every reservation before dispatch, and refuses to send any calls when that snapshot expires. No unattended or full-universe ingestion is claimed.

The `ingest.Runner` is now connected to a `PostgresStore` through an opt-in `backfill` command in **PGX-tagged builds**. It commits vendor frames, validated bars and job completion atomically, while writing a durable per-call reservation before invoking Python. It refuses to read unknown symbols (the authoritative listing import is still missing), will not proceed beyond a short-lived absolute quota guard, and does not touch SQLite serving. PostgreSQL integration tests have been added to CI, but execution against the live service has not yet been independently confirmed.

### Native PostgreSQL migrations and guarded backfill

The Go `migrate` command parses dollar-quoted PostgreSQL functions, applies numbered migrations in transactions, and stores SHA-256 checksums. **Never point integration/fault-injection tests at your valuable database.** On your local machine after obtaining pinned Go modules:

```powershell
# DATABASE_URL must be set locally; keep PostgreSQL bound to loopback.
go -C go build -tags postgres -o ../vnpipe.exe ./cmd/vnpipe
.\vnpipe.exe migrate --dir sql/migrations
```

If you have a **fresh, successful active probe**, absolute remaining quotas, and an already-populated `core.symbols` listing table, an explicitly authorized *subset* backfill is available:

```powershell
.\vnpipe.exe backfill --active --probe docs/probe/YYYY-MM-DD.json --symbols symbols.json --from 2018-10-01 --to 2026-10-16 --days 10 --source vci
```

This is **not** a one-click setup: `symbols.json` is a JSON array of ticker names that must already exist in `core.symbols` from a separately verified listing import. The command preflights every planned symbol before requesting data, checks the present vnstock tier and absolute quota again, and stops if it cannot guarantee a safe reservation. Do not hand-author market provenance or invent missing quota figures to bypass the restrictions. An end-to-end real-database test is required before relying on it for a large backfill. On Linux, compile with `-o ../vnpipe` and use `./vnpipe`.

# VN-Signal

**Single-user Vietnamese equity research system (in development).** Proprietary: copyright (c) 2026 Kashumir-Kaiser; see [LICENSE](LICENSE).

VN-Signal is designed around the **vnstock v5 free tier**. It must not claim that model predictions are investment advice. The system is deliberately **fail-closed**: unknown quota limits prevent scheduled ingestion; an unverified data source cannot produce recommendations.

## Current implementation

Phase 0 foundation and a portion of Phase 1, including an offline, transactionally persisted current-universe listing importer: a Go 1.23 CLI with offline OHLCV frame normalization and quota-aware backfill previews; supervised JSON-lines Python 3.12 vnstock adapter; status/usage/capability probes; fail-closed quota reservations and single-worker process bound; bar quality/publishing gates; crash-aware checkpoints; checked configuration; PostgreSQL schemas and transactional ingestion store with durable quota audit; tagged PostgreSQL driver and migration tooling; integration tests and CI. **No trained model, portfolio recommendations, usable desktop app, full backfill, or deployed scheduler yet.** See [Build status](docs/BUILD_STATUS.md).

## Prerequisites

- Python **3.12**, [`uv`](https://docs.astral.sh/uv/), Go **1.23+**. PostgreSQL 16+ is required for migrations and future ingestion.
- On your **local machine only**, install vnstock v5 and register your Community (free) key. The key is never written into this repository.

```powershell
uv venv --python 3.12 .venv
uv pip install --python .venv/Scripts/python.exe --extra-index-url https://vnstocks.com/api/packages "vnstock==5.0.3"
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

In Git Bash, point Go tests and the CLI at the venv interpreter with:

```bash
export VNPIPE_PYTHON="$(cygpath -aw "$PWD/.venv/Scripts/python.exe")"
```

`probe` writes a date-stamped report to `docs/probe/` locally. Without `--active`, it checks the installed tier and quota policy but does not request market data. The active probe checks one sample for each supported route (listings, equity/index OHLCV, three statements and market calendar), records actual columns and limitations, and never treats missing data as success. Use `--routes equity_list` to retry only the listing route after a partial probe. Reports include safe error categories, route durations, numeric worker exit codes, and safe worker cause labels where available, without worker stderr. **It refuses live calls unless `vnstock --json status` reports an authenticated `free`/`community` account and `vnstock --json usage` provides exact `limits.per_day` / `limits.per_month`, `used.day` / `used.month`, and `limits.per_minute` values.** Remaining counts are computed as limit minus used; percentages alone, Guest accounts and unknown fields fail closed. A durable API reservation ledger is implemented for explicit backfill, but real account entitlements and database transactions still require local verification. **Do not use GitHub-hosted runners for live vnstock calls.**

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

The `ingest.Runner` is now connected to a `PostgresStore` through an opt-in `backfill` command in **PGX-tagged builds**. It commits vendor frames, validated bars and job completion atomically, while writing a durable per-call reservation before invoking Python. It refuses to read unknown symbols (run the verified listing importer before backfill), will not proceed beyond a short-lived absolute quota guard, and does not touch SQLite serving. PostgreSQL integration tests have been added to CI, but execution against the live service has not yet been independently confirmed.

### Native PostgreSQL migrations and guarded backfill

The Go `migrate` command parses dollar-quoted PostgreSQL functions, applies numbered migrations in transactions, and stores SHA-256 checksums. **Never point integration/fault-injection tests at your valuable database.** On your local machine after obtaining pinned Go modules:

```powershell
# DATABASE_URL must be set locally; keep PostgreSQL bound to loopback.
go -C go build -tags postgres -o ../vnpipe.exe ./cmd/vnpipe
.\vnpipe.exe migrate --dir sql/migrations
```

After importing an authoritative complete listing snapshot and obtaining a **fresh successful active probe**, the opt-in backfill selects pending equities from PostgreSQL:

```powershell
.\vnpipe.exe backfill --active --probe docs/probe/YYYY-MM-DD.json --from 2018-10-01 --to 2026-10-16 --days 10 --source vci
```

There is **no `--symbols` argument for live backfill**. The command verifies a complete listing (at least 1,000 active equities, all three exchanges, current status matching the latest snapshot, provenance checksum intact, and no more than seven Vietnam calendar days old). It excludes already completed, blocked, and recently leased jobs *before* the fresh quota budget caps the plan, preventing repeated first-alphabet batches. Unknown, unauthenticated, or percentage-only vendor quotas block calls.

**For multi-day resumption, keep `--from`, `--to`, and `--source` identical.** A different range creates new job IDs and can require repeating calls. Refresh the authoritative listing snapshot as needed; never fabricate membership or account quotas. PostgreSQL integration and live-vnstock results still require verification on the registered machine. On Linux build with `-o ../vnpipe` and use `./vnpipe`.

### Verified equity listing import

The active Go probe preserves the already-metered `equity_list` response as `listing_frame`. The registered-machine probe on 2026-10-16 returned 1,754 provider rows: 406 HOSE, 299 HNX, 814 UPCOM and 235 `DELISTED`. The importer keeps the entire response in raw storage and imports only the 1,519 currently listed exchange members; it does not guess the original exchange for `DELISTED` rows. PostgreSQL import and historical backfill are still pending. See [Listing import workflow](docs/LISTING_IMPORT.md).

Raw landings now include `payload_bytes` (migration 004) in addition to queryable JSONB, so the original vendor payload SHA-256 can be checked against exact bytes rather than reserialized JSON.

### Inspect backfill without consuming quota

After a verified listing import, use the **read-only** command with the *same* exact dates and source as the live backfill:

```powershell
.\vnpipe.exe backfill-status --from 2018-10-01 --to 2026-10-16 --source vci
```

It checks source-frame provenance against **every current symbol, exchange and ICB industry code**, not just the total count or a checksum. It returns `completed`, `blocked`, `leased`, `pending` and a ten-symbol preview. It does not invoke the Python worker, reserve quota, or show a stock suggestion. A tampered, stale or incomplete universe fails closed. A PostgreSQL-tagged binary and your local database are still required.

### Multi-hour quota refresh

The five-minute PostgreSQL quota verification is now renewable **during an explicitly authorized backfill**. Before an unfinished job can reserve a call, the runner checks the stored expiry. Within 90 seconds of expiry it obtains a fresh passive vnstock status/absolute usage reading, rejects unknown or changed-tier reports, and commits the lower safe remaining budget. No previous reservations are refunded. Failure blocks the next market call.

An existing run does **not** carry a quota across Vietnam midnight: resume on a new day with a fresh authorized command and the same exact history range. The full live PostgreSQL integration and real-vendor flow still await independent verification; this is not an unattended scheduler or a finished Phase 1.

### Corrupt historical frame isolation

A vnstock route can succeed while some returned OHLCV bars contain nonpositive
prices or impossible high/low relationships. These are source-quality defects,
not authorization or PostgreSQL connection errors. `vnpipe backfill --active`
now quarantines such responses in `raw.landings` under
`route='equity_ohlcv_quarantine'` with exact original bytes and SHA-256, and
atomically marks the corresponding `ops.ingest_jobs` row `BLOCKED` with a
bounded date/field diagnostic. **No invalid rows enter `core.bars_daily`.**
Healthy symbols continue, with prior completions and all quota reservations
preserved. Three consecutive invalid symbols, or at least 20% quarantined once
20 symbols have been examined, halt the current command as a systemic-source
safety measure. Vendor errors, database faults and quota failures still halt.

Inspect quarantined jobs without consuming vendor quota:

```bash
psql "$DATABASE_URL" -c "SELECT symbol,state,last_error_type FROM ops.ingest_jobs WHERE state='BLOCKED' ORDER BY updated_at DESC;"
```

Previously blocked jobs stay blocked and **are not retried automatically**.
Investigate their archived source frames before adding a separately reviewed
recovery procedure. Never hand-edit job states or remove the bad bar to turn
an invalid history into a verified one.

### Source-aware row-level OHLCV ingestion

Migration `005_market_bar_quality.sql` and `AnalyzeMarketBars` distinguish zero-volume reference observations from traded bars and per-session vendor contradictions. Positive-volume valid candles are retained; rejected sessions are auditable in `ops.bar_quality_issues`; `PARTIAL` histories are never mislabeled complete. Archived quarantines can be reprocessed offline with `vnpipe reprocess-archived --from ... --to ... --source vci` and no new provider quota. See [market bar quality contract](docs/MARKET_BAR_QUALITY.md). Do not run live backfill before the migration and local database verification.

Previously blocked A32/ABC-style jobs without any saved raw frame can be explicitly requeued (not refetched) offline using `vnpipe requeue-unarchived --symbol SYMBOL --from DATE --to DATE --source vci` after migration 006. It writes an immutable requeue audit, preserves the original quota reservation, and leaves actual vendor requests to a separately authorized `backfill --active`. See [quality contract](docs/MARKET_BAR_QUALITY.md).

### Historical listing-date safety (migration 007)

Zero volume alone cannot distinguish a listed security with no trades from a company before initial public trading, during a trading halt, or outside an exchange trading episode. Prior `NO_TRADE` findings are migrated to `ZERO_VOLUME_UNVERIFIED`. Until separately evidenced, the `ops.zero_volume_lifecycle_status` view reports `LISTING_STATUS_UNVERIFIED`. See [docs/LIFECYCLE_EVIDENCE.md](docs/LIFECYCLE_EVIDENCE.md). No additional vnstock quota is required for this migration.

# Local runbook

## Installation

Install Python 3.12 and Go 1.23. Install `vnstock==5.0.3` using `--extra-index-url https://vnstocks.com/api/packages` from its official channel and register your free Community key on the **one designated machine**. See the [official guide](https://www.vnstocks.com/docs/vnstock/cau-hinh-va-dong-lenh). Never run `vnstock register` in CI, or paste the key into GitHub secrets for ingestion.

## Verify without spending market-data calls

`go -C go test ./...` and `py -3.12 -m unittest discover -s tests -v` (Windows) or `python3 -m unittest discover -s tests -v` (Linux).

From the repository root in Windows PowerShell, set the worker interpreter to an absolute path before using `go -C go`:

```powershell
$env:VNPIPE_PYTHON = (Resolve-Path .venv\Scripts\python.exe).Path
$env:VNSTOCK_HOME = (Resolve-Path (Join-Path $env:USERPROFILE '.vnstock')).Path
go -C go run ./cmd/vnpipe probe
```

Set `VNSTOCK_HOME` to the authenticated state directory printed by `vnstock env`. The worker runs from `go/`; without this setting it may select a separate project-local state and report `guest` even though the registered account exists under the Windows profile.

The passive probe checks CLI entitlement and usage without querying market quotes. An active probe explicitly spends up to seven calls and requires an explicit `--trading-days N` value. Inspect the report under `docs/probe/`. For a partial probe, rerun only selected routes with `--routes equity_list,income_statement` and set `--out` to a separate directory. Each route records a safe `error_type` and `duration_ms`, plus a numeric `exit_code` and safe `worker_cause` label when the worker process exits unsuccessfully; raw worker stderr is not saved. If quota/counts or routes cannot be determined, ingestion remains disabled until reviewed.

## PostgreSQL

Numbered migrations `001_init.sql` through the latest numbered migration are handled by a native Go migration engine, with checksums and transaction rollback. Compile on the registered Windows/Linux machine with `go -C go build -tags postgres -o ../vnpipe ./cmd/vnpipe` (Windows: `../vnpipe.exe`) and run `vnpipe migrate --dir sql/migrations`. Set `DATABASE_URL` in your local environment; do not expose PostgreSQL outside loopback. Run SQL migration checks and tagged integration tests only against a disposable `vnsignal_test` database, never the working `vnsignal` database. CI uses PostgreSQL 16; local testing on another PostgreSQL version does not establish exact PostgreSQL 16 compatibility.

The explicit `vnpipe backfill --active` command refuses unknown listings and needs a recent, successful active probe and newly observed absolute quota. Its database guard survives restarts and prevents budget refreshes from returning previously spent calls. The guard expires in five minutes or on a Vietnam trading-day boundary and is not refreshed automatically. Re-run only after reading updated vendor usage; no unattended daemon exists yet. Every bad vendor frame or mismatched response ID blocks its job for inspection.

For independent KBS equity comparisons, use `vnpipe ingest-kbs-cross-source --active --from YYYY-MM-DD --to YYYY-MM-DD --days N [--max-calls N]`. It selects symbols from positive-volume VCI bars in the requested range, defaults to one call, and caps each run at 30. Calls use `Gateway.CallRecorded`; exact KBS frames and their checksums are appended to `raw.landings` only. This command does not update `core.bars_daily` or select DQ pairs; Tier A membership and the DQ runner still control pair selection. A provider error remains visible in the job and reservation ledger. Do not retry after an adapter failure without new source evidence; every later attempt needs a fresh absolute quota check and reservation.

For reproducible local debugging, never use an account key in CI or a remote server, and never edit the raw landing or completion marker manually. Captured data and model output must remain non-authoritative until DQ gates and PIT/ML checks are built.

## Operational safety

- Don't infer successful data retrieval from HTTP 200 alone: empty rows or a truncated response are not a successful probe.
- Do not fetch today's close while HOSE/HNX/UPCoM bars remain unpublished; stale latest data must suppress signals.
- On any blocking data-quality failure leave the previous serving snapshot untouched and mark stale.
- Treat the initial repository as non-production until the phase exit criteria are independently verified.

## Renewing quota during an authorized historical run

`backfill --active` begins with a fresh passive vnstock quota check and installs a five-minute, cross-process PostgreSQL guard. Before each **unfinished** job it checks for impending expiry (90-second lead time); if due, it reads status and exact quota limits/usage again, derives remaining calls, and persists a reduced-or-equal remaining budget. These passive CLI checks do **not** request OHLCV, statements or other priced market-data routes.

An unauthenticated/Guest account, unknown or percentage-only report, changed RPM, or failed PostgreSQL refresh immediately aborts before another vendor call. A past-day guard cannot be carried across Vietnam midnight: start a new explicitly authorized command with a fresh probe and real remaining trading-day count. The command still has a two-hour overall deadline, and it does **not** run unattended or auto-start the next day.

For a non-consuming progress view, use `vnpipe backfill-status --from YYYY-MM-DD --to YYYY-MM-DD --source vci` against the same exact range. Check `ops.api_reservations` and `ops.quota_guard` if investigating a restart; never manually reset `spent` to bypass a limit.

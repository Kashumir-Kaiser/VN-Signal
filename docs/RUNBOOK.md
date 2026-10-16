# Local runbook

## Installation

Install Python 3.12 and Go 1.23. Install `vnstock==5.0.1` using `--extra-index-url https://vnstocks.com/api/packages` from its official channel and register your free Community key on the **one designated machine**. See the [official guide](https://www.vnstocks.com/docs/vnstock/cau-hinh-va-dong-lenh). Never run `vnstock register` in CI, or paste the key into GitHub secrets for ingestion.

## Verify without spending market-data calls

`go -C go test ./...` and `py -3.12 -m unittest discover -s tests -v` (Windows) or `python3 -m unittest discover -s tests -v` (Linux).

`go -C go run ./cmd/vnpipe probe` checks CLI entitlement and usage without querying market quotes. `go -C go run ./cmd/vnpipe probe --active` explicitly spends a small number of calls. Inspect the report under `docs/probe/`. If quota/counts or routes cannot be determined, ingestion remains disabled until reviewed.

## PostgreSQL

Numbered migrations `001_init.sql`, `002_ingest_state.sql`, `003_quota_guard.sql`, and `004_raw_bytes.sql` are now handled by a native Go migration engine, with checksums and transaction rollback. Compile on the registered Windows/Linux machine with `go -C go build -tags postgres -o ../vnpipe ./cmd/vnpipe` (Windows: `../vnpipe.exe`) and run `vnpipe migrate --dir sql/migrations`. Set `DATABASE_URL` in your local environment; do not expose PostgreSQL outside loopback. PostgreSQL's tagged tests run in CI using an ephemeral PostgreSQL 16 service; the local build environment cannot download pgx or execute PostgreSQL. Do not claim it passed until CI reports a green run.

The explicit `vnpipe backfill --active` command refuses unknown listings and needs a recent, successful active probe and newly observed absolute quota. Its database guard survives restarts and prevents budget refreshes from returning previously spent calls. The guard expires in five minutes or on a Vietnam trading-day boundary and is not refreshed automatically. Re-run only after reading updated vendor usage; no unattended daemon exists yet. Every bad vendor frame or mismatched response ID blocks its job for inspection.

For reproducible local debugging, never use an account key in CI or a remote server, and never edit the raw landing or completion marker manually. Captured data and model output must remain non-authoritative until DQ gates and PIT/ML checks are built.

## Operational safety

- Don't infer successful data retrieval from HTTP 200 alone: empty rows or a truncated response are not a successful probe.
- Do not fetch today's close while HOSE/HNX/UPCoM bars remain unpublished; stale latest data must suppress signals.
- On any blocking data-quality failure leave the previous serving snapshot untouched and mark stale.
- Treat the initial repository as non-production until the phase exit criteria are independently verified.

## Renewing quota during an authorized historical run

`backfill --active` begins with a fresh passive vnstock quota check and installs a five-minute, cross-process PostgreSQL guard. Before each **unfinished** job it checks for impending expiry (90-second lead time); if due, it reads status and absolute remaining usage again and persists a reduced-or-equal remaining budget. These passive CLI checks do **not** request OHLCV, statements or other priced market-data routes.

An unknown/percentage-only report, changed RPM tier, or failed PostgreSQL refresh immediately aborts before another vendor call. A past-day guard cannot be carried across Vietnam midnight: start a new explicitly authorized command with a fresh probe and real remaining trading-day count. The command still has a two-hour overall deadline, and it does **not** run unattended or auto-start the next day.

For a non-consuming progress view, use `vnpipe backfill-status --from YYYY-MM-DD --to YYYY-MM-DD --source vci` against the same exact range. Check `ops.api_reservations` and `ops.quota_guard` if investigating a restart; never manually reset `spent` to bypass a limit.

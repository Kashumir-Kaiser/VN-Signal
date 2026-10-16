# Local runbook

## Installation

Install Python 3.12 and Go 1.23. Install `vnstock==5.0.1` using `--extra-index-url https://vnstocks.com/api/packages` from its official channel and register your free Community key on the **one designated machine**. See the [official guide](https://www.vnstocks.com/docs/vnstock/cau-hinh-va-dong-lenh). Never run `vnstock register` in CI, or paste the key into GitHub secrets for ingestion.

## Verify without spending market-data calls

`go -C go test ./...` and `py -3.12 -m unittest discover -s tests -v` (Windows) or `python3 -m unittest discover -s tests -v` (Linux).

`go -C go run ./cmd/vnpipe probe` checks CLI entitlement and usage without querying market quotes. `go -C go run ./cmd/vnpipe probe --active` explicitly spends a small number of calls. Inspect the report under `docs/probe/`. If quota/counts or routes cannot be determined, ingestion remains disabled until reviewed.

## PostgreSQL

Apply `sql/migrations/001_init.sql` locally to an empty PostgreSQL 16+ database with `psql -v ON_ERROR_STOP=1 -f sql/migrations/001_init.sql`. Migrations have not been live-tested in this build environment, and Go migration orchestration is pending. Do not expose PostgreSQL outside loopback.

## Operational safety

- Don't infer successful data retrieval from HTTP 200 alone: empty rows or a truncated response are not a successful probe.
- Do not fetch today's close while HOSE/HNX/UPCoM bars remain unpublished; stale latest data must suppress signals.
- On any blocking data-quality failure leave the previous serving snapshot untouched and mark stale.
- Treat the initial repository as non-production until the phase exit criteria are independently verified.

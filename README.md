# VN-Signal

**Single-user Vietnamese equity research system (in development).** Proprietary: copyright (c) 2026 Kashumir-Kaiser; see [LICENSE](LICENSE).

VN-Signal is designed around the **vnstock v5 free tier**. It must not claim that model predictions are investment advice. The system is deliberately **fail-closed**: unknown quota limits prevent scheduled ingestion; an unverified data source cannot produce recommendations.

## Current implementation

Phase 0 foundation and a portion of Phase 1: a Go 1.23 CLI; supervised JSON-lines Python 3.12 vnstock adapter; status/usage/capability probes; conservative quota budgeting and rate limiting; bar validation; atomic checkpoints; initial PostgreSQL schemas; unit tests and CI. **No trained model, portfolio recommendations, usable desktop app, full backfill, or deployed scheduler yet.** See [Build status](docs/BUILD_STATUS.md).

## Prerequisites

- Python **3.12**, [`uv`](https://docs.astral.sh/uv/), Go **1.23+**. PostgreSQL 16+ is required for migrations and future ingestion.
- On your **local machine only**, install vnstock v5 and register your Community (free) key. The key is never written into this repository.

```powershell
uv venv --python 3.12 .venv
uv pip install --python .venv/Scripts/python.exe "vnstock>=5,<6"
.venv\Scripts\vnstock.exe register
go -C go test ./...
go -C go run ./cmd/vnpipe --help
```

On Linux, replace `.venv/Scripts/python.exe` with `.venv/bin/python`, and `.venv\\Scripts\\vnstock.exe` with `.venv/bin/vnstock`. For Python code on Windows, `py -3.12` can be used; the CLI invokes the configured interpreter directly.

```powershell
$env:VNPIPE_PYTHON = ".venv/Scripts/python.exe"
go -C go run ./cmd/vnpipe probe
# Active probe consumes your *local* free-tier allowance, opt in explicitly:
go -C go run ./cmd/vnpipe probe --active
```

`probe` writes a date-stamped report to `docs/probe/` locally. Without `--active`, it checks the installed tier and quotas but does not request market data. The active probe checks a minimal symbol/bar/calendar sample, records actual columns and limitations and never treats missing data as success. **Do not use GitHub-hosted runners for live vnstock calls.**

## Next gates

Read [Runbook](docs/RUNBOOK.md), [Data contract](docs/DATA_CONTRACT.md), and [Decisions](docs/DECISIONS.md). Nothing is presented as a validated market signal until historical point-in-time checks, walk-forward testing, cross-language parity, and paper-trading checks pass.

Attribution: [Vnstock](https://vnstocks.com/docs/vnstock) provides the source API and its own licensing and tier rules; this repository does **not** license Vnstock or redistribute its data.

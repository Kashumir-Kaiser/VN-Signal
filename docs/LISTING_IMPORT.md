# Verified market listing import (Phase 1)

The market universe must come from the installed **vnstock v5** `Reference().equity.list_by_exchange()` response, not from ticker guesses or a hard-coded list. Per the v5 reference output contract, fields include `symbol`, `exchange` and `icb_code_lv2`; the last field is an **ICB level-two code**, not a descriptive industry name. A local capability probe overrides the published description if the user's installed library differs.

## Workflow on the registered single-user machine

1. Install PostgreSQL 16+, register the Community-tier vnstock account locally and configure a Python **3.12** `uv` environment. Set `VNPIPE_PYTHON` to that environment's Python executable and set `DATABASE_URL` to the local PostgreSQL instance. Keep credentials out of tracked files.
2. Apply migrations using the native CLI: `go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations`.
3. **Only when the fresh passive report shows an authenticated Community/free account and exact quota counters:** run `go -C go run -mod=mod -tags postgres ./cmd/vnpipe probe --active --trading-days N --out ../docs/probe` with the true remaining trading-day count for that month. The active Go capability probe attempts seven metered route calls: equity listing, FPT daily bars, VNINDEX daily bars, FPT income statement, balance sheet, cash flow, and market calendar. It retains the listing response as `listing_frame`; the subsequent listings import is offline and makes no additional vendor call. For a focused retry after a partial probe, add `--routes equity_list` (or a comma-separated set of failed routes) and use a separate `--out` directory. Remaining calls are computed only from exact limits minus exact used counters; if either is missing or percentages are the only reading, stop instead of guessing.
4. The registered-machine listing-only probe succeeded on 2026-10-16 and is saved locally at `docs/probe/retry6/2026-10-16.json`. It contains 1,754 provider rows: 406 HOSE, 299 HNX, 814 UPCOM, and 235 `DELISTED`. Import from the repository root after migrations:
   ```bash
   go -C go run -mod=mod -tags postgres ./cmd/vnpipe import-listings --probe ../docs/probe/retry6/2026-10-16.json
   ```
   This is an offline import: it does not call vnstock or spend quota. **Do not commit the real probe report or credentials.**
5. Confirm the import summary reports 1,519 current symbols and 235 excluded delisted rows, then verify the dated `core.listing_snapshots` count before starting the quota-capped bar backfill.

## Safety and idempotency

- The importer requires a successful active Go probe containing the *actual* listing frame, not an old report with summary-only counts. By default it needs at least **1,000 currently listed symbols** across **all three exchanges**. This threshold is a conservative guard, not a contractual vnstock limit.
- A provider row marked `DELISTED` is retained in the exact raw frame but excluded from the current active universe because its original exchange is unknown. `HOSE`, `HNX`, and `UPCOM` rows alone become active symbols and backfill candidates.
- Malformed frames, repeated/invalid symbols, unrecognized exchange labels, row-count discrepancies, conflicting same-day snapshots, out-of-order dates and a count drop greater than **5%** are blocking errors. Correct the source/problem before retrying.
- The frame and its SHA-256 are archived in `raw.landings`. Within one PostgreSQL transaction the importer updates `core.symbols` and inserts immutable daily `core.listing_snapshots`. A symbol missing from a **validated complete** new snapshot is marked inactive; it is **not deleted**, so future backtesting can account for delistings.
- Import itself is **offline**, consumes no API quota and is safe to rerun with an identical probe. `VNPIPE_DISABLE_LIVE=1` prevents the separate active probe but does not prevent verifying/importing already-captured data.
- The active listing route and PostgreSQL CI have passed, but Phase 1 is still incomplete until the local PostgreSQL import, quota-capped multi-day backfill, resume behavior and end-to-end data-quality checks succeed on the registered machine.

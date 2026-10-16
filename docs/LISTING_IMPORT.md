# Verified market listing import (Phase 1)

The market universe must come from the installed **vnstock v5** `Reference().equity.list_by_exchange()` response, not from ticker guesses or a hard-coded list. Per the v5 reference output contract, fields include `symbol`, `exchange` and `icb_code_lv2`; the last field is an **ICB level-two code**, not a descriptive industry name. A local capability probe overrides the published description if the user's installed library differs.

## Workflow on the registered single-user machine

1. Install PostgreSQL 16+, register the Community-tier vnstock account locally and configure a Python **3.12** `uv` environment. Set `VNPIPE_PYTHON` to that environment's Python executable and set `DATABASE_URL` to the local PostgreSQL instance. Keep credentials out of tracked files.
2. Apply migrations using the native CLI: `go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations`.
3. **Only when the fresh passive report shows an authenticated Community/free account and exact quota counters:** run `go -C go run -mod=mod -tags postgres ./cmd/vnpipe probe --active --trading-days N --out ../docs/probe` with the true remaining trading-day count for that month. The active Go capability probe attempts seven metered route calls: equity listing, FPT daily bars, VNINDEX daily bars, FPT income statement, balance sheet, cash flow, and market calendar. It retains the listing response as `listing_frame`; the subsequent listings import is offline and makes no additional vendor call. For a focused retry after a partial probe, add `--routes equity_list` (or a comma-separated set of failed routes) and use a separate `--out` directory. Remaining calls are computed only from exact limits minus exact used counters; if either is missing or percentages are the only reading, stop instead of guessing.
4. Inspect the resulting probe file's `routes.equity_list` result and ensure the exchange universe and columns are as expected. Import without a network call: `go -C go run -mod=mod -tags postgres ./cmd/vnpipe import-listings --probe ../docs/probe/YYYY-MM-DD.json`. **Do not commit real probe reports or credentials.**
5. Confirm current `core.symbols` and dated `core.listing_snapshots`, and only then consider a separately authorized, quota-limited bar backfill.

## Safety and idempotency

- The importer requires a successful active Go probe containing the *actual* listing frame, not an old report with summary-only counts. By default it needs at least **1,000 symbols** across **all three exchanges**. This threshold is a conservative guard, not a contractual vnstock limit.
- Malformed frames, repeated/invalid symbols, unknown exchange strings, row-count discrepancies, conflicting same-day snapshots, out-of-order dates and a count drop greater than **5%** are blocking errors. Correct the source/problem before retrying.
- The frame and its SHA-256 are archived in `raw.landings`. Within one PostgreSQL transaction the importer updates `core.symbols` and inserts immutable daily `core.listing_snapshots`. A symbol missing from a **validated complete** new snapshot is marked inactive; it is **not deleted**, so future backtesting can account for delistings.
- Import itself is **offline**, consumes no API quota and is safe to rerun with an identical probe. `VNPIPE_DISABLE_LIVE=1` prevents the separate active probe but does not prevent verifying/importing already-captured data.
- This does **not** complete Phase 1: CI PostgreSQL validation, real installed-vendor probe, successful listing import and multi-day resumable backfill on the registered device are still required.

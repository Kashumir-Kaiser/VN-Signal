# Data contract (initial v1)

All `raw` landings are append-only, with `ingest_id` (UUID), `fetched_at` (timestamptz), `source`, `route`, `payload` (JSONB) and `payload_bytes` (BYTEA, nullable only for legacy rows); never replace a landing row. Compute `payload_sha256` against exact incoming bytes, not JSONB-serialized text. `core.bars_daily` is the deduplicated daily price table, keyed by `(symbol_id, trade_date)`. Its `adj_basis` must be explicitly determined before modelling.

`core.fundamentals_pit` has `period_end`, `period_type`, `first_seen_at`, `available_at`, `last_seen_at`, `restated`, and `payload`. For backfilled financial periods, availability **cannot be earlier** than conservatively assumed publication lag (quarter: 45 days, year: 100 days); once directly observed on local pulls, availability is the first seen timestamp. Training joins on `available_at <= signal_time`, not `period_end`.

`ops.api_calls` is an append-only audit with route, source, attempted/fetched timestamps, result type, quota bucket metadata and run ID. `ops.pipeline_runs` records an idempotency key, status, step and error. `feat`, `ml` schemas are deliberately created for future migrations, not populated with fake model outputs.

Go's DQ gate treats zero and negative prices, high < low, negative volume, duplicate symbol/date rows, invalid ISO session dates, and missing fields as blocking. Exchange price jumps require a separate adjustment/corporate-action review; do not mechanically delete genuine corporate actions.

`core.listing_snapshots` holds complete observations of currently listed HOSE/HNX/UPCOM membership by trade date. If a vendor listing frame includes rows labeled `DELISTED`, keep those rows in the complete raw landing but do not assign an exchange or insert them as active symbols; their former exchange is not established by that field. Previously observed symbols that disappear from the current exchange rows remain in `core.symbols` as inactive. `industry` stores ICB level-two codes from vnstock v5 `icb_code_lv2` (not descriptive sector names). Unknown or partial membership frames must not update the universe.

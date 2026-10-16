# Build status — 2026-10-16

**State: INCOMPLETE, no trading recommendations are enabled. Go offline CI failure fixed; a guarded Phase 1 PostgreSQL ingester is now implemented, but the tagged PostgreSQL test and live probe have not been independently observed.** This is an initial checked-in foundation, not a complete implementation of the master prompt.

| Phase | Status | Evidence | Unfinished exit criteria |
| --- | --- | --- | --- |
| 0: probe/schema/config | PARTIAL | Strict Python/Go JSONL tests, passive probe, metered active probe gateway, validated Go config, PostgreSQL 16 service test defined in CI | Observe CI PostgreSQL results and live probe on user's registered device, validate real data shapes |
| 1: ingestion/backfill | PARTIAL | Fail-closed quota parsing and metered call gateway with wait tests; Go OHLCV frame normalizer and backfill preview; SQL durable job and API reservation migration; checkpoint persistence, DQ blocking gates, worker-process concurrency bound | PostgreSQL pgx CopyFrom bulk path, real completed listings import, verified tagged PostgreSQL integration test and live full quota-safe backfill |
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

## CI repair and next Phase 1 increment (2026-10-16)

- Reproduced hosted Go failure by running `VNPIPE_DISABLE_LIVE=1 go -C go test -race -count=1 ./...`. Four injected gateway tests inherited the hosted CI live-disable flag; added `t.Setenv(..., "0")` only inside those tests. The `TestDisabledInCI` safety test retains the disabling flag and still passes.
- New `ingest.NormalizeBars` validates saved vendor OHLCV frames, refuses unknown/invalid columns, duplicates, non-chronological dates, and numeric invalidity, and never synthesizes missing prices.
- `preview-backfill` generates an offline, budget-capped deterministic plan only from a verified active probe and absolute quota readings. It cannot call the market API.
- `sql/migrations/002_ingest_state.sql` adds backfill jobs and per-attempt reservations for future Postgres integration; CI migration tests now apply both numbered migrations twice, with new invalid-completion and duplicate-reservation assertions.
- Historical note: this section predates the transactional PostgreSQL store added below. Remaining: live source verification, stock-listing import, full historical backfill, models and desktop app. No Phase 0/1 exit claimed.

### Backfill execution boundary (work in progress)

`go/internal/ingest/runner.go` now defines `Runner.RunBarsBackfill`. Offline tests confirm a successful worker response gets validated and committed once, repeated completed jobs consume no additional quota, storage errors fail closed, and hosted CI cannot call the vendor. Every market call goes through `live.Gateway`, never directly through the Python worker.

`LandingStore` was initially an interface; the PostgreSQL implementation and explicitly authorized tagged `backfill` command have now been added, as described below.


## Phase 1 continuation — transactional ingest boundary (2026-10-16)

Implemented and committed on main:

- New database transaction store (`go/internal/ingest/postgres.go`) records a per-attempt reservation before invoking vnstock, records dispatch and result status, and writes raw landing, canonical `core.bars_daily`, and `COMPLETED` marker together. Duplicate/completed job IDs do not request data twice.
- A new singleton `ops.quota_guard` (migration 003) enforces an absolute, durable, cross-process allowance; verifies short-lived vendor readings; retains cross-process pacing after restart; and never returns calls previously counted as spent. A reservation is spent even on a canceled or failed request.
- `live.CallRecorded` refuses absent/failing audit hooks and records failures/cancellation, and the runner quarantines frames that do not match the requested symbol/period/ID. Vendor rate limits remain retryable with a renewed verified quota and expired lease; entitlement errors and invalid frames block the affected job.
- A Windows/Linux native migration command with checksum registry and PostgreSQL dollar-string-aware parser replaces a shell-only runtime process.
- Tagged PostgreSQL integration tests cover real transaction commit/resume, absent-symbol rollback, and durable quota exhaustion across store instances. CI now runs PostgreSQL 16, the native migration command twice, and the tagged driver tests. These **have not been executed locally**, because PostgreSQL and the pinned pgx dependency are not available in this offline build environment.
- A narrowly scoped opt-in `backfill --active` path is wired only for PGX-tagged binaries, current verified absolute quota, a previous successful active probe, and already-known listed symbols. It intentionally does not infer missing symbol metadata or schedule itself.

Offline evidence: `VNPIPE_DISABLE_LIVE=1 go -C go test -race ./...`, `go -C go vet ./...`, and `VNPIPE_DISABLE_LIVE=1 python3 -m unittest discover -s tests -v` pass. No live price calls were made. **Phase 1 remains PARTIAL** until provider shape, PostgreSQL CI, full listed-universe import/backfill, DQ gates and runtime operation are verified. No Phase 2–6 exit milestones are claimed.

## Point-in-time equity listings and exact raw bytes (2026-10-16)

- Implemented and pushed strict v5 `equity_list` normalization using documented `symbol`, `exchange`, `icb_code_lv2` fields. Go active probe now saves the complete frame it already requested, alongside its summary, without an extra API call.
- Added `vnpipe import-listings --probe FILE`, requiring a complete active-probe frame with at least 1,000 symbols across HOSE/HNX/UPCOM. PostgreSQL importer preserves original rows and SHA-256, upserts `core.symbols`, appends dated `core.listing_snapshots`, and marks absent names inactive rather than deleting them. Transaction, advisory lock, idempotency, backdate rejection and >5% shrinkage guard enforce safe state changes.
- Migration `004_raw_bytes.sql` records the original vendor JSON bytes as `bytea`, because JSONB canonicalization prevents reliable original-byte SHA comparison; legacy rows remain nullable. Both listing and OHLCV landings write bytes. Added SQL and tagged PostgreSQL tests for exact-byte parity.
- **Verification:** new listing parser and store code passed isolated stdlib Go race/unit tests and vet locally. The full repository Go test suite, PostgreSQL 16 integration, GitHub push workflow result, installed vnstock v5 probe and actual listing import were **not** executed or observed in this environment. All Phase 0/1 exit gates remain open until these are verified on CI and the registered machine.

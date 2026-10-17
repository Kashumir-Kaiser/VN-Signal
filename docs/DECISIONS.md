# Decisions

1. **Initial commit is an honest bootstrap, not an invented working full stack.** No external market-data credentials are available in the build environment. A real v5 entitlement probe and multi-day quota backfill must happen on the designated user's machine.
2. **Keep API interaction strictly isolated** inside a single Python adapter (target <400 lines); Go calls a JSON-lines protocol. The adapter never learns model logic, and credentials never travel in the JSON protocol.
3. **No quota guessing.** The scheduler and future backfill must consume absolute available budgets from real reports or stop. Remaining *percentages* are not interchangeable with remaining API *calls*.
4. **No seed recommendations.** Until risk, cost, leakage and quality gates pass, no demo/mock rows should appear as a genuine BUY or SELL signal.
5. **No unnecessary infrastructure.** PostgreSQL wrangling plus SQLite serving as specified. No Docker, Redis, Celery, hosted VN API CI jobs, auth, or cloud DB.
6. **Raw PIT timestamps are never rewritten.** Earlier data published in later financial reports must be conservatively availability-stamped and identified as assumptions, not proven historical publication timestamps.


## 2026-10-16 P0 hardening

- A worker frame is valid only if it is the sole JSONL frame, has the matching request ID, a coherent success/failure envelope, and exits zero. A 45-second default deadline and one-worker semaphore bound hangs and process explosions. Python library stdout is redirected to stderr and stderr collection is capped; the subprocess receives only whitelisted local runtime environment keys.
- The Python adapter deliberately refuses `probe(active=True)`; Go's `live.Gateway` is the only metered API route gateway. Live calls require an authenticated `free`/`community` status, matching usage tier, and exact per-minute, per-day, and per-month limits plus used counters. Remaining calls are computed as limit minus used; Guest, percentage-only, inconsistent, or unknown reports block. There is no automated full ingestion yet.
- `source=` remains on `.ohlcv()` / statement methods as specified by vnstock v5's published API. It is **not** moved to `Market()` or `.equity()` constructor absent contrary evidence from a local Phase-0 probe.
- Exchange spelling is canonicalized to `UPCOM` by PostgreSQL before-insert/update triggers, so upstream `UPCoM` inputs are accepted without polluting downstream joins. Financial period-end timestamp comparison explicitly uses `Asia/Ho_Chi_Minh`.
- Checkpoint writers take an exclusive directory lock. A crash leaving the `.lock` behind blocks automatic writes until manually inspected; this is safer than racing a prior writer. Crash orphan temp files are removed under this lock; previous checkpoint remains readable after failed fsync/rename. Unix directory entry sync is attempted; Windows uses native rename guarantees, and durability remains filesystem-dependent.
- The Go configuration parser intentionally supports only the simple committed TOML subset; it rejects unknown/missing keys instead of silently accepting unexpected constructs. Python 3.12 `tomllib` also checks syntax in CI.
- Hardening tests do not turn absent components into implemented features. Scheduler recovery, SQLite swapping/inference parity, seven unattended runs and PostgreSQL disk-exhaustion recovery are future implementation gates.

### Phase 1: do not enable live backfill before transactional storage

The implementation introduces an offline-tested `LandingStore` boundary instead of publishing an unmetered backfill command. `RunBarsBackfill` always invokes routes through `live.Gateway`, and a failed validation or storage operation never marks a job complete. This still does **not** guarantee crash-safe quota accounting: before any production integration, implement durable reservations written *prior to* the API call in PostgreSQL (`ops.api_reservations`), with outcome updates and resumable job state. Neither a JSON checkpoint nor a memory-only pacer is acceptable as the sole source of quota truth.


## 2026-10-16 — Phase 1 PostgreSQL execution boundary

- Go uses `database/sql` for a transactionally tested store API; the explicitly tagged `postgres` binary registers the pinned `pgx/v5/stdlib` driver. This allows the offline standard-library tests to run without downloading third-party modules while hosted PostgreSQL CI verifies the real connection. The full `pgx.CopyFrom` fast path is not yet implemented; correctness and failure isolation take precedence over bulk throughput at this stage.
- An `ops.quota_guard` singleton serializes reservations across processes, tracks irrevocable spent calls, enforces min spacing and a five-minute freshness deadline, and retains prior pacing across restarts. Refreshing the guard within the same Vietnam date cannot increase the previous remaining allowance, even if the vendor returned stale absolute usage. This is deliberately conservative.
- `Gateway.CallRecorded` requires durable reserve, dispatch, and finish hooks. A failed hook cannot result in successful ingestion, and unknown quota always blocks. Temporary rate limits consume a reservation and require a new preflight; entitlement failures block the job, and malformed source frames are quarantined.
- A `PostgresStore` transaction writes the unmodified vendor JSON, its SHA-256, the canonical OHLCV rows, and job completion together; unknown symbols are not automatically assigned fictitious exchange/industry metadata. Listing import must be completed before a full-universe backfill.
- Tagged backfill is opt-in only. There is no automatic scheduler, no live calls from CI, no daily trading recommendations, no charting app, and no claim that Phase 1 is finished without PostgreSQL CI and a local vnstock probe. The native Go migration runner replaces shell-only runtime instructions and supports both Windows and Linux.

## 2026-10-16 — equity universe provenance

- Only an already-metered, successful v5 `Reference().equity.list_by_exchange()` probe with a complete embedded response is eligible for offline import. `symbol` and `exchange` are required; `icb_code_lv2` is an industry code, not an English/Vietnamese name. No guessed metadata.
- The CLI requires at least 1,000 equities and all three exchanges before changing the current listed universe. A drop of more than 5%, out-of-order input or same-day conflict blocks the whole transaction instead of silently mass-delisting stocks. This threshold is a protective heuristic, not an external free-tier limit.
- Keep inactive names and daily listing snapshots for future survivorship analysis. Store exact vendor response bytes alongside JSONB (migration 004): comparing SHA-256 with reserialized JSONB is invalid because its canonical representation need not match the input bytes.

## 2026-10-16 — verified queue before quota cap

- Historical backfill candidates are always derived from the latest complete local PostgreSQL listing snapshot. No live CLI-provided ticker array; the preview-only tool can still accept a file without authorizing API calls.
- The source frame's stored bytes must verify against `payload_sha256`; membership must match current active flags exactly and cover all three exchanges. A seven-day age limit is a conservative local operating guard, not a vnstock entitlement claim.
- Resume keys are exact `(route,symbol,source,from,to)`. Exclude already completed and blocked keys before applying the current absolute quota cap; otherwise the same first N alphabetical symbols starve later symbols. A new `--to` date creates different jobs and must not be treated as an automatic incremental 5-session refresh.
- Read membership/provenance/jobs in one repeatable-read PostgreSQL transaction. Existing per-attempt durable quota reservations, cross-process pacing and 15-minute recovery leases remain mandatory. Do not auto-enable background ingestion or financial suggestions before vendor/CI validation.

## 2026-10-16 — verify membership against immutable vendor data

- A SHA-256 match on `raw.landings.payload_bytes` alone **does not** show that `core.symbols` and the latest `core.listing_snapshots` still match the source. A coordinated mutation of both relational tables could satisfy previous count/active-flag guards.
- The backfill-universe read now reparses the archived, signed listing frame and compares every symbol, exchange and level-two ICB industry code against its latest database snapshot in sorted order, inside the existing repeatable-read transaction. Any mismatch disables ingestion.
- `vnpipe backfill-status` is a read-only reporting entry point using this same verified queue. Unlike `backfill --active`, it never contacts vnstock or mutates the PostgreSQL quota guard.

## 2026-10-16 — renewable, fail-closed short-lived quota proof

- A quota snapshot valid for five minutes is not a valid reason to abort all long-running historical jobs after five minutes; but extending its lifetime without a fresh absolute vendor observation would risk the account/device quota. Before **each pending** market job, check the durable guard; when it will expire in 90 seconds, fetch a fresh *passive* status/usage report and atomically install the lower permitted remaining allowance.
- Do not reset spent calls on renewal. `InstallQuota` already carries the minimum of prior remaining budget and newly observed account capacity forward; `ops.api_reservations` is append-only. The initial local Go pacer is not enlarged by a renewal.
- A tier/RPM change mid-run is a reason to stop and restart explicitly, not silently increase throughput. Errors from the CLI, status parsing, PostgreSQL, or date change block all further market calls. New trading-day quota is handled by a new explicitly authorized run, not unattended renewal.

7. **Provider `DELISTED` rows are archived but not backfilled.** The registered-device `equity_list` probe on 2026-10-16 returned a `DELISTED` exchange category. Preserve the complete exact provider frame in raw storage, but do not invent former exchange membership or treat those rows as currently listed. Active snapshots and history jobs use HOSE/HNX/UPCOM rows only; a name previously observed as listed is retained inactive when it disappears.


## 2026-10-17 — Historical securities master is Phase 1 data provenance, not Phase 2/3 execution

- Extend Phase 1 with `core.security_master` (observed ticker codes) and append-only `core.security_observations` (exact source landing, row index, observation day, provider category and reported exchange). Backfill the registry entirely from previously imported, SHA-256-verified complete VCI listing frames; future listing imports update the same registry transactionally.
- All 235 provider-`DELISTED` rows from the 2026-10-16 frame may be recovered as **observed provider symbols**. They are not automatically active, investable, formerly listed on any asserted exchange, or eligible for a historical price request. The provider's `DELISTED` label is **not** an effective delisting date.
- Avoid coalescing ticker renames/reuse as one legal issuer without independent corporate-action evidence. `core.security_master.first_observed_at` means first available local provider observation, not date of founding, IPO, first trading, exchange admission or delisting.
- Exact-dated `core.security_observed_days` reports only what the source observed on that date, with explicit same-day conflict status. Historical gaps and unverified periods stay unknown; the current 1,519-stock backfill queue is intentionally unchanged.
- The specification §4.2 explicitly accepts the survivorship caveat and a disclosed backtest haircut while daily snapshots accumulate. Phase 2 owns PIT investable-universe joins; Phase 3 owns historical walk-forward backtesting. This change cannot silently train, score or backtest.
- No undocumented vnstock route is introduced: obtaining historical first-ever trading dates, exchange transfer intervals and delisting effective dates requires new validated evidence and an entitlement/absolute-quota check, not guesses from an adjusted OHLCV row or company-profile `listing_date`.

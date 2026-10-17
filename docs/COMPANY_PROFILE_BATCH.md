# Phase 1: resumable VCI company profiles

## Purpose

The 1,754-row observed VCI security master contains 1,519 HOSE/HNX/UPCOM
securities and 235 provider-identified, **undated** delisted tickers as of
2026-10-17. The new collector follows that actual evidence-backed master,
not a guessed historical universe. Every request invokes
`Reference().company(symbol).info(source="vci")` on the user's registered
local machine using the Go live gateway, and archives the source frame and
SHA-256 in PostgreSQL.

A profile's provider-reported `listing_date` **cannot establish** its
first-ever market trade, effective delisting, suspension, or former exchange.
The provider may return no date. This collector makes no changes to
`core.security_lifecycle_evidence`, trading eligibility, or Phase-2 ML.

## Run from Git Bash in repository root

```bash
git pull --ff-only origin main
export VNPIPE_PYTHON="$(cygpath -aw "$PWD/.venv/Scripts/python.exe")"
go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations
unset VNPIPE_DISABLE_LIVE

# Real vendor requests; 50 is an explicit maximum, not a target/minimum.
# Adjust trading-days to the actual remaining trading sessions in the month.
go -C go run -mod=mod -tags postgres ./cmd/vnpipe collect-company-profiles \
  --active --trading-days 10 --max-calls 50

# Offline read-only coverage and collection status.
go -C go run -mod=mod -tags postgres ./cmd/vnpipe company-profile-status --limit 30
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f sql/diagnostics/company_profile_coverage.sql
```

## Resuming and quota accounting

Rerun the same command to continue. The PostgreSQL
`ops.company_profile_jobs` table persists one row for **each security**
including provider DELISTED, with `PENDING`, `IN_FLIGHT`, `IMPORTED`,
`MISSING_DATE`, `ERROR`, and `UNKNOWN` states. Prior one-symbol
`import-company-info` operations are detected and automatically excluded
before a new request. `MISSING_DATE` means a *successful archived frame*
actually reported no listing date; it is **not** a claim about pre-listing.

All attempts are written to `ops.company_profile_attempts` *before*
dispatch with account quota reservations and a deterministic archive path.
The collector uses the same cross-process `ops.quota_guard` as OHLCV
backfill, conservatively capped at 85% of authenticated RPM and 80% of
absolute daily/monthly capacity. A fresh passive `vnstock usage/status`
report is required on startup and on guard refresh; an account-tier change
halts further calls. Do **not** run the standalone live probe or an unrelated
external vnstock client concurrently; those do not participate in the DB
quota-guard serialization. This is one local single-account collector, not
an account-wide distributed limiter.

The provider frame is written atomically to a uniquely named file under
`docs/probe/company/batch`, then imported in PostgreSQL with checksum,
symbol and date validation. If a process dies after saving a file, the
next run attempts **offline recovery** from the file. If it dies without
a verified frame, the attempt is marked `UNKNOWN` and is never repeated
automatically. Explicitly specify `--retry-unknown` if you accept the
possibility of a duplicated *billed* call. Existing `ERROR` attempts
are also skipped until `--retry-errors` is passed. A provider rate-limit
or entitlement error stops the run; it will not hammer the route.

For every invocation, `ops.company_profile_batch_runs` stores attempts,
imported results, missing dates, errors, skipped previously imported
symbols, skipped failures, skipped uncertain outcomes and deferred
eligible symbols. This is distinct from successful company-profile
observations, which always link to their original `raw.landings`.

## Coverage diagnostic

`ops.company_profile_coverage_review` joins provider-reported dates to
actual validated `core.bars_daily` coverage and
`ops.bar_quality_issues`, preserving independent flags:

- `OHLCV_BEFORE_PROVIDER_REPORTED_DATE`: traded bars predating the
  *provider's current profile* (investigate historical transfers/identity)
- `OHLCV_BEGINS_AFTER_PROVIDER_REPORTED_DATE`: data starts later; this
  alone does not establish a missing listing or suspended session
- `ZERO_VOLUME_LIFECYCLE_UNVERIFIED`: source zero-volume observations
  remain unverified, even when profile metadata has been collected
- `FIRST_EVER_PUBLIC_TRADE_UNVERIFIED`: no primary-source first-ever
  trade notice is archived
- `PROFILE_NOT_COLLECTED`, `PROVIDER_LISTING_DATE_MISSING`, or
  `NO_VALID_OHLCV_ROWS`: exactly what their names indicate

This view **does not fill calendar gaps with synthetic observations** or
turn zero volume into a verified no-trade, pre-IPO, or delisted status.

## Safety and scope

This is an explicitly invoked Phase-1 collection command, not a scheduler.
Live calls require `--active` and a fresh registered free-tier quota
report, and are forbidden when `VNPIPE_DISABLE_LIVE=1`. Failed runs
preserve their persisted attempt log; the next invocation resumes with
remaining securities, without resetting imported work. `--max-calls`
counts actual reserved attempts, not securities marked skipped.

### Offline recovery of earlier import errors

The next batch invocation also examines saved source reports from attempts
in `ERROR` state, not just interrupted `IN_FLIGHT` attempts. A previously
failed provider request is **not** repeated merely because the importer
was broken: if the original saved success frame validates under the
current code, it is imported offline and the job is reconciled to
`IMPORTED`/`MISSING_DATE`. Invalid/error route frames remain `ERROR`
and require explicit `--retry-errors` to consume another quota unit.

## 2026-10-17 single-connection deadlock regression

Earlier `collect-company-profiles` appeared frozen after
`PostgreSQL migrations applied: 1`. No API calls were being made.
`openPostgres` intentionally configured `SetMaxOpenConns(1)`, while
`profileBatchLock` pinned that only connection for a session-level advisory
lock for the entire run. `SeedProfileQueue` waited for another connection
that would never be made; the five-hour context obscured the failure.

The collector now **only for this command** raises the pool to **two**
connections (one dedicated to the advisory lock and one for ordinary
queries), checks the configuration before taking its lock, and prints a
startup/progress line before any potentially blocking operation. An
actual-PostgreSQL regression test starts with the original single-connection
factory, confirms the lock refuses to run, then opens the second connection
and executes a query and transaction while the lock remains held.
No separate worker or parallel API request was introduced.

If a previous run has frozen, stop it with Ctrl+C, update main, then
rerun the same command. The database queue persists across restarts.
A frozen run that never passed initial seeding cannot have dispatched
profile requests. Existing rows and saved source frames are not cleared.

For offline inspection of preexisting attempts and batches:
```bash
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -c "
SELECT state,count(*) FROM ops.company_profile_jobs GROUP BY state ORDER BY state;
SELECT batch_id,started_at,finished_at,attempted,last_error_type
FROM ops.company_profile_batch_runs ORDER BY batch_id DESC LIMIT 10;"
```

## 2026-10-17 BBT timeout handling

Real collection completed 27 additional symbols and the BBT subprocess
exceeded its 60-second bound. Previously this recorded BBT as `ERROR` and
terminated the entire batch. A worker process timeout is **not** evidence
that VCI rejected the security; it is uncertain whether a provider request
was received or counted. The collector now archives the failure, marks
the attempt/security `UNKNOWN`, counts it as an attempted call, skips
it **without retrying**, and continues to the next symbol. Other
transport failures and provider rate-limit/entitlement errors still halt
the batch; a circuit breaker halts after three consecutive worker
timeouts to avoid wasting quota during a widespread outage.

The next invocation also corrects already-archived `WorkerTimeout`/
`ERROR` rows (including BBT) to `UNKNOWN` idempotently without
removing original error evidence. `--retry-errors` will not retry those
uncertain requests. Only `--retry-unknown` deliberately authorizes
another possibly billed call. This recovery needs no database schema
migration and performs no VCI calls.

## 2026-10-17 BPW isolated AdapterError

During batch 4, 56 successful profiles were archived, BHI and BLN
timed out (UNKNOWN), and BPW returned a structured `AdapterError`.
An adapter exception is not proof of a delisting, a missing listing
date, or anything about the security's historical trading eligibility.
A formerly generic structured adapter exception unconditionally stopped
the entire collector, even after dozens of successful tickers.

The collector now preserves that failure as `ERROR`, skips the ticker
without re-requesting it, and continues to the next pending security.
It does **not** silently retry BPW, BBT, BHI or BLN. Explicit
`--retry-errors` is required to retry BPW; `--retry-unknown` is
required to retry an uncertain request. Neither is part of the normal
continuation command.

A safety circuit stops subsequent live calls after three consecutive
worker timeouts, three consecutive other adapter failures, or five
transient failures in the most recent 10 calls. It still immediately
stops on provider quota/entitlement rejection, missing Python packages,
worker protocol/system exit or unknown error classes. Genuine
successes reset the consecutive failure counts. The error categories
are always persisted without leaking third-party exception text.

For an offline check of the BPW saved probe's safe error category:

```bash
py -c 'import json; p="docs/probe/company/batch/BPW-000000000142.json"; d=json.load(open(p,encoding="utf-8")); print(json.dumps(d.get("routes",{}).get("company_info",{}),indent=2))'
```

The saved batch report includes only the category known at collection
time; if it says `AdapterError`, that is *not sufficient* to diagnose
which third-party operation failed. Do not invent provider failure details.

## 2026-10-17 observed batch 5: sparse timeout cluster

Batch 5 attempted 515 profiles, committed 488, and recorded 27 errors,
then stopped because five uncertain worker timeouts were spread over
22 requests. This is about 5.2% failures overall, but exceeded an overly
sensitive five-in-25 circuit threshold. The collector now uses **five
transient errors among the most recent ten requests** in addition to its
unchanged three-consecutive-timeout and three-consecutive-adapter-error
limits. A single failure is still archived with its quota reservation and
skipped without retrying it; quota/entitlement and systemic failures still
fail closed. This does not change the individual 60-second worker timeout.
The worker completion log now includes elapsed milliseconds for further
real-world diagnosis. The reason individual VCI tickers stall remains
unverified; do not infer a market listing event from a timeout.

Review unresolved failures **offline**, before considering explicit retries:
```bash
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 \
  -f sql/diagnostics/company_profile_failures.sql
```

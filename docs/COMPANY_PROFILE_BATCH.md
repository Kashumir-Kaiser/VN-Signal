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

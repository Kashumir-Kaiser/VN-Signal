# Live VCI snapshot refresh and company listing-date evidence

## Two explicit, real API calls on the registered Windows workstation

VN-Signal now has **live** opt-in operations. They call the actual installed
vnstock v5 Community provider on the registered machine. These operations
cannot run from GitHub CI and never pretend a remote repository edit itself
contacted the user's authenticated local provider.

Official vnstock v5 Community documentation lists up to 60 requests/minute
with an account API key. This is a **rate ceiling**, not unlimited usage:
hour/day/month shared account budgets and route entitlements also apply,
and provider/worker calls are independently metered. VN-Signal reads a fresh
`vnstock status`/`vnstock usage` report and caps actual calls at 85% of
the verified available minute pace and 80% of the verified daily/monthly
allowance. It rejects unverified or percentage-only numeric capacity instead
of inventing remaining absolute calls. This conservative guard exists to
protect the registered account; it does NOT mean API calls are undesirable.

Documentation:
- https://vnstocks.com/docs/vnstock/gioi-thieu-vnstock
- https://vnstocks.com/docs/vnstock/tham-khao/cap-quyen-va-gioi-han
- https://vnstocks.com/docs/vnstock/tham-chieu-reference

From Git Bash in the repository root (the supplied `DATABASE_URL` and
`VNPIPE_PYTHON` must already point to the local PostgreSQL and vnstock v5
virtual environment):

```bash
git pull --ff-only origin main
go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations
unset VNPIPE_DISABLE_LIVE

# Make ONE metered Reference().equity.list_by_exchange() call, archive the
# unique original dated probe and import the snapshot transactionally.
go -C go run -mod=mod -tags postgres ./cmd/vnpipe refresh-listings \
  --active --trading-days 10

# Make ONE metered Reference().company("ABR").info(source="vci") call,
# archive the complete source frame and import reported listing_date.
go -C go run -mod=mod -tags postgres ./cmd/vnpipe refresh-company-info \
  --active --trading-days 10 --symbol ABR

psql "$DATABASE_URL" -X -c "
SELECT symbol, reported_listing_date, observed_at, listing_date_interpretation
FROM core.company_profile_listing_evidence
ORDER BY observed_at DESC LIMIT 20;"
```

`--trading-days 10` is the number of weekdays remaining in October
starting 2026-10-19, not a hardcoded default. Set it based on the actual
market calendar when you run these commands. Each command runs **one**
provider data request and the already-implemented quota checks; re-run for
different tickers only as capacity permits. There is no automatic
unbounded symbol loop.

Refresh source reports are written to unique UTC-timestamped folders under
`docs/probe/refresh` and `docs/probe/company`. Import failures preserve
the report for inspection. The existing dated `core.listing_snapshots`
import remains intentionally strict about same-date conflicting frames;
it does not corrupt the 2026-10-16 snapshot to force an update.
Future dated imports include all current HOSE/HNX/UPCOM and DELISTED
observations in the separate source-backed securities master.

Company metadata `reported_listing_date` is only the date *reported by
the currently queried provider*. It is not a verified IPO, first-ever
public trading date, admission to each historical venue, or effective
delisting. Migration 009 stores the raw provider bytes and SHA-256 with
the observed UTC timestamp and a fixed
`PROVIDER_CURRENT_PROFILE_UNVERIFIED` interpretation. It does not write
into `core.security_lifecycle_evidence`; therefore no `PRE_LISTING`
or `NO_TRADE` claims are made from these profiles.

## Limitations and next acquisition steps

A new VCI listing response proves the **new observation date**, not the
historical 2018 universe. For a complete historical PIT reconstruction,
official dated HNX/HOSE/VSDC admission/delisting/transfer notices and
effective dates are still required. Those must be collected and preserved
as primary-source evidence with actual publication timestamps.

This remains **Phase 1 ingestion/provenance**. Phase 2 PIT joins, Phase 3
backtests and Phase 4–6 recommendations/app/scheduler remain separate.

## 2026-10-17 company_info route registration defect

The first ABR company-profile attempt saved a failed probe with
`error_type=WorkerConfigurationError` and `duration_ms=0`. Inspection
showed that `go/internal/live/live.go` omitted `company_info` from the
Go live gateway's route allowlist even though the CLI and Python worker
supported that operation. Consequently, the gateway refused the request
before invoking the Python worker. The registered route has now been
enabled and tested with injected fake workers, one-call quota exhaustion,
and offline-mode rejection. The original failed probe contains **no
company frame**, so it cannot be imported; one new explicit profile
request is required on the registered workstation to obtain genuine data.

## 2026-10-17 original-byte validation correction

A subsequent real VCI ABR response returned one company_info row with
`listing_date` and attributes `fundamental.company.info` / `vci`.
The frame was saved successfully, but `ImportCompanyInfo` rejected it as
"company profile differs from vendor bytes". Root cause: importer
constructed a **synthetic JSON probe using json.Marshal** as its second
validation pass. json.Marshal normalizes the whitespace in the already
pretty-printed `json.RawMessage`; source SHA-256 hashes by raw bytes,
therefore the incorrect round trip changed the digest despite identical
provider data. It also redundantly pretended to authenticate another probe.

The importer now compares the original raw bytes against the original
SHA-256 and validates the original frame's ticker and reported date
without JSON re-encoding. Regression tests exercise the exact
`json.MarshalIndent` archive format, the previous digest mismatch,
transactional storage, corrupted digests, symbol mismatches and date
forgery. **No repeat VCI request is required** to import the retained
`docs/probe/company/20261017T014949.191191700Z/2026-10-17.json`
report. From the repo root:

```bash
export VNPIPE_DISABLE_LIVE=1
go -C go run -mod=mod -tags postgres ./cmd/vnpipe import-company-info \
  --probe "../docs/probe/company/20261017T014949.191191700Z/2026-10-17.json"
```

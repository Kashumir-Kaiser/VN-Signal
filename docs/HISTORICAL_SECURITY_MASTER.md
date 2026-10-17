# Phase 1 historical securities master — observed-only contract

This is a **data-layer extension**, not Phase 2 feature construction or
Phase 3 backtesting. It does not train models, modify an investable portfolio,
or enable a historical backfill of unverified delisted symbols.

## Why

The 2026-10-16 registered vnstock listing frame contained **1,754** symbols.
The original active importer inserted **1,519** HOSE/HNX/UPCOM symbols and
left **235** `DELISTED`-category symbols solely in immutable raw bytes.
Those are genuine current *provider observations*, not proof of when each
security originally traded, delisted or moved between exchanges.

## What is now preserved

Migration 008 introduces:

- `core.security_master`: stable **ticker-code key only**, first and last
  provider *observation* timestamps. These are NOT first/last trading dates.
  Ticker changes, company renames, and reuse are not automatically merged
  as a single legal security.
- `core.security_observations`: one row per symbol per archived source
  landing, preserving provider category, exchange when explicitly reported,
  names, ICB code, raw landing ID and source row index.
- `core.security_observed_days`: an exact-observation-date projection.
  Conflicting same-day provider reports are surfaced; gaps remain unknown.

The observed `DELISTED` category becomes
`PROVIDER_DELISTED_UNDATED`, with `exchange=NULL`. **No** IPO date,
delisting effective date, prior exchange, initial trading date, suspension
interval, or past investment eligibility is inferred.

## Provenance and consistency

`vnpipe rebuild-security-master` replays archived `raw.landings`
where route=`equity_list` and source=`vci` (no new vnstock calls).
For each landing, it verifies exact payload bytes against recorded SHA-256,
revalidates the *complete* source-frame schema including three active
venues, and cross-checks every currently listed symbol, exchange and
industry against the separately imported dated
`core.listing_snapshots` before projecting **any** row. One failed frame
rolls back its own transaction. Duplicate replays are idempotent, and `already_present` counts all independently validated existing source rows. A replay checks every canonical row field against its original archived source, refusing differences in security identity, exchange, classification, company name, industry or observation date instead of masking changes behind `ON CONFLICT DO NOTHING`.
New imports via `vnpipe import-listings` apply the same projection in
the original importer transaction, with a shared advisory lock.

```bash
export VNPIPE_DISABLE_LIVE=1
go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations
go -C go run -mod=mod -tags postgres ./cmd/vnpipe rebuild-security-master
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f sql/diagnostics/security_master.sql
```

This must not change the 12/6/1501 prior OHLCV job counters or the
`ops.api_reservations` ledger.

## Phase boundaries and missing evidence

- **Phase 1:** observed securities registry, dated source snapshot history
  and lifecycle-evidence infrastructure. No fabricated historical states.
- **Phase 2:** effective-dated/PIT investable-universe joins, features and
  gaps; absolutely no interpolation of today's surviving tickers into 2018.
- **Phase 3:** walk-forward training/backtests, enforcing PIT membership and
  explicit survivorship caveat/haircut from §4.2 and §9 of the master prompt.
- **Phase 4–6:** recommendations, desktop exporter/UI and scheduling; none
  enabled by this work.

The master prompt expressly accepts a known survivorship bias while
building forward dated listing snapshots, so collecting all current
`DELISTED` observations improves coverage **without contradicting its
phase exit policy**.

### Remaining acquisition gap

The vnstock v5 `Reference().equity.list_by_exchange()` feed reports
current venue and provider category, not historical admissions, exchange
transfers, initial trading dates and delisting event dates. The documented
company `listing_date` is not necessarily first-ever public trading.
The offline importer does **not** invoke unprobed `Reference().company()`
in the free tier. Historical notices need source-specific verified
acquisition and an explicit Phase-0 capability/quota check before any
new account-metered route is enabled. Relevant already-built
`core.security_lifecycle_evidence` remains empty until actual verified
notices are acquired; metadata cannot be conjured from OHLCV zeros.

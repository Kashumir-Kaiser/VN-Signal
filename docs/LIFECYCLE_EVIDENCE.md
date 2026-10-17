# Historical listing and trading eligibility (Phase 1 correction)

The previous `NO_TRADE` interpretation was **not justified**. VCI daily OHLCV
returns a zero-volume observation even when the security's historical market
eligibility is not known. Current listing membership from 2026-10-16 proves
nothing about tradability in 2018, and `core.symbols.first_seen_at` is the
database observation time, **not** the initial trading date.

## Different market dates

A company's establishment, equity issuance/IPO, date first publicly traded,
admission to its *current* exchange, exchange transfers, suspended dates,
delisting and relisting are different events. A single profile
`Reference().company(symbol).info().listing_date` is useful metadata but
does **not** guarantee the first-ever public trading date after transfers.
For example, HNX states ABT transferred from HOSE to HNX on 2021-04-01:
https://hnx.vn/vi-vn/chi-tiet-tin-60011286-0.html

Vnstock v5 company profiles provide a `listing_date`:
https://vnstocks.com/docs/vnstock/tham-chieu-reference

HNX first-trading notices distinguish **newly registered shares** from
**additional shares**:
https://www.hnx.vn/en-gb/co-phieu.html

## New contract (migration 007)

`ops.bar_quality_issues.category='ZERO_VOLUME_UNVERIFIED'` is exclusively
a provider measurement: volume = 0. It does not assert the security was
eligible to trade, not suspended, or even publicly listed on the date.
Migration 007 converts every old `NO_TRADE` observation, preserving the
unchanged original vendor bytes and the original ingestion job states.

`core.security_lifecycle_evidence` is an append-only provenance-backed
place to record independently verified official lifecycle observations.
Each record requires the original archived source landing, official URL,
source-document date, market, exact date or date interval, and evidence type.
It has **no fabricated initial data**. Only an independently verified
*first-ever* public trading notice (not just the current exchange's first
trading notice, listing date, or IPO date) can support
`BEFORE_FIRST_PUBLIC_TRADE`.

`ops.zero_volume_lifecycle_status` derives an interpreted status from
these explicit sources. Absent evidence it returns
`LISTING_STATUS_UNVERIFIED`; overlapping incompatible evidence returns
`CONFLICTING_EVIDENCE` rather than silently choosing a status.
`VERIFIED_ELIGIBLE_NO_MATCH` requires a proved tradable interval.
Suspensions and delistings require documented intervals as well.

The view is a **retrospective** metadata interpretation. Training and
historical universe membership require separate point-in-time
availability/effectiveness checks and must never reconstruct the investable
universe by projecting the 2026-10-16 active symbol list backwards.

### Offline check

```bash
export VNPIPE_DISABLE_LIVE=1
go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f sql/diagnostics/lifecycle_status.sql
```

Expected immediately after migration on your data: all 1,392 legacy zeros
appear as `LISTING_STATUS_UNVERIFIED`, pending independently verified lifecycle
evidence. No new vendor call or rebackfill is needed.

## Remaining work before a point-in-time ML-ready universe

Build and meter a dedicated verified company/market-lifecycle acquisition
path through the existing quota gateway (not an unmetered direct vnstock loop).
Collect official initial admission, exchange moves, suspension/return,
delisting/relisting, with dated primary-source documentation and raw hashes.
Only then populate the evidence table, derive intervals, and demonstrate
point-in-time universe membership and gap handling. Don't claim that
`FIRST_EVER_PUBLIC_TRADE` is proven by the earliest OHLCV record or
`company.info().listing_date` alone.

No positive-volume OHLC values, historic completed/partial jobs, quota
reservations or serving snapshots are changed by this correction.

# Historical OHLCV: exchange rules, source representation, and diagnosis

Updated 2026-10-17 after the registered-machine VCI backfill returned
six independent inconsistent-candle exceptions across ten more attempted
histories (four committed; six quarantined). This is **not** evidence that
Vietnamese exchanges permit contradictory OHLC values.

## Confirmed facts, with primary/reference sources

- HOSE, HNX and UPCoM have different reference-price and price-band regimes.
  Normal share bands are HOSE 7%, HNX 10%, UPCoM 15%; initial/resumption
  sessions and corporate actions have exceptions. These rules apply to
  actual market trading and unadjusted reference prices, **not** mechanically
  to backward-adjusted OHLCV comparisons.
  - https://www.ssi.com.vn/en/individual-customer/transaction-regulation-on-hsx
  - https://support.vndirect.com.vn/hc/en-us/articles/360002241873-Trading-regulations-at-HNX-Hanoi-Stock-Exchange
- Opening/closing auctions, continuous matching and put-through trading are
  distinct trade mechanisms. Feed field definitions must be checked before
  treating auction/negotiated prices as identical to continuous-session highs.
  - https://www.ssi.com.vn/en/individual-customer/transaction-regulation-on-hsx
- vnstock v5 `Market().equity(...).ohlcv(...,source="vci")` returns daily
  timestamps at 07:00 Vietnam time, prices in **thousands of VND**, and
  prices adjusted for corporate actions. The `floating` argument defaults
  to two decimal places; `floating=None` retains source precision.
  - https://www.vnstocks.com/docs/vnstock/thi-truong-market
- VCI and KBS can disagree slightly on their historical adjustment basis.
  Avoid mixing sources as though they are identical.
  - https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources
  - https://vnstocks.com/docs/vnstock/chuyen-doi/tu-vnstock-data-3x

## What the current failures actually establish

Each exception identifies a row failing `high >= max(open,close)` or
`low <= min(open,close)`. Those inequalities remain necessary for
conventional consistent-basis OHLC bars, regardless of Vietnamese price bands
or daily tick size. A *uniform* positive adjustment factor and monotone
rounding cannot reverse these inequalities. The failures could represent
source-specific field definitions, inconsistent adjustments, or bad source
rows; the logs alone cannot distinguish them. Do **not** declare a tolerance
of one exchange tick: old adjusted prices are not on today's exchange tick grid.

The current pipeline's granularity is wrong for 8 years of history: one
suspect daily observation quarantines the entire symbol. That is an operational
and data-coverage defect separate from whether the individual bar is valid.
A clean future fix must preserve raw data, isolate **individual** suspect
sessions, never silently rewrite highs/lows, preserve holes as missing data,
and record partial coverage with explicit non-production-quality status.

## No-quota evidence collection

The six newly blocked frames are already archived with exact bytes and
SHA-256 under `raw.landings.route='equity_ohlcv_quarantine'`. A32 and ABC
were blocked before this archive path existed and may have no raw frame.

Run on the registered machine from repo root:

```bash
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f sql/diagnostics/ohlcv_quarantine.sql
```

The diagnostic prints which blocked jobs have archived data, **every
problematic bar** up to 250, bar values, source row index, date, number of
affected rows per frame, and difference in 1,000 VND and basis points.
No live calls, database writes, quota reservations, or data cleaning occur.

Only after reviewing the observed absolute and percentage deviations should
we choose whether this is a tiny source representation issue or a material
discrepancy needing alternate-source comparison. Do not re-fetch the same
blocked symbols blindly. Existing completed jobs and blocked states remain
unchanged.


## Resuming OHLCV safely after 2026-10-17 quality review

Twelve histories were completed and six more partially accepted. Across
the six partial histories, 16 invalid traded bars were quarantined from
the canonical trade set while other valid sessions were retained. The
1,392 reported zero-volume source sessions have separate quality evidence.
No artificial prices, inferred tradability, or synthetic OHLC fixes are used.

A32 and ABC were earlier failed InvalidFrame histories requeued as
PENDING after original failed frames were not retained. Their archived
payload cannot be reconstructed offline. The verified universe loader
now defers **any already attempted PENDING InvalidFrame** by default,
without changing state, deleting rows, or reserving quota. The read-only
backfill-status includes `deferred_invalid_frame`. Retrying explicitly
requires `backfill --retry-legacy-invalid`.

`backfill --max-calls N` limits per-run metered calls after the verified
account quota budget; the default is 20. The deferred plan includes the
remaining unattempted jobs. Preserve the original requested history
range (2018-10-01 to 2026-10-16), or a different range creates distinct
jobs and can use fresh quota again. Existing 12 user-excluded tickers
remain excluded from per-symbol live calls.

Run locally with a fresh active equity_ohlcv probe report (one metered
call) and an explicit bounded backfill (up to 20 additional calls).
```bash
git pull --ff-only origin main
export VNPIPE_PYTHON="$(cygpath -aw "$PWD/.venv/Scripts/python.exe")"
unset VNPIPE_DISABLE_LIVE
go -C go run -mod=mod -tags postgres ./cmd/vnpipe probe --active --routes equity_ohlcv --trading-days 10 --out ../docs/probe/resume
go -C go run -mod=mod -tags postgres ./cmd/vnpipe backfill --active --probe ../docs/probe/resume/2026-10-17.json --from 2018-10-01 --to 2026-10-16 --days 10 --source vci --max-calls 20
go -C go run -mod=mod -tags postgres ./cmd/vnpipe backfill-status --from 2018-10-01 --to 2026-10-16
```
Check the real quota-month trading-day count before the active run. This
does not establish Phase-1 completion.

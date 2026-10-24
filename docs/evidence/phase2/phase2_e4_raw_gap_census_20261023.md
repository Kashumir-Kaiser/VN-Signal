# E4 raw landing and listing snapshot census — 2026-10-23

**Status: E4 remains open.** This read-only audit reviewed the 219 continuity
gaps (1,539 effective sessions) in the corrected 2026-10-22 E4 report against
the disposable report clone and checked-in Phase 1 evidence. No database rows
or feature classifications were changed.

## Results

The raw OHLCV payload census was bounded by gap year and exact ticker lists;
the expensive feature-window derivation was not rerun. Candidate raw payloads
were limited to `equity_ohlcv` and `equity_ohlcv_quarantine`, and their row
dates were matched to the missing effective sessions in
`core.effective_trading_sessions`.

| Gap year | Gap intervals | Exact raw OHLCV sessions | Raw row hits | Result |
| --- | ---: | ---: | ---: | --- |
| 2018 | 3 | 0 | 0 | No exact raw match |
| 2019 | 25 | 0 | 0 | No exact raw match |
| 2020 | 29 | 6 | 12 | Six VCI zero-volume observations; two landing versions per date |
| 2021 | 48 | 0 | 0 | No exact raw match |
| 2022 | 20 | 0 | 0 | No exact raw match |
| 2023 | 27 | 0 | 0 | No exact raw match |
| 2024 | 30 | 0 | 0 | No exact raw match |
| 2025 | 23 | 0 | 0 | No exact raw match after splitting the year into five-symbol bounded chunks |
| 2026 | 14 | 0 | 0 | No exact raw match after splitting the year into five-symbol bounded chunks |
| **Total** | **219** | **6** | **12** | **No valid traded-bar correction established** |

All six exact 2020 observations have `volume=0` and flat OHLC values. They do
not establish trades, suspension, or a safe feature-continuity repair. Each
was duplicated in two VCI landing payloads:

| Ticker | Date | Flat OHLC | Landing IDs and payload SHA-256 |
| --- | --- | --- | --- |
| DBT | 2020-10-20 | 10.77 | `2026` / `09e02f37eeadfe6457cdbf46e8b21d1ea366b360b9416d5ceb89eb1662747833`; `2570` / `8a757e63c2c520f61827fa779728abeff6d3030f7aed95f7ee987dc80b610ee9` |
| HTT | 2020-06-18, 2020-06-19 | 0.69 | `2876` / `9760d31528d87bb88aed68eb68003e89070c1d0c6d8efc3fac00a0196fb66eb9`; `3854` / `3844de99fff531bec18fa80aedf676ada2eb496926c43fe240b24bc36792fff6` |
| LMH | 2020-06-19 | 0.73 | `2996` / `db11f4d24a85268d799b778c7651cb4b72bfe92b8d9a26071e6ecf0cac2d3e9c`; `3974` / `48fa20bab8a339eca22acc3ed0d7227bc490fc195357479d4199e4513791f413` |
| MVB | 2020-10-19, 2020-10-20 | 12.24 | `3069` / `0c34a3f108197c725eff275572b8a94c338beff77d4af5c2ccb5dc2b5f7e1926`; `4047` / `55de7c30be6ccfbe2ec542277683814af7992cfc7328d657188e26ccf51d3a97` |

The clone contains 4,557 listing snapshot rows on only 2026-10-16, 2026-10-17,
and 2026-10-19. The primary key `(snapshot_date, symbol_id)` supports exact-date
lookups, but there are no historical snapshots for any E4 gap date. Therefore
the snapshot table cannot establish historical listing membership or a
suspension for these intervals.

## Source-backed transfer window

Thirteen 2021 intervals match the HNX-to-HOSE handover cohort: ABT, BSI, DXS,
HAP, KHG, LAF, NSC, PAN, QBS, SSC, TVB, VFG, and VND. The corrected E4 CSV
shows 12 intervals with three missing effective sessions each (2021-08-30
through 2021-09-01), and PAN with four sessions (one additional session before
its 2021-09-07 next feature row). The [official HNX notice](https://www.hnx.vn/vi-vn/chi-tiet-su-kien-60012723-0-hnx.html?_page=1)
records 2021-08-27 as the last HNX trading day for its 16-symbol cohort,
including these 13. The
checked-in Phase 1 report also records audited VNDIRECT/DNSE range requests and
CafeF history responses with no bars for the 39 Aug. 30–Sep. 1 ticker/date
pairs. Including PAN's additional 2021-09-06 session, these 13 intervals span
40 missing effective sessions in total.

These 39 dates are a strong transfer-window explanation candidate, not a
suspension classification or a database correction. The archived evidence
does not provide a source-keyed first-HOSE-trading-date record for every one
of the 13 tickers, and PAN's additional 2021-09-06 session remains unexplained.
No corresponding raw OHLCV payload row exists for the 39 dates in the report
clone.

## Counts and disposition

- **0** gaps have a confirmed valid traded-bar correction.
- **39** sessions in the shared Aug. 30–Sep. 1 window have source/archive
  evidence consistent with a venue transfer window; they remain candidates
  until per-ticker first-HOSE dates are recorded. This includes 12 fully
  aligned intervals and three of PAN's four missing sessions. PAN's additional
  2021-09-06 gap makes 40 transfer-context candidate sessions in total.
- **6** sessions have exact VCI raw rows, all zero-volume and flat-price; none
  is treated as a traded bar or a suspension determination.
- **1,494** sessions have neither an exact raw OHLCV row nor the 2021 transfer
  evidence above.
- Consequently, the original E4 result remains **219 unresolved gaps / 1,539
  expected sessions**. No gap is newly reclassified as a suspension.

## Reproduction references

- Baseline gap derivation and curated bar/source/lifecycle checks:
  [`phase2_integrity_gap_attribution_20261022.sql`](phase2_integrity_gap_attribution_20261022.sql)
  and [`phase2_integrity_gap_attribution_20261022.csv`](phase2_integrity_gap_attribution_20261022.csv).
- Corrected identifier-domain findings and lifecycle limits:
  [`phase2_e4_id_domain_correction_20261022.md`](phase2_e4_id_domain_correction_20261022.md).
- Phase 1 transfer notice, 13-symbol list, audited provider range requests,
  and archived CafeF replies:
  [`BUILD_STATUS.md`](../../BUILD_STATUS.md) and
  [`BSI-20210830-20210901.json`](../../probe/phase1-cafef-gap/BSI-20210830-20210901.json)
  (the other per-symbol responses are in the same folder).
- The report clone was queried in `BEGIN READ ONLY` transactions. Each raw
  payload chunk used a 60-second statement limit; the 2025 and 2026 chunks were
  split to at most five tickers after a larger 2025 chunk timed out. The 2020
  landing-detail check used landing IDs and matched exact ticker/date rows.

## Next concrete step

Resolve only the 2021 transfer subset by archiving HOSE's first-trading-day
notice for each of the 13 tickers (and a separate explanation for PAN's extra
session), then record the source landing/document key and event dates. For the
other intervals, request or locate source-keyed vendor/exchange evidence for
the exact ticker/date pairs; current raw coverage and listing snapshots do
not support a broader resolution.

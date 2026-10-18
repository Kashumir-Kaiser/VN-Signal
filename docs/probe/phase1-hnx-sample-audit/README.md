# Targeted HNX report sample for unresolved VCI zero-volume dates

Retrieved 2026-10-19. This is a bounded exact-date validation: one
deterministic median unresolved date per each of the 16 partial-history
symbols. The sample excluded dates with positive VNDIRECT/DNSE matched volume,
CafeF matched or negotiated activity, or an already archived exact HNX
no-match report. It is not a bulk history request or a representative sample
of all remaining dates.

## Result

All 16 official HNX report requests returned HTTP 200 and exactly one row for
the requested symbol/date. Every row reports zero total matched shares and
zero matched value. Ten rows also show buy or sell orders; an order is not an
execution. Six rows show no orders and zero matches.

| Symbol | HNX date | Buy orders | Sell orders | Matched shares | Matched value (VND) |
| --- | --- | ---: | ---: | ---: | ---: |
| CDG | 2022-08-15 | 6 | 0 | 0 | 0 |
| GGG | 2021-08-31 | 0 | 0 | 0 | 0 |
| HPI | 2022-07-08 | 7 | 1 | 0 | 0 |
| NAS | 2021-11-23 | 3 | 9 | 0 | 0 |
| SBD | 2021-08-04 | 3 | 1 | 0 | 0 |
| SDD | 2019-11-18 | 0 | 0 | 0 | 0 |
| SHC | 2022-10-05 | 4 | 4 | 0 | 0 |
| SNC | 2023-01-19 | 0 | 0 | 0 | 0 |
| SPC | 2020-12-08 | 0 | 4 | 0 | 0 |
| SVG | 2020-07-01 | 0 | 0 | 0 | 0 |
| TNB | 2022-04-08 | 8 | 8 | 0 | 0 |
| VFC | 2021-09-20 | 9 | 9 | 0 | 0 |
| VNI | 2021-12-14 | 0 | 0 | 0 | 0 |
| VNX | 2023-03-30 | 6 | 0 | 0 | 0 |
| XMC | 2020-03-13 | 3 | 5 | 0 | 0 |
| XPH | 2022-12-20 | 0 | 0 | 0 | 0 |

The queries used the HNX UPCoM daily report's exact-symbol filter:
`DD/MM/YYYY|0|0|'SYMBOL'|-1|DD/MM/YYYY|`. SPC was still on UPCoM on its
sample date in 2020; its later transfer to HNX does not change the historical
report route.

## Database effect

The 16 exact HTML responses and their parsed summaries were imported through
the append-only `raw.landings` and `ops.exchange_daily_bar_evidence` path. The
existing exchange-evidence count moved from 3 to 19. A read-only check of the
Phase 1 decision rules returns `VERIFIED_ELIGIBLE_NO_MATCH` for all 16 pairs:
each has one zero-volume HNX report, no positive alternate bar, and no dated
lifecycle interval or first-ever-trade record that conflicts with the report.
No canonical OHLCV bars, VCI quality issues, or manual lifecycle events were
changed. The 14,333 unresolved zero-volume issue dates therefore fall to
14,317; the 106 CafeF negotiated-only dates remain a separate activity group.

These results resolve only the 16 sampled sessions. Zero or absent rows from
other providers and an empty HNX response still do not prove no trade.

## Reproducibility and evidence

- `fetch_sample.py` chooses the sample from the archived row-level audit,
  makes one exact-date request per symbol with a one-second gap, and refuses to
  overwrite an existing archive.
- `raw/` contains the exact 16 HNX HTML response bodies.
- `sample-results.csv` contains each request filter, HTTP status, row count,
  parsed orders, matched totals, source URL, and raw SHA-256. Its SHA-256 is
  `849837642DEA0A811F0F9252B80F0CE47B0E4E576D234A77FDEE62DA77B99AD8`.
- `build_import.py` validates the archived bytes and builds
  `sample-evidence-import.csv`, including the exact payload bytes in Base64.
  The import CSV SHA-256 is
  `4FE2C96F6212E7C575C209214F85B8CA410D85932A301B45CE826F16128964CD`.
- `import_hnx_sample_evidence.sql` verifies all 16 hashes and zero matched
  totals before appending the reports to PostgreSQL.

Source: [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM).

# BSC historical activity audit

Retrieved 2026-10-19 from BSC's public [Historical Data page](https://www.bsc.com.vn/en/historical-data/). The page labels its fields as matching transactions and negotiated transactions, with volume and value shown separately. It provides closing and opening price, reference price, ceiling, and floor, but no daily high or low.

## Range pull

The bounded pull covers the 16 symbols with VCI partial history from
2018-10-01 through 2026-10-16. It fetched 31,935 rows from 47 paginated BSC
responses. Each response is preserved under [`raw/`](raw/) and its date range,
page, HTTP status, and SHA-256 are in [`manifest.csv` (local evidence file `manifest.csv`; not published). The
row-preserving [`daily-activity.csv` (local evidence file `daily-activity.csv`; not published) includes BSC's
matched and negotiated volumes separately. Rerun
[`fetch_bsc_partial_histories.ps1`](fetch_bsc_partial_histories.ps1) to repeat
the bounded fetch and [`reconcile_bsc_audit.py`](reconcile_bsc_audit.py) to
rebuild the issue join and summaries.

The manifest SHA-256 is
`5C1CF0681AC1ACCF986113E17E4AF4C7A3B820D12746D4200FB757189034BBFB`; the
derived daily activity CSV SHA-256 is
`0EF44233949BD48B72FD0068BF3EC70A01C6EB0246CDDB702F9D5013397E904A`.

## Cross-checks against the HNX reports

- All 23 existing BSC/HNX controls match exactly: 16 HNX-confirmed zero-match
  dates, four matched-volume positives, and three negotiated-only VNX dates.
- One largest BSC negotiated-volume date per each of the 12 symbols with a
  negotiated-volume issue row was checked at HNX. All 12 values match exactly,
  including SPC on the HNX-listed route;
  the route-specific filter omits its trailing delimiter. The sample responses
  and hashes are under [`positive HNX checks`](../phase1-bsc-hnx-positive-audit/).
- The last positive BSC activity date in the range was checked at HNX for each
  of the 16 symbols. All 16 exact-date rows match the reported matched and
  negotiated volumes. The row-level comparison is
  [`latest-activity-reconciliation.csv` (local evidence file `latest-activity-reconciliation.csv`; not published),
  with archived HNX responses under
  [`latest-activity HNX checks`](../phase1-bsc-hnx-last-activity-audit/).

The BSC history shows two later negotiated-only dates than the prior
VNDIRECT matched-volume audit: CDG has 3,768 negotiated shares on 2025-05-15
(its latest matched date remains 2025-05-13), and VNX has 7,813 negotiated
shares on 2026-08-26 (its latest matched date remains 2026-07-28). HNX confirms
both exact-date negotiated totals. These are latest positive observations
reported by BSC through 2026-10-16; they do not certify that BSC could not have
missed a later trade.

## Coverage of the VCI zero-volume issue dates

The [`issue-coverage.csv` (local evidence file `issue-coverage.csv`; not published) join covers all 14,466 VCI
`ZERO_VOLUME_UNVERIFIED` issue dates. BSC has a row on every one:

| BSC report on issue date | Dates | Cross-source result |
| --- | ---: | --- |
| Positive matched volume | 24 | Every amount matches positive VNDIRECT or DNSE volume already in the audit. |
| Positive negotiated volume only | 109 | 106 amounts match CafeF exactly; the other three are the HNX-confirmed VNX dates above. |
| No activity reported by BSC | 14,333 | A zero row is not proof of no exchange activity. |

Thus this broad source pull adds independent confirmation and improves the
latest-activity record, but it adds no newly discovered activity date to the
current issue-date partition. It does not reduce the 14,314 activity dates
that remain unresolved after prior HNX checks. The per-symbol counts and
machine-readable totals are in [`symbol-summary.csv` (local evidence file `symbol-summary.csv`; not published) and
[`summary.json` (local evidence file `summary.json`; not published).

## Source anomalies and use

BSC reports 27,000 matched shares for XMC on 2019-06-27, one day before the
current HNX UPCoM profile's first date of 2019-06-28. XMC had an earlier HNX
listing history, so this is a venue-attribution anomaly rather than proof of
an impossible first-ever trade. Keep the row archived but exclude it from
UPCoM use until the market/venue history is resolved. See
[`source-anomalies.csv` (local evidence file `source-anomalies.csv`; not published) and the
[HNX XMC profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-xmc.html).

The BSC page's daily fields do not supply high/low, and I found no public
statement of bulk storage or internal ML-use rights. Keep the feed attributed
to BSC and source-specific. Do not construct OHLC bars from its partial price
fields, replace matched volume with negotiated volume, or treat its zero rows
as no-trade facts. No BSC values were imported into PostgreSQL or canonical
OHLCV bars.

Sources: [BSC Historical Data](https://www.bsc.com.vn/en/historical-data/),
[HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX listed-market report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html),
[HNX VNX profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-vnx.html),
[HNX XMC profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-xmc.html), and
[VSDC SPC market-transfer notice](https://vsdc.vn/vi/ad1/147409).

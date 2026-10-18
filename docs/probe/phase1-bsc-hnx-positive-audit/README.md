# BSC negotiated-volume checks against HNX

Retrieved 2026-10-19. For each of the 12 symbols with negotiated activity on
the VCI zero-volume issue dates, the sample selects the BSC date with the
largest reported negotiated volume and requests that exact symbol/date from
HNX. All 12 negotiated volumes match HNX exactly.

| Symbol | Date | BSC negotiated shares | HNX negotiated shares | HNX route |
| --- | --- | ---: | ---: | --- |
| CDG | 2019-11-28 | 55,000 | 55,000 | UPCoM |
| GGG | 2023-07-28 | 951,600 | 951,600 | UPCoM |
| HPI | 2024-01-15 | 1,333,300 | 1,333,300 | UPCoM |
| NAS | 2024-07-18 | 900,376 | 900,376 | UPCoM |
| SBD | 2026-02-27 | 461,100 | 461,100 | UPCoM |
| SNC | 2019-09-10 | 224,800 | 224,800 | UPCoM |
| SPC | 2023-06-06 | 75,000 | 75,000 | HNX-listed |
| TNB | 2020-02-21 | 552,000 | 552,000 | UPCoM |
| VFC | 2020-09-11 | 8,800 | 8,800 | UPCoM |
| VNI | 2019-08-23 | 3,300 | 3,300 | UPCoM |
| VNX | 2022-01-05 | 30,700 | 30,700 | UPCoM |
| XMC | 2020-06-10 | 14,890 | 14,890 | UPCoM |

SPC's securities registration transferred from UPCoM to HNX effective
2022-01-21, so the UPCoM request returned no row. The HNX-listed report
requires the route filter
`DD/MM/YYYY|0|0|'SPC'|0|DD/MM/YYYY` without a trailing delimiter. The corrected
request returned the 75,000-share negotiated entry. The first wrong-route
response and initial empty response are preserved alongside the corrected raw
response; the final correction results are in
[`spc-listed-route-filter-fixed.csv` (local evidence file `spc-listed-route-filter-fixed.csv`; not published).

[`sample-results.csv` (local evidence file `sample-results.csv`; not published) retains the 12 symbol/date choices,
the 11 UPCoM report responses, raw paths, values, and hashes.
[`fetch_sample.py`](fetch_sample.py) includes the corrected venue-specific
route, and [`fetch_spc_listed_route.py`](fetch_spc_listed_route.py) reproduces
the targeted SPC checks. No rows were imported into PostgreSQL or canonical
bars.

Sources: [BSC Historical Data](https://www.bsc.com.vn/en/historical-data/),
[HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX listed-market daily report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html), and
[VSDC SPC transfer notice](https://vsdc.vn/vi/ad1/147409).

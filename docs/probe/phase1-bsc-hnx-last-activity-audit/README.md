# HNX checks of latest BSC activity dates

Retrieved 2026-10-19. For each of the 16 symbols in the BSC partial-history
pull, the latest BSC row with positive matched or negotiated volume was
checked with an exact-date HNX request. All 16 HNX rows match BSC's matched
and negotiated volumes exactly.

| Symbol | Latest positive BSC date | Matched shares | Negotiated shares | HNX route |
| --- | --- | ---: | ---: | --- |
| CDG | 2025-05-15 | 0 | 3,768 | UPCoM |
| GGG | 2026-10-16 | 14,601 | 0 | UPCoM |
| HPI | 2026-10-15 | 500 | 0 | UPCoM |
| NAS | 2026-10-15 | 100 | 0 | UPCoM |
| SBD | 2026-10-16 | 604 | 0 | UPCoM |
| SDD | 2026-10-16 | 5,492 | 0 | UPCoM |
| SHC | 2026-10-14 | 401 | 0 | UPCoM |
| SNC | 2026-10-15 | 71 | 0 | UPCoM |
| SPC | 2026-10-15 | 400 | 0 | HNX-listed |
| SVG | 2026-10-13 | 100 | 0 | UPCoM |
| TNB | 2026-10-12 | 600 | 0 | UPCoM |
| VFC | 2026-07-03 | 1 | 0 | UPCoM |
| VNI | 2026-10-16 | 700 | 0 | UPCoM |
| VNX | 2026-08-26 | 0 | 7,813 | UPCoM |
| XMC | 2026-10-16 | 1,120 | 0 | UPCoM |
| XPH | 2026-10-15 | 100 | 0 | UPCoM |

For CDG, this adds exact exchange evidence that a negotiated transaction took
place on 2025-05-15 after its latest VNDIRECT matched-volume date
(2025-05-13). For VNX, HNX confirms 7,813 negotiated shares on 2026-08-26,
after its latest VNDIRECT matched-volume date (2026-07-28). The other 14 dates
match their latest positive VNDIRECT matched-volume observations.

These are the latest positive observations in BSC's archived history through
2026-10-16, and their exact-date activity is verified at HNX. They are not a
certificate that BSC did not miss a later trade on a subsequent zero row.
Matched and negotiated activity remain separate fields.

[`last-activity-results.csv` (local evidence file `last-activity-results.csv`; not published) records the 15 valid
UPCoM requests and the initial empty SPC result. The corrected SPC HNX-listed
request and exact result are in the sibling
[`SPC route follow-up` (local evidence file `../phase1-bsc-hnx-positive-audit/spc-listed-route-filter-fixed.csv`; not published).
[`fetch_last_activity.py`](fetch_last_activity.py) contains the corrected
route-specific filter. All raw response bytes and hashes are preserved in
[`raw/`](raw/); the combined cross-source comparison is
[`latest-activity-reconciliation.csv` (local evidence file `../phase1-bsc-history-audit/latest-activity-reconciliation.csv`; not published).

Sources: [BSC Historical Data](https://www.bsc.com.vn/en/historical-data/),
[HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX listed-market daily report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html), and
[VSDC SPC market-transfer notice](https://vsdc.vn/vi/ad1/147409).

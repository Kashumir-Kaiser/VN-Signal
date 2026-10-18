# HNX latest five-session matched-volume check

Retrieved 2026-10-19 from HNX's official daily trading reports. The check covers
the 16 tickers in the VCI partial-history audit for 2026-10-12 through
2026-10-16, the latest five sessions in the local historical window. It used
one selected-symbol UPCoM report per date for 15 symbols and the HNX-listed
report for SPC, which had transferred to HNX. All 80 expected ticker/session
rows were returned; 32 show positive total matched volume.

The latest positive date within this five-session window is:

| Symbol | Latest positive date | Matched shares |
| --- | --- | ---: |
| CDG | none in window | 0 |
| GGG | 2026-10-16 | 14,601 |
| HPI | 2026-10-15 | 500 |
| NAS | 2026-10-15 | 100 |
| SBD | 2026-10-16 | 604 |
| SDD | 2026-10-16 | 5,492 |
| SHC | 2026-10-14 | 401 |
| SNC | 2026-10-15 | 71 |
| SPC | 2026-10-15 | 400 |
| SVG | 2026-10-13 | 100 |
| TNB | 2026-10-12 | 600 |
| VFC | none in window | 0 |
| VNI | 2026-10-16 | 700 |
| VNX | none in window | 0 |
| XMC | 2026-10-16 | 1,120 |
| XPH | 2026-10-15 | 100 |

`latest-positive-in-window.csv` is strictly bounded to the five queried
sessions. For CDG, VFC, and VNX, “none in window” does not establish their
last-ever trading date. The earlier [`phase1-hnx-last-trade-audit`](../phase1-hnx-last-trade-audit/README.md)
confirms the latest positive VNDIRECT observations in the archived range for
all 16 tickers, but does not certify that every intervening HNX session had no
execution. No zero-volume VCI or alternate-provider price was promoted to a
traded bar, and no lifecycle status or database row was changed by this check.

`matched-volume.csv` records each HNX route, ticker/date, total matched volume
and value, request filter, response filename, and SHA-256. The adjacent HTML
files preserve the exact ten report responses. Total-market volume is used;
buy/sell order quantities are not counted as executions.

Sources: [HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX listed-market daily report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html),
[HNX UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html).

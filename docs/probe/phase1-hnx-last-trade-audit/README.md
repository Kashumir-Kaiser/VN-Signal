# HNX confirmation of latest positive VNDIRECT sessions

Retrieved 2026-10-18. This audit checks whether the latest positive-volume
VNDIRECT row in the local, source-specific ML-eligible view for each of the 16
VCI partial-history tickers corresponds to an exchange-recorded execution. The
source query required `is_traded AND v > 0` and grouped by ticker. It did not
change PostgreSQL.

The HNX daily report was queried once for each exact ticker/date. The official
web page's date picker is limited, but its POST endpoint accepted the exact
historical date filters used here. Fifteen records were checked through the
UPCoM report. SPC was checked through the HNX-listed report because VSDC says
its securities registration moved from UPCoM to HNX effective 2022-01-21, and
HNX lists its first HNX trading date as 2022-01-27. A no-row UPCoM response for
SPC in 2026 is therefore not a no-trade finding.

| Ticker | Latest positive VNDIRECT date | VNDIRECT shares | HNX market/report | HNX total matched shares |
| --- | --- | ---: | --- | ---: |
| CDG | 2025-05-13 | 100 | UPCoM | 100 |
| GGG | 2026-10-16 | 14,601 | UPCoM | 14,601 |
| HPI | 2026-10-15 | 500 | UPCoM | 500 |
| NAS | 2026-10-15 | 100 | UPCoM | 100 |
| SBD | 2026-10-16 | 604 | UPCoM | 604 |
| SDD | 2026-10-16 | 5,492 | UPCoM | 5,492 |
| SHC | 2026-10-14 | 401 | UPCoM | 401 |
| SNC | 2026-10-15 | 71 | UPCoM | 71 |
| SPC | 2026-10-15 | 400 | HNX-listed | 400 |
| SVG | 2026-10-13 | 100 | UPCoM | 100 |
| TNB | 2026-10-12 | 600 | UPCoM | 600 |
| VFC | 2026-07-03 | 1 | UPCoM | 1 |
| VNI | 2026-10-16 | 700 | UPCoM | 700 |
| VNX | 2026-07-28 | 100 | UPCoM | 100 |
| XMC | 2026-10-16 | 1,120 | UPCoM | 1,120 |
| XPH | 2026-10-15 | 100 | UPCoM | 100 |

All 16 HNX rows exist and match the VNDIRECT volume exactly. These are the
latest positive dates in the archived VNDIRECT histories through 2026-10-16,
with exchange confirmation of the execution on each date. This audit does not
claim that HNX individually checked every later zero-volume session. Read the
dates as source-backed latest positive observations, not a separate HNX
certificate that no trade occurred on any subsequent session.

The UPCoM POST filter is
`dd/MM/yyyy|0|0|'TICKER'|-1|dd/MM/yyyy|`. The HNX-listed market filter is
`dd/MM/yyyy|0|0|'TICKER'|0|dd/MM/yyyy`. In both returned tables, cell 17 (zero
based) is total-market matched volume and cell 18 is total-market value in
VND; order quantities are not counted as executions. The raw one-row responses
and their hashes are in `hnx-last-trade-reconciliation.csv` and the adjacent
HTML files.

The VNDIRECT source lineage for the 16 maximum positive rows is in
`latest-vndirect-source-lineage.csv`; `latest-vndirect-lineage.psql` contains
the read-only query used to obtain each landing ID, zero-based source row and
raw-payload SHA-256.

This is targeted validation, not a bulk HNX download or a database import.
HNX separately lists historical data and licensed data packages in its
[UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html)
and its [2026 information-service catalog and price schedule](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf).
Public endpoint access does not establish bulk-reuse rights.

Sources: [HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX listed-market daily report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html),
[VSDC SPC market-transfer notice](https://vsdc.vn/vi/ad1/147409),
[HNX SPC issuer profile](https://www.hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-ny-spc.html).

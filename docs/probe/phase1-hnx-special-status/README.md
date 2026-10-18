# HNX special-trading status check

Retrieved 2026-10-19 to interpret the HNX issuer-page status shown for CDG,
VFC, and VNX. The three exact issuer-page responses are archived in this
folder. Their SHA-256 values are recorded below.

| Symbol | HNX profile | Displayed trading status | SHA-256 |
| --- | --- | --- | --- |
| CDG | [HNX issuer profile](https://hnx.vn/vi-vn/ModuleIssuer/UC_Issuer/Details/CDG/UC) | Giao dịch đặc biệt | `3c66f0ef9bb58a909105c1e191703795e4ee4e714576a63977227e5d2120141d` |
| VFC | [HNX issuer profile](https://hnx.vn/cophieu-etfs/chi-tiet-chung-khoan-uc-VFC.html) | Giao dịch đặc biệt | `3b336967e5056068e02e46dc69dc9bc25777a933cbdd5028890531cfbe2d81bf` |
| VNX | [HNX issuer profile](https://hnx.vn/vi-vn/m-tim-kiem-VNX.html) | Giao dịch đặc biệt | `2f7ba27c108759f6f9347636a709055b7a5d99edab052657109a2ec5ae3016e8` |

VNX's legal register lists Decision 23/QĐ-HĐTV, the current UPCoM registration
and trading regulation, effective 2026-03-18. Annex III defines status code
`SNE` as a security with no round-lot trades for more than 25 consecutive
trading sessions. The searchable text of Article 15 also specifies special
handling when trading resumes after that interval. HNX currently renders the
status in Vietnamese as “Giao dịch đặc biệt.” Interpreting the HNX display as
the SNE no-round-lot state is supported by the rule and the exchange profile;
the profile does not expose the status-start date. SNE concerns round-lot
trading and is not, by itself, proof that no odd-lot execution occurred.

The HNX issuer pages' “price movement” endpoint returned 64 dated rows for
each symbol, covering 2026-07-16 through 2026-10-16. CDG and VFC had no
price-bearing row in this window. VNX had one, on 2026-07-28; the existing
exact-date HNX matched-volume report confirms 100 shares that day and no
price-bearing rows after it in the retrieved window. The five-session HNX
matched-volume audit in [`phase1-hnx-latest-week`](../phase1-hnx-latest-week/README.md)
also returned zero total matched volume for all three symbols on 2026-10-12
through 2026-10-16.

For VFC, eight exact-date HNX daily reports for the remaining sessions from
2026-07-06 through 2026-07-15 each returned a VFC row with zero total matched
volume. The prior HNX exact-date audit confirms one share matched on
2026-07-03. No later price-bearing row appears in HNX's 64-row profile history
through 2026-10-16. This is the latest execution/price evidence located for
VFC; the profile history is not an all-mode daily-volume ledger, so it does
not prove that no later odd-lot trade occurred.

For CDG, the prior exact-date HNX report confirms the latest positive
VNDIRECT observation found, 100 shares on 2025-05-13. Investing.com's public
history page also shows that date as its latest positive-price row in its
history window through 2026-05-17. However, neither source is an exchange
zero-volume audit for every intervening session. The current HNX status and
2026-07-16–2026-10-16 profile history support recent inactivity but do not
prove that 2025-05-13 was the last execution ever.

No daily bars were synthesized and no PostgreSQL rows or lifecycle statuses
were changed. The older zero-volume issue rows remain unresolved.

The six profile-history response pages and eight VFC daily reports are saved
beside this README. The profile history requests used market `UC`, pages 1–2,
and 50 records per page; each returned 64 dated rows. The VFC daily reports used
the public HNX UPCoM report with exact-date filter
`DD/MM/YYYY|0|0|'VFC'|-1|DD/MM/YYYY|`.

| Archived response | SHA-256 | Finding |
| --- | --- | --- |
| `CDG-price-history-page1.html` | `ee16383663cbabcbfeeedc4643844e595e4793c1088386a266fc1ea161de4fd7` | Rows 1–50 of 64; no price-bearing row |
| `CDG-price-history-page2.html` | `397b91d807e75bcbddd1deefad05b326d00b7fb0cbd2e48e2db08f0629b7120a` | Rows 51–64; no price-bearing row |
| `VFC-price-history-page1.html` | `25e18b21f180101e4bf48eb05021dbc6794ea80a54c3996f9462a2b37c4f9e82` | Rows 1–50 of 64; no price-bearing row |
| `VFC-price-history-page2.html` | `64010c3b1df41e4db74b7ddf7034e47ad5d6ff264cf3fb0e7f2dbe938867704e` | Rows 51–64; no price-bearing row |
| `VNX-price-history-page1.html` | `10a7c45053ae020a8c69d493da45d4d91896048a6ce8c8babbc18c18e5554b72` | Rows 1–50 of 64; no price-bearing row |
| `VNX-price-history-page2.html` | `dad4fb9be59180f833c5c22ea8d5bfb7b18c48b9a86ef9d066fea16b80d61d93` | Rows 51–64; only price-bearing row is 2026-07-28 |
| `VFC-2026-07-06-UPCoM.html` | `0c4658f73cc11b36e5ac6b980ea571bd7230021dcb79735245878d28fea95cd8` | HNX total matched volume 0 |
| `VFC-2026-07-07-UPCoM.html` | `693d546bc624f47749a11c53791e58094521e19317ea03f0dd92d2cbbdabddd9` | HNX total matched volume 0 |
| `VFC-2026-07-08-UPCoM.html` | `b0150da469ae6abea1ed5d8868361dbb03c49fcd073d71724d6e7e1bb32bbaf1` | HNX total matched volume 0 |
| `VFC-2026-07-09-UPCoM.html` | `190a221a3c5a0916050ddd2a2e348f2af9d1400a7bb8f05669caae9342e47b80` | HNX total matched volume 0 |
| `VFC-2026-07-10-UPCoM.html` | `ecd21045818c45ad7377f2bd6fa9cdbaeeba342d1c60a6f9b2f2deeb908204b7` | HNX total matched volume 0 |
| `VFC-2026-07-13-UPCoM.html` | `5a99a88e23830dcc0a39fce2e4e42e70b87bf66ace0b982926a79cab86e97fa2` | HNX total matched volume 0 |
| `VFC-2026-07-14-UPCoM.html` | `b79216de53991cbc3f672457e78d3ecd2af791ea9e33ba524cc4b140db018851` | HNX total matched volume 0 |
| `VFC-2026-07-15-UPCoM.html` | `be26bdff91829af0c58ceaee2dff1fcc4989107d5380fde946b3a0a3a645ec21` | HNX total matched volume 0 |

Sources: [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [official
VNX regulation PDF](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), and a [searchable transcription of Decision
23/QĐ-HĐTV (2026)](https://thuvienphapluat.vn/van-ban/Chung-khoan/Quyet-dinh-23-QD-HDTV-2026-Quy-che-Dang-ky-va-quan-ly-giao-dich-chung-khoan-chua-niem-yet-699113.aspx), [HNX UPCoM daily report](https://hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM), and [Investing.com CDG history](https://www.investing.com/equities/cau-duong-historical-data).

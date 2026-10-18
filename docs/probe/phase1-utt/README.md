# UTT public history check

Retrieved 2026-10-18. This check looked for a defensible last executed-trade date for UPCoM ticker UTT; it did not create or import price bars.

## Exchange lifecycle

HNX's [official first-trading notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2017102025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20Moi%20truong%20Do%20thi%20Thanh%20Tri%20UTT-60021665-1.html) says UTT's first UPCoM trading session was 2025-10-17. The exact HTML and its PostgreSQL evidence are recorded in `../phase1-lifecycle/UTT-first-trading-2025-10-17.html`.

## CafeF annual history response

The public [CafeF UTT history page](https://cafef.vn/du-lieu/lich-su-giao-dich-utt-1.chn) describes daily OHLC and matched/negotiated volumes. Its API was paged using:

```text
GET https://cafef.vn/du-lieu/Ajax/PageNew/DataHistory/PriceHistory.ashx
    ?ExchangeType=UPCOM&Symbol=UTT
    &StartDate=17%2F10%2F2025&EndDate=16%2F10%2F2026
    &PageSize=30&PageIndex=1..8
```

All eight response pages are retained here. They report `TotalCount=232` and contain 232 distinct dates, from 2025-10-20 through 2026-10-16. All returned rows have zero matched volume and zero negotiated volume; the reported price fields are flat at 9.2. No returned row establishes an executed trade or a valid trade OHLC bar.

The HNX calendar has 248 sessions in the requested interval. CafeF returned no row for these 16 sessions:

```text
2025-10-17
2026-01-29  2026-01-30
2026-02-02  2026-02-03  2026-02-04  2026-02-05  2026-02-06
2026-02-09  2026-02-10  2026-02-11  2026-02-12  2026-02-13
2026-02-23  2026-02-24  2026-02-25
```

Absence from the feed does not prove that there was no execution on each omitted session. CafeF's profile reports the first-session close as `0.0`; this is not accepted as a price. Singleton-date API probes returned inconsistent default-range/empty responses and were discarded, so they are not used to fill or classify the omitted dates.

| Response | SHA-256 |
| --- | --- |
| `cafef-UTT-20251017-20261016-page01.json` | `FF870B1AC29E92FF49B9C3149F31DD3F2248712CFFEF203C7806791F0CD51E86` |
| `cafef-UTT-20251017-20261016-page02.json` | `80529C5E516D93EF60155C6538B6BF07BB209E24AA1D7FADE3B1C0504074F333` |
| `cafef-UTT-20251017-20261016-page03.json` | `396D69EAB408DE60ED68572A3D33A577983299176FC9A436F57CD80B0091DC18` |
| `cafef-UTT-20251017-20261016-page04.json` | `31BBAAC9B080A89134E2A35DD35E6D321F72325A6704267F7517115EA5F62709` |
| `cafef-UTT-20251017-20261016-page05.json` | `B63F149A0C0344F712C5E0055188AC82DECFFB3BE61E4D59388821CE9069781B` |
| `cafef-UTT-20251017-20261016-page06.json` | `E642E46403E06BB0C172E6CD476D8538AAD6D4E5964216FABA18DC1791B67273` |
| `cafef-UTT-20251017-20261016-page07.json` | `21421C4B395FFA79C8F51FBACBA41FC0C2154C2C98888DAB365031F735CBF660` |
| `cafef-UTT-20251017-20261016-page08.json` | `BFE68D39BD97F32B556E74771185A3657AD30A2DE005E3F48FB1025FF51E910E` |

## VNDIRECT full-period volume response

The public VNDIRECT Finfo endpoint was queried with the correct volume fields (`nmVolume` and `ptVolume`), not a generic `volume` field:

```text
GET https://api-finfo.vndirect.com.vn/v4/stock_prices
    ?q=code:UTT~date:gte:2025-10-17~date:lte:2026-10-16
    &size=1000&page=1&sort=date:asc
    &fields=code,date,adOpen,adHigh,adLow,adClose,nmVolume,nmValue,ptVolume,ptValue
```

VNDIRECT returned 248 rows, one for each HNX session from first listing through 2026-10-16. Every row reports `nmVolume=0`, `ptVolume=0`, `nmValue=0`, and `ptValue=0`; every adjusted OHLC field is the flat 9.2 reference. A positive control for KAI on 2026-10-16, using the same endpoint and fields, returned `nmVolume=62,800` and `nmValue=711,900,000`, confirming that the response exposes volume when a trade is recorded. These reference-price rows are evidence of activity status only; they are not imported as OHLCV bars or used to validate adjustment basis.

| Response | SHA-256 |
| --- | --- |
| `vndirect-UTT-20251017-20261016.json` | `15836ABD3958078BB4807984E7F66A3BA0EEF9C46FEE19E8934E7B3392520570` |
| `vndirect-KAI-20261016-positive-control.json` | `591FFCEE602EC0B469547283DDEC8205BC4FA5DEBD9C88FB6CC030793759DAED` |

## HNX latest-session detail query

The official [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM) was queried for UTT on 2026-10-16. The POST filter was `16/10/2026|0|0|UTT|0|16/10/2026|`; the HNX response says `Tổng số 0 bản ghi` (zero records). The saved response is `hnx-UTT-2026-10-16.html`, SHA-256 `D1C3685F4F0B2CADC29CD9615F39C5309FA8CC095CC4036A16984EECDE6BDAFF`. This confirms no detailed UTT record for that session only; this date-specific report does not establish earlier trade history.

## Result

No executed UTT volume is reported by VNDIRECT for any of the 248 HNX sessions from 2025-10-17 through 2026-10-16. CafeF independently reports zero matched and negotiated volume for its 232 returned rows; HNX's latest-session detail report has no UTT record on 2026-10-16. The exact last executed-trade date is therefore not applicable to the audited period: no trade is recorded by these sources. Keep UTT out of ML OHLCV training, and do not make bars from flat 9.2 reference prices, zero-volume rows, or repeated closes.

## 2026-10-18 follow-up — HNX reports for CafeF's 16 omitted sessions

The official HNX daily report was queried directly for all 16 dates omitted by
CafeF, including UTT's first session on 2025-10-17. Unlike the page's limited
date picker, the report POST accepted each exact historical date. Each request
returned an explicit UTT row; total-market matched volume and value were zero
on all 16 dates. The first-session report shows 19 buy orders for 13,000
shares, no sell orders, and zero matched volume. Orders are not executions.

The exact dates, row-found flags, volumes, response filenames and SHA-256
hashes are recorded in `hnx-daily-reports/hnx-reconciliation.csv`; all 16 HTML
responses are archived beside it. The evidence closes the CafeF missing-date
question for those sessions. It does not turn UTT's flat reference prices into
bars, and it does not constitute an HNX report audit of the other 232
sessions. Across the two full-period vendor histories, no positive UTT volume
is reported through 2026-10-16, so there is no observed last-trade date in
that interval; an exchange-wide claim for every session would require an
all-session HNX source.

## 2026-10-19 follow-up — KBS and public history-page check

The registered vnstock KBS OHLCV route was requested from UTT's official first
session (2025-10-17) through 2026-10-16 with `raw_prices=true`. It returned
zero rows. The compact one-call report is
`2026-10-18-UTT-185217.232605400Z.json`, SHA-256
`8E4E118F42D0E59C396B0DFA80BFF7FB77C97C4BFE39C89C348B6185EEBE7B48`.

The [public Simplize UTT history page](https://simplize.vn/co-phieu/UTT/lich-su-gia)
also offers an Excel export control and displays blank OHLC with zero volume
on its recent rows. It explicitly labels its prices as adjusted for dividends
and splits, and the displayed volume is not split into matched and negotiated
activity. This is a targeted corroboration only; its recent zeros do not
certify every historical session, and its adjusted prices are not used to
construct UTT bars.

KBS adds an independent provider with no OHLCV rows. Combined with the prior
CafeF, VNDirect and targeted HNX evidence, this continues to support excluding
UTT from trade-bar training. No full-period, every-session HNX no-trade claim
is made, and no flat 9.2 reference-price bar is synthesized.

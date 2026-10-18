# Phase 1 alternative-source search

Research performed 2026-10-19 to find usable independent evidence for the
remaining UPCoM zero-volume dates in the 16-symbol partial-history audit. This
search used public documentation and targeted public pages; it did not import
market data into PostgreSQL or change canonical bars.

## Source findings

| Source | What its documentation/data can provide | Access and current disposition |
| --- | --- | --- |
| CafeF | Public annual history exports with OHLC, matched volume and negotiated volume. The 16-symbol audit contains 31,381 rows in 144 hash-verified workbooks. | Usable now as separate source evidence. Its zero rows are not a no-trade certificate: HNX confirms 100 CDG shares on 2025-05-13 and one VFC share on 2026-07-03 where CafeF reports zero. See [`CafeF audit`](../phase1-cafef-history-audit/README.md) and [`HNX latest-positive audit`](../phase1-hnx-last-trade-audit/README.md). |
| KBS via the registered vnstock Community route | Daily OHLCV history, including UPCoM symbols. Official vnstock docs list KBS as an available equity OHLCV source. | Four one-call, raw-price-request probes confirm CDG's 100-share 2025-05-13 session and NAS's 80-share 2020-10-15 session, but KBS misses the HNX-confirmed VFC one-share 2026-07-03 execution and returns no UTT rows. Keep its price history separate; `raw_prices=true` did not establish the price adjustment vintage. See [`KBS probes`](../phase1-kbs-issue-probes-20261019/README.md). |
| HNX | Official exact-date reports expose matched and negotiated activity separately. Exact-date checks have already confirmed selected executions and no-match sessions. | Use for targeted validation. HNX lists historical UPCoM data as an information product; do not bulk-query its public daily report to replace the licensed product. |
| BSC historical page | Public exact-date history shows closing/opening prices, matched volume/value, and negotiated volume/value. | A no-login page request returned seven exact HNX control dates. Four matched controls agree; the three VNX dates appear under negotiated volume and agree with HNX's `Thỏa thuận` column. Useful for targeted activity checks, but its page lacks high/low and bulk ML-use terms have not been established. No BSC prices or volumes were imported. Evidence: [`BSC controls` (local evidence file `bsc-controls-20261019.json`; not published). |
| Stockbiz / FireAnt | Public per-symbol historical lookup returns daily OHLC and one `Khối lượng` field; Stockbiz says prices and trading data come from FireAnt. | VNX (15,100 / 4,900 / 4,900) and CDG (100) match HNX on tested positive dates, but NAS (80), VFC (1), and SNC (71) all show zero where HNX confirms odd-lot matches. A zero cannot mean no trade, and the feed is not independent of FireAnt. Keep it to targeted corroboration only; no rows imported. [Stockbiz data method](https://stockbiz.vn/phuong-phap-du-lieu), [VNX 29 Jan](https://web.stockbiz.vn/Stocks/VNX/LookupQuote.aspx?Date=29%2F01%2F2026), [NAS 15 Oct](https://web.stockbiz.vn/Stocks/NAS/LookupQuote.aspx?Date=15%2F10%2F2020), [VFC 3 Jul](https://web.stockbiz.vn/Stocks/VFC/LookupQuote.aspx?Date=03%2F07%2F2026), [SNC 15 Oct](https://web.stockbiz.vn/Stocks/SNC/LookupQuote.aspx?Date=15%2F10%2F2026). |
| SHS archive | Public archive pages advertise separate matched and negotiated historical volume columns. | The legacy stock-history callback was reachable, but exact-date and broad-range requests returned empty callback content for VNX and HPG. No history rows were available to verify or import. [SHS history page](https://archive.shs.com.vn/HistoricalQuotesCompany.aspx?Symbol=VNX), [archive table](https://archive.shs.com.vn/IndicesStats.aspx). |
| FireAnt | Official Excel documentation exposes historical Open/High/Low/Close, `DealVolume` (matched volume), `PutthroughVolume` (negotiated volume), and `TotalVolume` by symbol/date range. | Strongest identified next independent feed if an authorized account is available. FireAnt documents OAuth2 for its REST API; the unauthenticated historical-quotes route returned HTTP 401. FireAnt's current membership information lists the Excel add-in under Premium. No authenticated FireAnt access was available in this work session. |
| FiinGroup | The per-stock UPCoM schema provides OHLC and adjusted-price fields. It defines `TotalMatchVolume` as round-lot matched, `TotalDealVolume` as negotiated round+odd-lot, and `TotalVolume` as matched+negotiated round+odd-lot. | `TotalVolume - TotalDealVolume` is an inferred all-lot matched-volume candidate from those published definitions; validate against HNX round-lot and odd-lot controls. Public docs do not establish backfill depth or internal ML rights. Use only through an authorized trial/license; no sample was fetched. |
| SSI FastConnect | Current official docs list HOSE/HNX/UPCOM daily OHLC with `Volume` defined as normal matched volume. `DailyStockPrice` exposes matched volume, negotiated volume, and total traded volume including odd lots. Daily history starts at each security's first trading date, with bulk historical file/ZIP delivery. | The current service overview says an existing SSI customer can create API keys online with no manual email approval and no current API fee. A separate Terms & Environments page still says registration requires approval, while the legacy FCData guide says credentials are issued through iBoard. Treat onboarding as a documentation conflict to resolve in the live portal. No SSI key is configured here, so there is no authenticated history sample yet. Bulk ML retention terms and odd-lot matched semantics still need confirmation. A separate SSI iData page advertises a free six-month trial with all historical EOD, but delivery is through AmiBroker and its account/export/ML terms are not stated publicly. |
| EODHD | Official exchange pages list Vietnam (`VN`) and 585 active instruments; its EOD API offers daily OHLCV. | Not a usable public backfill route in this search: requests require an API token; the shared demo covers only six unrelated sample instruments, and the free plan is limited to 20 calls/day and the past year. No EODHD account was available. |
| Investing.com / issuer pages | Individual issuer history pages can corroborate selected last-positive observations. | Use for targeted research only. [CDG history](https://www.investing.com/equities/cau-duong-historical-data) lists 2025-05-13 as its latest positive-volume row in the displayed range; HNX confirms that exact 100-share session. It does not resolve every intervening exchange session. |
| Simplize | Public UPCoM history pages expose OHLCV columns and an Excel-export control. The UTT page displays blank OHLC and zero volume on its recent rows. | Its page says prices are adjusted for dividends and splits and shows a single volume field; the adjustment vintage and matched-versus-negotiated meaning are not documented there. Use for targeted cross-checks, not canonical price or no-trade evidence. [UTT history](https://simplize.vn/co-phieu/UTT/lich-su-gia). |
| Yahoo Finance | Its official exchange list identifies Vietnam's `.VN` suffix for Ho Chi Minh City Stock Exchange. | Not a UPCoM history source; no UPCoM market suffix is listed. [Yahoo exchange list](https://help.yahoo.com/kb/SLN2352.html). |
| Kaggle TowardDataScience competition | `price_train.csv` is described as OHLCV for 30 Vietnamese tickers from 2021-01-04 through 2021-10-29; the page says the source package was `vnquant`. | The historical window is short and the universe is only 30 tickers. Files are subject to competition rules and require agreeing to them to download. It cannot cover the 16 UPCoM partial-history symbols as a full-universe source. No files were downloaded or imported. [Competition dataset](https://www.kaggle.com/competitions/stock-market-prediction/data). |
| Mendeley Data, “Unrewarded but Amplified” | 1.8 million daily close observations for 627 HOSE/HNX/UPCoM shares over 2014–2024, plus VN-Index closes and annual firm data. | `daily_prices.csv` contains only `ticker,date,close`; identifiers are anonymized (`VN001`, etc.) and no mapping is published. It is CC BY 4.0, but cannot currently join to the project universe or fill OHLCV/volume gaps. Treat as a possible close-only research lead only if a defensible symbol mapping and price basis are established. No files were downloaded or imported. [Dataset and description](https://data.mendeley.com/datasets/8584zp8rtr/1). |
| OpenStockAPI | Its public docs advertise Vietnam historical OHLCV and name TCBS/KBS/VCI in the normalized source flow. | It is a convenience API over the same provider families already checked, rather than an independent exchange feed. Community access requires its own login; no account or new data route was used. [Documentation](https://openstockapi.com/document). |
| `vn-market-data` open-source adapter | Its documented OHLCV fallback chain is DNSE and Vietcap; other modules use VNDirect and CafeF. | Those source families are already in the project’s evidence set. It adds useful cache/fallback implementation ideas, not a new underlying source or independent evidence. [Repository and source list](https://github.com/trangcm/vn-market-data). |
| TCBS / SSI historical APIs | Current TCBS and SSI official docs describe daily OHLCV with UPCoM coverage. | The installed vnstock v5 source table does not expose TCBS for equity OHLCV. A public-code legacy TCBS `apipubaws` request for CDG on the HNX-confirmed 2025-05-13 date returned HTTP 403 and no data. TCBS's current OpenAPI requires an API key exchanged for a JWT with OTP. SSI's current portal offers online API-key creation to existing SSI brokerage customers, but no SSI key is configured in this project; documented routes require bearer authorization. Neither has produced a new sample yet. [Current vnstock source table](https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources), [TCBS OHLCV docs](https://developers.tcbs.com.vn/docs/v1.0.0/stock/bars-long-term/), [TCBS OpenAPI](https://developers.tcbs.com.vn/), [SSI FastConnect](https://developers.ssi.com.vn/docs/faq/service-overview), [SSI data API specs](https://guide.ssi.com.vn/ssi-products/fastconnect-data/api-specs). |
| FINCO academic data export | Its guide advertises daily, full-history OHLCV for more than 1,600 HOSE/HNX/UPCoM companies. | The unauthenticated CDG profile API returned company metadata only; the documented stock-history export preview returned `Not authenticated`. Bulk download requires explicit Data Export Access approval. FINCO describes prices as retrospectively adjusted, and does not establish matched-versus-negotiated volume semantics or the underlying daily-price provider. Candidate after access, source-lineage, adjustment-vintage, and ML-use checks; no export was used. [FINCO guide](https://www.finco.vn/docs). |
| FinLens EOD API | Its published SDK documentation advertises historical daily OHLCV from 2007, an `adjusted=False` option, and volume in actual shares. | Requires a separate FinLens API key; the vnstock key does not authenticate this service. The raw-price option, source lineage, known-trade accuracy, and internal-use terms were not independently verified. Candidate for testing if authorized access is available. [FinLens SDK documentation](https://docs.finlens.vn/python-sdk). |
| DNSE OpenAPI | Official docs expose historical OHLCV and symbol/date-bounded historical executions. | Requires a separately registered DNSE API key. Its OHLCV is the same DNSE source family already archived locally, so it is not independent evidence; its trade-history endpoint may add detail if authorized access is available. [OHLC history](https://developers.dnse.com.vn/docs/dnse/get-ohlc-history/), [trade history](https://developers.dnse.com.vn/docs/dnse/get-history-trades/), [API registration overview](https://developers.dnse.com.vn/docs/guide/intro/api_platform/). |
| Lich Su Gia public history pages | The public site displays historical OHLCV pages for Vietnamese shares. | A targeted CDG request reports zero volume on 2025-05-13 while the official HNX report confirms 100 matched shares. The inspected page does not disclose its source. Exclude its zero/missing values from activity evidence. [CDG page, page 5](https://lichsugia.site/lich-su-giao-dich/CDG.html?page=5), [HNX sample evidence](../phase1-hnx-sample-audit/README.md). |
| Kaggle VN30 history | A third-party catalog describes 30 VN30 constituents with OHLCV from 2013-01-01 to 2023-06-30. | The Kaggle page did not expose the underlying files or license details in this check, and the 30-stock universe does not address the UPCoM gaps. Do not ingest until the actual files, license, and source basis are verified. [Kaggle dataset](https://www.kaggle.com/datasets/thangtranquang/stock-vn30-vietnam). |
| Kaggle Vietnam Stock Returns with Efficiency Scores (DEA) | Dataset metadata describes quarterly rows for 26 HOSE real-estate companies, 2019–2024, with financial ratios, technical indicators, efficiency scores, and next-quarter returns. | Metadata reports CC BY-SA 4.0 and a 46 KB archive. This is a prebuilt quarterly research sample, not daily OHLCV or a replacement for raw point-in-time inputs. It cannot close the UPCoM issue dates. The linked PLOS study confirms the 26-company HOSE real-estate scope and 2019–2024 period. [Kaggle dataset](https://www.kaggle.com/datasets/thaonguyentrang/vietnam-stock-returns-with-efficiency-scores-dea), [PLOS One paper](https://doi.org/10.1371/journal.pone.0332154). |

Official documentation: [FireAnt historical function overview](https://help.fireant.vn/fireant-excel/cac-ham-lay-du-lieu-giao-dich-qua-khu/fa-historical/tong-quan/), [FireAnt matched volume](https://help.fireant.vn/fireant-excel/cac-ham-lay-du-lieu-giao-dich-qua-khu/fa-historical/fa-historical-dealvolume/), [FireAnt negotiated volume](https://help.fireant.vn/fireant-excel/cac-ham-lay-du-lieu-giao-dich-qua-khu/fa-historical/fa-historical-putthroughvolume/), [FireAnt REST API authentication](https://api.fireant.vn/), [FireAnt membership plans](https://help.fireant.vn/fireant-membership/so-sanh-goi/), [HNX UPCoM data service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html), [FiinGroup UPCoM schema](https://datafeed.fiingroup.vn/api-giao-dich/co-phieu/co-phieu/upcom-stock-v2), [SSI history and access terms](https://developers.ssi.com.vn/docs/getting-started/terms-and-environments), and [EODHD historical API](https://eodhd.com/financial-apis/api-for-historical-data-and-volumes).

## 2026-10-19 follow-up

The KBS probe added a fourth provider confirmation for NAS's 80-share
2020-10-15 matched-volume session. That date was already covered by positive
CafeF, VNDirect and DNSE rows, so the 14,333 unresolved issue-date count did
not change. KBS also missed VFC's HNX-confirmed one-share 2026-07-03 trade;
this is direct evidence that a missing provider row cannot certify no trade.

For UTT, KBS returned no rows over the full first-listing-to-2026-10-16
request window. Simplize's public page shows recent blank-price, zero-volume
rows and labels prices as adjusted, which is useful context but does not
provide valid trade bars. UTT remains out of OHLCV training; do not synthesize
bars from its flat reference price.

Yahoo Finance covers `.VN` (HOSE) according to its own exchange table and
does not address these UPCoM gaps. The Internet search and probe outputs are
archived under [`KBS probes`](../phase1-kbs-issue-probes-20261019/README.md)
and [`UTT audit`](../phase1-utt/README.md).

## Result for Phase 1

The public CafeF data initially left 14,333 VCI zero-volume issue dates
without positive activity or exact HNX no-match evidence. The bounded
16-report sample described below reduces that current partition to 14,317.
Two HNX-confirmed executions missed by
CafeF demonstrate why its zero or absent rows cannot be used to classify
no-trade sessions. FireAnt is the best documented next provider for separate
matched and negotiated volume if an authorized account is already available;
otherwise the broad UPCoM options identified by this search are licensed HNX
or FiinGroup data. Keep every provider's OHLC and volume in its own lineage;
do not blend adjusted-price series until adjustment vintages are resolved.

No FireAnt, SSI, EODHD, FiinGroup, or bulk HNX data were accessed or imported.

## 2026-10-19: three VNX execution dates validated at HNX

A bounded public-history lookup surfaced VNX on 2026-01-29, 2026-01-30, and
2026-02-12 as candidate positive-volume dates. Exact-date requests to the
[official HNX UPCoM report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM)
report zero matched volume and 15,100, 4,900, and 4,900 negotiated shares,
respectively. Those dates
were absent from the prior VNDIRECT/DNSE positive rows and CafeF history, so
they reduce the unresolved activity-date partition from 14,317 to 14,314.
The three raw HNX responses were appended to the existing exchange-evidence
ledger; no OHLCV bars were changed. See
[`HNX verification and database record`](../phase1-simplize-history-audit/README.md).

Simplize's public history interface was used only to select the three dates.
Its [terms of use](https://simplize.vn/terms) describe its data as proprietary
and restrict copying or derivative products without written consent. No
Simplize values were imported or used for ML. A temporary local snapshot is
still untracked because the shell rejected its cleanup command; it must not be
committed.

## 2026-10-19 wider public-dataset and adapter search

The Kaggle competition data has genuine OHLCV fields, but covers only 30
tickers for roughly ten months in 2021 and is governed by competition rules.
It is too narrow to reconcile the project’s 16 UPCoM partial histories.

The Mendeley dataset is substantially broader by ticker count and time range,
but publishes only closing prices under anonymized identifiers. Its public
description does not provide a symbol crosswalk, volume, or OHLC. It cannot
be merged into the symbol-level bars or used to certify execution/no-trade
dates. The CC BY 4.0 license does permit attribution-based research use, so it
remains a candidate for a separate close-only experiment if symbol identity
and price adjustment basis can later be independently established.

Current vnstock v5 documentation confirms the registered Community routes
available for equity OHLCV (`vci`, `kbs`, and provider options subject to the
account tier); it explicitly says `tcbs` is not a supported v5 route. The
older TCBS/SSI package documentation and OpenStockAPI therefore do not add an
independent feed to the already-probed VCI/KBS sources. Official TCBS and SSI
documents show the route-specific credentials/approval required for those
feeds. The `vn-market-data` package wraps DNSE, Vietcap, VNDirect, and CafeF,
which are already represented in this audit.

This search found no newly accessible, symbol-mapped, historical OHLCV source
that covers the remaining UPCoM gaps. Keep FireAnt, FiinGroup, SSI, and HNX's
historical product as authorized-access candidates; keep public HNX report
queries targeted rather than using them as a bulk replacement feed. No files
or market rows were imported.

## 2026-10-19 targeted HNX exact-date sample

A separate bounded validation selected one median still-unresolved date for
each of the 16 partial-history symbols. The official HNX report returned one
symbol/date row in every request, with zero matched shares and zero matched
value. These exact reports provide primary-source no-match evidence for those
16 sessions; they reduce the unresolved activity partition from 14,333 to
14,317. The exact report HTML bytes were appended through the existing HNX
evidence landing path; no bars or quality records were repaired. See the
[`16-date HNX evidence bundle`](../phase1-hnx-sample-audit/README.md).

## 2026-10-19 additional public-source checks

The [Lich Su Gia CDG page](https://lichsugia.site/lich-su-giao-dich/CDG.html?page=5)
reports zero volume for 2025-05-13, despite the archived HNX exact-date report
confirming 100 matched shares. Its inspected page does not identify the source
of its history, so it fails this known-trade check and is excluded from volume
or no-trade evidence.

The current [FINCO guide](https://www.finco.vn/docs) describes broad daily
OHLCV coverage across HOSE, HNX, and UPCoM, but says bulk exports require
separately approved research access. The public CDG endpoint returned company
metadata only; the stock-history preview returned `Not authenticated`. FINCO
labels the price series adjusted without documenting the adjustment vintage
or matched/negotiated volume split.
The [FinLens SDK](https://docs.finlens.vn/python-sdk) separately advertises
history from 2007, raw-price selection, and share-unit volume, but requires its
own API key. Neither service was accessed or imported, and its claims remain
unverified against archived exchange evidence.

DNSE's official [OpenAPI docs](https://developers.dnse.com.vn/docs/dnse/get-history-trades/)
describe a historical matched-trade endpoint as well as OHLC history, but
require separately registered DNSE API credentials. Existing DNSE history in
this project comes from that same provider family, so this is a route to test
for trade-level detail rather than an independent source. The Kaggle VN30
listing could not be verified beyond a third-party description and does not
cover UPCoM. None of these checks changed the current 14,317 unresolved
activity-date count or the 19 persisted exact HNX no-match records.

## 2026-10-19 additional dataset and FireAnt documentation checks

The Kaggle API metadata for [Vietnam Stock Returns with Efficiency Scores
(DEA)](https://www.kaggle.com/datasets/thaonguyentrang/vietnam-stock-returns-with-efficiency-scores-dea)
reports a 46 KB, CC BY-SA 4.0 research dataset with quarterly observations for
26 HOSE real-estate companies from 2019 through 2024. It supplies derived
features and next-quarter returns rather than raw daily bars; the linked
[PLOS One paper](https://doi.org/10.1371/journal.pone.0332154) confirms that
sample scope. It can inform a narrow quarterly replication, but cannot repair
the daily UPCoM history gaps. No Kaggle archive was downloaded or imported.

The current [FireAnt Excel documentation](https://help.fireant.vn/fireant-excel/cac-ham-lay-du-lieu-giao-dich-qua-khu/fa-historical/fa-historical-open/)
confirms symbol/date-range history functions; `DealVolume` returns matched
volume and `PutthroughVolume` returns negotiated volume. The current
[plan comparison](https://help.fireant.vn/fireant-membership/so-sanh-goi/)
places the Excel add-in in Premium, while base MetaKit data are included from
Essential upward. This strengthens FireAnt as a technically suitable
authorized source, but no FireAnt account/session data were available for a
known-HNX-trade probe, and the REST history request checked without
authentication returned HTTP 401. Coverage depth, internal ML rights, and
observed values still require an authorized test.

A direct one-date request to the legacy public-code TCBS `apipubaws` OHLCV
route for CDG on 2025-05-13 returned HTTP 403 with no response data. The
official current [TCBS OHLCV docs](https://developers.tcbs.com.vn/docs/v1.0.0/stock/bars-long-term/)
describe the `/nyx/v2/stock/bars-long-term` route, and the [developer portal](https://developers.tcbs.com.vn/)
requires a registered API key and JWT token exchange. This legacy endpoint
check found no usable alternate series; it did not change the activity counts.

## 2026-10-19 VNDIRECT public API exact-date verification

The public [VNDIRECT history page](https://dstock.vndirect.com.vn/lich-su-gia/VND)
displays matched (`KLGD khớp lệnh`) and negotiated (`KLGD thỏa thuận`) volume
separately. Targeted requests to its public Finfo history endpoint returned
one row each for VFC on 2026-07-03 (`nmVolume=1`, `ptVolume=0`), NAS on
2020-10-15 (`nmVolume=80`, `ptVolume=0`), and CDG on 2025-05-13
(`nmVolume=100`, `ptVolume=0`). These values match already archived
VNDIRECT/HNX evidence; NAS is already a positive alternate row in the issue
reconciliation, while VFC and CDG are outside the VCI zero-volume issue set.
The direct probe therefore verifies the public route and field semantics but
does not reduce the 14,317 unresolved dates. The browser page's
`tradingDate` sort key caused HTTP 500 when used directly; Finfo accepts the
`date` field and `sort=date:asc` request. Raw payloads, exact URLs and hashes
are recorded in [`VNDIRECT API verification`](../phase1-vndirect-api-verification-20261019/README.md).
No rows were imported or database records changed.

## 2026-10-19 additional provider and endpoint search

[DataPro SmartAPI](https://datapro.vn/smartAPI.html) is the strongest newly
documented candidate: its official product page advertises EOD OHLCV, matched
and negotiated volume/value, adjustment rates, and a one-time historical EOD
backfill from 2000-07-28 for HOSE/HNX/UPCoM. Its API documentation shows a
subscription/login-gated `GetHistD` history call. The service is custom-priced;
the published terms prohibit giving the data to third parties or operating a
conflicting data-distribution service. It does not establish per-symbol depth,
odd-lot/matched-volume scope, upstream provenance, or permission for this
project's retention and ML use. No key, trial, or paid access was available to
test, so it is a lead rather than verified coverage.

The official [TCBS long-term OHLCV API](https://developers.tcbs.com.vn/docs/v1.0.0/stock/bars-long-term/)
documents daily bars and volume. The [TCBS developer portal](https://developers.tcbs.com.vn/)
requires an API key and OTP-to-JWT exchange; the endpoint's adjustment basis
and whether volume includes negotiated trades are not established. It remains
a customer-authorized cross-check, not a currently callable public source.
[Fialda API](https://fialda.vn/san-pham/api) advertises historical HOSE/HNX/UPCoM
data, but API scope, request limits, and pricing are contract-specific, and
its page does not specify the matched-versus-negotiated fields. These three
leads did not provide a no-auth source to resolve the remaining issue dates.
No data was requested, imported, or used to change the unresolved count.

The installed vnstock 5.0.3 Community profile was also probed once through
`vnpipe probe --routes equity_trade_history`. The documented route returned a
structured `EntitlementError`; official vnstock docs place daily `trade_history`
under the Extended tier and say unsupported-tier routes send no query. Exact
server quota usage remained unchanged. This rules out that Community route as
an activity-history fallback; the archived active probe is in
[`trade-history probe` (local evidence file `../phase1-trade-history-probe-20261019/2026-10-19.json`; not published).

## 2026-10-19 official exchange-feed and odd-lot schema follow-up

The official [HNX information-service guide](https://ny.hnx.vn/vi-vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-sgtc.html)
lists end-of-day trading data for individual securities and says customers may
request a two-week free trial. HNX's [2026 service-price catalogue](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf)
describes UPCoM package `DKGD.DLCN 2.1` as per-stock end-of-day data with
reference/open/close/average/high/low prices and separate matched and
put-through volume/value, delivered as an Excel InfoFile around 18:30; its
listed price is VND 2,000,000 per month. The guide/catalogue do not establish
whether the trial or subscription includes a retrospective archive. Treat this
as the strongest exchange-authoritative route for the ongoing feed and an
archive-scope request, not as already accessible historical data. No trial was
requested and no HNX file was obtained through this service.

FiinGroup's official [UPCoM Stock V2 schema](https://datafeed.fiingroup.vn/api-giao-dich/co-phieu/co-phieu/upcom-stock-v2)
reveals a material volume distinction: `TotalMatchVolume` is explicitly
round-lot order matching, while `TotalDealVolume` includes round- and odd-lot
put-through and `TotalVolume` includes round- and odd-lot order matching plus
put-through. Thus `TotalVolume - TotalDealVolume` is a documented candidate
for all-lot matched volume, subject to a controlled sample verifying the
provider's row semantics and nonnegative arithmetic. `TotalMatchVolume` alone
is not suitable for adjudicating odd-lot no-trade dates. FiinGroup's [API Data
Service page](https://dff.fiingroup.vn/ApiDataFeed?lang=vi-vn) is a request-for-
service form; no local credentials or authorized response were available, so
the endpoint was not called and the field-derived volume was not imported.

As another licensed-history lead, [ICE's HNX feed catalogue](https://developer.ice.com/fixed-income-data-services/catalog/hanoi-stock-exchange-hnx)
lists UPCoM Level 1/2 and historical/end-of-day availability, with history
starting February 2020. Price, access, and the exact odd-lot volume semantics
are not published on that page and remain unverified. It could cover the later
part of the backfill if an authorized product is available; it cannot cover
the project's 2018–2019 start without an additional source.

These official-source findings do not change the 14,314 unresolved
activity-date count: none of the licensed routes was accessed, and no market
rows or quota records changed.

The [official FPTS MarketWatch guide](https://accounts.fpts.com.vn/Help/MarketWatch_En?s=36)
also documents a client-side historical lookup for past-session price and
quantity, across HOSE, HNX, and UPCoM. It documents an account UI, not an
authorized bulk API or export scope, so it is a manual research fallback rather
than a scalable ingestion source.

Two more public chart endpoints were checked against exact HNX controls.
VNDIRECT's public DChart history returned 80 shares for NAS on
2020-10-15, 1 for VFC on 2026-07-03, and 71 for SNC on 2026-10-15, matching
the HNX matched-volume reports. It returned zero for VNX on 2026-01-29,
2026-01-30, and 2026-02-12; HNX and BSC classify those sessions as
negotiated-only. It is the same provider family as the existing VNDIRECT
history, not an independent source. The VPS chart-history endpoint returned
CDG's HNX-confirmed 100 matched shares on 2025-05-13, but returned zero for
NAS and VNX and no row for VFC/SNC. No official API documentation or data-use
terms were found for this direct VPS endpoint. Keep positive exact matches as
corroboration only; a zero/missing response is not evidence of no market
activity. No chart rows were imported. The five request windows per provider,
parsed rows, raw responses, exact URLs, and SHA-256 digests are preserved in the
[`public chart control manifest` (local evidence file `public-chart-controls/manifest.json`; not published).

## 2026-10-19 BSC controls and HNX volume-column correction

The public [BSC historical-data page](https://www.bsc.com.vn/en/historical-data/)
loaded without a login and returned a dated history row through its normal
public form. Its table exposes matched and negotiated volume/value separately,
but does not supply high/low prices. Seven exact dates were requested using
the page's ticker and date filters. BSC reported matched volume of 100 CDG
(2025-05-13), 80 NAS (2020-10-15), 1 VFC (2026-07-03), and 71 SNC
(2026-10-15), matching the HNX controls. For VNX, it reported zero matched
volume and negotiated volumes of 15,100 (2026-01-29), 4,900 (2026-01-30),
and 4,900 (2026-02-12), matching the HNX `Thỏa thuận` column. All seven raw
responses, values, and response hashes are in
[`bsc-controls-20261019.json` (local evidence file `bsc-controls-20261019.json`; not published); the targeted
probe can be repeated with [`probe_bsc_controls.ps1`](probe_bsc_controls.ps1).

This cross-check exposed a first-pass parser error in the three archived VNX
HNX reports: it read columns 17–18 (`Toàn thị trường`, total market) as matched
volume/value. The report's actual matched components are columns 9–14
(continuous, closing auction, after-hours); negotiated activity is columns
15–16 (`Thỏa thuận`). Each VNX report has zero in all matched components and
positive negotiated volume/value. This corrects the earlier “positive matched”
description. The immutable source reports remain intact;
[`build_hnx_interpretation.py`](../phase1-simplize-history-audit/build_hnx_interpretation.py)
validates the columns, and migration 025 plus
[`import_hnx_interpretations.sql`](../phase1-simplize-history-audit/import_hnx_interpretations.sql)
append the corrected interpretation without rewriting the original evidence.
The current lifecycle view classifies these dates as negotiated-only, not as
positive matched-volume conflicts. They are three positive activity dates
already removed from the 14,317 unresolved set; correcting their class leaves
the remaining unresolved count at 14,314. The distinct negotiated-only tally
increases from 106 CafeF dates to 109 when these three HNX dates are included.
BSC provides activity corroboration, not missing OHLC bars, and its
public page does not establish bulk storage or ML-use rights. No BSC rows are
imported.

## 2026-10-19 official calendar and full-history route follow-up

The official HNX notices for 2021 and 2025 were searched directly and match
the closure dates already recorded in
[`phase1-calendar-overrides-2019-2026.sql`](../phase1-calendar-overrides-2019-2026.sql).
The notices explicitly identify the 2025 make-up Saturday 2025-04-26 as a
non-trading day and the 2021 closures, including Lunar New Year and observed
holidays. HNX's current
[public UPCoM market-data page](https://dauthautp.hnx.vn/vi-vn/m-upcom/du-lieu-thi-truong.html)
shows only five recent market-level aggregate rows, not per-symbol daily
history. The canonical calendar already reconciles all 2,008 sessions from
2018-10-01 through 2026-10-16, so these holiday checks confirm that the
remaining 14,314 records are symbol-level activity gaps, not missing calendar
dates. Sources: [HNX 2021 calendar](https://hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60010564.html?_page=1),
[HNX 2025 calendar](https://www.tp.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60020153.html?_page=1),
and [HNX 2026 calendar](https://portal.hnx.vn/vi-vn/chi-tiet-lich-nghi-gd-60021971.html?_page=1).

SSI's official
[Market Data FAQ](https://developers.ssi.com.vn/docs/faq/market-data)
states that daily bars start at each symbol's first trading date, and its
[access guide](https://developers.ssi.com.vn/docs/getting-started/terms-and-environments)
requires FastConnect registration and approval. A single exact-date FPT
request to `Market/DailyOhlc` without an Authorization header returned HTTP
200 with API status 401 and `Missing Authorization header`; no market data
was returned. This confirms that the full-history route is available only
after separate SSI authorization. No SSI rows were imported.

## 2026-10-19 BSC bounded history pull and latest-activity check

The BSC page's ordinary symbol/date filters accepted a bounded 2018-10-01 to
2026-10-16 range for all 16 partial-history symbols. The pull returned 31,935
rows across 47 pages. It is archived with per-page response hashes in
[`BSC history audit`](../phase1-bsc-history-audit/README.md); it adds the
page's distinct matched and negotiated volumes while retaining the source's
limited price fields separately.

The complete pull reconciles all 14,466 VCI zero-volume issue dates. On 24
dates BSC reports matched volume, each amount equal to an existing positive
VNDIRECT or DNSE row. On 109 dates BSC reports negotiated-only volume: 106
amounts exactly equal CafeF's negotiated volume and the remaining three are
the HNX-confirmed VNX totals. BSC reports zero volume on the other 14,333
dates; those rows remain non-evidence of no trade. The broad pull therefore
adds no previously unknown activity date and does not change the 14,314
unresolved activity-date count.

For validation beyond the original seven controls, 12 largest negotiated
amounts (one per symbol) match HNX exactly. The last positive BSC activity date
per symbol also matches an exact HNX report for all 16 symbols. CDG's latest
reported activity is 3,768 negotiated shares on 2025-05-15, two days after its
latest matched-volume date; VNX's latest reported activity is 7,813 negotiated
shares on 2026-08-26, after its latest matched-volume date of 2026-07-28. These
are latest positive BSC observations through 2026-10-16, not proof that the
source could not have missed a later trade.

The audit flags an XMC row with 27,000 matched shares on 2019-06-27, one day
before HNX's current UPCoM profile date of 2019-06-28. XMC has older HNX
listing history, so the row's venue attribution remains unresolved; keep it
out of UPCoM evidence until that interval is established. The BSC page omits
daily high/low and no public bulk-storage or internal ML-use terms were found.
Keep its rows source-attributed; no BSC prices or volumes were imported into
canonical bars or PostgreSQL.

The same symbol-depth check found that EasyStock's VNX file starts on
2025-04-10 (377 rows), although HNX records VNX's first UPCoM trading date as
2010-06-10. See the [EasyStock history-depth note](../phase1-easystock-history-audit/README.md).

## 2026-10-19 — updated SSI FastConnect documentation

The current SSI FastConnect service overview says existing SSI brokerage
customers can create API keys online without manual email approval and that
API use is currently free. A separate SSI Terms & Environments page still says
registration requires approval, and the legacy FCData guide says credentials
are issued through iBoard. Confirm the active onboarding flow in the portal.
Its Market Data documentation covers HOSE, HNX, and UPCOM; `DailyOhlc` returns
OHLC plus normal matched volume/value, and `DailyStockPrice` separately exposes
matched volume, negotiated volume, and a total-traded-volume field that includes
odd lots. The portal documents daily history from each security's first trading
date and bulk historical file/ZIP download. This is a substantially more
actionable UPCoM backfill lead than the older credential-approval wording in
this file.

No SSI credentials are configured in this project environment, so no
authenticated sample was fetched. Before ingestion, validate a known HNX
round-lot date and odd-lot date, determine whether the matched field includes
odd-lot executions, inspect adjustment semantics, and confirm internal ML
retention rights. SSI iData separately advertises a six-month free trial with
all historical EOD through AmiBroker; its login-gated guide and public page do
not specify export or ML-use rights. No market rows or database records changed.

Sources: [FastConnect overview and registration](https://developers.ssi.com.vn/docs/faq/service-overview),
[Terms & Environments](https://developers.ssi.com.vn/docs/getting-started/terms-and-environments),
[legacy FCData connection guide](https://guide.ssi.com.vn/ssi-products/tieng-viet/fastconnect-data/huong-dan-ket-noi),
[Daily OHLC API schema](https://guide.ssi.com.vn/ssi-products/fastconnect-data/api-specs),
[daily history scope and bulk-download FAQ](https://developers.ssi.com.vn/docs/faq/market-data),
[SSI iData trial](https://idata.ssi.com.vn/).

A further FiinGroup schema check found a per-security UPCoM EOD record with
OHLC, explicitly adjusted-price fields, and distinct round-lot matched,
negotiated round+odd-lot, and total round+odd-lot volumes. From its definitions,
`TotalVolume - TotalDealVolume` is a candidate all-lot matched-volume value;
this is an inference, so it must be checked against known HNX odd-lot and
round-lot sessions before use. The public schema does not show the accessible
history depth, trial scope, or ML retention rights. No credentials or data
sample were used. Source: [FiinGroup UPCoM Stock V2 schema](https://datafeed.fiingroup.vn/api-giao-dich/co-phieu/co-phieu/upcom-stock-v2).

## 2026-10-19 — continued public-source search

The additional search checked public adapters, OpenStockAPI, VietstockFinance,
and fresh UTT history references.

- The public MIT [`vn-market-data` adapter](https://github.com/trangcm/vn-market-data)
  names DNSE, Vietcap, VNDirect, and CafeF as its data sources. Its Vietcap
  implementation calls the same public `/chart/OHLCChart/gap-chart` endpoint
  used by vnstock's VCI source, so the adapter is a useful implementation
  reference but not an independent market-data feed. The software license does
  not grant rights to the underlying providers' data.
- [OpenStockAPI's documentation](https://openstockapi.com/document) advertises
  historical OHLCV on its free Community plan after login (30 requests/minute),
  while its documented Vietnam feed graph lists TCBS, KBS, and VCI. Its
  [legal notice](https://openstockapi.com/terms) says it connects to provider
  APIs, is not a data provider, and leaves provider terms and rate limits to
  users. It adds a client/service account requirement but no new upstream
  provider for the current gap.
- A targeted anonymous VietstockFinance check found a public
  [`gettradingresult` route](https://finance.vietstock.vn/data/gettradingresult)
  with separate matched and negotiated fields. It returned no row for CDG on
  2025-05-13 despite the exact HNX report showing 100 matched shares. For SNC
  on 2026-10-15 it returned zero total, matched, and negotiated volume despite
  HNX confirming 71 matched shares. A public market-wide history request with
  a historical date filter returned current-date rows instead. The route's
  [public request description](https://www.postman.com/vietstockapi/public/request/mufpotv/ii-1-https-finance-vietstock-vn-data-kqgdthongkegiapaging)
  therefore fails the known controls and cannot resolve the remaining dates;
  its storage and ML-use terms are also undocumented. No Vietstock rows were
  imported.
- A fresh web search of UTT corroborated HNX's official first-trading date of
  2025-10-17 and found recent zero-volume references from
  [Simplize](https://simplize.vn/co-phieu/UTT/lich-su-gia) and
  [Taichinh.com](https://taichinh.com/chung-khoan/utt). Those references do
  not establish a positive last-trade date. The full-period VNDIRECT and
  CafeF histories and the targeted HNX reports already archived in
  [`phase1-utt`](../phase1-utt/README.md) remain the basis for saying that no
  positive UTT execution was observed through 2026-10-16; do not infer that UTT
  has never traded.

The repository's read-only `backfill-status --from 2018-10-01 --to
2026-10-16` command was also run against the recovered local PostgreSQL
database. It reports listing snapshot 2026-10-17, 1,502 complete, 16 partial,
1 blocked, 0 leased, 0 deferred-invalid, and 0 pending symbols out of 1,519.
The extra search produced no eligible new bars and did not change the 14,314
unresolved activity-date count. No market-data or quota records changed.

## 2026-10-19 — verify current FiinQuant and SSI access paths

- FiinQuant's current pricing page lists a free plan with 100,000 requests per
  month, a 90-request/minute limit, up to 33 tickers, and one year of daily
  history. Its current home page says online account registration is temporarily
  suspended. This cannot backfill the 1,519-symbol, 2018-10-01–2026-10-16
  window, and there is no FiinQuant login available here. No account was
  created and no data were fetched. Sources: [FiinQuant pricing](https://fiinquant.vn/Pricing),
  [FiinQuant home and registration notice](https://fiinquant.vn/).
- SSI's current FastConnect V3 FAQ says an SSI securities account is required,
  the API currently has no service fee, and Market Data keys are created in the
  Developer Portal; per-key rate limits are returned in response headers. The
  older FastConnect V2 registration page still describes counter/representative
  registration and manual approval, so the live account flow should take
  precedence if an SSI account is available. Sources: [current SSI service FAQ](https://developers.ssi.com.vn/docs/faq/service-overview),
  [older registration guide](https://guide.ssi.com.vn/ssi-products/service-registration).
- The documented V2 market-data API is token-authenticated with ConsumerID and
  ConsumerSecret. Its `DailyOhlc` schema explicitly covers UPCOM and defines
  `Volume` as normal matched volume; `DailyStockPrice` separates `TotalMatchVol`
  and `TotalDealVol`, and documents `TotalTradedVol` as including odd lots. It
  also exposes raw OHLC and `ClosePriceAdjusted`. Page size is at most 1,000
  rows with up to 10 pages per request. This is the strongest no-fee backfill
  path found if an SSI brokerage account is already available, but no SSI key
  or authenticated sample is configured here. Volume fields, adjustment
  vintage, the current V2/V3 route relationship, and internal ML retention
  rights still require a controlled sample and terms review. Sources: [SSI FastConnect data API schema](https://guide.ssi.com.vn/ssi-products/fastconnect-data/api-specs),
  [SSI Market Data history FAQ](https://developers.ssi.com.vn/docs/faq/market-data).
  An older official FCData specification describes analysis through customers'
  own applications, but it does not spell out ML dataset retention or the
  current license scope: [SSI FCData specification](https://ftp2.ssi.com.vn/Customers/GDDT/Document/SSI_FastConnectData_Specs.pdf).
- HNX's official 2026 catalog lists `DKGD.DLCN 2.1` at VND 2,000,000 per
  month for per-security UPCoM EOD data with both matched and negotiated
  volumes/values. HNX advertises a two-week trial, but its technical guide says
  connection specifications are provided after a contract is signed. The
  public materials do not confirm whether the trial includes historical
  archive files or whether local ML retention is included. Sources: [HNX UPCoM package catalog](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf),
  [HNX trial and technical-registration guidance](https://w.hnx.vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-sgtc.html),
  [HNX InfoFile technical requirements](https://hnx.vn/vi-vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-YCKT.html).
- The expanded public dataset and adapter search added no licensed full-universe
  dataset with known symbol mapping, adjustment basis, matched/negotiated
  semantics, and ML-use scope. The remaining 14,314 activity dates therefore
  remain unresolved. No provider calls, imports, or PostgreSQL/quota changes
  were made during this documentation check.

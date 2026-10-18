# Phase 1 VCI partial-job coverage audit

Audit date: 2026-10-18. PostgreSQL reads ran in explicit read-only transactions.
No market-data rows, job states, quality issues, lifecycle evidence, or quota
records were changed.

## Scope and result

The VCI `equity_ohlcv` backfill has 32 `PARTIAL` jobs for 16 UPCoM tickers:
CDG, GGG, HPI, NAS, SBD, SDD, SHC, SNC, SPC, SVG, TNB, VFC, VNI, VNX, XMC,
and XPH. Each ticker has two overlapping attempts ending 2026-10-16, one from
2018-10-01 and one from 2018-10-18. The exports retain job IDs and landing IDs;
counts below deduplicate by ticker and trade date.

| Measure | Result |
| --- | ---: |
| Canonical positive-volume VCI bars for these tickers | 13,955 |
| Unique VCI quality-issue ticker/date pairs | 14,492 |
| `ZERO_VOLUME_UNVERIFIED` | 14,466 |
| `INVALID_PRICE` | 25 |
| `INVALID_OHLC` | 1 |
| Invalid-price/OHLC dates with a positive same-day VNDIRECT bar | 26 / 26 |
| Invalid-price/OHLC dates with a positive same-day DNSE bar | 15 / 26 |
| Zero-volume issue dates with a positive same-day VNDIRECT bar | 24 / 14,466 |
| Zero-volume issue dates with a positive same-day DNSE bar | 23 / 14,466 |
| Zero-volume issue dates with a positive bar from either alternate | 24 / 14,466 |

For the 16 tickers, VNDIRECT has 14,338 positive-volume ticker/date rows:
13,950 overlap a positive canonical VCI bar, and 388 have no positive
canonical VCI bar. DNSE has 13,485 positive-volume rows: 13,385 overlap VCI,
and 100 have no positive VCI bar. Those 100 DNSE dates are also present in
VNDIRECT. VCI has five positive dates without a positive bar from either
alternate provider.

The 388 VNDIRECT dates without a positive VCI bar include 50 dates with a
recorded VCI quality issue (26 invalid-price/OHLC dates and 24 zero-volume
dates). The other 338 have no VCI canonical bar and no matching VCI quality
issue. These are useful, source-attributed supplemental observations; they
remain separate from VCI. The zero-volume issue dates without a positive
alternate execution remain unverified, not confirmed non-trades.

Every one of the 14,492 issue dates has a VNDIRECT source row, but most of
those rows also have zero volume. Presence of a reference row is not evidence
of an execution. All 14,492 issue dates lack a canonical VCI bar; the 13,955
valid positive VCI bars are separate ticker/date observations.

## Public exchange lookup

The HNX profile and notice pages were searched for all 16 tickers. The
profile-displayed dates are in `hnx-profile-dates.csv`. They are current HNX
venue/profile dates, not automatically first-ever public-trading dates. For
example, HNX's current UPCoM profile reports XMC from 2019-06-28, while XMC's
older annual report records its first HNX trading session as 2007-12-20.
Exchange transfers mean the current profile date cannot be used to classify
pre-date observations as pre-listing. Likewise, an absence of a positive bar
does not prove a listing, suspension, delisting, or last-trade date.

The existing lifecycle view returns `LISTING_STATUS_UNVERIFIED` for all
14,466 zero-volume issue dates on these tickers. I did not insert a lifecycle
record: the project requires archived, checksum-verified primary-source bytes
under the `security_lifecycle_notice` route, and the searched profile dates do
not establish complete first-ever and suspension/delisting histories.

## Public-source checks for individual market-data findings

### SNC, 2026-10-15

StockBiz and Cophieu68 history pages report zero SNC volume on 2026-10-15.
The official HNX UPCoM daily trading report for that date returns SNC
(VN000000SNC5) with 71 shares and VND 1,547,800 in continuous matching
(3 buy orders, 4 sell orders; total-market volume 71). This confirms an
execution and matches VNDIRECT landing 8002, source row 2006 (nmVolume=71,
close=21.8; payload SHA-256
2b94dba13615420cb69216bcf2b96746ecf2921774507eca112446ca4168c3e1). This is
one of the positive VNDIRECT observations without a positive canonical VCI bar
or a VCI quality issue in the audit export.
The current VNX UPCoM rule (Decision 23/QD-HDTV, effective 2026-03-18)
defines a continuous-matching lot as 100 shares, odd lots as 1–99 shares,
and allows odd lots through continuous matching or put-through. It also says
odd-lot trades do not determine the reference price or index. HNX classifies
this 71-share amount as continuous matching. This confirms the odd-lot
execution; it is consistent with the third-party zero-volume pages showing a
reference price without reporting the odd-lot amount, but their exact volume
filter is not documented.

The HNX response is archived in `hnx-snc-2026-10-15.html`
(SHA-256 `4A3EC14FAECF96AF0B3BC9725B7D822A22571EDF7F47322587589A5DE4108396`).
It was fetched on 2026-10-18 from the [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM)
using `p_keysearch=15/10/2026|0|0|'SNC'|-1|16/10/2026|`. The zero-volume
third-party summaries do not override the official daily execution record.
Sources: [StockBiz](https://web.stockbiz.vn/Stocks/SNC/LookupQuote.aspx?Date=16/10/2026),
[Cophieu68](https://cophieu68.vn/download/historydaily.php?d=2026-10-15),
and the current [VNX UPCoM trading rule](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), listed in the [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6).

### VNDIRECT price adjustment basis

For the archived VNDIRECT responses used in this partial-job audit, the
imported OHLC is confirmed raw/unadjusted: `go/internal/vndirect/client.go`
parses `open/high/low/close`, not the separate `adOpen/adHigh/adLow/adClose`
fields, and `go/internal/ingest/alternate_market.go` stores those values as
`unadjusted`. A read-only comparison covered 31,931 payload rows from 16
VNDIRECT responses; raw and adjusted OHLC differed on 15,773 rows, and raw
close differed from `adClose` on 15,777 rows. For example, CDG on 2018-10-01
has raw OHLC of 14.0 and adjusted OHLC of 1.541. VNDIRECT's public history
page separately labels ordinary close and adjusted close, and says its
adjusted close accounts for splits and dividends.

This verifies the stored VNDIRECT import basis. It does not establish a
point-in-time adjustment workflow for joining sources. VCI and DNSE remain
unknown; keep all providers source-homogeneous until VCI/DNSE basis and the
required point-in-time corporate-action treatment are verified. Source:
[VNDIRECT historical prices](https://dstock.vndirect.com.vn/lich-su-gia/VND).

## Evidence files

- `partial-jobs.csv`: all 32 VCI partial jobs, date ranges, job IDs and landing
  IDs.
- `issue-coverage.csv`: 14,492 deduplicated ticker/date issues, issue lineage,
  canonical-bar presence, and same-session VNDIRECT/DNSE fields.
- `alternate-positive-without-vci.csv`: 488 source rows covering 388 distinct
  ticker/dates with positive alternate volume and no positive canonical VCI
  bar. Each row includes source landing, source row and raw-response SHA-256.
- `export.psql` and `export-alternate-gap.psql`: read-only export queries. Run
  from the repository root against the user's local database.
- `hnx-profile-dates.csv`: researched official HNX profile dates and source
  links, retained as lookup leads rather than lifecycle classifications.
- `hnx-snc-2026-10-15.html`: archived official HNX result for SNC's
  2026-10-15 UPCoM trading activity, with the search filter and SHA-256 above.

| File | Rows | SHA-256 |
| --- | ---: | --- |
| `partial-jobs.csv` | 32 | `1A9669EE3509CC828DF2524AC86A985DA4A1662CEF1D4603EC573F8C1300CACB` |
| `issue-coverage.csv` | 14,492 | `D992E8C66F34AF6B2BB315AF56AB02C225F2990C544B0A6AF1BB948A6872FB96` |
| `alternate-positive-without-vci.csv` | 488 | `6C1B8E154FEBB5BD345F2D128E201A9C1E18DBAE0E1258FA6CC9D2E6C5D4468E` |
| `hnx-snc-2026-10-15.html` | 1 | `4A3EC14FAECF96AF0B3BC9725B7D822A22571EDF7F47322587589A5DE4108396` |

The stored VNDIRECT import basis is verified as raw/unadjusted. VCI and DNSE
adjustment basis remain unknown. Do not join any provider into the VCI
canonical series until VCI/DNSE basis and point-in-time adjustment behavior
are verified. No price series was spliced or relabelled in this audit.

## Public-source checks of recent SHC zero-volume rows

The official HNX UPCoM daily report was queried for all three SHC zero-volume
issue dates inside its currently exposed 30-day search window: 2026-09-16,
2026-09-18, and 2026-09-21. Each report row shows buy and sell orders, but all
matched-volume columns, including total-market volume, are zero. These reports
confirm no matched trade on those sessions while SHC had active orders. The
HNX order volumes are orders, not executed volume.

| Date | Buy orders / shares | Sell orders / shares | HNX total matched volume |
| --- | ---: | ---: | ---: |
| 2026-09-16 | 4 / 5,400 | 4 / 12,700 | 0 |
| 2026-09-18 | 1 / 100 | 5 / 1,304 | 0 |
| 2026-09-21 | 1 / 200 | 6 / 6,731 | 0 |

The raw HNX HTML responses and hashes are in `hnx-recent/`. The downloaded HNX
page source is also archived there; its date-selection code only permits the
latest month. A direct request for SNC on 2020-09-17 returned no rows even
though archived VNDIRECT/DNSE data have positive-volume records for that date.
Treat an empty response from this current-month page as unavailable historical
evidence, not proof of a non-trade. HNX's official information guide lists
UPCoM EOD and historical trading data as services; public access and fee terms
were not verified.

These external records have not been ingested or reprocessed in PostgreSQL;
the database's zero-volume lifecycle view still classifies all 14,466 VCI
zero-volume issue dates as unverified. This is documented evidence, not a
database status change.

## 2026-10-18 follow-up — historical HNX checks for invalid VCI bars

The date-picker limit does not prevent a historical lookup: the official HNX
daily-report POST endpoint accepted exact dates in 2018–2020. Targeted queries
for every one of the 26 distinct VCI invalid-price/OHLC ticker/date pairs
returned an HNX report row with positive total-market matched volume. This
confirms that the VCI quality findings are invalid source prices, not no-trade
dates. The HNX values agree with positive VNDIRECT volume for all 26 pairs.

| Ticker | Date | HNX total matched shares |
| --- | --- | ---: |
| CDG | 2020-09-17 | 29 |
| GGG | 2019-11-22 | 30 |
| HPI | 2019-11-22 | 3 |
| NAS | 2020-09-17 | 50 |
| SBD | 2020-09-23 | 20 |
| SDD | 2020-09-17 | 20 |
| SHC | 2020-09-17 | 1 |
| SNC | 2020-09-17 | 10 |
| SPC | 2020-09-17 | 1 |
| SVG | 2018-11-19 | 100 |
| TNB | 2019-11-22 | 68 |
| VFC | 2019-11-22 | 71 |
| VNI | 2019-11-22 | 2 |
| VNX | 2018-11-06 | 100 |
| VNX | 2019-03-22 | 100 |
| VNX | 2019-03-25 | 100 |
| VNX | 2019-03-26 | 100 |
| VNX | 2019-03-27 | 100 |
| VNX | 2019-03-28 | 100 |
| VNX | 2019-03-29 | 100 |
| VNX | 2019-04-01 | 100 |
| VNX | 2019-04-02 | 100 |
| VNX | 2019-04-03 | 100 |
| VNX | 2019-04-04 | 100 |
| XMC | 2020-09-18 | 100 |
| XPH | 2020-09-17 | 1 |

The archived report bodies, exact pair keys, row-found status, matched value,
and SHA-256 are in `../phase1-hnx-invalid-bar-audit/`. A fresh read-only query
of `core.bars_daily_sources_ml_eligible` matched these same 26 keys to 26
positive `vndirect` rows (`is_traded=true`, `adj_basis=unadjusted`), retaining
their source landing and row lineage. Use those rows only in the separately
attributed VNDIRECT series; do not repair or relabel VCI prices from another
provider. This finding does not classify the separate 14,466 zero-volume issue
dates.

## 2026-10-18 follow-up — latest positive dates for the 16 audited tickers

The most recent positive VNDIRECT row for each ticker through 2026-10-16 was
looked up on the correct HNX market report. HNX confirms the date and the exact
total matched volume for all 16. Fifteen current/period UPCoM records used the
UPCoM report. SPC used the HNX-listed report because VSDC records its market
transfer effective 2022-01-21 and HNX lists its first HNX session on
2022-01-27. This correct venue selection matters: the UPCoM endpoint returns
no SPC row for its 2026 HNX-listed trading history.

The symbol/date/volume reconciliation and 16 raw response hashes are in
[`../phase1-hnx-last-trade-audit/README.md`](../phase1-hnx-last-trade-audit/README.md).
These are the latest positive dates in the archived VNDIRECT data; the audit
confirms each execution, but does not query HNX for every later zero-volume
session. They are not complete exchange-certified last-trade histories.

This corrects the earlier statement above that a direct historical HNX request
returned no rows: that request used the page's limited-date-picker behavior.
The official report POST endpoint accepts the exact historical dates recorded
in the evidence folder.

| HNX evidence file | SHA-256 |
| --- | --- |
| `hnx-recent/SHC-2026-09-16.html` | `ffd746c451e5086aaf47448ff7e99c3aa5a37e0ba67070220b256d4db487cb59` |
| `hnx-recent/SHC-2026-09-18.html` | `1d696451236e8788f9abe603431652f9d157f1e88a7fde749ee630bfc101a739` |
| `hnx-recent/SHC-2026-09-21.html` | `b29d6e3fd592bb33218f689000ae5c86ce7caf841b97384296dd16914a039cca` |
| `hnx-recent/hnx-upcom-report-page-2026-10-18.html` | `6106ebc7050b5afae33bf5e4faa889d635fc959566ae1201af59810ed0f5dc86` |

Sources: [HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
[HNX UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html),
and [HNX information-service guide](https://owa.hnx.vn/ftp/PORTALNEW/PUBLICFACTBOOK_FA/20161202/Guide%20to%20HNX.pdf).

## 2026-10-18 follow-up — persist the three HNX no-match reports

The three SHC report responses above were imported from their archived raw HTML
after checksum verification. Migration 023 stores them as append-only exchange
execution evidence; it does not add or repair an OHLCV bar. The updated
`ops.zero_volume_lifecycle_status` classifies all three symbol/session pairs as
`VERIFIED_ELIGIBLE_NO_MATCH`. The exact responses, SHA-256 values, extraction
script and idempotent SQL import are in `hnx-recent/` and
`import_hnx_shc_evidence.sql`.

The same view now identifies 24 unique zero-volume issue pairs with positive
alternate-source bars as `CONFLICTING_EVIDENCE`. Of the 14,466 audited zero-
volume issue dates, three are HNX-confirmed no-match sessions and 14,439 remain
`LISTING_STATUS_UNVERIFIED`. The earlier statement above that none of the HNX
reports were persisted is historical and is superseded by this follow-up.

## 2026-10-19 follow-up — 16 additional exact HNX reports

The separate [`phase1-hnx-sample-audit`](../phase1-hnx-sample-audit/README.md)
adds one median unresolved exact-date report for each of the 16 partial-history
symbols. All 16 reports show zero matched shares and value, and the direct
Phase 1 evidence-rule check classifies all 16 as `VERIFIED_ELIGIBLE_NO_MATCH`.
Together with the earlier three SHC reports, 19 of the 14,466 VCI
zero-volume issue pairs now have exact HNX no-match evidence. The broader
lifecycle-unverified count is 14,423; the narrower unresolved activity
partition was 14,317 at this audit point because it excluded the 106 CafeF negotiated-only dates. Three subsequent HNX-confirmed VNX negotiated-only dates bring the current partition to 14,314; the distinct negotiated-only group now has 109 dates.
No canonical bars, VCI quality issues, or manual lifecycle events were changed.

# CafeF historical data audit for VCI zero-volume issues

Retrieved 2026-10-19. This is a public-source cross-check of the 16 symbols
in `phase1-partial-audit/issue-coverage.csv`; it did not write to PostgreSQL
or modify canonical bars, quality issues, or lifecycle status.

## Retrieval and evidence

CafeF's public history pages provide daily OHLC, matched volume, negotiated
volume, and an Excel export control. The page documents a one-year maximum
export range. The history API's date inputs use `MM/DD/YYYY`; using
`DD/MM/YYYY` can silently return the default recent range. That explained the
earlier inconsistent singleton checks. The corrected route was validated on
NAS for calendar 2020: CafeF reports 80 matched shares on 2020-10-15, in line
with the existing VNDIRECT and DNSE volume observations.

The audit retrieved nine annual windows per symbol (2018 partial, 2019–2025,
and 2026 partial): 144 valid XLSX files and 31,381 source rows. The annual
files are preserved under [`raw/`](raw/). [`manifest.csv` (local evidence file `manifest.csv`; not published)
records period, source, byte count, and SHA-256 for every file. The reproducible
fetch and reconciliation scripts are [`fetch_cafef.ps1`](fetch_cafef.ps1) and
[`reconcile_cafef.py`](reconcile_cafef.py).

[`daily-activity.csv` (local evidence file `daily-activity.csv`; not published) is a row-preserving extraction of
all 31,381 rows. It keeps reported close and adjusted close separate, retains
matched and negotiated volumes separately, preserves CafeF's stated price and
value units, and links each row to its source workbook, worksheet row, and
SHA-256. Price columns are included as source data but were not used to repair
or replace any VCI/VNDIRECT/DNSE bar.

## Results on the VCI issue dates

The issue audit contains 14,492 unique symbol/session rows: 14,466
`ZERO_VOLUME_UNVERIFIED`, 25 `INVALID_PRICE`, and one `INVALID_OHLC`. Of the
14,466 zero-volume rows, CafeF reports:

| CafeF result | Dates |
| --- | ---: |
| Positive matched volume | 23 |
| Positive negotiated volume only | 106 |
| Explicit zero matched and negotiated volume | 14,159 |
| No CafeF row | 178 |

All 23 positive CafeF matched-volume dates already overlap positive VNDIRECT
or DNSE bars. Together with the earlier KBS cross-check, this adds no unique
matched-volume date. One existing VNDIRECT/DNSE positive date does not have a
positive CafeF row.

The 106 negotiated-only dates are new source-reported activity, with no
positive same-day matched volume in the existing VNDIRECT or DNSE rows. Keep
them as separate negotiated-activity evidence. Do not turn them into matched
OHLC bars or treat negotiated volume as a substitute price series. The HNX
trading reports also separate matched and negotiated totals; CafeF's own
history export presents those fields separately.

## Confirmed CafeF false negatives

A separate latest-positive audit cross-checked exact dates at HNX. CafeF reports
zero matched and negotiated volume for CDG on 2025-05-13, but HNX confirms 100
matched shares. CafeF also reports zero matched and negotiated volume for VFC
on 2026-07-03, but HNX confirms one matched share. Both exchange responses are
archived in [`phase1-hnx-last-trade-audit/`](../phase1-hnx-last-trade-audit/).
These dates are outside the 14,466-row issue-date partition above. They show
that CafeF's zero rows can miss real, including odd-lot, matched executions;
they reinforce that neither zero nor absence in CafeF can certify no trade.

At this CafeF reconciliation stage, the 14,466 issue dates were partitioned as follows: 24 dates with a
positive VNDIRECT/DNSE matched bar (23 also reported positive by CafeF), 106
CafeF negotiated-only dates, three HNX-confirmed zero-matched sessions for
SHC (2026-09-16, 2026-09-18, and 2026-09-21), and 14,333 dates with no
positive volume evidence in these sources. CafeF reports zero volume for each
of those three SHC sessions. At that stage, 14,333 dates were still unverified. Subsequent exact HNX checks
reduced the current unresolved activity count to 14,314; the distinct
negotiated-only evidence group now contains 109 dates. A CafeF zero or missing
row is not an exchange no-trade certificate.

[`issue-coverage-cafef.csv` (local evidence file `issue-coverage-cafef.csv`; not published) gives the row-level
join and source-file lineage. [`symbol-summary.csv` (local evidence file `symbol-summary.csv`; not published) and
[`summary.json` (local evidence file `summary.json`; not published) provide aggregate counts.

## Source interpretation

CafeF describes its history lookup as covering a security's price and volume
history from its listing date, including open, high, low, close, and trading
volume. Its page is a secondary data source, not an exchange audit. HNX
publishes daily UPCoM reports and separately distinguishes matched from
negotiated activity in its trading-scale reports. A negotiated transaction
can establish activity without providing a matched-order OHLC observation.

This evidence updates source coverage only. It does not reclassify the VCI
quality ledger, clear a VCI zero-volume issue, or assert that a zero/absent
CafeF row proves no trade. The 106 negotiated-only observations may support a
distinct activity feature in a later phase, subject to the Phase 2 data
contract; they are not daily price bars. Point-in-time adjustment vintages
remain unresolved.

Sources: [CafeF history page](https://cafef.vn/du-lieu/lich-su-giao-dich-nas-1.chn),
[CafeF data-history guide](https://cafef.vn/du-lieu/huong-dan-su-dung.chn),
[HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM),
and [HNX trading-scale report example](https://owa.hnx.vn/ftp/THONGKEGIAODICH/20250724/CP/20250724_UC_Quy_mo_giao_dich.pdf).

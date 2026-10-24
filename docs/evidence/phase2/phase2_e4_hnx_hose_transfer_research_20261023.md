# E4 HNX-to-HOSE transfer source research (2021-10-23)

## Scope

This review concerns the 13 E4 gap rows after the final HNX trading date of 2021-08-27. The report CSV identifies 40 missing effective sessions: three sessions (2021-08-30, 2021-08-31, 2021-09-01) for twelve symbols and four (through 2021-09-06) for PAN.

The E4 source is `phase2_integrity_gap_attribution_20261022.sql`; the row-level source is `phase2_integrity_gap_attribution_20261022.csv`. Those identify the gaps but do not establish a transfer or a suspension.

## Primary-source findings

The HNX announcement [HNX transfer announcement](https://www.hnx.vn/vi-vn/chi-tiet-su-kien-60012723-0-hnx.html?_page=1) names the transfer cohort and gives 2021-08-27 as the last HNX trading date. It does not state each symbol's first HOSE trading date.

Ticker-specific first-HOSE-day records found:

| Symbol | First HOSE date | Source and evidence | E4 gap sessions potentially explained |
|---|---|---|---:|
| ABT | 2021-09-06 | HOSE notice PDF, hosted by Vietstock: [ABT first-day notice](https://static2.vietstock.vn/vietstock/2021/8/27/20210827_ABT%20210827%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf) | 3 |
| BSI | 2021-09-06 | HOSE notice PDF, hosted by Vietstock: [BSI first-day notice](https://static2.vietstock.vn/vietstock/2021/8/30/20210830_BSI%20210830%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf) | 3 |
| DXS | 2021-09-06 | HOSE notice PDF hosted on issuer site: [DXS first-day notice](https://datxanhservices.vn/wp-content/uploads/2021/08/DXS-TB-ngay-giao-dich-dau-tien-tren-HOSE.pdf), HOSE notice no. 1536/TB-SGDHCM | 3 |
| VND | 2021-09-06 | HOSE notice PDF: [VND first-day notice](https://static2.vietstock.vn/vietstock/2021/8/30/20210830_VNDS%20210830%20Notice%20of%20the%20first%20trading%20day%20on%20HOSE%20-%20MN.pdf) | 3 |

For the four rows above, both the HNX final-day and ticker-specific HOSE first-day endpoints are located. The interval between those endpoints is consistent with the respective no-trading transfer window. However, the dated originals have not been registered as intact `raw.landings` with route `security_lifecycle_notice` in the report clone. Therefore no `core.security_lifecycle_evidence` rows were inserted and no E4 lifecycle reclassification was made.

## Unresolved exact gaps

The following first-HOSE dates were not proven by a ticker-specific primary exchange or issuer record in this review. All their gap sessions remain unresolved:

| Symbol | Gap sessions | Exact dates | Status |
|---|---:|---|---|
| HAP | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | No ticker-specific primary first-HOSE notice found |
| KHG | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | Secondary reporting says 2021-09-06; primary notice not found |
| LAF | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | No ticker-specific primary first-HOSE notice found |
| NSC | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | Issuer annual-report search excerpt gives venue return/listing context, not first trading day |
| PAN | 4 | 2021-08-30, 2021-08-31, 2021-09-01, 2021-09-06 | Issuer confirms last HNX day 2021-08-27; 2021-09-07 first day appeared only in a secondary JSI table |
| QBS | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | Secondary venue-history page says 2021-09-06; primary notice not found |
| SSC | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | No ticker-specific primary first-HOSE notice found |
| TVB | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | Secondary venue-history page says 2021-09-06; primary notice not found |
| VFG | 3 | 2021-08-30, 2021-08-31, 2021-09-01 | No ticker-specific primary first-HOSE notice found |

Secondary research leads (not accepted as lifecycle evidence): JSI's 2021-09-01 market note has a “Date of switch back to HOSE” table showing HAP, LAF, NSC, and TVB on 2021-09-06 and PAN on 2021-09-07. KHG is reported as moving to HOSE on 2021-09-06 in [VietnamMới's report](https://vietnammoi.vn/khai-hoan-land-dung-giao-dich-tren-hnx-se-qua-san-hose-tu-6-9-20210901090006847.htm). Search snippets from VNSignal/Soima pages list 2021-09-06 for QBS and TVB but are not primary records. These sources are only leads for locating original notices.

## Lifecycle mechanism and disposition

Migration `sql/migrations/007_lifecycle_evidence.sql` supports only `FIRST_EVER_PUBLIC_TRADE`, `TRADE_ELIGIBLE`, `TRADING_SUSPENDED`, and `DELISTED`. Its insert trigger requires an intact archived landing whose route is `security_lifecycle_notice`; migration `057_lifecycle_landing_symbol_integrity.sql` additionally requires the landing ticker to match the evidence ticker. The table is append-only. The existing E4 attribution SQL consumes overlapping lifecycle evidence, so no new E4 classification can be supported from web links alone.

Result at this review's initial search stage: 4/13 first dates found in ticker-specific HOSE notices (12/40 candidate sessions had paired endpoint documentation); 9/13 dates and 28/40 sessions were unresolved. No DB mutation or E4 label change was made. A bounded report-clone connection attempt produced no query output, so clone-side fixture validation and post-change SQL reconciliation could not be completed in that review.

Next concrete evidence path: obtain the original HOSE notice (or issuer-distributed copy of the HOSE notice) for HAP, KHG, LAF, NSC, PAN, QBS, SSC, TVB, and VFG; archive each original document under its own ticker as `security_lifecycle_notice`; then validate inserts against the triggers and use the existing E4 attribution query restricted to those 13 gap rows. Archive the four located notices the same way before recording them as lifecycle evidence.

## Addendum: notice originals subsequently located

The web search status above was superseded later on 2026-10-23. Ticker-specific HOSE notice PDFs were located and their original PDF bytes saved for all nine remaining tickers, including KHG. Together with ABT, BSI, DXS, and VND, all 13 dates are now supported by ticker-specific notices. PAN's notice specifies 2021-09-07; the other twelve notices specify 2021-09-06. The archived bytes, source URLs, retrieval timestamps, SHA-256 values, and exact dates are in [`hose_transfer_sources_20261023/manifest.csv`](hose_transfer_sources_20261023/manifest.csv), with a packet summary in [`hose_transfer_sources_20261023/README.md`](hose_transfer_sources_20261023/README.md).

This resolves the source-research gap for all 40 candidate sessions, but does not alter the SQL report's status: no database writes were made and no audited lifecycle rows were inserted. The remaining blocker is to archive these source bytes as ticker-matched `raw.landings`, append the corresponding lifecycle records through the existing mechanism, and validate using the scoped fixture and bounded report-clone query.

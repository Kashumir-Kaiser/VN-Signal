# Public web check of last matched UPCoM dates

Checked: 2026-10-19. These were three individual research lookups, not a bulk
download. No page data were imported into PostgreSQL.

| Symbol | Page's latest matched date | Page snapshot | Evidence |
| --- | --- | --- | --- |
| CDG | 2025-05-13 | 2026-09-18 | [taichinh.com/CDG](https://taichinh.com/chung-khoan/cdg) says no match on its snapshot date and names 2025-05-13 as the latest match. HNX's exact-date report confirms 100 shares on 2025-05-13. |
| VFC | 2026-07-03 | 2026-10-09 | [taichinh.com/VFC](https://taichinh.com/chung-khoan/vfc) names 2026-07-03 as the latest match. HNX confirms 1 share on that date; eight exact-date HNX reports then show zero matched volume from 2026-07-06 through 2026-07-15. |
| VNX | 2026-07-28 | 2026-10-12 | [taichinh.com/VNX](https://taichinh.com/chung-khoan/vnx) names 2026-07-28 as the latest match. HNX confirms 100 shares on that date. |

All three taichinh.com pages identify VNDirect as their price/volume source.
The positive-date exchange confirmations and request/response hashes are in
[`../phase1-hnx-last-trade-audit/README.md`](../phase1-hnx-last-trade-audit/README.md)
and `../phase1-hnx-last-trade-audit/hnx-last-trade-reconciliation.csv`.
HNX's later 2026-10-12–16 reports show zero matched volume for all three; see
[`../phase1-hnx-latest-week/README.md`](../phase1-hnx-latest-week/README.md).

## Interpretation

Use these dates as the latest matches represented in the VNDirect-derived
series, with exact positive-date confirmation from HNX. The web pages do not
provide an independent, session-by-session exchange audit of every later
date. The evidence applies only to CDG, VFC, and VNX; it does not classify the
14,439 other zero-volume issue dates in the partial-job audit.

The site's [usage terms](https://taichinh.com/dieu-khoan-su-dung) allow
individual research lookups and citations with source attribution. They ask
users to contact FTMI before automated collection across the site or broad,
deep extraction. No automated collection or local copy of the pages was made.

## Candidate source for volume reconciliation

FiinGroup's [official UPCoM Stock V2 schema](https://datafeed.fiingroup.vn/api-giao-dich/co-phieu/co-phieu/upcom-stock-v2)
distinguishes the latest round-lot `MatchVolume`, total round-lot matched
`TotalMatchVolume`, negotiated `TotalDealVolume`, and `TotalVolume` for
matching plus put-through, including round and odd lots. This could help
explain cases where providers report different volume definitions. The public
schema does not state historical backfill depth or grant data use rights.
Before using it for bulk reconciliation, obtain a sample covering the 16
partial-history tickers and 2018-10-01 through 2026-10-16, together with
written coverage, history, odd-lot, put-through, adjustment-vintage, and
internal ML research terms. HNX also lists historical UPCoM data as an
information service; its public daily page was used only for bounded checks.

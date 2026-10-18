# VNDIRECT public history API verification

Checked 2026-10-19 (Vietnam time) through the public VNDIRECT Finfo
`/v4/stock_prices` endpoint. These were three exact-date source checks, not a
backfill. The request filter accepted `date` with `sort=date:asc`; a first
attempt using the DStock page's `tradingDate` sort key returned HTTP 500.

| Symbol | Date | Matched (`nmVolume`) | Negotiated (`ptVolume`) | HTTP / rows |
| --- | --- | ---: | ---: | --- |
| VFC | 2026-07-03 | 1 | 0 | 200 / 1 |
| NAS | 2020-10-15 | 80 | 0 | 200 / 1 |
| CDG | 2025-05-13 | 100 | 0 | 200 / 1 |

VNDIRECT's public history page labels these columns separately as matched
volume (`KLGD khớp lệnh`) and negotiated volume (`KLGD thỏa thuận`), and
separately explains that adjusted close reflects corporate actions. The
three returned `nmVolume` values agree with existing source-attributed
VNDIRECT rows and the archived exact-date HNX reports. NAS is also already
positive in the partial-job reconciliation. VFC and CDG are outside the
14,466 VCI zero-volume issue-date population. This verifies the public
endpoint and its matched-volume field, but adds no new gap coverage and does
not change the 14,317 unresolved-date count.

The exact request URLs, raw JSON bodies, retrieval timestamp, row summaries,
and SHA-256 hashes are recorded in `manifest.json` and `raw/`. The related
exchange lineage is in [`phase1-hnx-last-trade-audit`](../phase1-hnx-last-trade-audit/README.md).
No market-data rows, canonical bars, quality findings, lifecycle statuses,
quota records, or PostgreSQL records were changed.

Sources: [VNDIRECT historical prices](https://dstock.vndirect.com.vn/lich-su-gia/VND),
[VFC response](https://api-finfo.vndirect.com.vn/v4/stock_prices?sort=date%3Aasc&q=code%3AVFC~date%3Agte%3A2026-07-03~date%3Alte%3A2026-07-03&size=15&page=1),
[NAS response](https://api-finfo.vndirect.com.vn/v4/stock_prices?sort=date%3Aasc&q=code%3ANAS~date%3Agte%3A2020-10-15~date%3Alte%3A2020-10-15&size=15&page=1),
and [CDG response](https://api-finfo.vndirect.com.vn/v4/stock_prices?sort=date%3Aasc&q=code%3ACDG~date%3Agte%3A2025-05-13~date%3Alte%3A2025-05-13&size=15&page=1).

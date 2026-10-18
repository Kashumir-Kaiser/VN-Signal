# Targeted KBS checks for Phase 1 gaps

Audit date: 2026-10-19. Targeted KBS calls ran on the registered Community
profile through the Go `probe-ohlcv` command. These were metered probes, not
ingestion jobs; the probe uses `live.Gateway.Call`, and the probe responses
were not imported into PostgreSQL.

The database already contains 495 completed, full-range KBS raw landings for
2018-10-01 through 2026-10-16, including all 16 partial-history tickers. A
read-only join of their archived frames to the 14,466 unique VCI
`ZERO_VOLUME_UNVERIFIED` issue dates found 23 KBS-positive rows and no KBS-zero
rows. All 23 positive dates already have a positive VNDIRECT or DNSE bar;
KBS adds no unique positive issue date, while one of the 24 alternate-positive
dates has no KBS row. The other 14,443 issue dates have no KBS row, which does
not establish a no-trade result. A durable ingestion selection run found no
unattempted KBS jobs for the partial tickers and made no market-data calls; it
refreshed the persisted quota snapshot only. KBS landings remain raw archives
and have not been materialized in `core.bars_daily_sources`.

## NAS, 2020-10-15

One KBS request for NAS from 2020-10-14 through 2020-10-15 returned two rows.
The requested final row is 2020-10-15, with open/high/low/close 26.93 and
volume 80. The saved probe summary includes the target row, requested source,
date range and provider attribution.

The local partial-history export for the same issue date shows:

| Source | Volume | Close | Price basis recorded locally |
| --- | ---: | ---: | --- |
| VCI | zero-volume issue; no positive canonical bar | — | — |
| VNDIRECT | 80 | 29 | unadjusted |
| DNSE | 80 | 26.9294 | unknown |
| KBS probe | 80 | 26.93 | not yet classified in a stored series |

This is positive-volume agreement across three non-VCI providers for one
VCI issue date. The HNX public report lookup for this historical date returned
an empty result, so this is provider corroboration rather than exchange
confirmation. Do not use the KBS probe to clear other dates, to change the
VCI canonical bar, or to treat a missing KBS row as proof of no execution.

Probe summary: `2026-10-18-NAS-173923.927584400Z.json`
SHA-256: `3172E2FB40F2E9CE3D0A3E9E1F3C5AB23B5B83A90B4FFE003EECBFABD382F2B2`

Local comparison: `../phase1-partial-audit/issue-coverage.csv`, NAS row for
2020-10-15; the export's row-level provenance and checksum are documented in
that audit's README.

## FPT, 2024 cash-dividend event

Two successful KBS default OHLCV probes (`raw_prices=false`) returned the FPT
close on each side of the 2024-12-02 ex-right date. The KBS close return is
108.88 / 109.72 - 1 = -0.7656%, matching the dividend-adjusted branch. The
local raw VNDIRECT closes are 144.3 and 142.2; its adjusted closes are 109.658
and 108.813. VCI closes are 109.66 and 108.81; DNSE closes are 109.65 and
108.81. KBS is therefore classified `adjusted` for its default OHLC price
columns. This labels price basis; it does not resolve the historical
adjustment vintage needed for point-in-time training.

| Report | Target row | SHA-256 |
| --- | --- | --- |
| `2026-10-18-FPT-175244.714413300Z.json` | 2024-11-29 close 109.72; volume 11,586,700 | `0F6DCEF11387E2322A423105C701A63C6824B6344ABF977FF59020FBEC89CF17` |
| `2026-10-18-FPT-175216.125444000Z.json` | 2024-12-02 close 108.88; volume 6,616,800 | `5F85E5A8221880870A56924892361E6B017889A5D9C120A516DE47C4312AED39` |

## KBS range and freshness sample

The full-range GGG request for 2018-10-01 through 2026-10-16 returned 380 rows,
first 2018-10-12 and last 2026-10-09. A separate exact-date request for
2026-10-16 returned no row. For this sample, KBS supplies useful supplemental
history but lags the final local VCI date by one week.

| Report | Result | SHA-256 |
| --- | --- | --- |
| `2026-10-18-GGG-173233.738740400Z.json` | 2026-10-16 exact-date request: zero rows | `D37C3CF78487416A9A51E8C4BCAD83DDD47D4D41D90A463B9F195C88C0BB87EF` |
| `2026-10-18-GGG-173323.901737300Z.json` | 380 rows; 2018-10-12–2026-10-09 | `03DE82CEBA5595DDC3A0464420ABE6B87594ED28F5C9459CB393CCE627FF5145` |

## Source treatment

Official vnstock v5 documentation lists `kbs` as an available Community
source for equity OHLCV. Source selection is explicit and vnstock does not
silently substitute another provider. Its source documentation warns that
adjusted prices can differ across providers after corporate actions. Store
default KBS OHLCV as source-keyed and adjusted; validate its vintage before
point-in-time use.
Sources: [vnstock source selection](https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources),
[vnstock equity OHLCV](https://www.vnstocks.com/docs/vnstock/thi-truong-market).

HNX's official UPCoM data service lists historical data products and offers a
two-week trial. Use that registered information-service route for a complete
exchange audit. Targeted attempts against the public report endpoint for NAS
on 2020-10-15, with and without quotes around the symbol, returned the same
zero-record HTML (SHA-256
`D1C3685F4F0B2CADC29CD9615F39C5309FA8CC095CC4036A16984EECDE6BDAFF`). The
response is unavailable evidence for this date, not proof of no trade. The
three saved response variants are `../phase1-hnx-kbs-reconciliation/`.
Sources: [HNX UPCoM data service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html),
[HNX service terms and technical requirements](https://www.upboard.hnx.vn/vi-vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-sgtc.html).

Phase 1 remains PARTIAL. The 14,439 unresolved zero-volume issue dates,
historical adjustment vintages, KBS materialization into its own source series,
and required current-tree CI gates remain open. No canonical bars, lifecycle
statuses or quality records changed during these checks.

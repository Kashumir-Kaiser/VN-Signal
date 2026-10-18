# EasyStock historical export cross-check

Retrieved 2026-10-19 from EasyStock's public [OHLCV download page](https://easystock.vn/easystock-download.html), which offers free single-symbol and market-wide CSV downloads and describes history from 2007 onward. The page's public ticker JSON files are the data backing its history chart/download. This is a secondary-source check; no data were written to PostgreSQL or used to replace VCI, VNDIRECT, or DNSE bars.

## Archived sample

The audit fetched one JSON history file for each of the 16 symbols in the VCI partial-history issue audit. The page labels the data OHLCV, says prices are in thousands of VND, and says updates occur after 17:30. Raw responses are preserved under [`raw/`](raw/); [`manifest.csv` (local evidence file `manifest.csv`; not published) records URL, HTTP status, response size, row count, date bounds, volume counts, and SHA-256. This captured 35,684 rows, all ending on 2026-10-16, with 23,893 positive-volume rows in the full files.

[`issue-coverage.csv` (local evidence file `issue-coverage.csv`; not published) joins the source to all 14,466 VCI zero-volume issue dates. EasyStock has a row with reported volume zero on 7,434 dates, no row on 7,032 dates, and a positive-volume row on **zero** issue dates. It therefore adds no positive matched-volume evidence. At this issue-date reconciliation stage, the unresolved count was 14,333; later exact HNX checks reduced the current activity gap to 14,314. The audit separately classifies 106 CafeF negotiated-only dates, 24 positive alternate matched-volume dates, and three HNX-confirmed zero-match sessions for SHC. Per-symbol counts are in [`symbol-summary.csv` (local evidence file `symbol-summary.csv`; not published); rerun [`reconcile_easystock.py`](reconcile_easystock.py) to regenerate the derived files from the preserved raw bytes.

## False-negative checks

| Symbol/date | Independent evidence | EasyStock row |
| --- | --- | --- |
| CDG, 2025-05-13 | HNX archived report confirms 100 matched shares | No row |
| VFC, 2026-07-03 | HNX archived report confirms one matched share | OHLC row present, volume 0 |
| NAS, 2020-10-15 | CafeF, VNDIRECT, DNSE, and KBS each report 80 shares | OHLC row present, volume 0 |
| VNX, 2026-07-28 | HNX archived report confirms 100 matched shares | OHLC row present, volume 100 |

The source misses known trades, including the one-share and 80-share observations, and the page does not document whether its `Volume` is matched volume, total volume, or an adjustment-normalized field. It also does not document the historical price-adjustment vintage. Treat positive rows as leads for validation and zero/absent rows as non-evidence; do not use this source to certify a no-trade date or to build the price series without separate adjustment checks.

## Conclusion

This public source adds broader alternate-provider coverage for these 16 tickers, but does not close the VCI zero-volume gap. Keep Phase 1 partial. No canonical bars, quality issues, lifecycle states, or quota records were changed by this audit.

## Per-symbol history-depth check

EasyStock's landing page describes history since 2007, but the VNX file in
this audit contains only 377 rows from 2025-04-10 through 2026-10-16. HNX's
official VNX issuer profile records its first UPCoM trading date as
2010-06-10. The file therefore does not provide full listing-to-date history
for VNX, despite the site-wide headline. This does not change the 2018-10
issue-date reconciliation above, but it rules out assuming uniform history
depth from the download page's general claim. See the
[HNX VNX issuer profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-vnx.html).

# EasyStock public-feed coverage probe

Probe date: 2026-10-18. The [EasyStock download page](https://easystock.vn/easystock-download-en.html)
advertises free HOSE/HNX/UPCoM OHLCV downloads, more than 700 symbols, history
since 2007, daily updates after 17:30, and prices in thousand VND. Its page
loads per-symbol JSON from `https://easystock.vn/stock-data/{SYMBOL}.json`.

## Files and coverage

Archived the full JSON response for each of the 16 UPCoM symbols in the VCI
partial-job audit: CDG, GGG, HPI, NAS, SBD, SDD, SHC, SNC, SPC, SVG, TNB, VFC,
VNI, VNX, XMC, and XPH. Together these files contain 35,684 rows: 23,893 rows
with positive volume and 11,791 with zero volume.

Matched those responses against the 14,492 deduplicated VCI issue symbol/dates
in `../phase1-partial-audit/issue-coverage.csv`. EasyStock has a row for 7,447
dates; all 7,447 report zero volume. It has no row for the other 7,045 issue
dates and reports positive volume for none of the 14,492 dates. Per-symbol row
counts, date spans, positive/zero counts, issue-date matches, and source-file
hashes are in `manifest.json` (SHA-256
`6c1724cedf549492e00f55035d6329ee1fdd680529337b4e2d27a2252f0272df`).

## What the feed can and cannot resolve

EasyStock is a useful independently archived price-history candidate, but
its zero-volume rows cannot establish that no execution occurred. For SNC on
2026-10-15, EasyStock reports volume 0, while the official HNX report records
71 shares matched in continuous trading; VNDIRECT also reports 71. The feed
therefore misses at least this odd-lot execution. Do not use its zero volume
to clear `ZERO_VOLUME_UNVERIFIED`, and do not replace exchange volume with it.

The VCI event sample is also adjusted: EasyStock reports closes 24.26 and
24.04 for 2024-09-11 and 2024-09-12, while unadjusted VNDIRECT values are 43.80
and 33.40. This indicates corporate-action adjustment in that sample, but the
endpoint does not document adjustment timing or a complete basis contract.
Keep it source-attributed and out of point-in-time training until its
adjustment and volume semantics are validated. Its positive-volume rows remain
available as candidate supplemental history; no database rows were changed.

## Evidence inventory

- `manifest.json`: 16-symbol audit summary and SHA-256 for every downloaded
  response.
- `CDG.json` through `XPH.json`: the 16 raw symbol responses listed above.
- `VCI.json`: 2,297 rows from 2017-08-03 through 2026-10-16, including the
  adjustment-event sample; SHA-256
  `d6711eee27dfa5a43a7be6cf5ce8570d30a299905ade28aa509f9fd25764af75`.
- The official HNX execution check for SNC is archived in
  `../phase1-partial-audit/hnx-snc-2026-10-15.html`.

The provider's download page and JSON endpoint are the sources for these
files. No claim is made that EasyStock is an exchange-authoritative feed or
that a zero-volume row means no trade.

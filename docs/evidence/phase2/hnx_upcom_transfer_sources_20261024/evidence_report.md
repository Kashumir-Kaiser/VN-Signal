# HNX-to-UPCoM lifecycle evidence: APP, C92, VIE

Captured from official HNX sources on 2026-10-23 UTC. Each HNX delisting notice identifies the ticker, states final HNX trading day 2022-07-15, and states delisting effective 2022-07-18. The corresponding official HNX UPCoM profile records first trade on 2022-08-03.

| Ticker | HNX notice | Notice date / id | Last HNX trade | Delisting effective | First UPCoM trade | Official UPCoM profile |
|---|---|---|---|---|---|---|
| APP | `APP_HNX_delisting_notice_2022-07.jpg` | 2022-07-05 / 2236/TB-SGDHN | 2022-07-15 | 2022-07-18 | 2022-08-03 | [HNX APP profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-app.html) |
| C92 | `C92_HNX_delisting_notice_2022-07.jpg` | 2022-07-05 / 2239/TB-SGDHN | 2022-07-15 | 2022-07-18 | 2022-08-03 | [HNX C92 profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-C92.html) |
| VIE | `VIE_HNX_delisting_notice_2022-07.pdf` | 2022-07-05 / HNX signed notice | 2022-07-15 | 2022-07-18 | 2022-08-03 | [HNX VIE profile](https://hnx.vn/vi-vn/cophieu-etfs/chi-tiet-chung-khoan-uc-vie.html) |

The E4 interval for each ticker is 2022-07-15 to 2022-08-03, matching the documented venue handoff boundaries. These records support a lifecycle/venue-transition explanation only; they do not classify the interval as a suspension or establish any missing bars. File URLs, local filenames, SHA-256 hashes, and byte lengths are in `manifest.csv`; the capture date is stated above.

## File-backed landing import preparation

`landing_stage.csv` contains the six exact source files encoded as base64, along with their manifest SHA-256 values, sizes, official URLs, ticker, and source-backed date claims. Its `retrieved_at_utc` fields use each local file's filesystem `LastWriteTimeUtc` as the staging timestamp; the original HTTP retrieval time was not recorded. `import_hnx_upcom_transfer_landings_reportclone.sql` is guarded to `vnsignal_phase2_report_20261019`, checks the embedded manifest and decoded original bytes, inserts only `raw.landings`, is idempotent by source/route/ticker/hash, and validates the resulting landing count and bytes. The SQL was prepared but not executed. It does not create lifecycle rows or bars.

## Verified report-clone import — 2026-10-24

The first attempt rolled back because quoted empty CSV document dates were rejected. The importer now explicitly treats empty document_date fields as NULL. The corrected import committed six source landings; an immediate repeat committed zero additional landings. Both executions validated source identities, original-byte SHA-256 and sizes, and exactly one matching landing per document. Logs: import_20261024.log (failed), import_retry_20261024.log (passed), import_repeat_20261024.log (passed). Target: vnsignal_phase2_report_20261019 only. No lifecycle events or market bars were created. Staging timestamps are not asserted to be original HTTP retrieval times.

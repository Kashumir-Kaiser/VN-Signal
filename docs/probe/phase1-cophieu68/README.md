# Cophieu68 limited history cross-check

Reviewed 2026-10-18 as a public cross-check for the UPCoM partial-job audit.
This folder contains source notes only; no bulk Cophieu68 price history is
retained or imported.

## Cross-check findings

- Cophieu68's SHC history page shows zero volume on 2026-09-16, 2026-09-18,
  and 2026-09-21. The archived official HNX reports independently show zero
  matched volume on all three dates. Treat HNX as the evidence for those
  sessions; the third-party zeroes are corroboration only.
- Cophieu68's SNC history page shows zero volume on 2026-10-15, while the
  official HNX report records 71 shares matched in continuous trading and the
  VNDIRECT landing reports 71. The public page therefore misses this known
  odd-lot execution. Its zero volume cannot classify a date as no-trade.
- Cophieu68's download page advertises adjusted history since 2000 through an
  AmiBroker script. The script's current `_amibroker.php` check and download
  endpoints returned HTTP 404 when checked on 2026-10-18.

## Source-use limit

The site's terms prohibit copying, republication, distribution, or derivatives
without explicit consent, with a limited exception for a small number of pages
used for internal information. Do not bulk scrape, archive, or train on its
history unless the provider grants permission. The history page also does not
document point-in-time adjustment semantics or whether volume includes every
odd-lot execution.

## Sources

- [Cophieu68 SHC history](https://cophieu68.vn/quote/history.php?id=SHC)
- [Cophieu68 SNC history](https://cophieu68.vn/quote/history.php?id=SNC)
- [Cophieu68 download page](https://cophieu68.vn/download/ami.php)
- [Cophieu68 terms of use](https://cophieu68.vn/terms.php)
- [HNX UPCoM daily report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM)
- The archived official SNC report and SHC reports are documented in
  [`phase1-partial-audit/README.md`](../phase1-partial-audit/README.md).

No PostgreSQL rows, VCI quality statuses, or alternate-source projections were
changed by these checks.

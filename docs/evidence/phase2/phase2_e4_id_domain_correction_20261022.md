# E4 identifier-domain correction — 2026-10-22

Target: disposable report clone `vnsignal_phase2_report_20261019`. This is a
read-only correction to the E4 diagnostics. No raw, core, or feature rows were
modified.

## Cause of the earlier misattribution

The earlier source-attribution CSV and TSB bar-check output are superseded.
They joined `core.symbols.symbol_id` values to
`core.security_master.security_id` values, which are separate identifier
domains. Lifecycle evidence, bars, source-archive rows, and Phase 2 features
reference `core.symbols`; security observations reference
`core.security_master` instead. The old output therefore attached the PTM
lifecycle rows to KTL and the CTR lifecycle row to TSB. The old files are
retained with `.superseded` in their names. The gap query's observation count
was also corrected to cross the domains by ticker.

The report clone's current ticker map is `264=CTR`, `668=KTL`, `972=PTM`, and
`1279=TSB`. Re-running the corrected lifecycle attribution shows four rows:
CTR evidence ID 6 references a CTR landing; PTM evidence IDs 3, 4, and 5
reference PTM landings. No KTL or TSB lifecycle records are present in this
subset. See [`corrected lifecycle attribution`](phase2_lifecycle_source_attribution_20261022.csv)
and its [`SQL`](phase2_lifecycle_source_attribution_20261022.sql).

## Corrected continuity findings

The corrected gap CSV still contains 221 feature gaps. It classifies 219
intervals across 1,539 effective sessions as having no daily bars and no
source-archive rows; no dated security observations cover them. Their cause
remains unresolved.

The other two intervals are supported by ticker-matched lifecycle evidence:

- **CTR:** six effective sessions from 2022-02-15 through 2022-02-22 are
  covered by HNX lifecycle evidence. The HNX notice says the last UPCoM session
  was 2022-02-14 and registration was cancelled 2022-02-15. CTR's first HOSE
  session was 2022-02-23, also recorded by the issuer in a document hosted by
  HOSE ([issuer document](https://staticfile.hsx.vn/Uploads/News/60135bc5b7e546558ef35a5bdced90c5/20250418_20250417%20-%20CTR%20-%20Nghi%20quyet%20DHDCD%20thuong%20nien%202025%20kem%20Bien%20ban%20va%20tai%20lieu%20%28TV%20va%20TA%29.pdf)).
  There are five VCI rows inside that interval in `core.bars_daily`, but none
  in `core.bars_daily_sources` and none in either feature version. The raw VCI
  landing repeats the exact OHLCV tuple `88.6/88.6/86.2/87/729829` on
  2022-02-16, 17, 18, 21, and 22. Those rows are not treated as valid trades:
  their dates are inside the documented venue gap, and their values repeat the
  final UPCoM source row. This is a VCI input anomaly to investigate in source
  reconciliation; the Phase 2 feature table excludes the rows.
- **PTM:** 1,680 effective sessions from 2018-11-28 through 2025-08-21 are
  covered by PTM-matched UPCoM delisting evidence. Trade eligibility resumes
  on 2025-08-22.

The exchange-notice landing URL for CTR is recorded in
[`corrected lifecycle attribution`](phase2_lifecycle_source_attribution_20261022.csv)
and its payload hash is retained there. The corrected bar and raw-landing
details are in [`CTR transition rows`](phase2_ctr_lifecycle_bar_check_20261022.csv)
and [`their query`](phase2_ctr_lifecycle_bar_check_20261022.sql).

## Status

The CTR and PTM gaps are explained by venue/lifecycle history; the stale KTL
and TSB mismatch claims are withdrawn. E4 remains incomplete because 219 other
gaps have no source or lifecycle explanation. Corrected gap counts and the
ticker-crosswalked observation column are in
[`corrected gap attribution`](phase2_integrity_gap_attribution_20261022.csv)
and [`its SQL`](phase2_integrity_gap_attribution_20261022.sql).

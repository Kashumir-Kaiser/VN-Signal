# Phase 2 gate status after full rank repair — 2026-10-22

> Historical snapshot as of 2026-10-22. E2 and E3 completed on 2026-10-23, and
> E5 has separate repeat-build evidence; use the current status in
> [`BUILD_STATUS.md`](../../BUILD_STATUS.md) for Phase 2 readiness. E4's 219
> unexplained continuity gaps remain open.

Phase 2 is **not ready for sign-off**. This status follows the Master Build
Spec and the Phase 2 recovery checklist. It applies to the disposable report
clone and current local verification only.

| Gate | Status | Evidence / reason |
| --- | --- | --- |
| E1 — real V3 null rates | **REPORT PRODUCED; attribution open** | 73 of 88 measured features exceed the lookback-only expectation; 15 are within and 13 are source-unverified. The source audit confirms that this expectation omits traded-row, full-window, adjustment-episode, and shared-series availability rules. The null-rate report is produced; per-feature NULL attribution remains open. See [`current E1 report`](null_rates_full_rank_repaired_20261022.md), [`E1 model audit`](phase2_e1_null_model_audit_20261022.md), and [`CSV`](null_rates_full_rank_repaired_20261022.csv). |
| E2 — real-data leakage | **INCOMPLETE / no result** | The three-cut run passed its 60-symbol selection and began the first cut's full-history feature rebuild, but was stopped after 28.5 minutes before any comparison. See [`real-data attempt report`](phase2_e2_real_attempt_20261022.md) and [run log](phase2_e2_real_20261022_retry2.log). |
| E3 — real-data feature parity | **INCOMPLETE / no result** | Real-data attempts were interrupted during sample selection or point-in-time history loading; no 20-row SQL/Rust comparison completed. See [`rank-recovery checkpoint`](phase2_rank_recovery_checkpoint_20261022.md) and [`latest attempt log`](phase2_e3_real_parity_20261022.log). |
| E4 — real-data integrity | **INCOMPLETE** | 97 monthly slices pass row count, key, feature hash, session membership, and repaired-rank checks. Corrected ID-domain diagnostics explain the CTR and PTM lifecycle gaps; 219 other intervals still have no daily bars, source-archive rows, or lifecycle evidence. Five VCI rows inside CTR's exchange transition are a source anomaly and are absent from V2/V3. See [`rank-repaired E4 report`](phase2_integrity_report_rank_repaired_summary_20261022.md) and [`identifier-domain correction`](phase2_e4_id_domain_correction_20261022.md). |
| E5 — reproducibility | **PASS, one label chunk** | The 2023 label chunk was rebuilt twice with identical input and output hashes. See [`label recovery evidence`](phase2_label_recovery_20261022.md). |
| Local checks | **PASS** | Go tests, Go vet, 27 Python tests, and the fresh two-pass PostgreSQL migration harness pass. The SQL migration harness includes migration 056 and the date-bound regression assertion. Logs use `datefilter_20261022` under `docs/evidence/phase2/`. |
| Hosted CI | **NOT RUN** | No hosted CI run is recorded. |

The 97-month rank repair is complete for 2,844,435 rows in each feature version.
The current feature-set hash is `f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.
Rank values are in range, finite where required, NULL when their mapped inputs
are NULL, and present when mapped inputs are available.

Phase 2 also requires PIT-fundamentals coverage and verified sources for the
remaining source-dependent fields. Thirteen fields remain source-unverified,
E1 fails, real E2 and E3 are unrun, E4 has unresolved continuity gaps, and
hosted CI is unrun. Do not enable suggestions or report Phase 2 complete while
these gates remain open.

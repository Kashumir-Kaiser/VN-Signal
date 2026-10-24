# Phase 2 recovery checkpoint — 2026-10-22

> Historical checkpoint. The full feature and label builds subsequently
> completed; real E2 and E3 passed on 2026-10-23, and the rank-repaired E4
> report was produced. See [`BUILD_STATUS.md`](../../BUILD_STATUS.md) for the
> current Master Spec gate result and remaining E4/data-quality follow-up.

Scope: the disposable report clone `vnsignal_phase2_report_20261019` and disposable migration database `vnsignal_phase2_ci_20261022_v4_test`. No registered `vnsignal` data was changed and no live vnstock/fundamentals calls were made.

## Build and migration result

Build `phase2-vci-full-rebuild-20261021` has eight completed feature chunks through 2025-12-31 (2,552,145 rows), one failed 2026 chunk, and nine pending label chunks. See [`chunk state`](phase2_feature_chunk_state_20261022.csv) and the [`failed build log`](phase2_build_phase2-vci-full-rebuild-20261021.failed.20261021-235301.log). A previous full-history V3/label snapshot exists, but it predates the VCI correction and is not current acceptance evidence.

The fresh two-pass PostgreSQL 18.3 harness passed after the V3 eligibility change and migration 045; its success marker is [`here`](phase2-migration-harness-v4-20261022.log). Migration 045 also patched the old builder on the disposable report clone ([`upgrade log`](phase2_apply_045_symbol_eligibility_20261022.log); the set-based join marker was verified). The migration 044 real-data backfill was canceled twice, the second run at 10 minutes, and rolled back. Its `EXPLAIN` plan estimates a scan of 2.88 million rows in a 3.55 GB feature table. The clone therefore does not have migration 044's VCI index-feature backfill. See [`retry log`](phase2_apply_044_vci_retry_20261022.log).

The recovery prompt's fallback—a full-universe last-400-session slice plus a 60-symbol real-data subset—was not run because migration 044's corrected VCI values were not materialized. This is an explicit incomplete deviation; Phase 2 is not conditionally complete.

## Acceptance evidence

| Gate | Status | Evidence and scope |
| --- | --- | --- |
| E1 null rates | NOT RUN on corrected current V3; prior full-history report fails its 1 percentage-point count (79/88 fields outside tolerance) | [`prior report`](null_rates_full_20261021.md), [`CSV`](null_rates_full_20261021.csv). It predates VCI correction; the current E1 diagnostic must be rerun after correction and eligibility analysis. |
| E2 future perturbation | NOT RUN on real data | Synthetic fixture leakage assertions passed in the migration harness; they do not cover the 60-symbol, three-cut real-data test. |
| E3 SQL/Rust parity | NOT RUN on real data | [`prior attempt`](parity_fresh_rebuild_20261021.md) timed out during adjustment-cache preparation before comparisons. Rust offline tests pass; PostgreSQL parity was skipped. |
| E4 integrity | NOT RUN | [`CSV output`](phase2_integrity_report_20261022.csv) contains no metrics; [`log`](phase2_integrity_report_20261022.log) records the five-minute statement timeout. |
| E5 reproducibility | NOT RUN | Chunk hashes exist, but no real chunk was rebuilt twice and compared. See [`chunk state`](phase2_feature_chunk_state_20261022.csv). |
| CI | NOT RUN hosted; local checks PASS | PostgreSQL 18.3 migration harness, Go tests/vet/race, 27 Python tests, Rust format/tests/clippy passed. Logs: [`Go test`](go_test_20261022.log), [`Go vet`](go_vet_20261022.log), [`race retry`](go_race_20261022_retry.log), [`Python`](python_tests_20261022.log), [`Rust`](rust_checks_20261022.log). The first race invocation lacked `VNPIPE_PYTHON`; see [`initial attempt`](go_race_20261022.log). |

The PIT fundamentals overlay remains incomplete: 2018–2021 chunks produced zero rows, the 2022 input-hash chunk was canceled, 2023–2026 are pending, and no live fundamentals calls were made. Source-unverified features remain NULL by design.

## Readiness

Phase 2 is **not ready for sign-off**. Master Build Spec §13 requires green leakage and feature-parity tests plus a null-rate report. The recovery gates additionally require real E2/E3 evidence, current integrity metrics, and repeated output hashes. Full-history features and labels must be rebuilt against the corrected VCI contract before those results can be accepted.

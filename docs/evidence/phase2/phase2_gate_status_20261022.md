# Phase 2 gate status — 2026-10-22

Phase 2 is **not ready for sign-off**. The Master Build Spec defines Phase 2 as
SQL features, labels, and the point-in-time fundamentals archive, with leakage
and feature-parity tests green and a null-rate report produced. The recovery
checklist adds the explicit E1–E5 integrity/reproducibility evidence and CI
gates.

| Gate | Status | Evidence / reason |
| --- | --- | --- |
| E1 — real V3 null rates | **FAIL** | 73 of 88 measured fields exceed the 1pp threshold. See [E1 report](null_rates_full_20261022.md) and [CSV](null_rates_full_20261022.csv). |
| E2 — real-data leakage | **NOT RUN** | Synthetic fixture leakage assertions pass in the [v9 harness](phase2-migration-harness-v9-20261022.md); the required 60-symbol, three-cut future-input perturbation has no completed result. |
| E3 — real-data feature parity | **NOT RUN** | The 20-row real attempt was interrupted after 772.65 seconds in the per-symbol point-in-time history loader. See [attempt report](parity_real_20261021.md) and [log](parity_real_20261021.log). The new local Rust run had no `DATABASE_URL`, so its PostgreSQL integration case skipped. |
| E4 — real-data integrity | **NOT RUN** | The full diagnostic hit its five-minute statement timeout and returned no metrics. See [timeout log](phase2_integrity_report_20261022.log); its CSV contains only the header. |
| E5 — reproducibility | **PASS, one chunk** | The 2023 label chunk was rebuilt twice with identical input and output hashes. See [label recovery evidence](phase2_label_recovery_20261022.md). |
| Local checks | **PASS** | Go tests, vet, race; 27 Python tests; Rust fmt, tests, clippy; fresh two-pass PostgreSQL 18.3 migration harness v9. The first Go-test invocation used the Windows Store Python alias; rerunning with `.venv/Scripts` on `PATH` passed. |
| Hosted CI | **NOT RUN** | No hosted run is recorded. Local fixture results do not substitute for hosted CI. |

Current V3 coverage is 2,844,435 feature rows and 5,688,870 label rows across
2018-10-01–2026-10-16. The fundamentals archive's required point-in-time
coverage is not yet evidenced as complete. The next work is to diagnose the
traded-row E1 gaps, implement or optimize bounded real-data E2/E3/E4 evidence,
verify PIT fundamentals coverage, and then run hosted CI. Do not enable
suggestions or report Phase 2 as complete while these gates remain open.

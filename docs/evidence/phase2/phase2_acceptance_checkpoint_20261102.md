# Phase 2 acceptance checkpoint — 2026-11-02

This matrix records the current recovery-prompt E1–E5 checklist alongside the
fixture-only CI gate. It does not override the Master Build Spec §13 Phase 2
exit criteria: a real null-rate report, passing leakage test, and passing
feature-parity test. The PIT fundamentals archive is also a Phase 2
deliverable.

| Gate | Status | Current evidence and limitation |
| --- | --- | --- |
| E1 — current-hash null-rate report | **PASS — report produced** | [2026-10-29 report](phase2_current_hash_null_rates_full_20261029.md), for 2,844,435 rows / 1,518 symbols at hash `28089ed1…`. It records 73/88 measured fields outside the lookback-only 1 pp diagnostic and 13 source-unverified fields; these flags are reported, not all confirmed as defects. |
| Full current-hash labels and targets | **PASS — durable build complete** | The [post-refresh integrity audit](phase2_postrefresh_label_integrity_20261101.log) confirms 97/97 month-aligned chunks, 5,688,870 labels, 3,161,496 READY rows, and feature hash `28089ed1…`. The [target/weight audit](phase2_execution_weight_target_integrity_post109_20261101.log) finds no missing target among READY labels. The 225 remaining NULL execution weights are confined to 2018 rows outside the eligible/investable cohort; see the current target-side census below. |
| E2 — real-data leakage | **PASS — scoped cohort** | [Post-migration-109 report](phase2_e2_currenthash_post109_20261101.md): 60 symbols across three cut dates; zero pre-cut feature, completed-label, and label-boundary mismatches. Rank perturbation is limited to that selected cohort. |
| E3 — feature parity | **PASS — sampled real rows and recursive golden** | [Current-hash report](phase2_e3_currenthash_20261029.md): 20 source-attributed symbol-days matched the Rust/Polars reference at `1e-9`; recursive Rust and SQL golden evidence is linked there. |
| E4 — integrity and continuity | **PASS — all gaps are documented** | The [97-chunk integrity report](phase2_e4_integrity_report_currenthash_20261029.csv) covers the full 2,844,435-row current-hash feature set and records zero duplicate-key groups and zero rank range failures. The updated [E4 continuity report](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_postgdw_20261102.md) records 219 strict transfer matches / 1,539 sessions and two separately documented CTR/PTM lifecycle intervals / 1,686 sessions; no other intervals remain unresolved. GDW event 292 is backed by official HNX Notices 1385/TB-SGDHN and 1458/TB-SGDHN. The final UPCoM session was 2018-12-06, cancellation was effective 2018-12-07, and first HNX trading was 2018-12-18. The HNX daily report records zero matched volume on Dec 6; no individual intervening session status is inferred. See the [GDW source and import packet](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/README.md), [gap census CSV](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_gap_pairs_20261102_postgdw.csv), and [endpoint audit CSV](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_feature_endpoint_semantics_20261102_postgdw.csv). |
| E5 — repeatability | **PASS — one full year** | The [post-BSC read-only recheck](phase2_e5_repeatability_after_bsc_20261101.log) matched the two independent 2023 builds across all 12 months. Both durable year hashes remain `9492d3cd…`; the canonical content hash remains `320159a4…`. |
| Phase 3 rank-target readiness | **PASS — explicit exclusions preserved** | The [current-hash target census](phase2_phase3_training_target_readiness_20261102.log) records 716,739 eligible/investable, tiered, ranked targets with non-null execution weights, before the migration-059 250-session source-gap cooldown. It finds zero missing weights in that cohort and no non-null volatility score without a target rank. The 225 NULL weights are all 2018, where eligible/investable target count is zero. It also identifies 5,776 retained members without a tier and 152 tiered rows without `realized_vol60`; their tier/rank fields remain NULL rather than being imputed. |
| PIT fundamentals archive | **PASS — current investable L1/L2 scope** | The [post-backfill census](phase2_fundamentals_pit_coverage_20261101.md) records 114,293 archive-managed line-item versions for all 159 current `is_investable_member` symbols (100 L1, 59 L2) across all six statement/frequency groups; availability and observation lineage checks report zero violations. This is not archive coverage for all 1,518 feature-universe symbols. Line-item/industry mappings and overlay rows remain zero, so model B stays disabled. |
| Local fixture/test gates | **PASS — rechecked 2026-11-02** | Current [Go tests](phase2_resume_acceptance_20261102_go_test.log), [Go vet](phase2_resume_acceptance_20261102_go_vet.log), and [Python tests](phase2_resume_acceptance_20261102_python_unittest.log) pass; Python reports 47 tests. The current Go tree also passed [Go race](phase2_20261101_post109_go_test_race.log), [Rust format](phase2_20261101_post109_rust_fmt.log), [Rust workspace tests](phase2_20261101_post109_rust_test.log), [Rust Clippy](phase2_20261101_post109_rust_clippy.log), and the [fresh two-pass PostgreSQL migration harness](phase2_109_full_migration_harness_20261101.log); only evidence and documentation have changed since those runs. |
| Fundamental batch-cap fix local checks | **PASS — current Go/Python tree** | The [Go suite](phase2_20261101_fundamental_batchfix_go_test_final2.log), [Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_batchfix_python_unittest_final.log) pass after changing the one-call pacer to preflight the unfinished batch against durable remaining quota. |
| Fundamental job-state preflight fix | **PASS — current Go/Python tree** | The [full Go suite](phase2_20261101_fundamental_jobstate_preflight_go_test.log), [current Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_jobstate_preflight_python_unittest.log) pass. Blocked, actively leased, or unknown durable states now stop a batch before dispatch; expired leases are resumable. |
| Fundamental response diagnostics fix | **PASS — current Go/Python tree** | The [Go suite](phase2_20261101_fundamental_error_diagnostics_go_test.log), [Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_error_diagnostics_python_unittest.log) pass after exposing only allowlisted/sanitized adapter failure details and suppressing vendor messages. |
| Fixture-only CI / hosted PostgreSQL 16 | **PASS for code candidate `a4b4497`** | GitHub Actions [run 165](phase2_github_actions_a4b4497_20261102.md) and [run 166](https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/41335878890) passed all Go, Python, PostgreSQL 16, and Rust jobs on exact code SHA `a4b4497a10459f852e7a499e1e3f0a03686f7374`. Later changes are source evidence and documentation; hosted CI will rerun on the updated branch commit. |

See the [post-migration-109 local validation summary](phase2_20261101_post109_validation_summary.md)
for exact command results and environment notes.

## Phase 3 entry contract and deferred optional scope

Phase 3 must start from `feat.phase2_training_eligible_v3` (migration 059) or a
proven equivalent, then join the current-hash target rows. Tier-ranked heads
must require `membership_gate_status='ELIGIBLE'`, `is_investable_member`, a
non-NULL `liquidity_tier`, `target_uniform_rank`, and `execution_weight`.
Head-specific raw-return training must define its own eligibility and must not
impute missing rank inputs. The target-side counts above are before the
migration-059 rolling-gap cooldown. The disposable report clone lacked the
read-only migration-059 views; the exact repository migration was applied to
that clone for view setup only. A full scan through that view was skipped under
the machine's memory limit; its target-side rules and current-hash counts are
recorded separately.

The 225 NULL execution weights stay quarantined and are not Phase 3 training
rows: all are 2018 labels with zero eligible/investable targets. Keep their
weights NULL. The 5,776 retained members without a tier and 152 tiered rows
without realized volatility likewise remain unranked; do not infer or impute
their tier scores. These rows do not enter the tier-ranked Phase 3 head.

The PIT archive covers the 159 symbols marked investable in the latest
current-hash L1/L2 cohort with zero availability or lineage violations. The
other 1,359 feature-universe symbols are outside that archive run. No
line-item/industry mappings or overlay rows are approved; model B remains
disabled as the separate optional fundamentals model. The core Phase 3 trainer
can proceed without model B. Suggestions stay disabled until their later-phase
gates pass. See [the updated PIT census](phase2_fundamentals_pit_coverage_20261101.md).

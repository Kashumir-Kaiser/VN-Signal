# Phase 2 acceptance checkpoint — 2026-11-01

This matrix records the current recovery-prompt E1–E5 checklist alongside the
fixture-only CI gate. It does not override the Master Build Spec §13 Phase 2
exit criteria: a real null-rate report, passing leakage test, and passing
feature-parity test. The PIT fundamentals archive is also a Phase 2
deliverable.

| Gate | Status | Current evidence and limitation |
| --- | --- | --- |
| E1 — current-hash null-rate report | **PASS — report produced** | [2026-10-29 report](phase2_current_hash_null_rates_full_20261029.md), for 2,844,435 rows / 1,518 symbols at hash `28089ed1…`. It records 73/88 measured fields outside the lookback-only 1 pp diagnostic and 13 source-unverified fields; these flags are reported, not all confirmed as defects. |
| Full current-hash labels and targets | **PASS — durable build complete** | The [post-refresh integrity audit](phase2_postrefresh_label_integrity_20261101.log) confirms 97/97 month-aligned chunks, 5,688,870 labels, 3,161,496 READY rows, and feature hash `28089ed1…`. The [target/weight audit](phase2_execution_weight_target_integrity_post109_20261101.log) finds no missing target among READY labels; 225 weights remain NULL only for the quarantined 2018 limit-evidence conflict. |
| E2 — real-data leakage | **PASS — scoped cohort** | [Post-migration-109 report](phase2_e2_currenthash_post109_20261101.md): 60 symbols across three cut dates; zero pre-cut feature, completed-label, and label-boundary mismatches. Rank perturbation is limited to that selected cohort. |
| E3 — feature parity | **PASS — sampled real rows and recursive golden** | [Current-hash report](phase2_e3_currenthash_20261029.md): 20 source-attributed symbol-days matched the Rust/Polars reference at `1e-9`; recursive Rust and SQL golden evidence is linked there. |
| E4 — integrity and continuity | **PARTIAL** | The [97-chunk integrity report](phase2_e4_integrity_report_currenthash_20261029.csv) covers the full 2,844,435-row current-hash feature set and records zero duplicate-key groups and zero rank range failures. The latest [E4 continuity census](phase2_e4_currenthash_posttielcm1_20261031.md) reports 218 strict transfer matches / 1,532 sessions and three non-matches / 1,693 sessions: the separately supported CTR and PTM lifecycle cases / 1,686 sessions, plus the unresolved seven-session GDW interval. No gap-session status is inferred. The [2026-11-01 HNX disclosure recheck](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_disclosure_search_20261101/capture_manifest.json) found no cancellation or final-trade notice. A subsequently captured [official HNX 2018 annual report](phase2_e4_remaining_gap_probe_20261031/gdw_hnx_2019_annual_report_capture_20261101/capture_manifest.json) corroborates the listing history but does not state the final UPCoM session; see the [source review](phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md). |
| E5 — repeatability | **PASS — one full year** | The [post-BSC read-only recheck](phase2_e5_repeatability_after_bsc_20261101.log) matched the two independent 2023 builds across all 12 months. Both durable year hashes remain `9492d3cd…`; the canonical content hash remains `320159a4…`. |
| PIT fundamentals archive | **PASS — current investable L1/L2 scope** | The [post-backfill census](phase2_fundamentals_pit_coverage_20261101.md) records 114,293 archive-managed line-item versions for all 159 current `is_investable_member` symbols (100 L1, 59 L2) across all six statement/frequency groups; availability and observation lineage checks report zero violations. This is not archive coverage for all 1,518 feature-universe symbols. Line-item/industry mappings and overlay rows remain zero, so model B stays disabled. |
| Local fixture/test gates | **PASS — rechecked 2026-11-02** | The current Go tree passes [Go tests](phase2_20261102_resume_retry1_go_test.log) and [Python tests](phase2_20261102_resume_retry1_python_unittest.log) (47 tests) using the project Python 3.12.10 virtual environment. [Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log) passed after the last Go source change on 2026-11-01; no Go code changed afterward. [Go race](phase2_20261101_post109_go_test_race.log), [Rust format](phase2_20261101_post109_rust_fmt.log), [Rust workspace tests](phase2_20261101_post109_rust_test.log), [Rust Clippy](phase2_20261101_post109_rust_clippy.log), and the [fresh two-pass PostgreSQL migration harness](phase2_109_full_migration_harness_20261101.log) passed on the same code tree; only documentation has changed since. |
| Fundamental batch-cap fix local checks | **PASS — current Go/Python tree** | The [Go suite](phase2_20261101_fundamental_batchfix_go_test_final2.log), [Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_batchfix_python_unittest_final.log) pass after changing the one-call pacer to preflight the unfinished batch against durable remaining quota. |
| Fundamental job-state preflight fix | **PASS — current Go/Python tree** | The [full Go suite](phase2_20261101_fundamental_jobstate_preflight_go_test.log), [current Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_jobstate_preflight_python_unittest.log) pass. Blocked, actively leased, or unknown durable states now stop a batch before dispatch; expired leases are resumable. |
| Fundamental response diagnostics fix | **PASS — current Go/Python tree** | The [Go suite](phase2_20261101_fundamental_error_diagnostics_go_test.log), [Go vet](phase2_20261101_fundamental_error_diagnostics_go_vet.log), and [Python suite](phase2_20261101_fundamental_error_diagnostics_python_unittest.log) pass after exposing only allowlisted/sanitized adapter failure details and suppressing vendor messages. |
| Fixture-only CI / hosted PostgreSQL 16 | **PRIOR SHA PASS — CURRENT TREE NOT COVERED** | GitHub Actions run [162](phase2_github_actions_run_162_20261101.md) passed all Go, Python, and PostgreSQL 16 jobs for committed SHA `c65adf6edc2b722999d38aa1dcc23c8832875faa`, including the migration harness and PostgreSQL-tagged integration race suite. That hosted result predates this candidate tree; CI on the current tree is still pending. |

See the [post-migration-109 local validation summary](phase2_20261101_post109_validation_summary.md)
for exact command results and environment notes.

## Phase 2 items still open

- PIT archive coverage passes for all 159 symbols marked investable in the
  latest current-hash L1/L2 cohort, with zero availability or lineage
  violations. The other 1,359 feature-universe symbols are not covered by this
  archive run. No line-item or industry mappings are approved and daily overlay
  rows remain zero; keep model B disabled. See [the updated PIT census](phase2_fundamentals_pit_coverage_20261101.md).
- Of 14,866 current-hash execution windows spanning 2019-01-02, 225 remain
  null because 31 symbols' BSC closes conflict with the archived VNDIRECT bars
  (KHP's BSC close is zero). Their matching volumes and reference prices agree,
  but the close conflict leaves the VNDIRECT OHLC path unverified against the
  limit evidence. BSC reports zero matched volume for 28 of these symbols; the
  other three have positive volume and still conflict on close. They remain
  quarantined; see
  [the price-limit backfill report](phase2_bsc_price_limit_backfill_20190102_20261101.md).
- E4 continuity evidence and hosted CI for the current candidate tree remain
  incomplete. The retrieved HNX annual report confirms listing history but
  not GDW's final UPCoM session or cancellation-effective date; no date or
  session state is inferred. Suggestions stay disabled, and Phase 2 is not
  signed off.

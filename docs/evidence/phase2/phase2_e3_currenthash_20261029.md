# E3 current-hash feature parity — 2026-10-29

**Result: PASS for the current-hash candidate.** The real-data SQL/Rust test selected 20 source-attributed symbol-days spanning three dates, verified every selected row against its archived VNDIRECT payload, and confirmed that the stored V3 rows use the current feature hash. SQL values and NULL masks matched the independent Rust/Polars reference within the unchanged relative tolerance of `1e-9`.

- Feature-set hash: 28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b
- Real parity dates: 2023-04-04, 2022-10-10, and 2024-09-04
- Point-in-time source cache: 2,844,435 rows loaded in 26 bounded batches
- Polars market context: 2,059,819 rows through the latest sampled date
- Real parity result: 20 rows passed; 0 failed; process exit code 0
- The test transaction was rolled back against disposable report clone `vnsignal_phase2_report_20261019`.

## Recursive feature evidence

The recursive Rust suite passed all three tests, including the independent pandas golden series, missing/untraded-row and episode-reset behavior, and the exact prior-1,000-session year-anchor rule. The corresponding 320-row PostgreSQL recursive-builder golden ran and passed in the clean two-pass migration 094 harness. The current-hash real SQL smoke also rebuilt symbol 824 for 2023-04-04: `ema_100_ratio` was `0.0040100067402384365`, matching the independent Rust reference `0.00401000674023843651` within `1e-9`.

A separate attempt to run the synthetic SQL golden directly in the report clone was rejected before feature-building by that test's disposable-database-name guard. No changes were committed by that attempt; the clean disposable migration harness is the SQL golden evidence.

## Evidence

- Real current-hash parity output: [phase2_e3_real_parity_currenthash_20261029.log](phase2_e3_real_parity_currenthash_20261029.log)
- Rust recursive golden output: [phase2_e3_recursive_golden_currenthash_20261029.log](phase2_e3_recursive_golden_currenthash_20261029.log)
- PostgreSQL recursive SQL golden in the clean migration harness: [phase2_094_full_harness_retry_20261029.log](phase2_094_full_harness_retry_20261029.log)
- Current-hash EMA smoke: [SQL](phase2_e3_year_anchored_smoke_20261025.sql), [result](phase2_e3_year_anchored_smoke_20261025.log), and [independent Rust reference](phase2_e3_symbol824_ema100_trace_reference_20261025.rs)
- SQL golden assertion: [phase2_recursive_builder_golden.sql](../../../tests/sql/phase2_recursive_builder_golden.sql)

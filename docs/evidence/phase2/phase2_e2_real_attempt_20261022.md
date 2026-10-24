# Real-data E2 attempt — 2026-10-22

**Status: incomplete; no leakage conclusion.** The required three-cut
comparison did not finish. It ran only on the disposable report clone
`vnsignal_phase2_report_20261019`; the registered `vnsignal` database was not
used.

## Setup and run

The first invocation stopped at the database guard because migration 055's
`feat.phase2_market_inputs_scoped` function was absent from the report clone.
No cohort or feature work began in that invocation. The additive projection
function from migration 055 was then applied directly to the report clone and
verified present. See
[`the migration apply log`](phase2_migration_055_report_apply_20261022.log)
and [`the first guard failure`](phase2_e2_real_20261022_retry.log).

The second invocation materialized 2,844,683 VNDIRECT adjustment rows and
passed the 60-symbol cohort checks. The first 40% cut prepared its branch
inputs and full-market projections, then began the production feature and
label builders. The log records 2,009 sessions, 103,680 rank rows, and feature
batches of 97,567 and 19,984 rows. At 1,710.475 seconds, the test was canceled
while the perturbed branch was rebuilding V3 features. No pre-cut byte
comparison, label-boundary comparison, or cut report completed. The full
[`attempt log`](phase2_e2_real_20261022_retry2.log) preserves the notices and
cancellation context.

The SQL wraps its branch schemas and output tables in one transaction and
rolls it back. After cancellation, a read-only check found zero residual
`p2e2_*` schemas and zero active E2 statements. The attempt used a 30-minute
statement limit and a 20 GB temporary-file cap; disk space remained available.

## Replan required

The current runner places all three cuts in one long statement and repeats
full-market support work for each perturbed branch. The first cut had not
reached its comparison within 28.5 minutes. E2 remains open until the runner is
split into bounded cut checkpoints and reuses verified baseline support where
inputs are unchanged, while still perturbing every post-cut equity and index
input and checking all three cuts against the production builders.

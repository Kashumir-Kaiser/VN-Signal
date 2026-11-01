# E2 real-data performance gate — 2026-10-23

## Scope and safety

This review used only the disposable PostgreSQL report clone
`vnsignal_phase2_report_20261019`. No registered `vnsignal` database, vnstock
route, or account/device quota was accessed. The timed E2 attempts used the
then-current production feature and label builders and unchanged comparison
assertions. Migration 064 described below subsequently changes only the V2
builder's exact 250-session extrema implementation; E2 comparison logic and
assertions remain unchanged.

## Timed evidence

The strongest current-tree measurement is the 16 MB work-memory run in
[`phase2_e2_real_20261023_cohort_scoped_16mb.txt`](phase2_e2_real_20261023_cohort_scoped_16mb.txt):

| Stage | Elapsed | Result |
| --- | ---: | --- |
| Populate/finalize all 2,844,435 cached adjustment rows | 22.139 s finalization (26 population batches also logged) | Completed |
| Copy adjustment inputs to the raw snapshot | 122.364 s | Completed |
| Build snapshot key index | 29.967 s | Completed |
| PIT-stratified 60-symbol cohort selection | 24.971 s | Completed |
| Validate/copy current-hash baseline and rebuild baseline labels | 192.050 s | Completed |
| Build 40% branch and apply future perturbations | 6.816 s after branch creation | Completed; 117,551 copied input rows, 72,208 perturbed equity rows, 1,204 perturbed index rows |
| Production V2 feature rebuild in the perturbed branch | 916.142 s (15:16) until manual cancellation | Incomplete; no feature or label comparison; transaction rolled back |

An earlier indexed-input attempt reached the same production V2 insert and was
cancelled at 758.250 s (12:38), also without a comparison. The diagnostic
plan capture was canceled after 63.840 s and reports only estimates: a
48,060-row estimate, root estimated cost 42,880.7, 20 `WindowAgg` nodes, 9
`Sort` nodes, and 1 `IncrementalSort`. It provides no actual node times,
buffers, or spill data. See the [plan summary](phase2_e2_v2_plan_20261023.md)
and [plan capture](phase2_e2_real_20261023_090410_974.txt).

A separate bounded `auto_explain` attempt on the same 40% branch was canceled
at the configured 29-minute statement timeout. Its psql log ends at the V2
insert and contains no emitted analyzed plan, so it does not distinguish CPU
window processing from temporary sort I/O. See
[`phase2_e2_real_20261023_auto_explain.txt`](phase2_e2_real_20261023_auto_explain.txt).

After the integrated candidate was added, the first report-clone replay failed
because obsolete standard-deviation aggregates still depended on helper
functions scheduled for removal. Migration 064 now removes all five stale
aggregates before their transition/final functions. Its first successful
replay still failed in the real E2 baseline after 1:41: PostgreSQL's `n`
regular-expression flag prevented the CTE replacement from crossing line
breaks, and the incomplete `extrema250` projection omitted downstream columns.
The rewrite now uses the `s` flag, fails if it makes no replacement, and
asserts that the installed CTE carries `session_no`, `is_traded`, and both
extrema outputs. The corrected report-clone replay and projection check passed;
the independent extrema fixture passed before and after migration. The failed
attempts are retained in
[`phase2_moving_window_migration_current_20261023.log`](phase2_moving_window_migration_current_20261023.log),
[`phase2_e2_real_20261023_102549_688.txt`](phase2_e2_real_20261023_102549_688.txt),
and [`phase2_moving_window_rewrite_verification_20261023.log`](phase2_moving_window_rewrite_verification_20261023.log).

## Bounded operator probes

Earlier synthetic split probes tested custom moving averages and a separate
extrema/rolling join. They are diagnostic only: at 60 × 2,000 rows,
custom-average plus block-extrema was slower than native direct windows, and
the plan showed extra local reads/writes plus a join and output sort. Prefix
sum/count averages also showed no 60-symbol win. Full outputs remain in
[`phase2_v2_window_scaling_split_20261023.txt`](phase2_v2_window_scaling_split_20261023.txt)
and [`phase2_v2_window_scaling_prefix_20261023.txt`](phase2_v2_window_scaling_prefix_20261023.txt).

Migration 064 keeps native avg/stddev and carries exact trailing extrema on the
row stream with block prefix/suffix windows. Strict average/stddev parity is
preserved by using PostgreSQL's native operators. The fixture compares extrema
with native 250-row frames across NULLs, episode resets, large levels with
small variation, all-NULL inputs, and singleton inputs; it passed after the
corrected migration on the report clone. The final bounded probe is
[`phase2_v2_window_scaling_20261023.sql`](phase2_v2_window_scaling_20261023.sql):
15/30/60 symbols × 2,000 sessions, five alternating/interleaved runs per
candidate, medians, log-log row-count exponent, and full analyzed plans with
buffer and temporary-I/O summaries. Its database-name guard restricts it to
the disposable report clone; each EXPLAIN statement has a five-minute timeout.
The medians (direct/integrated) were 1,122/841 ms at 15 symbols,
2,213/1,597 ms at 30, and 4,528/3,146 ms at 60. Integrated medians were
25–31% faster; its row-count exponent was 0.952 versus 1.006 for direct
windows. All six size/variant groups reported zero temporary blocks. The full
plans and measurements are in
[`phase2_v2_window_scaling_final_20261023.txt`](phase2_v2_window_scaling_final_20261023.txt).

## Disposition

The current limiting stage remains production `build_features_v2_shared` in
the 40% branch. With the corrected migration, the current-hash baseline's
V2/V3 feature rebuild took 1:40.811 and baseline labels completed; the full
baseline stage took 4:00.206. The 40% branch copied and perturbed its inputs in
about 15 seconds, then its V2 rebuild stayed CPU-active for 12:45.856 without
reaching the V3/label stages or cutoff comparisons. It was canceled and the
outer transaction rolled back. See
[`phase2_e2_real_20261023_103110_365.txt`](phase2_e2_real_20261023_103110_365.txt).
The synthetic speedup therefore did not clear the real-data gate. Current-tree
E2 remains **NOT PASS**; no 70% or 95% comparison ran. Further production
profiling or optimization is required before spending time on another full
E2 attempt.

A bounded one-cut diagnostic then repeated the same 40% branch with
`work_mem=128MB` and JIT disabled. Its current-hash baseline completed in
3:58.300 (V2/V3 rebuild: 1:41.652; label rebuild completed). Branch setup and
future perturbation copied 117,551 equity rows and perturbed 72,208 equity plus
1,204 index rows. The V2 rebuild remained active for 20:10.797 without a stage
completion notice or comparison, then was canceled. PostgreSQL reported the
report-clone temporary-byte counter increasing from 7,472,470,202 to
8,041,232,570 bytes during this run (568,762,368 bytes); this is cumulative
database accounting while the diagnostic connection was the only active
session. The `psql` log records the cancel inside the V2 insert, exits with
status 3, and the subsequent session check is empty, so the outer transaction
rolled back. `auto_explain` did not emit an analyzed nested plan before
cancellation. This confirms lower spill growth than the earlier 16 MB/JIT-on
profile, but does not improve V2 completion or produce E2 evidence. The
diagnostic SQL and log are
[`phase2_e2_40_profile_128mb_jit_off_second_20261023.sql`](phase2_e2_40_profile_128mb_jit_off_second_20261023.sql)
and
[`phase2_e2_40_profile_128mb_jit_off_second_20261023.log`](phase2_e2_40_profile_128mb_jit_off_second_20261023.log).

The current-tree Go tests, race tests (using MSYS2 UCRT64 GCC), Go vet, all 29
Python tests, and a fresh two-pass PostgreSQL migration harness passed after
this run. The harness covered migrations 061/063/064 and the SQL assertions,
including the V2 projection and extrema fixtures; it does not establish a
real-data leakage comparison. Its log is
[`phase2_migration_harness_064regex5_20261023.log`](phase2_migration_harness_064regex5_20261023.log).
E3's earlier 20-symbol-day parity pass predates migration 064 and remains stale
until rerun against the updated builder.

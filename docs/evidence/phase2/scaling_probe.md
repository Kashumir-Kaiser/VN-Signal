# V3 feature scaling probe

Date: 2026-10-20

## Method

Ran the Phase 2 V3 internal builder for calendar year 2020 in a single transaction on the disposable full-history clone. Each sample selected the first N eligible symbols in symbol-ID order, used a 250-symbol batch size so the sample fit in one feature batch, retained the full-universe market ranks, and rolled the transaction back. The 2020 V2 population contained 1,381 symbols and 341,357 rows; the builder used 567 effective sessions including available warm-up history and ranked 113,828 complete rows.

The measured time is the `Phase 2 batch 0 feature rows` notice, which covers the feature calculation, update of the temporary output rows, and final V3 insert. Shared cache, market-context, rank, and session setup are reported separately by the builder notices. Raw output: [`scaling_probe_15_30_60.log`](scaling_probe_15_30_60.log).

## Results

| Symbols | V3 rows built | Feature batch time | Scaling exponent |
|---:|---:|---:|---:|
| 15 | 3,341 | 2.580 s | — |
| 30 | 7,111 | 5.448 s | 1.078 for 15→30 |
| 60 | 14,350 | 10.684 s | 0.972 for 30→60 |

Across 15→60 symbols, `b = ln(10.684 / 2.580) / ln(60 / 15) = 1.025`. This is below the recovery prompt's 1.3 proceed threshold. All three samples completed, and the transaction rolled back, leaving no probe V3 rows in the clone.

The first sample's shared setup took 79.7 seconds for the 2,844,435-row adjusted-price cache, 38.0 seconds for market context, and 1.94 seconds for ranks. The later samples reused the same transaction-local adjustment cache; market context and ranks were recalculated for each sample. These setup measurements are not included in the symbol-scaling exponent.

## Decision

Proceed with the full V3 feature build using the resumable year runner, 50 symbols per batch, JIT disabled, 64 MB `work_mem`, and a 30-minute statement timeout per chunk. Stop and investigate if a year chunk reaches the timeout or takes more than twice its observed estimate.

## 2026-10-24 — full-cache symbol-first eligibility probe

Migration 068 changes only how the builder finds eligible symbols. The exact
V3 eligibility predicate remains VNDIRECT source plus a finite positive
adjustment factor on a selected effective session. The rollback-only probe
loaded all 2,844,435 adjustment-cache rows in 26 bounded batches, created the
same 1,000-session warm-up plus 2020 Q1 session spine used by the builder, and
timed the symbol-first eligibility CTE with 15, 30, and 60 requested symbols.
The script and complete plans are in
[`phase2_symbol_first_eligibility_full_cache_probe_20261024.psql`](phase2_symbol_first_eligibility_full_cache_probe_20261024.psql)
and its paired `.log` file.

| Requested symbols | Eligible rows | Query time | Exponent from prior sample |
|---:|---:|---:|---:|
| 15 | 15 | 56.064 ms | — |
| 30 | 30 | 87.732 ms | 0.646 (15→30) |
| 60 | 60 | 160.823 ms | 0.874 (30→60) |

The overall exponent is `b = ln(160.823 / 56.064) / ln(60 / 15) = 0.760`.
The linear-power projection for 1,500 symbols is 1.86 seconds for this
eligibility query only. Every plan used `phase2_adjustment_rows_symbol_date_idx`
with one index lookup per requested symbol; none scanned the full cache by
date. All three transactions rolled back. This probe passes the recovery
prompt's `b <= 1.3` gate for the eligibility stage; it does not measure the
full-history V3 build.

The current-hash full-history estimate still exceeds the remaining build
allowance: the known 2019 chunk took 884.2 seconds for 326,456 output rows,
which projects about 110 minutes for the remaining 2.44 million V2 rows before
reserves. At this checkpoint the recovery prompt's stated 203-minute remainder
has about 14 minutes elapsed, giving roughly 84 minutes after its 90-minute
downstream reserve and 15-minute margin. Use the specified fallback: build and
report the full-universe last-400-session slice (2025-03-11 through 2026-10-16)
and identify it as a slice, with a full-history rebuild remaining open.

## 2026-10-24 — cache preflight memory re-probe

The 32 MB cache preflight was unstable: two runs reported adjacent exponents
1.304 and 1.672, so the existing 1.3 guard blocked the build. The 15-symbol
`EXPLAIN (ANALYZE, BUFFERS)` completed the cache insert in 628 ms. A separate
60-symbol component capture found that the wide `ordered` adjustment CTE held
108,331 rows of 253-byte tuples in a 32,769 kB disk work table, read/wrote
4,047 temp blocks, and emitted a 33,147,574-byte temporary file. The 60-symbol
populate took 2.133 s and finalization 0.514 s. The paired SQL, psql output,
and server-log capture are
[`phase2_cache_scale_plan_15_20261024.psql`](phase2_cache_scale_plan_15_20261024.psql),
[`phase2_cache_stage_components_60_20261024.psql`](phase2_cache_stage_components_60_20261024.psql),
and their corresponding `.log` files.

At 64 MB `work_mem`, the runner-equivalent warm-up and measured series passed
the unchanged assertion: 15/30/60 symbols took 566/1,134/2,786 ms; adjacent
exponents were 1.003 and 1.297, overall `b=1.150`. The cache assertion
projected 1.48 minutes for the 1,518-symbol cache against its 40-minute budget.
PostgreSQL's temp-file counters did not change during this probe. Total RAM was
3.83 GiB, with 0.42 GiB free at measurement time; this was a single-session,
64 MB probe, not a parallel build. Re-run the bounded last-400 build at 64 MB
and retain the same scaling guard. See
[`phase2_cache_scale_retry_64mb_20261024.psql`](phase2_cache_scale_retry_64mb_20261024.psql)
and its paired `.log` file.

## 2026-10-24 — last-400 build stopped in canonical input hashing

The 64 MB cache preflight passed with 15/30/60-symbol timings of
566/1,134/2,786 ms and overall exponent 1.150. The runner loaded all
2,844,435 adjustment rows, then began the first requested feature chunk
(2025-03-11 through 2025-12-31). Its canonical price-day input hash requested
1,206 dates from 2021-03-09 through 2025-12-31. The comparable 374-date hash
took 2m43s, giving a linear estimate of 8m43s and a 2x checkpoint at 17m26s.

The runner recorded failure at 05:00:30, before the feature SQL statement
started. The PostgreSQL backend remained active after the psql client stopped;
`pg_stat_activity` showed the exact `phase2_features` backend waiting on
`IO:DataFileRead` with 26m49s query age. An explicit `pg_cancel_backend` call
returned true, and a follow-up query for that PID returned no row by 05:11
local. No V3 feature rows were committed and the last-400 slice was not built.
The measured hash exceeded 3x its estimate, so the same build was not retried.
The [runner failure log](phase2_build_phase2-e1-e5-v3-068-20261024-last400.failed.20261024-050030.log)
and [backend cancellation record](phase2_last400_hash_overrun_20261024.md)
preserve the outcome. Replan the hash aggregate and reusable date-hash staging
before resuming this slice; full-history V3 and current-hash E1 remain open.

## 2026-10-25 — runner-equivalent S2 rank scaling

Migration 088 adds a 139 MB partial covering index for the V2 fields consumed
by cross-sectional ranks. It changed the 120-session plan from a wide-table
bitmap heap scan with 24,627 heap blocks to an index-only scan with 3,471 heap
fetches; the measured plan took 3.50 seconds. The index is recorded on the
disposable report clone and in the forward migration.

The accepted read-only probe warmed the largest range before timing all three
sizes, used the feature runner settings (`work_mem=32MB`,
`random_page_cost=1.1`, `effective_io_concurrency=16`, no parallel query, and
JIT off), and ran three trials per size. Medians were 1.048837 s for 30
sessions, 1.817660 s for 60, and 3.917864 s for 120. Adjacent exponents were
0.793292 and 1.107985, both below 1.3. The SQL and log are
[`phase2_s2_rank_stage_runner_settings_20261025.sql`](phase2_s2_rank_stage_runner_settings_20261025.sql)
and
[`accepted warm-first result`](phase2_s2_rank_stage_coveridx_rewarmed_20261025.log);
the index-only plan is in
[`phase2_s2_rank_stage_explain_coveridx_20261025.log`](phase2_s2_rank_stage_explain_coveridx_20261025.log).
The earlier 16 MB/zero-prefetch probe and the first custom run with warm-up
after the 30/60 samples are not accepted scaling evidence. This closes the S2
scaling probe only. The complete current-hash V3 feature range was subsequently
rebuilt through 2026-10-16; the remaining E1–E5 gates are still open.

## 2026-10-25 — current-builder S1 V3 feature scaling

The V3 builder was run for calendar year 2020 on the disposable report clone,
using the first 15, 30, or 60 eligible V2 symbols in deterministic symbol-ID
order. All samples retained the full-universe market context and ranks, used
the feature runner's 15-symbol input batches and 5-symbol compute batches,
and rolled output transactions back. The scaling measure is the sum of the
builder's `Phase 2 batch N feature rows` timings; it excludes the shared
session, market-context, and rank stages because those are not symbol-local
feature work. Three measured trials completed at each size. The initial SQL
script omitted the third 60-symbol trial, so a separate rollback-only script
refilled the same bounded adjustment cache, warmed 60 symbols, and ran that
missing replicate. The accepted fixed 90-sample adjustment-cache calibration
is recorded separately in
[`phase2_cache_guarded_90_after_migration087_20261025.log`](phase2_cache_guarded_90_after_migration087_20261025.log).

| Symbols | V3 rows | Feature-batch median | Adjacent exponent |
|---:|---:|---:|---:|
| 15 | 3,341 | 10.085 s | — |
| 30 | 7,111 | 15.141 s | 0.586 (15→30) |
| 60 | 14,350 | 32.633 s | 1.108 (30→60) |

Both adjacent exponents are below the unchanged 1.3 limit. This passes S1
symbol-local feature scaling under the measured runner settings. All measured
builder output transactions rolled back. The complete SQL and logs are
[`phase2_s1_v3_symbol_scale_current_20261025.sql`](phase2_s1_v3_symbol_scale_current_20261025.sql),
[`phase2_s1_v3_symbol_scale_current_20261025.log`](phase2_s1_v3_symbol_scale_current_20261025.log),
and
[`phase2_s1_v3_symbol_scale_60_replicate_20261025.log`](phase2_s1_v3_symbol_scale_60_replicate_20261025.log).
The four 2026 monthly feature chunks were subsequently committed through
2026-10-16 using the measured 15/5 batch profile and 32 MB work memory. Their
results are in
[`phase2_build_phase2-v3-074-clean-full-20261024.log`](phase2_build_phase2-v3-074-clean-full-20261024.log).
This closes the current feature-row coverage gap only; none of the E1–E5 gates
is thereby closed.

## 2026-10-26 — Cache scaling re-probe stopped before feature writes

The corrected Windows runner completed all 90 cache samples on the disposable
report clone with 15-symbol cache batches, 32 MB `work_mem`, and 16 MB
`maintenance_work_mem`. Migration 087 evaluates the maximum exponent across
three balanced blocks, not pooled medians. Block means (15/30/60 symbols) were
631/1,192.7/2,239.6 ms (exponents 0.920/0.909),
581.2/1,117.4/2,022.9 ms (0.944/0.857), and
697/1,948.7/2,335.2 ms (about 1.48/0.26). The guard reported a maximum
15-to-30 exponent of 1.483, above the unchanged 1.3 limit, so the builder stopped before cache load or
feature writes. The pooled medians are not accepted in place of the guarded
block result. All 90 measurements are in
[`phase2_cache_scaling_reprobe_90_20261026.log`](phase2_cache_scaling_reprobe_90_20261026.log);
the failed assertion and runner record are in the adjacent `.stderr.log` and
[`phase2_build_phase2-v3-089-last400-20261026-r2.failed.20261026-073013.log`](phase2_build_phase2-v3-089-last400-20261026-r2.failed.20261026-073013.log).

A rollback-only 15-symbol `EXPLAIN (ANALYZE, BUFFERS)` returned 23,765 rows in
597.8 ms for the adjustment-details helper (868 shared hits, 834 reads). The
nested `auto_explain` captured the cache insert at 771.9 ms with the same row
count; it used index scans, a merge join, incremental sort, and hash join, with
no external sort or temporary-file spill. One downstream join estimated 2
rows and produced 23,765, so that estimate remains worth monitoring. The
direct plan, nested plan, and server excerpt are in
[`phase2_cache_scaling_explain_15_20261026.log`](phase2_cache_scaling_explain_15_20261026.log),
[`phase2_cache_scaling_inner_explain_15_20261026.log`](phase2_cache_scaling_inner_explain_15_20261026.log),
and
[`phase2_cache_scaling_nested_plan_15_20261026.server.log`](phase2_cache_scaling_nested_plan_15_20261026.server.log).
The plan did not justify weakening the guard. Re-probe before retrying the
two-month full-universe slice.

## 2026-10-26 — Cache guard passed; 089 feature chunk timed out

Two later full 90-sample calibrations passed the unchanged cache guard before
the last-400 build retries. The first reported a maximum adjacent exponent of
0.958, 15/30/60 timings of 906/1,412/2,542 ms, and a 1.54-minute projected
full-cache time. The 30-minute retry reported 0.993, 1,305/2,404/4,490 ms,
and 2.22 minutes. Both stay below the existing 1.3 exponent and 40-minute
projection limits. The measurement and retry output is preserved in
[`25-minute attempt`](phase2_build_phase2-v3-089-last400-20261026-r2.failed.20261026-090721.log)
and
[`30-minute retry`](phase2_build_phase2-v3-089-last400-20261026-r2.failed.20261026-095151.log).

The full-universe last-400 build committed four two-month feature chunks from
2025-03-11 through 2025-11-10 (250,328 rows). The next chunk,
2025-11-11–2026-01-10, timed out at 25 minutes and then again at the maximum
30-minute statement timeout. The second attempt reached feature batch 96 and
started batch 97; the timeout was in the V3 computed-feature insert. No OOM
event was recorded. This does not complete the 400-session window or close
Phase 2. The 1.483 calibration failure above remains part of the evidence; the
later passing measurements do not erase it or justify changing the guard.

## 2026-10-26 — Complete the remaining 089 feature window in monthly chunks

After the two-month transaction timed out, the remaining 2025-11-11–2026-10-16
slice was run as 12 calendar-aligned monthly transactions. The run used
15-symbol input batches, five-symbol compute groups, 32 MB `work_mem`, and one
PostgreSQL process. All 12 chunks committed 347,505 rows, with no OOM event;
the runner exited 0. With the four earlier successful chunks, the selected
last-400-session period now has 16 successful migration 089 chunks and
597,833 rows from 2025-03-11 through 2026-10-16.

The 12-month run took about 2 h 42 min, longer than the 40-minute full-build
plan and the recovery prompt's remaining 98-minute build allowance. Keep the
result scoped to this recent full-universe slice; it does not estimate or
complete the remaining full-history rebuild. The earlier timeouts stay in the
record as failed attempts. The runner summary, monthly row counts, and
price-hash notice interpretation are in
[`phase2_v3_089_last400_build_20261026.md`](phase2_v3_089_last400_build_20261026.md);
the raw output is in
[`phase2_build_phase2-v3-089-last400-20261026-r3_20261026-104135-874-dd8d4e0f.log`](phase2_build_phase2-v3-089-last400-20261026-r3_20261026-104135-874-dd8d4e0f.log).

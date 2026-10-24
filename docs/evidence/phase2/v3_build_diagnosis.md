# Phase 2 V3 build diagnosis

Date: 2026-10-20

## Finding

The slow part of the sampled V3 build was output-row construction, not the window calculations or a nested-loop plan. A PostgreSQL `auto_explain` run on a rollback-only 15-symbol, 2020 sample reported an 87.55-second feature statement. Its outer `Hash Left Join` consumed 85.67 seconds, while the child join completed in about 2.32 seconds. The outer projection used `to_jsonb(f)`, `jsonb_build_object(...)`, and `jsonb_populate_record(...)` for each output row. The plan showed no nested-loop scan or external sort in that feature statement.

That timing gap pointed to the per-row JSONB conversion as the bottleneck. Replacing it with direct copying of the V2 composite row into a temporary output table, then updating only V3 columns from a narrow computed table, reduced the measured 15-symbol feature stage to 2.58 seconds for 3,341 output rows in the scaling run (about 34× faster than the 87.63-second pre-change feature stage). The synthetic SQL suite verified inherited V2 fields and V3 batch parity after the rewrite.

The same plan audit found that PostgreSQL 18 has no moving inverse transition for `regr_slope`, `var_samp`, or `covar_samp` over `double precision`. The 20/60/250-session rolling sums and paired regression moments now use cumulative sums and fixed-offset differences. Synthetic assertions compare beta, idiosyncratic volatility, and Amihud values with direct rolling aggregate references at a 1e-9 tolerance.

## Stage timings

The rollback-only 2020 probe used 567 effective sessions, 113,828 complete rank rows, and a 1,381-symbol V2 population of 341,357 rows. The full-history adjusted-price cache contained 2,844,435 rows and took about 80 seconds to build. Its server plan read about 3.34 GiB and wrote about 3.42 GiB of temporary work files, with large intermediate CTEs spilled to disk; see [`cache_plan_excerpt.md`](cache_plan_excerpt.md). This is a shared setup cost, separate from the optimized symbol-batch feature statement. Market context took about 36–38 seconds in repeated probe calls and global ranks about 2 seconds.

See [`scaling_probe.md`](scaling_probe.md) and the raw command output in [`scaling_probe_15_30_60.log`](scaling_probe_15_30_60.log). The pre-change timing run is preserved in [`timed_plan_probe_15.log`](timed_plan_probe_15.log); PostgreSQL's server log recorded the nested plan used for the diagnosis.

## Current status

The synthetic feature assertions and resumable-runner checks passed. The real full-history V3 feature stage has started on the disposable report clone in one-year transactions with a 30-minute statement timeout. Full-history completion, labels, and E1–E5 data evidence are still pending; this diagnosis does not mark Phase 2 complete.

## 2020 full-universe retry checkpoint

The disposable-clone retry for build `phase2-full-20261020`, feature chunk `20200101-20201231`, reached the 30-minute statement timeout before any V3 rows committed. Its log is [`full_history_retry_2020.log`](full_history_retry_2020.log). The notices recorded 2,844,435 adjustment-cache rows (8m17.8s), 567 effective sessions (8m18.2s), 567 market-context rows (14m42.5s), and 113,828 rank rows (48.8s). At timeout, PostgreSQL reported the active inner operation as the insert into `pg_temp.phase2_v3_symbol_batches`, using a full-universe `SELECT DISTINCT` over the adjustment cache joined to the 567-session table. Because the timeout applied to the enclosing feature-builder statement, that context identifies where it was interrupted, not how much of the 30 minutes that inner operation consumed.

The runner recorded the feature chunk as `failed`; a read-only check found `rows IS NULL` and zero `phase2-v3` rows for 2020. Existing committed 2018/2019 chunks remain unchanged. One read-only activity sample showed the active statement waiting on `IO:DataFileRead`; this identifies file reads as the observed wait, but does not establish which plan node caused the delay. No registered database was used.

The rollback-only 15/30/60 probe exponent of 1.025 measured the symbol feature batch, not the no-limit full-universe symbol-population query. Its cache and market-context timings (about 80 seconds and 36–38 seconds) also differ sharply from the retry's 8m17.8s and 14m42.5s notices. A fresh cache-backed `EXPLAIN (VERBOSE)` attempt exceeded twice the earlier 80-second cache estimate before producing a plan, so it was stopped and no plan artifact was produced. Do not retry the full build until the cache, market-context, and no-limit population operations have bounded timings under representative conditions; then rerun the year chunk and verify committed row counts before scheduling later years.

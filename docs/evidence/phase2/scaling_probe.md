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

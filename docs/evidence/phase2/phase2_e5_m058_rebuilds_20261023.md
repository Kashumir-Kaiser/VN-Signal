# E5 repeatability checkpoint and current-hash audit — 2026-10-25

Database: disposable report clone `vnsignal_phase2_report_20261019`.
Stage and range: labels, 2023-01-01 through 2023-12-31.

| Attempt | Build ID | Result | Rows | Duration |
|---|---|---|---:|---:|
| 2023 label build in prior checkpoint | `phase2_e5_m058_20261023` | Completed, but its label input hash is stale | 720,718 | 367,240 ms |
| Initial forced repeat | `phase2_e5_m058_20261023_repeat` | Interrupted early; no durable attempt | No committed row count | Stopped before the 2× threshold; exact duration not recorded |
| Clean forced retry | `phase2_e5_m058_20261023_repeat` | Interrupted before commit | No committed row count | 753-second label-build statement, just over 2× the first step |

The first build's complete output is in
[`phase2_build_phase2_e5_m058_20261023.log`](phase2_build_phase2_e5_m058_20261023.log).
The clean forced retry rebuilt the adjustment cache, input hashes, label
targets, endpoint days, adjustment prefixes, endpoint bars, and
first-bad-factor set, then remained in the shared label-span calculation. At
753 seconds the PostgreSQL session was active on disk reads and not waiting on
a lock. A local interrupt was followed by the backend ending before a separate
`pg_cancel_backend` could target it. Follow-up inspection found no active Phase
2 sessions. The transaction rolled back:
`ops.feature_chunks` records the original chunk as `done` and the repeat chunk
as `pending`; the interrupted transaction left no repeat `ops.step_runs` row
or output hash.

## Current-candidate hash audit — 2026-10-25

A read-only inspection of the disposable report clone found that the 720,718
2023 label rows use feature input hash
`f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1` and label
version `close-next-open-v1`. The current V3 feature candidate uses hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`. The
completed 2023 build therefore does **not** establish a current-hash label
build. The interrupted repeat has no committed output hash and cannot be
compared with it.

**Disposition:** E5 remains inconclusive. Rebuild the 2023 label range from the
current V3 feature hash, then force a repeat and compare the canonical output
hashes. Until both builds complete, do not count the historical row count or
the interrupted repeat as current-candidate repeatability evidence.

## Bounded span-plan probes — 2026-10-25

The initial 50-symbol probe repeatedly expanded
`core.vndirect_reference_adjustment_details` for each label endpoint and timed
out. Rework the diagnostic to stage the canonical symbol-filtered helper once
before resolving endpoints.

The three-symbol rollback-only probe staged 6,018 adjustment rows and 96
January endpoints. Its span query completed in 2.247 ms using the episode
index; it contained no episode-change rows. See the [SQL](phase2_e5_span_plan_staged_sample_20261025.sql)
and [output](phase2_e5_span_plan_staged_sample_20261025.log).

A single 30-symbol helper call exceeded its 60-second statement limit before
reaching the span query. It made no persistent writes. Splitting the same
symbols into ten three-symbol calls completed and staged 56,313 adjustment
rows for all 14,124 2023 endpoints. The span query took 124.517 ms, used the
`(symbol_id, episode_start_date, trade_date)` index for same-episode lookups,
and showed 84,939 local buffer hits, 61 reads and four writes. No episode
changes occurred in this sample, so the cross-episode branch remains untested.
See the [timed-out single-batch SQL](phase2_e5_span_plan_batch30_20261025.sql)
and [log](phase2_e5_span_plan_batch30_20261025.log), plus the
[staged-batch SQL](phase2_e5_span_plan_batch30_staged_20261025.sql) and
[log](phase2_e5_span_plan_batch30_staged_20261025.log).

These probes show the same-episode lookup is fast on a 56,313-row staged
sample and that the source helper benefits from small symbol batches. They do
not reproduce the full 2023 memory and I/O footprint or explain the earlier
753-second full span build. No builder code was changed. E5 remains
inconclusive until current-hash 2023 labels are built twice and their
canonical hashes match.

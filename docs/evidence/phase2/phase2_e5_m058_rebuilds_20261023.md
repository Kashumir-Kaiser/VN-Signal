# E5 current-hash rebuild checkpoint — 2026-10-23

Database: disposable report clone `vnsignal_phase2_report_20261019`.
Stage and range: labels, 2023-01-01 through 2023-12-31.

| Attempt | Build ID | Result | Rows | Duration |
|---|---|---|---:|---:|
| First current-hash build | `phase2_e5_m058_20261023` | Done | 720,718 | 367,240 ms |
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

**Disposition:** the first current-hash E5 build passed, but the forced
reproducibility comparison is inconclusive. Do not treat the historical
pre-migration-058 E5 repeat as current-hash evidence.

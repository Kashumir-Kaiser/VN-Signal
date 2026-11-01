# Phase 2 last-400 input-hash overrun — 2026-10-24

This record covers only disposable report clone
`vnsignal_phase2_report_20261019` and build
`phase2-e1-e5-v3-068-20261024-last400`. No registered `vnsignal` database or
live vnstock route was used.

The run passed the 64 MB cache scaling gate, loaded 2,844,435 adjustment rows
into its transaction-local cache, and began hashing inputs for the first
requested feature chunk, 2025-03-11 through 2025-12-31. The canonical price-day
hash requested 1,206 dates, 2021-03-09 through 2025-12-31. The comparable
374-date hash took 2m43s; the linear estimate was 8m43s, making the required 2x
checkpoint 17m26s.

The runner wrote
[`phase2_build_phase2-e1-e5-v3-068-20261024-last400.failed.20261024-050030.log`](phase2_build_phase2-e1-e5-v3-068-20261024-last400.failed.20261024-050030.log)
at 05:00:30 local. Its transcript ended during the price-day hash, before the
V3 feature statement. The psql client had stopped, but a read of
`pg_stat_activity` found the exact build backend still active:

```text
pid=4516 | application=phase2_features | state=active
wait=IO/DataFileRead | query_age=00:26:49 | query=DO $phase2_chunk$...
```

The explicit `SELECT pg_cancel_backend(4516)` returned `t` with psql exit code
0. A subsequent targeted `pg_stat_activity` query for PID 4516 returned no row
by 05:11 local. The 26m49s runtime exceeded 3x the estimate and the 17m26s
checkpoint. No V3 feature SQL ran and no feature rows from this attempt were
committed. The planned last-400-session slice was not produced.

Replan the canonical per-day input-hash aggregate and reusable staging before
resuming. Preserve the current hash semantics and scaling/time gates; do not
repeat the same wide-range hash step. Full-history V3, the last-400 slice, and
the current-hash E1 null-rate report remain open.

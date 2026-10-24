# Phase 2 rank probe correction — 2026-10-22

## Result of the previous probe

The report-copy runner timed the entire repair transaction and rolled it back:

- 30 effective sessions: 45,513 rank rows, 91,026 changed rows, 34.303442 seconds.
- 60 effective sessions: 90,885 rank rows, 181,770 changed rows, 151.062488 seconds.
- Apparent 30-to-60 exponent: 2.138720, above the 1.3 threshold.
- 120 effective sessions: the 2026-04-24..2026-05-24 chunk completed in 256.770052 seconds with rollback verified. The next chunk (2026-05-25..2026-06-24) was cancelled before completion.

That exponent is not accepted as the S2 scaling result. Rolling back an UPDATE
does not remove the aborted heap tuple versions. After the sequential samples,
`pg_stat_user_tables` reported 393,406 estimated dead tuples and 396,278 updated
rows for `feat.features_daily`. The probe had therefore changed the physical
state seen by the later samples. The cancellation verification records zero
committed repair audit rows and zero other active rank-probe sessions. The
JSON certificate is marked `aborted_incomplete_measurement` and cannot be used
to start repair.

Evidence files:

- `phase2_rank_repair_phase2-rank-repair-053-20261022.log` — sample timings and per-chunk rollback record.
- `phase2_rank_probe_phase2-rank-repair-053-20261022.json` — incomplete, failed certificate.
- `phase2_rank_probe_cancel_verify_20261022.log` — no committed probe audit rows and no other active probe session.
- `phase2_rank_probe_dead_tuple_stats_20261022.log` — table statistics after the probe.

## Component profile

On the 2026-08-22..2026-09-21 range, a read-only rank-panel hash took 6.771
seconds (20,157 shared blocks read; 3,325 temporary blocks read and written).
The shared rank function took 3.168 seconds and returned 16,771 rows. These
single-range profiles help isolate the work but do not constitute scaling
evidence. See `phase2_rank_hash_profile_20261022.log` and
`phase2_rank_rank_profile_20261022.log`.

## Corrected S2 measurement

S2 scaling is measured at 30, 60, and 120 effective trading sessions using
`feat.phase2_cross_sectional_ranks` in `READ ONLY` transactions. The largest
window is run once as a warm-up before the timed samples. The probe does not
update `feat.features_daily`; historical repair remains a distinct monthly,
checkpointed operation. Each statement retains a five-minute timeout and the
existing 1.3 exponent gate. Remeasurement is pending a report-copy vacuum to
remove the dead tuple versions created by the previous probe.

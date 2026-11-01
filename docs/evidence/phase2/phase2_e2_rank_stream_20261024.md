# Phase 2 E2 rank-stream recovery — 2026-10-24

## Result

E2 passed against only the disposable report clone `vnsignal_phase2_report_20261019`.
The selected point-in-time cohort remained 60 symbols, five per exchange and
liquidity-tier stratum. The 40%, 70%, and 95% cutoffs all reported zero
pre-cut feature mismatches, zero completed-label mismatches, and zero label
boundary mismatches, with labels crossing each cutoff. Independently perturbed
future equity and index inputs changed the expected post-cut rows. The test
ended in `ROLLBACK`; the registered `vnsignal` database and vnstock routes were
not used.

| Cut | Cut date | Feature rows | Crossing labels | Equity rows perturbed | Index rows perturbed |
|---:|---|---:|---:|---:|---:|
| 40% | 2021-12-14 | 90,686 | 1,620 | 72,208 | 1,204 |
| 70% | 2024-05-21 | 163,030 | 1,620 | 36,036 | 601 |
| 95% | 2026-05-27 | 223,228 | 1,601 | 5,937 | 99 |

## Performance diagnosis

The old exact branch-context 15-symbol call took 147.2 seconds. Its plan
recomputed three percentile-rank windows thousands of times through nested
loops, discarding roughly 73–97 million rows by join filters. Migration 066
rewrites the three independent populations into one narrow long-form stream,
one materialized window pass, and one pivot before a key join back to `picked`.
The original eligibility predicates remain intact, including the full 20-return
requirement for volatility.

The rollback-only E2 branch-context profile after migration 066 measured:

| Cohort | Builder elapsed | Output rows | Temp files / bytes |
|---:|---:|---:|---:|
| 15 | 3.02 s | 10,389 | 0 / 0 |
| 30 | 5.82 s | 22,430 | 0 / 0 |
| 60 | 12.61 s | 45,343 | 0 / 0 |

The 15-to-60 power-law scaling exponent is `b = 1.03`, below the recovery
prompt's `b > 1.6` stop threshold. Each profile plan has one rank `WindowAgg`
execution and a hash join back to the picked rows. The separate canonical
adjustment-cache preparation took 12:52 in the cold 60-symbol profile and 8:20
in the full E2 gate; those setup times are not V2 builder timings.

## Reproduction and related checks

- [E2 SQL and captured output](phase2_e2_real_assertions.sql)
- [Full E2 run log](phase2_e2_real_rank_stream_20261024_retry1.log)
- [15/30/60 profile SQL](phase2_e2_v2_branch_context_15_30_60_rank_stream_20261024.sql)
- [15/30/60 profile log and plans](phase2_e2_v2_branch_context_15_30_60_rank_stream_20261024.log)
- [Independent V2 rank-population assertion](../../../tests/sql/phase2_rank_population_assertions.sql)

The V2 assertion recalculates each metric's `percent_rank` on its own eligible
population and checks exact stored values. The existing SQL fixture also
checks independent V3 rank populations, ties, singleton/empty inputs, and stale
V2 rejection. Migration 066 was applied twice on the disposable report clone,
verifying its replay behavior.

The first E2 retry stopped at the earlier stored-V3-hash guard before running a
cutoff. The harness now verifies current V3 hashes on its rebuilt immutable
baseline, where they matter for E2 comparisons. The stale stored V3 hash remains
an E1/current-data rebuild gap; this change does not certify those stored rows.

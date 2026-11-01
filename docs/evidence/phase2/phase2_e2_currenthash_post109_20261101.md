# E2 current-hash real-data leakage check after migration 109 — 2026-11-01

**Result: PASS.** The real-data test was rerun after the full label refresh
under migration 109. It used the current feature-set hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b` and a
deterministic PIT-stratified cohort of 60 symbols.

For each of the 40%, 70%, and 95% session-history cutoffs, future equity and
VNINDEX prices and volumes were perturbed by up to 20%. The production scoped
feature and label builders were rerun. Pre-cut features, completed labels,
and label boundaries were compared exactly. The test transaction rolled back;
the registered `vnsignal` database was not modified.

| Cutoff | Cut date | Pre-cut feature rows | Feature mismatches | Completed-label mismatches | Boundary mismatches | Crossing labels | Perturbed equity/index rows |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 40% | 2021-12-14 | 90,686 | 0 | 0 | 0 | 1,620 | 72,208 / 1,204 |
| 70% | 2024-05-21 | 163,030 | 0 | 0 | 0 | 1,620 | 36,036 / 601 |
| 95% | 2026-05-27 | 223,228 | 0 | 0 | 0 | 1,601 | 5,937 / 99 |

The rank comparison population remains the selected 60-symbol cohort. This
test demonstrates point-in-time invariance for that controlled population,
not full-market rank-population parity.

## Evidence

- Executed assertions and perturbation manifest:
  [phase2_e2_real_leakage_post109_20261101.log](phase2_e2_real_leakage_post109_20261101.log)
- Test SQL:
  [phase2_e2_real_assertions.sql](../../../tests/sql/phase2_e2_real_assertions.sql)
- Client exit code: `0`; `ROLLBACK` appears at the end of the transcript.

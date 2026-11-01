# Phase 2 E4 integrity report summary

Target: disposable `vnsignal_phase2_report_20261019` only. The registered `vnsignal` database and vnstock were not accessed. The completed diagnostic ran 97 non-overlapping monthly ranges covering `2018-10-01` through `2026-10-16`. Each report query ran in a read-only transaction with `statement_timeout=180s` and `lock_timeout=5s`. The completed main log contains no timeout or error.

## Coverage, keys, calendar, and feature hash

| Check | Result |
|---|---:|
| V2 rows | 2,844,435 |
| V3 rows | 2,844,435 |
| V2 keys missing in V3 | 0 |
| V3 keys absent in V2 | 0 |
| V3 null-key rows | 0 |
| V3 duplicate symbol-date groups | 0 |
| V3 rows without an effective session | 0 |
| Adjacent V3 symbol rows separated by more than one effective session | 221 |
| Distinct feature-set hashes | 1 |
| V3 rows with the current V3 feature-set hash | 2,844,435 |

The single hash was `397fec9c226e5c8d1ad9742ac264bb07f2012f43f71f29fe67499d835444f11c`.

## Rank checks

| Check | Result |
|---|---:|
| Uniform rank values outside `[0,1]` or non-finite | 0 |
| Gaussian rank non-finite values | 0 |
| Non-null rank values mapped to a null input | 935,747 |
| Unverified industry ranks that are non-null | 0 |

All 935,747 null-input mappings were `rank_realized_vol20`; the other five checked rank/input mappings were 0. This mapping was already present in the V2 rows: the 12-row October 2018 lineage sample has identical V2 and V3 `rank_realized_vol20` values while both corresponding `realized_vol20` inputs are NULL. This report does not establish why V2 produced those ranks.

## Recorded build timing evidence

The queried build ID was `phase2-vci-full-rebuild-20261021`. The 21 matching `ops.step_runs` records comprise:

| Stage/status | Records | Rows recorded | Sum of recorded duration_ms |
|---|---:|---:|---:|
| features / done | 9 | 2,844,435 | 5,101,766 |
| features / failed | 4 | NULL | 139,501 |
| labels / done | 6 | 3,018,252 | 2,304,012 |
| labels / failed | 2 | NULL | 0 |

Failed and successful attempts are both retained in the log; duration sums therefore describe recorded step attempts, not wall-clock build duration.

## Evidence and uncovered checks

- Main monthly report output: [`phase2_integrity_report_monthly_20261022.log`](phase2_integrity_report_monthly_20261022.log).
- Reproducible bounded SQL: [`phase2_integrity_report_chunked.sql`](../../../sql/diagnostics/phase2_integrity_report_chunked.sql).
- Monthly runner: [`run_phase2_integrity_report_monthly_20261022.ps1`](run_phase2_integrity_report_monthly_20261022.ps1).
- Rank/input lineage query and sample: [`phase2_integrity_rank_realized_null_sample_20261022.log`](phase2_integrity_rank_realized_null_sample_20261022.log), [`phase2_integrity_rank_realized_null_sample.sql`](../../../sql/diagnostics/phase2_integrity_rank_realized_null_sample.sql).
- A half-year attempt exceeded its 180-second statement timeout; the quarterly retry also timed out on its first chunk. Both failures were preserved separately. The final monthly run completed without errors.
- The 221 continuity gaps are counted but not attributed to suspensions, source gaps, or calendar/data defects.
- The hash check confirms the stored feature-set hash matches the current V3 contract hash; it does not recompute each hash from raw source inputs.
- No return-window/count columns were present in `feat.features_daily`; the sample cannot identify the upstream count responsible for the null realized-volatility values.
- The report checks non-null rank with null input. It does not check the reverse case (null rank with non-null mapped input).

# Phase 2 label recovery — 2026-10-22

> Historical snapshot. E2 and E3 subsequently passed on 2026-10-23; the
> current Phase 2 readiness decision is in [`BUILD_STATUS.md`](../../BUILD_STATUS.md).

All database writes in this checkpoint used the disposable report clone
`vnsignal_phase2_report_20261019` on `localhost:5432`. The registered
`vnsignal` database and vnstock routes were not used.

## Label coverage

Current V3 features contain 2,844,435 rows through 2026-10-16. The label table
contains 5,688,870 rows for the same feature set, exactly two horizon rows per
feature row. Coverage is provided by the completed chunks below; 2022's failed
annual attempt is retained as history and covered by the successful H1/H2
chunks.

| Range | Rows | Duration | Output SHA-256 |
| --- | ---: | ---: | --- |
| 2018-10-01–2018-12-31 | 164,436 | 135,779 ms | `46eafe4da9bcd39db0dbd1d3aee3d89f687d698b0a11a1cd4df66f91e9827cd2` |
| 2019 | 652,912 | 509,992 ms | `d61540833d2b3f8ce7aa17476782f22106eabfdca44630ed33f9b04c3cba66dc` |
| 2020 | 682,714 | 412,186 ms | `c98b4d22fa8349794c26113477736a9eeed0a0dae32d2f555694f75b5d1bd35e` |
| 2021 | 700,842 | 773,284 ms | `8aef5f67d0187250da24d155a7af377a26689ac2ae4414a1f306a47db4e3b907` |
| 2022 H1 | 342,614 | 294,205 ms | `b8ff37e6c7d334e4efec72a04e2216b1a99d8aa2575cbf01e8d73cfd2a91b7c5` |
| 2022 H2 | 370,978 | 260,659 ms | `71e10ee592342bc4cb70c271754dbd188f18e711b43428ba420d6611fcfe4971` |
| 2023 | 720,718 | 276,162 ms on final rebuild | `3c6d2ad64925d19264287c41c6e2ba805826ac3beac653cd2e6bfeac87bcdf2e` |
| 2024 | 731,154 | 244,310 ms | `7ea5c21e38503a0a437f189acca3e15d0f0f0449af318c912ea9a0e231a70ea5` |
| 2025 | 737,922 | 270,972 ms | `8fda1d0342cfb2f3bad64406b677dc0ad816f440619026d4034cb99982f11e48` |
| 2026 through 2026-10-16 | 584,580 | 204,499 ms | `773ebc9be3c2380c790c9895e8dabbfadaefa4a8c194fcecb3b35980a3aa6f92` |

The durable current and historical chunk ledger, including input hashes, is
[`phase2_label_chunk_status_20261022.csv`](phase2_label_chunk_status_20261022.csv).
Runner output for the 2023–2026 chunks is preserved in the correspondingly
named `phase2_build_phase2-vci-labels-rechunk-20261022_*.log` files.

## First-bad-factor scan

The 2022 plans exposed a repeated nested-loop/index-scan pattern taking 181–189
seconds per half-year chunk. A rollback-only 2023 full-year probe with
`enable_nestloop=off` used one sequential scan of 2,844,435 adjustment rows and
hash joins to the 1,454 latest-exit symbols. The plan returned zero bad-factor
rows in 1,566 ms; details are in
[`factor scan plan and full-row check`](phase2_label_factor_probe_2023_20261022_badfactor_find.log)
and its reproducible
[`rollback-only probe SQL`](phase2_label_factor_probe_2023_20261022.sql).

Migration 051 scopes the planner setting to that query and restores the caller
setting. A follow-up found that restoring before `GET DIAGNOSTICS` overwrote the
row count with the setting call's count of one. The migration and regression
assertion now capture the CTAS count before restoring the setting. The final
2023 runner log reports zero bad-factor rows and keeps the original output
hash; the one-off report-clone correction is recorded in
[`row-count fix log`](phase2_label_factor_rowcount_fix_report_clone.log).

## Reproducibility and remaining gates

The 2023 chunk was built twice with the same input hash
`80feb992cbfddd677199567490683c31a5fab8c12ca8214004a6b8c706bdf7ee` and output
hash above. This passes E5 for that chunk. Both runs have preserved logs; the
final run is `phase2_build_phase2-vci-labels-rechunk-20261022_2023_rowcount_rebuild.log`.

E1 now has a current **FAIL** result (73 of 88 measured features exceed the
specified 1pp threshold); see [`current E1 report`](null_rates_full_20261022.md).
E2–E4, PIT-fundamentals coverage, final local gates after this edit, and hosted
CI remain open. Completed label coverage alone does not close Phase 2.

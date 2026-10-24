# 2022 corrected-label split checkpoint — 2026-10-22

This checkpoint records the recovery of corrected V3 labels for 2022 on the disposable report clone `vnsignal_phase2_report_20261019` at `localhost:5432`. The registered `vnsignal` database and vnstock routes were not used.

## Completed chunks

| Chunk | Status | Rows | Elapsed | Input SHA-256 | Output SHA-256 |
| --- | --- | ---: | ---: | --- | --- |
| 2022-01-01–2022-06-30 | done | 342,614 | 294,205 ms | `d39bbc60ccd918de3405196ed309f14d7a3924584025f27a91c8297864b21986` | `b8ff37e6c7d334e4efec72a04e2216b1a99d8aa2575cbf01e8d73cfd2a91b7c5` |
| 2022-07-01–2022-12-31 | done | 370,978 | 260,659 ms | `7a614a5c1419526e129767d4eae824a9f6927338a3cf5928053aa1d8e173f1dc` | `71e10ee592342bc4cb70c271754dbd188f18e711b43428ba420d6611fcfe4971` |

The two chunks total 713,592 label rows, matching the 2022 annual target count recorded by the earlier failed attempt. Their durable status and hashes are in [`phase2_label_chunk_status_20261022.csv`](phase2_label_chunk_status_20261022.csv). The H2 runner output is in [`phase2_build_phase2-vci-labels-rechunk-20261022_2022H2.log`](phase2_build_phase2-vci-labels-rechunk-20261022_2022H2.log).

## Captured plans and timeout interpretation

`auto_explain` captured nested statements with analysis and buffer counts. The final assembled insert took 37,694 ms for H1 and 31,666 ms for H2; PostgreSQL reported 342,614 and 370,978 inserted tuples, respectively, with zero conflicts. The first-bad-factor scan took 189,116 ms for H1 and 181,061 ms for H2 and returned no bad-factor rows. The H1 plan used 1,434 per-symbol index scans and reported substantial local-buffer reads and writes, so this stage is a performance watch item for later chunks. It completed in both half-year runs. See [`captured plan excerpts`](phase2_labels_2022_autorun_plans_20261022.log).

The prior annual failure's context names the final insert as the PL/pgSQL statement active at cancellation. The runner set `statement_timeout=30min` before calling the label function from one outer `DO` block. PostgreSQL documents `DO` as one statement and measures the timeout from command arrival, so the context alone does not prove that the insert itself ran for 30 minutes; this is an inference from the runner and PostgreSQL 18 documentation ([client timeout settings](https://www.postgresql.org/docs/18/runtime-config-client.html), [`DO`](https://www.postgresql.org/docs/18/sql-do.html)). The successful half-year runs show that this split keeps 2022 chunks below the configured limit.

## Remaining Phase 2 work

Labels for 2018–2021 are `done` in the earlier build, and both 2022 halves are now `done` in build `phase2-vci-labels-rechunk-20261022`. Label chunks for 2023–2026 remain pending. Corrected availability-aware E1, real-data E2–E5, PIT-fundamentals coverage review, final local gates, and hosted CI also remain open. This checkpoint does not close Phase 2.

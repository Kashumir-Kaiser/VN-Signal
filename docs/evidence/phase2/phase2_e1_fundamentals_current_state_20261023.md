# Phase 2 E1 hash and PIT fundamentals checkpoint — 2026-10-23

> **Hash section superseded by migration 065:** the E1 material below describes the pre-065 full V3 hash `f4d61dd5…`. The current feature hash is `775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`; only three date partitions have been refreshed, so the full E1 report is stale. The PIT-fundamentals counts below remain a read-only snapshot of the same disposable report clone.

## Pre-065 E1 feature-set hash snapshot

At the time of this pre-065 checkpoint, the V3 hash was `f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.
Migration 056 explicitly maps the prior V3 hash `397fec9c226e5c8d1ad9742ac264bb07f2012f43f71f29fe67499d835444f11c` to the rank-repaired hash. The post-repair, 97-month E4 report records one V3 hash and all 2,844,435 rows on `f4d61dd5…`; the current E1 report, generated 2026-10-23, covers that same row count and hash. The older `null_rates_full_20261022.md` is pre-repair and should not be used as the current E1 report. See [migration 056](../../../sql/migrations/056_phase2_rank_repair_date_scoped_updates.sql), [post-repair E4 summary](phase2_integrity_report_rank_repaired_summary_20261022.md), [current E1 report](null_rates.md), and [older pre-repair E1 report](null_rates_full_20261022.md).

At the time of this pre-065 checkpoint, the latest durable report covered 2,844,435 V3 rows at hash `f4d61dd5…`: 73 of 88 measured features were outside the lookback-only 1pp diagnostic, 15 within, and 13 source-unverified. The report preserves `sum(min(L,T_s))/sum(T_s)` and the all-row denominator. Six verified rank/input pairs had zero rowwise NULL-eligibility mismatches. The lookback-only model omitted traded-row, full-window, adjustment-episode, paired-index-session, and shared-date prerequisites; per-cell attribution remains open. This checkpoint is not current E1 acceptance evidence after migration 065.

## PIT fundamentals archive (disposable report clone)

Queried `vnsignal_phase2_report_20261019` on 2026-10-23 in an explicit read-only transaction with a 10-second PostgreSQL statement timeout. No registered database or vnstock route was accessed.

| Read-only check | Result |
| --- | ---: |
| `core.fundamentals_pit` rows, all classes | 0 |
| Archive-managed rows | 0 |
| Legacy unmanaged rows | 0 |
| Symbols represented | 0 |
| `available_at` range | none |
| `core.fundamentals_pit_observations` rows/snapshots | 0 / 0 |
| `feat.fundamental_features_daily` rows | 0 |
| Fundamental `ops.ingest_jobs` by income/balance/cash-flow route | 0 |

The `ops.feature_chunks` ledger is for fundamental-overlay materialization, not statement ingestion. Build `phase2-full-20261021` has four `done` chunks for 2018-10-01–2021-12-31 with zero output rows, one `failed` 2022 chunk, and four `pending` chunks for 2023-01-01–2026-10-16. Its attempt ledger has four completed zero-row attempts and one failed attempt. No archive rows or availability timestamps exist to evaluate for period or symbol coverage.

The schema and a durable active collector do exist: [`vnpipe backfill-fundamentals`](../../../go/cmd/vnpipe/fundamental_backfill.go) requires a recent saved capability probe and fresh quota evidence, [`RunFundamentalsBackfill`](../../../go/internal/ingest/fundamentals.go) submits each request through `Gateway.CallRecorded`, and [`CommitFundamentalLanding`](../../../go/internal/ingest/fundamental_postgres.go) atomically stores its raw landing and PIT snapshots/observations. The collector accepts at most 100 user-supplied symbols per invocation. The report clone has zero fundamental ingestion jobs, so this path has not populated the archive. No scheduled/full-universe archival run or completed coverage ledger is evidenced here. Do not infer historical publication availability; [the archive contract](../../../sql/migrations/034_fundamentals_pit_archive.sql) uses the documented conservative lag for backfills and fetch time for observed pulls when rows are actually ingested.

The bounded read-only checks were:

```sql
SELECT count(*) AS snapshots,
       count(*) FILTER (WHERE archive_managed) AS archive_managed,
       count(*) FILTER (WHERE NOT archive_managed) AS legacy_unmanaged,
       count(DISTINCT symbol_id) AS symbols,
       min(available_at), max(available_at)
FROM core.fundamentals_pit;

SELECT count(*) AS observation_rows,
       count(DISTINCT snapshot_id) AS snapshots,
       min(fetched_at), max(fetched_at)
FROM core.fundamentals_pit_observations;

SELECT count(*) AS overlay_rows,
       min(trade_date), max(trade_date)
FROM feat.fundamental_features_daily;

SELECT build_id, status, count(*) AS chunks, sum(rows) AS output_rows,
       min(date_from), max(date_to)
FROM ops.feature_chunks WHERE stage='fundamentals'
GROUP BY build_id, status;

SELECT route, state, count(*) AS jobs FROM ops.ingest_jobs
WHERE route IN ('income_statement','balance_sheet','cash_flow')
GROUP BY route, state;
```

The Master Build Spec §13 names the PIT archive as a Phase 2 deliverable but does not set a numerical completeness target. This check establishes that the archive is currently empty and cannot support a claim that PIT fundamentals are populated or coverage-complete; the Phase 2 exit criteria should be assessed against the specification and any recovery-prompt additions separately.

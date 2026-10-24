# Phase 2 rank and real-evidence recovery — 2026-10-22

Status: **IN PROGRESS; no Phase 2 sign-off.**

## Shared builders

The clean, two-pass migration replay before migration 053 completed with exit
code 0 and `Phase 2 SQL migration harness passed.` in
`phase2_sql_migration_harness_20261022_final.log`. The printed division-by-zero
error is the harness's deliberate rollback fault injection. Migration 052 was
then applied only to `vnsignal_phase2_report_20261019`; its transaction committed
in `phase2_shared_builders_report_db_apply_20261022.log`. No registered-market
database was modified by these steps.

## E2 cohort diagnosis

The original PIT listing-snapshot query selected zero symbols. The report
clone has 2,009 effective sessions; its 40% cut is 2021-12-14. Listing snapshots
span 2026-10-16–2026-10-19, with zero rows before that cut. The turnover data is
present: 689 symbols have exactly 60 positive values in the selected trailing
window, and 648,549 positive turnover rows precede the cut. These are diagnostic
query outputs, not a completed E2 run.

The E2 cohort now uses the latest source-row-linked VNDIRECT historical bar's
`exchange_code` on or before the cut. Migration 028 documents this field as the
venue for that historical bar. Unknown/latest-invalid venues are excluded;
selection does not fall back to an older valid venue or a current snapshot.
The selected cohort will include each venue observation's date, landing ID and
source-row number in the E2 output. The 60-symbol/12-stratum assertions remain.
The revised cohort and E2 perturbation run are still unverified.

## E3 sampling bottleneck

The initial real parity attempt was canceled after 369.40 seconds while still
selecting its sample; PostgreSQL activity showed the candidate-history query
waiting on `IO/AioIoCompletion` after 4m09s. It compared no feature values.
`phase2_e3_real_parity_20261022.log` records the explicit cancellation and failed
test result. This is **NOT a parity pass**.

The revised test first chooses the deterministic 20 observations across three
dates, then requires all 20 to retain their exact source-row lineage and intact
archived VNDIRECT payload hashes. A corrupt selected payload fails the test;
it is not removed from the sample universe. The previous all-candidate payload
hashing and all-candidate source-table join were removed. The selected-date
production rebuild and 1e-9 comparison remain mandatory. The sampling edit
compiled before the later rank-reference edits; those later edits require new
verification. No revised real-data parity result is claimed.

## Rank root cause and upgrade

The E4 mapping is correct: the 935,747 non-null `rank_realized_vol20` values with
NULL `realized_vol20` already occur in persisted V2 and are copied into V3.
Runtime function inspection found the report clone's shared V2 function still
uses `FROM picked WHERE vol20 IS NOT NULL`, without the `return_n20=20` guard
present in the checked-in migration 035. This is an installed-definition and
persisted-output issue, not a reason to change the diagnostic.

Migration 053 upgrades that installed definition, checks rank/value eligibility
after V2 builds, requires current and rank-consistent V2 input before V3 builds,
and gives each V3 Gaussian rank its own non-null population. Feature hashes
change with the semantics. Existing historical output must be rebuilt and
reaudited; installing functions does not repair existing rows.

The SQL regression exercises disjoint nullable inputs, ties, singleton and
empty populations, and rejection of a stale V2 hash through the production
builder. It passed in `phase2_rank_population_assertions_retry_20261022.log`.
The first test-only stale hash violated the hash-format constraint; the retry
uses a correctly shaped but stale 64-hex hash and reaches the intended rejection.
All eight Rust library tests passed in `phase2_rust_rank_unit_20261022.log`,
including independent-null/tie and singleton/empty rank cases. All 27 Python
tests passed in `phase2_python_rank_recovery_20261022.log`.

The full clean replay applied migrations twice and passed preceding feature and
leakage assertions, but timed out in the shared-builder fixture's single `DO`
(`phase2_rank_migration_harness_20261022.log`). An isolated retry also hit its
cumulative 180-second statement budget. Inspection found that all four builder
passes were inside one top-level statement; the endpoint joins already have
primary keys and analyzed inputs. The fixture now separates those four passes
into statements in the same transaction. The 180-second statement setting and
all original byte comparisons, counts, boundary and schema guards remain.
[PostgreSQL documents the timeout per statement](https://www.postgresql.org/docs/18/runtime-config-client.html).
The complete remaining sequence (shared builder, new ranks, source inputs,
chunks) passed with exit code 0 in
`phase2_rank_remaining_sql_retry_20261022.log`. A new uninterrupted full-harness
success marker is still pending; these complementary logs do not pretend that
the earlier invocation completed.

Migration 053 then committed on the disposable report clone, with no historical
row repair, in `phase2_rank_upgrade_report_apply_20261022.log`. The three
`phase2_*builders_*053_20261022.json` snapshots preserve installed definitions
before/after and the fresh CI definitions for comparison. Old output hashes
remain stale until a verified rebuild/repair completes. The unbounded-parallel
Go attempt was interrupted for resource contention and provides no pass; Go
test/vet must be rerun with bounded local compilation.

Exact snapshot comparison found upgraded and fresh V3 definitions byte-identical;
V2 differs only in comments/line wrapping. The executable before/after changes
are the V2 volatility-rank eligibility, three V3 Gaussian-rank populations, and
integrity guards. Other numerical expressions are unchanged. This supports
designing a bounded historical rank-stage recomputation instead of recomputing
unchanged non-rank formulas. It does not prove historical rows or their sources
are correct or repaired. A repair must recompute full date populations, retain
before/after hashes and provenance, reject unknown source/target semantic hashes,
and pass fresh-build parity before any sign-off.

The read-only archived daily-band coverage query reached its five-minute timeout
without measurements (`phase2_archived_price_limit_coverage_20261022.log`). There
is still no full-history band coverage claim. The next inventory needs bounded
landing batches and a measured plan; do not rerun the same whole-archive query
or infer missing data from that timeout. The documented source leads and gaps
are in `phase2_source_input_inventory_20261022.md`.

## Remaining completion gates

Real E2/E3, refreshed E4, strict E1 interpretation and unexplained nulls, PIT
fundamental coverage/builds, required source-dependent feature families, final
local checks, and current-main hosted CI remain open. The historical E5 label
chunk repeatability result remains evidence for that earlier feature version,
not proof that outputs under the new rank hashes are reproducible.

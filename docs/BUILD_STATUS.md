# Build status — 2026-10-24

## Current Phase 2 status

Current execution state: the prior feature wrapper and queued follow-up
processes disappeared during an execution-host interruption. PostgreSQL confirmed
no feature backend. Thirteen quarters through 2021-12-31 remain committed,
totaling 1,100,452 rows; the unfinished transaction rolled back. Stale status
files were marked process lost. The replacement temporary on-demand Windows task
`VN-Signal-Phase2-Recovery-20261024` runs outside the execution host process tree.
Its fourth resume attempt rebuilt all 2,844,435 adjustment cache rows and is
validating unchanged committed chunks. See the
[current log](evidence/phase2/phase2_v3_078_scheduler_resume4_20261024.log).
The first scheduled attempt failed before database work when the original
credential path was unavailable. The retry uses an encrypted user-bound,
ACL-restricted, Git-excluded handoff file; no plaintext credential is stored.
Migration 076 passed the fresh two-pass migration harness and required local
checks. The VCI provenance archive committed 160,116 observations across 135
symbols before deliberate cancellation to avoid slowing the feature build.
Its current transaction rolled back; remaining archive work will run serially.
The ABR check found 1,424 exact matches and two missing accepted-route landings;
both missing cases have exact rows in a quarantined response, which does not
satisfy the accepted-source contract. The unchanged ABR repeat inserted zero.
These observations do not establish listing tenure or complete Phase 2.

The current fundamentals checkpoint has six FPT statement/frequency archives,
768 versions and 824 observations, with source bytes and availability verified.
Frequency-specific probes and daily observed-refresh idempotence are implemented.
Current Go tests/vet, Python32 and the explicit UCRT64 race suite pass; the older
Windows race limitation recorded below is superseded by these successful runs.
See [fundamental refresh evidence](evidence/phase2/phase2_fundamental_period_refresh_20261024.md).
Migration078's V3-cohort and unknown-industry rank corrections passed targeted
checks. The replacement serial078 follow-up waits for the feature build before
the fresh full harness, report077/078/079/080/081 applications and remaining lineage archive.
Those queued operations, mappings, bank inputs, listing tenure and hosted CI
remain open.

Earlier cache checkpoint: migration 069's full-range input hash passed using
15-symbol batches, 8 MB work memory, and 16 MB maintenance memory. It loaded
2,844,435 cache rows and hashed all 1,206 dates in 73.943s; a repeated request
reused coverage in 129.107ms. This supersedes the earlier canceled full-range
attempts below. See [full-range hash evidence](evidence/phase2/phase2_hash_lowmem_069_20261024.md).
The feature rebuild and E1 remain open. Migration 070's configured execution
weights passed targeted/replay assertions, default-label assertions, and CLI
default/override checks; its fresh full two-pass migration harness passed. Migration 070 is applied to the disposable report clone. Its earlier last-400-session attempt was superseded by the full-history run described above. See [070 harness](evidence/phase2/phase2_migration_harness_070_20261024.log). See
[policy evidence](evidence/phase2/phase2_execution_policy_070_20261024.md).

Phase 2 is **not ready for sign-off or Phase 3**. Its deliverable is the SQL feature and label pipeline plus the point-in-time fundamentals archive. The recovery prompt's completion evidence consists of E1 null rates, E2 leakage, E3 feature parity, E4 integrity/scaling, E5 repeatability, and fixture-only CI. The Master Build Spec's minimum Phase 2 exit criteria are a produced null-rate report and passing leakage and feature-parity tests.

E2 **PASSES** on the current tree. Migration 066 replaces three separately joined V2 percentile-rank windows with one narrow, materialized rank stream and pivot while preserving each metric's eligibility and rank semantics. In the exact branch-schema profile, the 15/30/60-symbol builder times were 3.02/5.82/12.61 seconds, with zero temp-file growth and a 15-to-60 scaling exponent of 1.03. The full rollback-only E2 test passed its 40%, 70%, and 95% cutoffs with zero pre-cut feature, completed-label, and label-boundary mismatches; see the [E2 recovery report](evidence/phase2/phase2_e2_rank_stream_20261024.md), [full run log](evidence/phase2/phase2_e2_real_rank_stream_20261024_retry1.log), and [captured scale plans](evidence/phase2/phase2_e2_v2_branch_context_15_30_60_rank_stream_20261024.log). The old repeated rank-window join is a strongly supported explanation for the earlier 12:45 V2 stall: the canceled statement's completed plan was not captured, while the same branch-context shape reproduced the slow behavior and the replacement profiled linearly.

E1 is **NOT RUN for the current hash**: the latest recorded audit found 2,844,435 V3 rows, but only 4,349 use current hash `775b9bd5…`; 2,840,086 still use pre-065 hash `f4d61dd5…`. The E1 null-rate report therefore remains stale and must be refreshed after a full current-hash V3 build. E2 rebuilt and checked V3 only inside rollback-only branch schemas; it did not repair these stored rows. See the [current-state report](evidence/phase2/phase2_v3_current_state_20261023.md) and captured [read-only query output](evidence/phase2/phase2_v3_current_state_20261023.log).

The first 2026-10-24 E1 rebuild preflight did not pass, so no feature chunk ran. Its mandatory adjustment-cache guard rejected inconsistent 15/30/60-symbol timings; see [the failed build log](evidence/phase2/phase2_build_phase2-e1-v3-066-20261024.failed.20261024-011952.log), [the repeatability probe](evidence/phase2/phase2_e1_cache_probe_stability_20261024.log), and [the first 32 MB probe](evidence/phase2/phase2_e1_cache_probe_workmem32_20261024.log). A later isolated 60-symbol diagnostic at 32 MB took 0.66s to initialize, 2.99s to populate, and 0.44s to finalize; its nested plan showed 108,331 rows and 4,047 temporary blocks read/written during population ([client timings](evidence/phase2/phase2_e1_cache_probe_nested_plan_20261024.log), [captured plan](evidence/phase2/phase2_e1_cache_probe_nested_plan_server_20261024.log)). After this warm-up, a fresh rollback-only 15/30/60 guard run passed at 1.323/1.720/2.475s, exponent 0.525, and projected the 1,518-symbol adjustment-cache stage at 1.19 minutes ([probe log](evidence/phase2/phase2_e1_cache_probe_workmem32_retry1_20261024.log)). That 32 MB result was an earlier checkpoint, not the final build configuration. Host evidence showed 342–344 MiB available of 3.83 GiB ([resource capture](evidence/phase2/phase2_e1_host_resources_20261024.txt)); resource pressure is plausible but not proven as the cause of the earlier variance. Keep all scaling and time guards enabled; a cache preflight pass does not certify the feature rebuild.

The bounded last-400-session feature attempt passed its 64 MB cache guard (overall scaling exponent 1.150) and loaded all 2,844,435 adjustment rows into the transaction-local cache. It then stalled in the canonical price-day input hash for the first 2025 chunk: 1,206 requested dates from 2021-03-09 through 2025-12-31. The comparable 374-date hash took 2m43s, estimating 8m43s; the 2x stop point was 17m26s. The server statement remained in `IO:DataFileRead` for at least 26m49s, over 3x that estimate. The runner log records failure at 05:00:30, but its PostgreSQL backend remained active after the client stopped; `pg_cancel_backend` returned true, and a follow-up activity query found no backend by 05:11 local. The statement was canceled before feature SQL ran, so this attempt produced no V3 feature rows and no last-400 slice. A bounded 60-session probe then showed the current cache's scattered heap layout: date-local insertion reduced the exact hash query from 23.855s to 1.855s and local block reads from 82,419 to 1,864, with all 60 hashes identical. Migration 069 and its cache-order fixture assertion passed the fresh two-pass PostgreSQL harness; Go tests/vet and all 31 Python tests also passed. Migration 069 is applied to the disposable report clone, and the full-range probe was canceled during cache loading after available RAM fell to 145 MiB and batch 23 took 3m30s. The hash aggregate had not started; the full-range checkpoint remains unverified. See [probe record](evidence/phase2/phase2_hash_full_069_20261024.md). See [069 harness output](evidence/phase2/phase2_migration_harness_069_20261024.log). See the [runner log](evidence/phase2/phase2_build_phase2-e1-e5-v3-068-20261024-last400.failed.20261024-050030.log), [hash-overrun record](evidence/phase2/phase2_last400_hash_overrun_20261024.md), [date-local probe](evidence/phase2/phase2_hash_batch_order_probe_60d_20261024.md), and [scale record](evidence/phase2/scaling_probe.md). E1 remains NOT RUN for the current hash.

E3 **PASSES to the recovery prompt's stated scope**. The non-recursive real-data slice passed strict SQL↔Rust parity on 20 deterministic, source-attributed symbol-days at `1e-9` under current hash `775b9bd5…`. The independent production-builder golden passes in the fresh migration harness and in Rust for every recursive feature currently in production (EMA/MACD), using 320 fixture rows. Wilder RSI, Wilder ATR/ADX, and EWMA variance are not current production features: RSI/ATR use complete rolling windows, V3 ADX is explicitly `adx_14_simple_average`, and EWMA variance is absent. Do not add features merely to satisfy the recovery prompt's generic recurrence examples. A separate diagnostic compared real recursive SQL/Rust values and found a small `ema_100_ratio` difference for symbol 824 on 2023-04-04 (`SQL=0.004010006674335`, `Rust=0.004010006740238`); the recovery gate does not require recursive real-data parity, so preserve this diagnostic and tolerance without treating it as a failed required check. See [real non-recursive parity](evidence/phase2/phase2_e3_real_parity_065_nonrecursive_20261023.log), [recursive diagnostic](evidence/phase2/phase2_e3_real_parity_065_20261023.log), and [E3 audit](evidence/phase2/e3_parity_audit_20261023.md).

E4 is **INCOMPLETE**. The integrity review found 219 continuity intervals across 1,539 effective sessions. Official-source review supports 20 interval explanations covering 164 sessions (13 HNX-to-HOSE transfers, TDP, GEE, DNM, MIC, APP, C92, and VIE); The 14-document HNX-to-HOSE packet and six-document APP/C92/VIE packet are now archived as checksum-verified, ticker-matched raw landings in the report clone; repeat imports added zero duplicates. Lifecycle/interval classifications are still pending. The other 199 intervals remain unsupported. See the checksum-verified [HNX-to-UPCoM source packet](evidence/phase2/hnx_upcom_transfer_sources_20261024/evidence_report.md) for APP, C92, and VIE. Do not infer suspensions or synthesize bars. See [the gap assessment](../probe/phase2-lifecycle-20261023/gap_assessment.csv), [raw-landing census](evidence/phase2/phase2_e4_raw_census_20261023.md), and [transfer-source packet](evidence/phase2/hose_transfer_sources_20261023/README.md). Migration 059's synthetic eligibility assertion passes, but real-data eligibility counts have not been recomputed.

E5 is **INCONCLUSIVE**. One current-hash 2023 label build completed for 720,718 rows in 367,240 ms. A forced repeat reached 753 seconds in its label-build statement—over twice the first step's duration—and was cancelled without a second output hash. The first build log is [here](evidence/phase2/phase2_build_phase2_e5_m058_20261023.log), and the repeat cancellation record is [here](evidence/phase2/phase2_e5_m058_rebuilds_20261023.md).

The recovery prompt's additional label outputs are authored but remain unverified: date-wise winsorized excess returns, volatility-scaled scores with a date-level volatility floor, point-in-time liquidity-tier ranks, and execution weights for price-limit entries. A source-row audit links 1,810,727 of 1,810,729 canonical VCI bars to checksum-verified raw rows and finds 1,321 of 1,505 symbols with at least 250 exact prior positive-volume sessions. Migration 061 does not yet consume this lineage, so real membership and tier outputs remain unverified; see the [audit](evidence/phase2/phase2_vci_source_row_lineage_audit_20261023.md). The report clone has no materialized price-limit or listed-share observations from which to derive valid execution weights. A read-only archive census found numeric price-band pairs for all 2,844,683 VNDIRECT source rows, of which 1,287 are invalid. Historical availability and execution use remain unverified. PIT-fundamental coverage and the 219-gap eligibility impact are also open. Keep suggestions disabled without a valid champion.

Migration 068 was applied to the disposable report clone; its symbol-first eligibility predicate preserves the VNDIRECT, finite-positive-factor, selected-session semantics. The fresh two-pass migration harness passed with production feature assertions (see [harness log](evidence/phase2/phase2_migration_harness_068_20261024.log)). The full current E2 SQL finished with `ROLLBACK`. Local Go tests, Go vet, and all 31 Python tests passed after the relevant edits. Rust formatting, clippy, and workspace tests passed on the earlier code checkpoint. The Windows race test could not start package tests because ThreadSanitizer could not reserve shadow memory with MSYS2 UCRT64 GCC (error 87). Hosted CI has not run; its workflow sets `VNPIPE_DISABLE_LIVE=1`. The registered `vnsignal` database and live vnstock routes were not used.

The dated sections below preserve the state known at each checkpoint. Later entries supersede earlier pending or failed runs.

## 2026-10-23 — current-hash real E3 and independent recursive goldens

Using only the disposable report clone, the production V3 builder refreshed all
rows for the three deterministic real-data E3 dates under current hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`. The
builder reported 1,439 rows for 2022-10-10, 1,446 for 2023-04-04 and 1,464 for
2024-09-04. No raw, core or V2 rows were changed.

The real E3 test selected 20 source-attributed symbol-days across those dates,
verified each selected VNDIRECT landing payload hash and bar lineage, confirmed
the current V3 feature hash, and passed the non-recursive SQL↔Rust comparisons
at the unchanged `1e-9` tolerance. Its passing log is
[`phase2_e3_real_parity_065_nonrecursive_20261023.log`](evidence/phase2/phase2_e3_real_parity_065_nonrecursive_20261023.log).

The first broader comparison also compared recursive real features and found
`ema_100_ratio` differed for symbol 824 on 2023-04-04: SQL
`0.004010006674335`, Rust `0.004010006740238`. The failed run is preserved in
[`phase2_e3_real_parity_065_20261023.log`](evidence/phase2/phase2_e3_real_parity_065_20261023.log).
The recovery prompt defines real E3 parity for non-recursive features and
requires recursive EMA/MACD checks against independent goldens. In response,
[`tests/golden/phase2_recursive_ema.csv`](../tests/golden/phase2_recursive_ema.csv)
was generated with pandas 3.0.1 (`adjust=False`, `ignore_na=True`) and checked
by both the Rust reference tests and the SQL feature assertions. The tolerance
was unchanged. This does not establish recursive SQL↔Rust parity on real
history; the observed EMA difference remains a disclosed diagnostic.

The fresh two-pass SQL migration harness passed with the golden assertions in
[`phase2_migration_harness_ema_golden_20261023.log`](evidence/phase2/phase2_migration_harness_ema_golden_20261023.log).
Rust formatting, clippy and workspace tests passed, including the pandas
fixture check ([focused output](evidence/phase2/phase2_rust_recursive_ema_golden_20261023.log)). Go tests/vet and all 29 Python tests passed. The Windows race
run remains unavailable due to ThreadSanitizer shadow-memory allocation error
87. E3's non-recursive real-data slice passed, but recursive golden coverage is
incomplete, so E3 remains open alongside E1, E2, E4, E5 and hosted CI. Phase 2
is not ready for sign-off.

## 2026-10-23 — stabilize V3 rolling market regression

Rust/PostgreSQL parity isolated a small but material numerical mismatch in `idio_vol_vnindex_60`: cumulative-prefix subtraction produced `8.911217534444352e-06`, while a direct rolling sample-variance/covariance reference produced `8.911217502410939e-06`. The relative difference exceeded the existing `1e-9` parity tolerance. Keep the tolerance unchanged. Migration 065 switches the paired 60/250-session regression moments to PostgreSQL's rolling `var_samp`/`covar_samp`, requires the stock and lagged-index return to be present for every moment, adds a stable-moment feature-hash token, and preserves the inherited VNINDEX-return hash token.

The migration patches the shared V3 function body in place so migrations 053/054 can still inspect their rank and repair anchors. A fresh `template0` database passed two complete migration passes plus the full SQL harness. Strict Rust/PostgreSQL parity then passed for 20 deterministic synthetic symbol-days at the existing tolerance. The fixture does not constitute the outstanding real-market E3 comparison.

Current local checks after the migration: Go tests and vet, 29 Python tests, Rust fmt/clippy/workspace tests and the strict database-backed synthetic parity test passed. The Windows race run reached ThreadSanitizer but failed to reserve its shadow memory (error 87), even with UCRT64 GCC configured. Hosted CI is not run. E2 remains blocked on the real 40% branch rebuild; E4 still has 206 unsupported continuity intervals; E5 still lacks a second output hash. Phase 2 remains open.

## 2026-10-23 — corrected window rewrite and E2 retry (latest)

Migration 064 now preserves native averages and standard deviations while
computing exact 250-session extrema with block prefix/suffix windows. The
first replay uncovered stale custom-window aggregate dependencies; cleanup now
drops the full obsolete aggregate/function set. The first real E2 retry also
found that the `n` regular-expression flag prevented the CTE rewrite from
crossing newlines, leaving required spine columns out of `extrema250`. The
rewrite now uses the multiline-safe `s` flag and checks the resulting
projection before replacing the function. On the disposable report clone, the
corrected function projection check and numerical extrema fixture passed.

The repeated synthetic probe completed five alternating runs at 15, 30 and 60
symbols × 2,000 sessions. Direct/integrated medians were 1,122/841 ms,
2,213/1,597 ms and 4,528/3,146 ms, respectively. The integrated method had
zero temporary blocks and a 0.952 row-count scaling exponent (direct: 1.006).
Despite that synthetic win, current-tree E2 remains **NOT PASS**: the latest
corrected real run completed its baseline in 4:00.2, then the 40% branch's V2
rebuild remained CPU-active for 12:45 without a comparison. It was canceled,
and the outer transaction rolled back. No 70% or 95% cut ran. See the
[scaling output](evidence/phase2/phase2_v2_window_scaling_final_20261023.txt),
[rewrite verification](evidence/phase2/phase2_moving_window_rewrite_verification_20261023.log),
and [latest E2 log](evidence/phase2/phase2_e2_real_20261023_103110_365.txt).

After this E2 attempt, the latest current-tree Go tests, race tests, vet, all
29 Python tests, and a fresh two-pass PostgreSQL migration harness passed. The
harness includes migrations 061/063/064 and their SQL assertions; it does not
replace the real-data E2 comparison. The complete harness log is
[here](evidence/phase2/phase2_migration_harness_064regex5_20261023.log).
E3 has not yet been rerun against the migration 064 V2 implementation, so its
earlier 20-symbol-day result is stale for sign-off. Hosted CI remains unrun.

### Earlier recovery recheck (before migration 064)

The production adjustment cache now loads all 2,844,435 rows in 26 bounded
symbol batches, and the E2 current-hash baseline completes. The run then spent
579.592 seconds before entering the 40% perturbed branch; that branch remained
active beyond 16 minutes without a comparison, versus 8:06 in the prior
completed attempt. It was cancelled, the outer transaction rolled back, no
branch schemas or active Phase 2 sessions remained, and current-tree E2 is
NOT PASS. A later indexed-input retry completed branch setup and future
perturbation in about 19 seconds, but its V2 statement remained active for
12:38 without a comparison; it was canceled and rolled back. A plan-only run
captured the estimated V2 tree and was canceled after 63.840 seconds. The plan
has 20 WindowAgg and 9 Sort nodes for an estimated 48,060-row cohort spine;
it contains no actual timing or buffer data. No 70% or 95% branch ran. See the
indexed-input run and plan links above, plus the [plan summary](evidence/phase2/phase2_e2_v2_plan_20261023.md).

The current-hash E5 first build completed 720,718 rows in 367.240 seconds.
An initial repeat was stopped early; a clean forced repeat then reached 753
seconds in the label-build statement, just over twice the first step duration,
without completing. The original chunk is `done`, the repeat chunk is
`pending`, there is no second `step_runs` row or output hash, and follow-up
inspection found zero active Phase 2 sessions. E5 reproducibility is therefore
inconclusive on the current label definition. The run evidence is linked above.

The fresh two-pass PostgreSQL migration harness passed after the fixture was
corrected to build labels for both sides of the 250-session gap-eligibility
boundary. Go tests, vet, race tests, and all 27 Python tests also passed with
the configured bundled Python and MSYS2 UCRT64 GCC. No worker or Rust code was
changed in this recheck. Hosted CI remains unrun.

## 2026-10-22 — corrected E4 attribution and E1 null-model review (historical checkpoint)

The E4 identifier-domain review corrected two false lifecycle mismatches. Bars,
features, lifecycle evidence, and the symbol directory use
`core.symbols.symbol_id`; `core.security_master.security_id` is separate. The
PTM and CTR lifecycle records point to PTM and CTR landings respectively. The
PTM gap is covered by its delisting interval. CTR's six-session gap is the
UPCoM-to-HOSE transition from its last UPCoM session on 2022-02-14 to its first
HOSE session on 2022-02-23. Five VCI rows inside that transition are source
anomalies: they are absent from the audited source archive and both feature
versions. The earlier KTL/TSB attribution and five-TSB-bar conclusions are
withdrawn. Corrected evidence is in
[`the E4 identifier-domain correction`](evidence/phase2/phase2_e4_id_domain_correction_20261022.md).

E4 still has 219 unexplained continuity gaps across 1,539 effective sessions
with no daily bars, source-archive rows, or dated security observations.
Coverage, keys, calendar membership, and rank/input checks pass, but E4 is not
complete.

The E1 report exists and preserves the original denominator and 1pp diagnostic
threshold. Its 73/88 flags compare observed nulls with a lookback-only
expectation. A source audit found that this expectation omits nontraded rows,
complete-window requirements, adjustment-episode resets, and shared
market/index series. These results are not evidence that 73 builders are
broken; feature-by-feature null attribution is still open. The Master Build
Spec calls null-rate shifts a warning and requires a report; it does not set a
1pp Phase 2 exit gate.

At this checkpoint, real-data E2 and E3 did not yet have completed results.
Those gates later passed on 2026-10-23; see the current acceptance entry below.
E5 covers one 2023 label chunk. PIT-fundamentals coverage and source
verification remain incomplete, and hosted CI has not run.

## 2026-10-22 — full rank repair and Phase 2 readiness review

The 97 monthly rank-repair ranges are complete on the disposable report clone
`vnsignal_phase2_report_20261019`: 2,844,435 rows in each of V2 and V3. The
read-only S2 scaling probe passed with exponents 0.359774 and 0.935869. The
current V3 feature-set hash is
`f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.

Phase 2 is **not ready for sign-off**. Refreshed E1 flags 73 of 88
source-measured fields against the lookback-only expectation; this model does
not account for all builder availability conditions, and 13 fields remain
source-unverified. Real-data E2 is incomplete: the first
three-cut attempt was stopped during the first cut's perturbed V3 rebuild
after 28.5 minutes, before any comparisons; see the
[`E2 attempt report`](evidence/phase2/phase2_e2_real_attempt_20261022.md).
E3 has no completed real-data result. E4 has 221 symbol-session continuity
gaps; corrected review explains the PTM and CTR gaps with ticker-matched
lifecycle evidence, while 219 intervals have no daily bars or source-archive
rows and remain unresolved. Five VCI rows inside CTR's venue transition are
source anomalies absent from the audited source archive and V2/V3. See the
[`E4 gap review`](evidence/phase2/phase2_integrity_report_rank_repaired_summary_20261022.md)
and [source-attribution evidence](evidence/phase2/phase2_lifecycle_source_attribution_20261022.csv).

E5 passed for one 2023 label chunk rebuilt twice with identical input and
output hashes. PIT-fundamentals coverage and source verification remain
incomplete, and hosted CI has not run. The registered `vnsignal` database and
live vnstock routes were not used. Local Go tests, Go vet, 27 Python tests,
and the fresh two-pass PostgreSQL migration harness passed after migration
056; logs are linked from the current gate report
[`phase2_gate_status_rank_repaired_20261022.md`](evidence/phase2/phase2_gate_status_rank_repaired_20261022.md).
Suggestions remain disabled because no valid champion exists.

## 2026-10-22 — date-scoped rank update and 88-month checkpoint

The corrected S2 probe was rerun after the repair-function definition changed.
Its read-only rank-stage medians were 0.951241/1.220656/2.335167 seconds for
30/60/120 effective sessions; exponents were 0.359774 and 0.935869, within the
1.3 limit. The certificate is
[`phase2_rank_probe_phase2-rank-repair-055-20261022.json`](evidence/phase2/phase2_rank_probe_phase2-rank-repair-055-20261022.json).

The first March 2025 repair attempt was cancelled after 139.483 seconds while
waiting on table reads. Its durable attempt record is failed and the transaction
rolled back. The separate rank and hash profiles took 2.749 and 2.568 seconds;
the update plan showed a nested loop doing about 31,000 primary-key lookups.
Migration 056 adds the same monthly date bounds to both version updates. The
date-scoped plan uses `features_daily_date_version_idx` and a hash join. The
March retry committed in 36.354 seconds. Plan and profile evidence is in
[`the March update-plan logs`](evidence/phase2/phase2_rank_update_plan_2025-03_date_default_20261022.log)
and [`component profile`](evidence/phase2/phase2_rank_component_profile_2025-03_20261022_retry.log).

The disposable report clone now has 88 successful monthly ranges, covering
2018-10 through 2026-01: 2,582,067 rows per feature version and 5,164,134 rank
updates. February through October 2026 remain. The March 2025 audit row records
two attempts; the completed retry is authoritative. The latest estimated dead
tuple count is 647,221. Phase 2 remains open pending the remaining rank ranges,
forced same-chunk rebuild verification, real E1–E5 evidence and source-dependent
feature coverage. Suggestions remain disabled without a valid champion.

Verification after migration 056: Go tests and vet passed, all 27 Python tests
passed, and the full PostgreSQL migration harness passed on a fresh disposable
test database. Logs are under `docs/evidence/phase2/` with `datefilter_20261022`
in their names. The initial Go test invocation lacked the bundled Python
runtime on PATH; the corrected run passed. The rank runner also now treats an
omitted optional start date as unset, and the passing probe exercises that path.

## 2026-10-22 — S2 probe corrected after rollback-bloat finding

The latest 30/60-session full-repair probe measured 34.303442/151.062488
seconds (exponent 2.138720), then was stopped during the second 120-session
chunk. This is not valid S2 scaling evidence: rolled-back updates still left
393,406 estimated dead tuples in the report-clone feature table. The probe
JSON is marked incomplete, the report copy has zero committed probe audit
rows, and no probe session remains active. The component profile for
2026-08-22..2026-09-21 measured one rank-panel hash at 6.771 seconds and the
read-only rank function at 3.168 seconds; neither alone is a scaling pass.

The runner now measures the read-only shared rank stage over 30/60/120
effective sessions, with a largest-window warm-up and 5-minute statement
timeouts. This matches S2's stage boundary and avoids table writes during the
scaling comparison. The disposable report clone must be vacuumed before that
probe, then real monthly repair remains a separate, checkpointed operation.
No historical repair has started. Phase 2 remains open; real E2/E3, refreshed
E4/E5 and remaining feature-source gates are still outstanding.

## 2026-10-22 — rank probe timeout; market projection fixture passes

Migration 054 is installed on the disposable report database and fixture
database. It shares the production cross-sectional rank calculation with a
bounded repair, records durable chunk attempts and hashes, and rejects changes
to non-rank feature fields. Its fixture assertions pass. Historical repair has
not yet run. The first scaling probe processed 45,513/90,885 V3 rows in
130.478345/167.053286 seconds for its 30/60-session samples, verifying rollback.
The 120-session sample timed out in a later chunk's non-rank hash. No probe
repair rows or audit completions committed. The probe now matches repair's
one-chunk transaction boundary and uses 16 MiB work_mem. Report-clone vacuum
is in progress before a fresh complete 30/60/120-session measurement.
See [the repair log](evidence/phase2/phase2_rank_repair_phase2-rank-repair-053-20261022.log).

The bounded Go test and vet reruns pass, as do eight Rust
unit tests, Rust formatting, and all-target clippy with warnings denied. See
the `phase2_*_rank_recovery_20261022.log` and
`phase2_rust_*_20261022.log` evidence files. A final uninterrupted migration
harness, race run, real E2/E3 and hosted CI are still required. The earlier
27-test Python pass remains recorded, but its latest rerun failed the
five-second health subprocess timeout during vacuum/resource contention
(`phase2_python_market_projection_20261022.log`); a quiet rerun is required.

An additional E2 gap is confirmed: the scoped fixture rebuilds its 60-symbol
cohort, but supplies non-cohort market context from one unchanged persisted
V2 panel. Migration 055 now derives a narrow market-support projection from
the exact canonical production V2 SQL and rejects definition drift. Its fixture
passes binary comparison with fresh V2 output, pre-cut invariance, changed
non-cohort future support, and drift rejection. The revised E2 uses separate
full-universe raw inputs in both branches and routes the canonical VCI view
to branch-specific index bars. The real E2 result remains **NOT RUN**. See
`phase2_market_projection_assertions_20261022.log`. Required source-dependent features and PIT
fundamentals coverage also remain open. Phase 2 is **not ready for Phase 3**.

## 2026-10-22 — rank upgrade and real-evidence harness verification in progress

The clean migration replay through 052 passed, and 052 was installed on the
disposable report clone. Runtime inspection then confirmed that its installed
V2 builder still ranks partial volatility windows, explaining the inherited
E4 mismatch. New migration 053 upgrades that definition, checks rank/input
eligibility, gives Gaussian ranks independent non-null populations, changes the
feature hashes, and rejects stale V2 inputs during V3 builds. All eight Rust
unit tests, the new rank SQL cases, and the complete remaining shared/source/
chunk SQL assertion sequence passed. The clean replay had applied migrations
twice and passed earlier feature/leakage assertions before a cumulative fixture
timeout; an uninterrupted full-harness rerun remains pending. The fixture now
keeps its four passes in one transaction as separate statements with the same
180-second per-statement setting and all original comparisons. Migration 053
was installed on the report clone. Historical output has not been repaired or
certified under these new hashes. All 27 Python tests pass; the Go test attempt
was interrupted for resource contention and must be rerun with bounded build
parallelism.

The original real E3 attempt was canceled while scanning candidate archive
payloads and compared no features. Sampling now precedes mandatory hash and
lineage validation of all 20 selected observations. E2 selection also required
correction: listing snapshots start in October 2026, after its first cut, so the
cohort now uses source-linked historical bar venues. Neither revised real-data
test has a passing result yet. See the [recovery checkpoint](evidence/phase2/phase2_rank_recovery_checkpoint_20261022.md).

Phase 2 remains **IN PROGRESS**. E1, real E2/E3, refreshed E4/E5, PIT coverage,
required source-dependent feature work, current local gates and hosted CI remain
open. Suggestions remain disabled.

## 2026-10-22 — label coverage complete; current E1 fails; Phase 2 remains open

The completed V3 label coverage now spans 2018-10-01 through 2026-10-16. The
current feature set has 2,844,435 rows and `feat.labels_daily` has 5,688,870
rows (two horizons per feature row). 2022 was recovered as H1/H2; the 2023,
2024, 2025 and 2026-to-date chunks are complete in
`phase2-vci-labels-rechunk-20261022`. See the [label recovery checkpoint](evidence/phase2/phase2_label_recovery_20261022.md)
and [durable chunk status and hashes](evidence/phase2/phase2_label_chunk_status_20261022.csv).

The measured 2023 bad-factor scan changed from a 181–189 second per-symbol
nested-loop pattern to a 1.57 second sequential/hash plan. Migration 051 scopes
the planner setting to that query and captures its row count before restoring
the setting. A forced 2023 rebuild reproduced the original output hash
`3c6d2ad64925d19264287c41c6e2ba805826ac3beac653cd2e6bfeac87bcdf2e`, passing
E5 for that chunk. The factor scan and both runner attempts are linked from the
checkpoint above.

The current full-history E1 audit is **FAIL**: 73 of 88 measured features are
outside the literal 1pp null-rate tolerance; 15 are within it and 13 are
source-unverified. A read-only availability breakdown confirms that all
1,021,077 `is_traded=false` rows have null `ret_1` and `close_sma200_ratio`,
but traded-row nulls and other feature deviations remain. This explains some
raw nulls but does not change the E1 result. See the [current E1 report](evidence/phase2/null_rates_full_20261022.md)
and [full CSV](evidence/phase2/null_rates_full_20261022.csv).

The fresh PostgreSQL 18.3 two-pass migration harness v9 **passes**; it is
fixture evidence only, not real-data E2–E4 or hosted CI. Go tests, vet and race,
27 Python tests, Rust fmt/tests/clippy also pass locally; the Rust PostgreSQL
integration test skipped without `DATABASE_URL`. See the [harness
summary](evidence/phase2/phase2-migration-harness-v9-20261022.md) and [current
gate table](evidence/phase2/phase2_gate_status_20261022.md). E2–E4,
PIT-fundamentals coverage, and hosted CI remain open. Completed labels and
passing local fixture checks do not close Phase 2.

## 2026-10-22 — recover 2022 labels as half-year chunks; Phase 2 remains open

This supersedes the preceding “labels remain 0/9” checkpoint. On disposable report clone `vnsignal_phase2_report_20261019`, build `phase2-vci-labels-rechunk-20261022` completed 2022 H1 (342,614 rows, 294,205 ms) and H2 (370,978 rows, 260,659 ms). Both chunks have durable input and output hashes; their combined 713,592 rows match the 2022 annual target count. See the [2022 split checkpoint](evidence/phase2/phase2_labels_2022_split_checkpoint_20261022.md), [chunk status CSV](evidence/phase2/phase2_label_chunk_status_20261022.csv), [captured query plans](evidence/phase2/phase2_labels_2022_autorun_plans_20261022.log), and [H2 runner log](evidence/phase2/phase2_build_phase2-vci-labels-rechunk-20261022_2022H2.log).

`auto_explain` measured the final assembled inserts at 37.7 seconds for H1 and 31.7 seconds for H2, with no conflicts. The earlier annual timeout context names the final insert as the command active at cancellation, but the runner's 30-minute `statement_timeout` was set for the outer `DO` call; that context does not establish that the insert alone consumed 30 minutes. The repeated first-bad-factor scan took about three minutes per half-year and is the measured performance watch item. The old failed annual ledger row remains as historical evidence; the two completed half-year rows cover the 2022 output range.

At this checkpoint labels for 2023–2026 were pending; the newer full-label
checkpoint above records their completion. Corrected E1, real-data E2–E4,
PIT-fundamentals coverage, final local gates, and hosted CI remain open. Phase 2
is **not ready for sign-off**.

## 2026-10-22 — fix the V3 selected-symbol CTE; Phase 2 remains open

Migration 046 fixes a production-path bug: migration 045 renamed the symbol eligibility CTE to `eligible_symbols` but left the downstream selection reading `symbols`. The real 2026 feature attempt failed after 139,501 ms with `relation "symbols" does not exist`; the failed chunk transaction committed no feature rows. An assertion now checks the CTE reference directly, and the fresh PostgreSQL 18.3 two-pass harness v8 passed, including synthetic batch parity and leakage checks ([harness evidence](evidence/phase2/phase2-migration-harness-v8-20261022.md)).

The report-clone migration runner stopped before migration 046 because its existing migration 034 checksum differs from the current source; no migration ledger entry was changed. The additive 046 SQL was applied directly to the disposable report clone, and function introspection confirmed the corrected reference and absence of the stale one. The registered `vnsignal` database and live vnstock quota were not used.

The corrected retry completed the 2026-01-01–2026-10-16 feature chunk: 292,290 rows, `done`, with a 730,650 ms durable step duration and output SHA-256 `5ff467f883e607634c0630ef5458d569d077a8ee6e967b5d7760a0ff1d0c46b2`. All nine feature chunks now total 2,844,435 rows over 2018-10-01–2026-10-16, matching the V2 row count. The full adjustment cache was loaded in 26 fill batches; the measured projection was 22.10 minutes. Runtime detail is in [the corrected 2026 feature recovery evidence](evidence/phase2/phase2_v3_2026_feature_recovery_20261022.md) and [captured runner log](evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021_features_20261022.log). Labels remain 0/9, and availability-aware E1, real E2–E5, PIT fundamentals, final local gates, and hosted CI remain open. Phase 2 is **not ready for sign-off**.

## 2026-10-22 — bounded VCI repair checkpoint; Phase 2 remains open

Migration 044 now installs only bounded backfill support; it no longer rewrites the full V3 table during migration apply. The repair freezes one session-level, one-session-lagged VCI context snapshot and commits 30-calendar-day chunks with durable attempts, row counts, and input/output hashes. Completed chunks are skipped on resume. The PostgreSQL 18.3 two-pass fixture harness v7 passed, including interrupted repair, resume, output-hash verification, and completed-chunk retry assertions ([harness log](evidence/phase2/phase2-migration-harness-v7-20261022.log)).

The DDL is applied to the disposable report clone only. Repair build `phase2-vci-repair-bounded-20261022` is complete: all 98 chunks repaired 2,844,435 V3 rows from 2018-10-01 through 2026-10-16, with 98/98 output hashes and one consistent context hash. The frozen context contains 2,009 rows and has SHA-256 `fca2e344e5cb46a79c021ad5babcb0f23b3f3fba197d3e521cd503a61039d10`. One chunk overlapped autovacuum and took 323.74 seconds; the 63 chunks after cleanup averaged 7.32 seconds (maximum 12.68). After repair, `VACUUM (ANALYZE)` completed in 520.92 seconds, reported zero estimated dead tuples, and the table's normal autovacuum setting was restored. Per-chunk durable state and output hashes are exported to [`VCI repair status`](evidence/phase2/phase2_vci_backfill_status_20261022.csv). The registered `vnsignal` database and live vnstock quota have not been used.

This repairs VCI-derived V3 inherited-index fields; it does not rebuild the stale pre-VCI features and labels. Corrected feature/label builds, eligible-history E1, real E2–E5, PIT fundamentals, final local gates, and hosted CI remain open. Phase 2 is **not ready for sign-off**.

## 2026-10-22 — V3 recovery checkpoint; Phase 2 remains open

Build `phase2-vci-full-rebuild-20261021` committed eight V3 feature chunks for 2018-10-01 through 2025-12-31 (2,552,145 rows). Its 2026-01-01–2026-10-16 feature chunk failed before commit while populating the temporary symbol-batch map; all nine label chunks remain pending for this build. The exact chunk state is [`phase2_feature_chunk_state_20261022.csv`](evidence/phase2/phase2_feature_chunk_state_20261022.csv), and the failed runner output is [`2026 feature chunk log`](evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021.failed.20261021-235301.log). Earlier full-history V3/label rows predate the VCI correction and are stale for sign-off.

The recovery prompt's fallback—a full-universe last-400-session slice plus a 60-symbol real-data subset—was not run. Migration 044's corrected VCI backfill did not complete within the time box, so neither slice has current-correction evidence; the phase remains open rather than conditionally complete.

The synthetic VCI migration and feature assertions pass in the two-pass PostgreSQL 18.3 harness. Migration 045 now uses one set-based join from selected sessions through the adjustment cache's date-first index; it passed the fresh-install harness and patched the already-installed V3 function on the disposable report clone. Migration 044's real-data backfill was canceled after 10 minutes on that clone while scanning/updating the 3.55 GB feature table; the transaction rolled back, so the clone still lacks the VCI backfill view. No registered `vnsignal` data or live vnstock quota was used. See [`recovery evidence`](evidence/phase2/phase2_recovery_checkpoint_20261022.md), [`migration harness`](evidence/phase2/phase2-migration-harness-v4-20261022.log), and [`044 backfill retry`](evidence/phase2/phase2_apply_044_vci_retry_20261022.log).

The read-only E4 integrity query timed out at five minutes without returning metrics. E1–E5 are not complete on corrected current data: the prior E1 report flagged 79 of 88 measured features outside the one-percentage-point tolerance, but it predates the VCI correction and does not account for every feature's trade/input eligibility. The real E2 perturbation, real E3 parity, corrected E1 report, E4 metrics, and E5 repeat-build hash comparison remain open. The fundamentals overlay also lacks PIT coverage for 2018–2021; its 2022 input-hash chunk was canceled, later chunks remain pending, and no live fundamentals calls were made.

Local Go tests, vet, race tests, 27 Python tests, Rust formatting/tests/clippy, and the two-pass SQL harness passed. Hosted CI was not run. Phase 2 is **not ready for sign-off**; do not promote or enable suggestions.

## 2026-10-21 — full-history feature/label checkpoint and VCI benchmark correction

The disposable report clone completed all 2018-10-01–2026-10-16 V3 feature chunks (2,844,435 rows) and label chunks (5,688,870 rows). These outputs were built before the V3 benchmark-source correction below and must be rebuilt before treating them as current. The full-history E1 diagnostic measured 2,844,435 rows and found 79 of 88 measured features outside the one-percentage-point null-rate tolerance; 13 source-unverified fields are expected NULL. VNINDEX context was 100% NULL because the code selected VNDIRECT while the local history has 1,995 VCI VNINDEX rows and no VNDIRECT VNINDEX rows. Other large null-rate deviations remain unexplained. See [`full-history E1 report`](evidence/phase2/null_rates_full_20261021.md) and [`CSV`](evidence/phase2/null_rates_full_20261021.csv).

V3 feature and label benchmark reads now select the registered VCI VNINDEX history. The two-pass SQL migration harness passed on fresh disposable PostgreSQL 18.3 database `vnsignal_phase2_vci_harness2_20261021_test`, including the one-session lag leakage control against the V3-only `vnindex_realized_vol60` field; the final marker is in [`VCI migration harness log`](evidence/phase2/vci_migration_harness2_20261021.log). The fundamentals overlay remains partial: 2018Q4–2021 chunks completed with zero rows; 2022 was marked failed when the build was canceled at the recovery time limit while computing its input hash; 2023–2026 remain pending. The stable chunk summary is [`full-history checkpoint`](evidence/phase2/full_history_checkpoint_20261021.log), with runner output in `docs/evidence/phase2/phase2_build_phase2-full-20261021.failed.20261021-202421.log`. No live fundamentals calls were made.

Phase 2 is **not ready for sign-off**. Rebuild full-history features/labels after applying migration 043, rerun E1 and explain the remaining null deviations, finish the real-data E1–E5 checks, verify PIT fundamentals coverage, and rerun the current-tree Go/Python/Rust/race gates and hosted CI. Real E3 parity remains unrun; see the existing parity evidence below.

## 2026-10-21 — cache manifest scan fixed; two-pass fixture gates passed

The first real 15-symbol cache probe timed out after five minutes while building its manifest, before reading the adjustment view. The old manifest found symbols by scanning and hashing all 2.84M VNDIRECT source-bar rows. Migration 042 now starts from the one-row-per-security `core.symbols` directory and checks source coverage through its symbol index; it retains delisted historical names and excludes only explicit `ops.ml_symbol_scope` exclusions. The cache records readiness, refuses reuse until every batch is loaded and both lookup indexes are valid, and limits the convenience path to small fixtures. The runner keeps one repeatable-read snapshot across probe and cache batches, with a statement timeout per SQL operation; losing that session still requires rebuilding the temporary cache.

The updated two-pass migration harness passed on disposable PostgreSQL 18.3 database `vnsignal_phase2_cache_retest2_20261021_test`. It replayed migrations twice and passed the 2,282-row exact cache parity, batch retry and cache persistence assertions, existing feature/leakage/chunk assertions, rollback fault injection, and unreachable-connection check. The expected injected `ERROR: division by zero` precedes the final `Phase 2 SQL migration harness passed.` marker. Full output: [`phase2_cache_migration_final_pg18_20261021.log`](evidence/phase2/phase2_cache_migration_final_pg18_20261021.log).

This validates fixture mechanics only. The new manifest has not yet completed real 15/30/60 cache probes, so full-history cache time and the full V3 build remain unmeasured. E1–E5 and hosted CI are incomplete; Phase 2 is **not ready for sign-off**. The previous 5432-clone probe used the old manifest and remains the only real cache timing attempt.

## 2026-10-21 — local fixture migration replay passed after cache batching

The two-pass migration harness completed against a fresh disposable PostgreSQL 18 cluster and database. Migrations replayed twice; the Phase 2 cache assertion verified exact row/column parity against the unchanged `core.vndirect_reference_adjustment_details` view, idempotent batch retry, and cache persistence across committed year chunks. Existing Phase 2 feature, leakage, chunk, rollback, and unreachable-connection assertions reached the harness success marker. The injected rollback fault is expected to print `ERROR: division by zero` before the harness reports `Phase 2 SQL migration harness passed.` See [`phase2_migration_local_pg18_20261021.log`](evidence/phase2/phase2_migration_local_pg18_20261021.log).

This proves the migration and fixture mechanics only. The 2,282 cached fixture rows do not measure full-history performance; the required real 15/30/60 symbol adjustment-cache probe, full V3 build, full-history E1–E5 evidence, Go/Python/Rust current-tree gates, and hosted CI remain incomplete. Phase 2 is **not ready for sign-off**. The local PostgreSQL 18 listener on port 5432 did not provide a usable connection in this turn; only the disposable test cluster was used.

## 2026-10-21 — E3 fresh SQL parity attempt timed out; Phase 2 remains blocked

The real-data parity test compiled, then spent 2,015.05 seconds before PostgreSQL canceled `feat.prepare_phase2_adjustment_rows(true)` at its 30-minute statement timeout while creating the transaction-local adjusted-price cache from `core.vndirect_reference_adjustment_details`. It did not reach the selected-date V2/V3 rebuild or compare any of the 20 symbol-days, so E3 has **no parity result**. The test used the disposable `vnsignal_phase2_e3_20261021_disposable` database and an explicit rollback transaction; the cache timeout occurred before feature builders ran, and a follow-up check found no remaining `phase2_sql_parity` connection. See [`E3 fresh rebuild attempt`](evidence/phase2/parity_fresh_rebuild_20261021.md) and its [run log](evidence/phase2/parity_fresh_rebuild_20261021.log). The SQL parity test compiled and `cargo fmt --check` passed. E1 independently remains unmet: the measured null rates exceed tolerance and the disposable report clone has sparse coverage. Phase 2 is **not ready for sign-off**; the full adjustment-cache path needs a bounded performance fix before real E3 can be completed.

## 2026-10-21 — offline verification after E3 test edit

`cargo fmt --check`, the Rust workspace tests (six unit tests; real PostgreSQL parity skipped in the no-database run), Rust clippy, `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python tests passed. `git diff --check` reported no whitespace errors; it only noted the existing CRLF/LF normalization for the two edited Markdown files.

## 2026-10-21 — E1 null-rate diagnostic completed; acceptance remains unmet

The optimized read-only diagnostic completed against disposable report clone `vnsignal_phase2_report_20261019` with a five-minute statement timeout. It returned 101 feature rows for 408,924 V3 rows, 1,346 symbols, and 320 dates. Coverage is limited to 2018, 2019, and five dates in 2026; no 2020–2025 feature rows are present. Many measured features exceed the expected null-rate tolerance by more than one percentage point, so this is a completed diagnostic but **not a passing E1 acceptance result**. The CSV and coverage interpretation are in [`null_rates_optimized_20261021.csv`](evidence/phase2/null_rates_optimized_20261021.csv) and [`null_rates_optimized_20261021.md`](evidence/phase2/null_rates_optimized_20261021.md). The earlier canceled attempt below is retained as historical evidence. No registered database was used.

## 2026-10-21 — E1 null-rate query checkpoint

The read-only null-rate diagnostic ran against disposable database `vnsignal_phase2_report_20261019` with a five-minute statement timeout, then was canceled at line 327 of `sql/diagnostics/phase2_feature_null_rates.sql`. It produced no rates or CSV rows; the captured output is [`null_rates_attempt_20261021.log`](evidence/phase2/null_rates_attempt_20261021.log), with the attempt details in [`null_rates_attempt_20261021.md`](evidence/phase2/null_rates_attempt_20261021.md). E1 remains **NOT RUN**. No production database was used and the diagnostic made no data writes.

## 2026-10-21 — local verification checkpoint

The full migration harness was started on a fresh disposable database and stopped after migration 023 when the next PostgreSQL connection timed out; it did not reach the Phase 2 fixtures/assertions or its success marker. The test database was dropped after confirming it had no active sessions. The attempt log and check summary are [`phase2_migration_ci_20261021.log`](evidence/phase2/phase2_migration_ci_20261021.log) and [`phase2_local_verification_20261021.md`](evidence/phase2/phase2_local_verification_20261021.md). A current-tree Go test run was also interrupted after more than five minutes without returning package results. Neither attempt is a code-test pass or a code-test failure. Go vet, Python, race, current-tree Rust clippy/tests, and hosted CI remain unverified for this checkout.

## 2026-10-20 — Phase 2 implementation checkpoint

**Phase 2 remains IN PROGRESS.** Migration 037 now computes global market context/ranks once, uses an ordered EMA aggregate and prefix-sum differences for rolling float8 statistics, and assembles V3 rows without a per-row JSONB round-trip. The rollback-only 15/30/60 feature-batch scaling probe passed at exponent 1.025; synthetic feature assertions passed for inherited V2 fields, rolling-stat formulas, and batch-size parity. The resumable runner built 2,239 synthetic V3 rows across two year chunks and skipped both on rerun. On the disposable report clone, real 2018 and 2019 feature chunks remain committed. The 2020 retry hit its 30-minute statement timeout while preparing the full-universe symbol-batch map and committed zero 2020 rows. The full-history run is paused pending an actual plan and bounded timing for that population query; see `docs/evidence/phase2/v3_build_diagnosis.md`. The current full-migration, Go, Rust, Python, race, and CI gates must be rerun after these edits before sign-off.

The required null-rate report has **not** yet been produced from full materialized market history. The disposable report clone contains 2,844,683 VNDIRECT source rows and 2,844,435 V2 feature rows. The 2020 retry used 100-symbol batches and a 30-minute statement timeout, but failed before feature output because its full-universe setup exceeded the timeout; no 2020 V3 rows committed. The offline Rust suite passes, including the EMA golden test. A real-data parity attempt was stopped after 772.65 seconds because the reference loader repeatedly reads point-in-time history per symbol and date; it produced no parity result. Labels and E1–E5 evidence are still pending. Source-dependent fields remain NULL until their evidence and mappings are verified. No live fundamentals calls or quota probes were made; the exact source row-ID/unit mapping and fresh absolute quota reservation are still required before such ingestion. Suggestions remain disabled because Phase 3 has not established a champion.

## 2026-10-19 — correction to VNDIRECT price adjustment status

The earlier Phase 1 completion note was too broad for Phase 2 price use: VNDIRECT rows had only their raw, unadjusted OHLC materialized even though archived responses contained a separate `ad*` OHLC snapshot. Migration 026 now materializes that snapshot with its fetch-time vintage while preserving raw `o/h/l/c`, and adds `core.vndirect_bars_as_of(symbol_id, as_of_date)` to reconstruct a point-in-time series. It is applied to the local PostgreSQL 18.3 database: **2,844,683/2,844,683 rows have complete adjusted OHLC and vintage (100.000%; zero missing)**. FPT's 2024-11-29 raw close remains 144.3; its close reconstructed as of the 2024-12-02 ex-right session is 143.3043, versus HOSE's published adjusted reference of 143.300. The 2024-12-02 close remains 142.2 on its own date basis. Phase 2 must use this function for VNDIRECT feature and label prices. VCI, DNSE, and KBS still need their own adjustment-vintage handling before cross-source price joins.

The 2026-10-19 OHLC audit contains 374 VNDIRECT observations across 214 symbols and 35 sessions where the raw open or close is outside the reported matched-price high/low range; 347 opens and 33 closes are outside, with six observations in both sets. The user confirmed the open/range relationship can be valid in Vietnamese market data, so it is not an exclusion or rewrite rule. Five of the 33 close conflicts already had action-related model-price corrections; migration 033 is applied and corrects the remaining 20 positive-volume HOSE model closes using CafeF's exact same-session open/high/low and matched volume plus official HOSE tick increments. The other eight close conflicts have zero volume and remain in the history as non-traded observations. The registered database now has 25 total evidence-linked model OHLC overrides, 1,328 reference-factor decisions with zero invalid factors, and all 2,844,683 adjusted snapshots complete. Raw VNDIRECT bars and lineage remain intact; all 374 rows stay in the Phase 2 price series. Cophieu68 comparisons remain separate because their price levels use a different basis. Row evidence and source hashes are in the [OHLC conflict audit](probe/phase2-adjustment/ohlc-discrepancy-audit-20261019/README.md).

**State: INCOMPLETE overall; Phases 0 and 1 are COMPLETE, Phase 2 is in progress, Phases 3–5 are not started, and Phase 6 is in progress. No trading recommendations are enabled.** The official HNX calendar and canonical bar dates reconcile for 2018-10-01–2026-10-16: 2,008 expected sessions, 2,008 observed, no missing or unexpected dates. For partial research, the user approved treating residual VCI zero-volume observations with no conflicting positive matched-volume evidence as zero-volume/no-matched-trade observations. This is a working classification, not exchange-certified proof of no trade or lifecycle status; it is not a missing-bar count. Preserve raw rows and `ZERO_VOLUME_UNVERIFIED` audit findings; 24 positive alternate matched-volume dates remain conflicts, 109 negotiated-only dates remain separate activity, and 19 exact HNX zero-matched reports remain exchange-confirmed. Do not synthesize OHLC bars or fill dates without a source row. Zero-volume sessions can occur on UPCoM, HNX (including SPC), and HOSE. Vietstock's tested route failed known HNX positive controls and is not used to certify the residual zeros. The 2026-10-16 DQ run (`3cd86137-dec5-4dc3-9e35-ccee9c886f1b`) PASSED with 30 audited, same-session VCI/VNDIRECT pairs. VNDIRECT supplies a separate source-attributed historical research series; The daily task refreshes VCI canonical bars and VNDIRECT in its separate source series; Phase 2 reads VNDIRECT through its point-in-time adjustment view. CTR's five post-UPCoM/pre-HOSE VCI rows remain intact in canonical history and are excluded from the ML-eligible view through source-row-linked lifecycle events.

Latest Phase 1 update (2026-10-19): official HNX reports returned all 80 selected ticker/session rows for the 16 partial-history tickers across 2026-10-12–2026-10-16. Thirteen tickers traded in that window; CDG, VFC, and VNX had zero matched volume on all five sessions. VNDirect-attributed pages report latest matched dates for those three as CDG 2025-05-13, VFC 2026-07-03, and VNX 2026-07-28; HNX confirms positive volume on each stated date. A targeted KBS probe returned 80 NAS shares on 2020-10-15, matching local VNDIRECT and DNSE volume. A new 16-date exact HNX sample (one unresolved date for each partial-history ticker) returned one row per symbol and zero matched volume/value on all 16. Seven BSC exact-date responses corroborate four HNX matched controls and show the three later VNX totals were negotiated volume with zero matched volume; the parser correction is now committed as an append-only interpretation in the working database. The unresolved zero-volume issue partition remains 14,314 ticker/dates, not 14,314 confirmed missing bars; 22 HNX reports comprise 19 zero-total and three negotiated-only rows.

The wider provider search found HNX's official UPCoM daily InfoFile package with separate matched/put-through volume and value, listed at VND 2,000,000/month with a two-week trial; the public product documents do not confirm whether a trial supplies historical archive files. FiinGroup's per-stock UPCoM schema defines `TotalMatchVolume` as round-lot matching, `TotalDealVolume` as round+odd-lot negotiated, and `TotalVolume` as matched+negotiated round+odd-lot activity. `TotalVolume - TotalDealVolume` is a candidate all-lot matched measure by inference from those field definitions, pending a controlled authorized HNX sample. ICE lists HNX/UPCoM historical and EOD data from February 2020. Current SSI docs make FastConnect a practical no-fee lead: existing SSI brokerage customers can create API keys online, and daily OHLC covers UPCOM from a symbol's first trading date with bulk history. SSI's service overview says there is no manual approval, but its Terms & Environments page still says registration requires approval; verify the live portal flow. No SSI key is configured here, and matched odd-lot semantics, adjustment behavior, and ML retention rights still need a sample and confirmation. These feeds have not been accessed, so the 14,314 activity-date partition and Phase 1 status are unchanged. Exact findings and provider links: [`source search`](probe/phase1-source-search/README.md).

The registered database already has 495 completed full-range KBS raw landings for all 16 partial tickers. Their 23 positive rows on VCI zero-volume issue dates all overlap positive VNDIRECT/DNSE dates. A KBS FPT cash-dividend probe classifies its default OHLC price fields as adjusted; adjustment vintage remains unresolved. A broader CafeF export used its public annual download for the same 16 tickers: 144 hash-recorded workbooks, 31,381 rows, and full symbol/date reconciliation. On the 14,466 VCI zero-volume issue dates, CafeF reports 23 positive matched-volume rows (all overlap existing VNDIRECT/DNSE positives), 106 negotiated-only activity rows, 14,159 zero-volume rows, and 178 absent rows. The 106 negotiated-only dates remain activity evidence, not matched OHLC bars. The original CafeF/HNX partition had 14,333 dates with neither positive matched nor negotiated-volume evidence nor an exact HNX no-match finding; the targeted HNX sample resolved 16, leaving 14,317. Three later VNX dates add negotiated-only activity confirmed by HNX and BSC, leaving 14,314 remaining unresolved dates and 109 distinct negotiated-only dates. The 22 exact HNX reports comprise 19 zero-total and 3 negotiated-only findings. CafeF's corrected MM/DD/YYYY date filter resolved the earlier inconsistent singleton results. See [`CafeF audit`](probe/phase1-cafef-history-audit/README.md), [`KBS audit`](probe/phase1-current-kbs-verify/README.md), [`HNX/public activity checks`](probe/phase1-public-activity-check/README.md), and the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md). No canonical bars, VCI quality-issue rows, or manual lifecycle-event rows changed; exact HNX reports were appended to the exchange evidence ledger.

Verification after the VNDIRECT adjustment and close correction: `go -C go test ./...` (with `VNPIPE_PYTHON=py`), `go -C go vet ./...`, and `py -m unittest discover -s tests -v` passed (27 Python tests). `tests/sql/test_migration.sh` passed against a clean PostgreSQL 18.3 database, including two complete migration passes, the adjusted-price backfill fixture, the 20 close-correction fixture/assertions, and schema checks. The tagged PostgreSQL integration suite passed without `-race` against the disposable `vnsignal_test` database. The local Windows toolchain has CGO disabled and no GCC/Clang compiler, so the race-enabled tagged PostgreSQL suite could not run here; hosted CI remains the place to verify race instrumentation. The registered database has migration 033 applied; all 2,844,683 VNDIRECT rows retain complete adjusted OHLC and fetch-time vintage.

Local PostgreSQL 18.3 confirms 1,519 current listings, 1,754 observed securities, 1,742 company profile observations and 12 profile errors. Each full VCI range has 1,502 COMPLETED, 16 PARTIAL and 1 BLOCKED job; across both ranges this is 32 PARTIAL jobs and two blocked UTT attempts. SHA-verified offline replay audited 989 landings and removed 3,131 stale issue records; `core.bars_daily` has 1,809,966 rows across 2,008 dates. Separate history tables contain 2,844,683 VNDIRECT rows and 2,172,122 DNSE rows. `core.index_bars` now contains a source-keyed 1,995-row VCI VNINDEX history. VCI quality records include two copies of one `high < low` observation and 50 invalid-open issue rows (25 distinct symbol/dates); 25/25 have valid same-session VNDIRECT bars and 14/25 also have DNSE bars. The invalid-open reports concern unusable source open values, not an open outside high/low; auction-price extrema remain allowed. The 158-member Tier A snapshot remains recorded. The two malformed UTT backfill attempts remain BLOCKED as audit evidence, but UTT is excluded from future per-symbol collection and has no verified positive-trade tenure; the Tier A selector requires 250 prior traded sessions, so UTT is outside its candidate set. Source `traded_value` remains NULL; its separately labeled proxy is approved for research.

The 32 VCI partial jobs (16 tickers, two overlapping ranges each) now have a deduplicated date-level source audit. Across those tickers, 13,955 positive VCI bars and 14,338 positive VNDIRECT dates were found; 388 positive VNDIRECT dates have no positive canonical VCI bar (338 have no VCI quality issue and 50 map to a VCI issue date). DNSE has 13,485 positive dates, including 100 without a positive VCI bar. Of 14,466 VCI zero-volume issue dates, 24 have a same-day positive alternate bar; the remaining 14,442 have no positive alternate. Nineteen of those dates are now verified as HNX no-match sessions (three prior SHC reports plus the 16-date sample); 14,423 remain lifecycle-unverified, including 109 separately tracked negotiated-only dates. The narrower activity partition has 14,314 dates with neither positive matched nor negotiated-volume evidence nor an exact HNX no-match report. New targeted HNX lookups confirmed positive exchange volume for all 26 VCI invalid-price/OHLC dates and confirmed the latest positive VNDIRECT date for all 16 audited tickers (15 UPCoM records plus SPC on the HNX-listed route). UTT's 16 CafeF-omitted sessions also have explicit HNX zero-volume rows; HNX was not queried for every UTT session. See [`phase1-partial-audit/README.md`](probe/phase1-partial-audit/README.md), [`HNX latest-positive audit`](probe/phase1-hnx-last-trade-audit/README.md), the [`UTT history audit`](probe/phase1-utt/README.md), the [`EasyStock source audit`](probe/phase1-easystock/README.md), the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md), and the [`corporate-action price-basis check`](probe/phase1-adjustment/README.md).

The BSC follow-up downloaded 31,935 dated rows for these 16 tickers from 2018-10-01 through 2026-10-16, archived across 47 hash-recorded pages. It found no new activity date beyond existing evidence: 24 matched-volume issue rows equal existing VNDIRECT/DNSE values, 106 negotiated-only rows equal CafeF, and three more equal the HNX-confirmed VNX deals. All 23 prior BSC/HNX controls, 12 additional per-symbol negotiated-volume samples, and the last positive BSC activity date for all 16 tickers match the exact HNX reports. The last positive BSC activity observations for CDG and VNX are negotiated-only and later than the previously recorded matched-volume dates. BSC's zero rows remain non-evidence of no trade; its table lacks high/low and reuse terms were not established. One XMC row on 2019-06-27 is flagged for venue attribution because its current UPCoM profile starts on 2019-06-28. No BSC rows were imported. See the [BSC history audit](probe/phase1-bsc-history-audit/README.md).

| Phase | Status | Evidence | Unfinished exit criteria |
| --- | --- | --- | --- |
| 0: probe/schema/config | COMPLETE | Registered-machine vnstock 5.0.3 probes; absolute quota verified; migrations 001–026 applied locally; worker uses the registered Community profile; local Go test/vet, Python, PostgreSQL 18 migration/integration checks pass; clean-HEAD GitHub Actions run 39023562253 passed Go race/vet, Python, and PostgreSQL 16 checks | None; current-tree PostgreSQL 16.15 migration and integration checks passed locally |
| 1: ingestion/backfill | COMPLETE | VCI has 1,502 complete histories; all 16 VCI-partial symbols have completed source-keyed VNDIRECT histories; UTT is explicitly excluded; all 1,518 in-scope symbols therefore have at least one completed history; 30 VCI/VNDIRECT pairs passed the 2026-10-16 DQ gate; zero-volume handling is approved for the residual partial-research observations; VNDIRECT adjusted snapshots are materialized for 2,844,683/2,844,683 rows with raw OHLC preserved | None for Phase 1. Phase 2 must use the VNDIRECT as-of function; VCI, DNSE, and KBS still need separate adjustment-vintage handling before cross-source price joins |
| 2: features/PIT | IN PROGRESS | Migrations 034–046; bounded VCI inherited-index repair is complete for 2,844,435 existing V3 rows on the disposable clone; migration harness v8 passes; the 2026 V3 chunk retry is in progress, labels are 0/9, and E1/real E2–E5 remain open | complete corrected features and labels; complete availability-aware E1, real E2–E5, PIT fundamentals, current-tree Go/Rust/Python/race gates, and hosted CI |
| 3: models/backtest | NOT STARTED | architecture specified | real Rust training, 36+ monthly OOS folds, calibration, backtest |
| 4: serving/portfolio | NOT STARTED | architecture specified | atomic SQLite export, parity, optimisation |
| 5: desktop UI | NOT STARTED | architecture specified | Tauri/Svelte views and performance evidence |
| 6: daemon/operations | IN PROGRESS | local Windows Task Scheduler refresh registered for 06:00 Asia/Ho_Chi_Minh through audited VCI and separate VNDIRECT ingestion | backups, seven unattended trading-day runs, and recovery evidence |

**No mock or fabricated price history, quota report, test performance, expected return, or model confidence is presented as genuine.** CI is deliberately offline and may not consume a user's vnstock account/device quota.

> The dated sections below preserve earlier evidence. The latest 2026-10-19 Phase 0/1 exit audit below supersedes older queue, zero-volume, and test-status snapshots; earlier entries are historical records.

## 2026-10-18 — Phase 1 verification update

- Tier A tenure counts distinct pre-as-of positive-volume VCI bars linked to checksum-valid raw landings. The exact verified listing snapshot still defines the as-of candidate universe. A local check found 1,321/1,505 candidates with at least 250 prior traded dates. The 2026-10-16 build passed tenure, then correctly refused ranking because source `traded_value` is NULL for A32 on 2026-09-18; no Tier A membership was written.
- DQ replay now accepts the observed provider route `market.equity.ohlcv` as well as the internal `equity_ohlcv` alias. The current gate run `e13ea9a1-5837-4a63-a061-95689ee19889` remains STALE with no Tier A members and no selected cross-source pairs. A targeted KBS probe for APF/2018-10-19 returned `AdapterError` and no repair row.
- Added `VNSTOCK_HOME` to the worker's narrow environment allowlist so Go can use the already registered profile state after changing directories. Validation passed: `VNPIPE_DISABLE_LIVE=1 go -C go test -count=1 ./...`; `go -C go vet ./...`; `.venv\Scripts\python.exe -m unittest discover -s tests -v` (26 tests); and `go -C go test -mod=mod -tags "postgres postgres_integration" -p 1 ./... -count=1` against disposable `vnsignal_test`.
- The PostgreSQL-tagged tests deadlocked once when package binaries ran concurrently against their shared disposable database; serial execution passed and CI now uses `-p 1`. Migrations 001–016 and SQL schema assertions ran twice on PostgreSQL 18.3, and the numbered Go migrator verified checksums twice. Direct rollback and unreachable-database assertions passed. The shell wrapper could not finish locally because Git Bash did not resolve `grep`; PostgreSQL 16 hosted CI remains unverified.
- `go -C go test -race ./...` remains unverified locally: with `CGO_ENABLED=1` and installed GCC selected, Go's Windows `cgo.exe` exits with status 2. No race-test pass is claimed.
- A full-range VNDIRECT Finfo query corrected the initial volume-field mistake: `nmVolume` and `ptVolume` are both zero on all 248 HNX sessions for UTT from its first session (2025-10-17) through 2026-10-16. The same endpoint returns 62,800 `nmVolume` for KAI on 2026-10-16 as a positive control. CafeF's 232 returned rows also have zero matched/negotiated volume. Classify UTT as having no recorded executions in the audited period; its repeated 9.2 reference fields are not ML bars. Raw responses and hashes are in [`phase1-utt/README.md`](probe/phase1-utt/README.md).
- A read-only reconciliation of the 32 VCI `PARTIAL` jobs found 16 tickers, each with two overlapping range attempts. The audit deduplicates 14,492 issue ticker/dates: 14,466 zero-volume, 25 invalid-price and one invalid-OHLC. All 26 invalid-price/OHLC dates have a positive same-session VNDIRECT bar; 24 zero-volume dates have a positive same-session bar in at least one alternate source. The remaining 14,442 zero-volume dates stay unverified. VNDIRECT has 14,338 positive dates across these tickers, including 388 without a positive canonical VCI bar; 338 of those have no VCI issue record. DNSE has 13,485 positive dates, 100 without a positive VCI bar. Source rows remain separate and keep raw landing/row/hash lineage. Exact CSV exports, read-only queries, and HNX profile-date lookup links are in [`phase1-partial-audit/README.md`](probe/phase1-partial-audit/README.md); researched venue-profile dates were not inserted as first-ever lifecycle evidence.

## 2026-10-16 P0 hardening evidence

- `go -C go test ./...`, `go -C go test -race ./...`, `go -C go vet ./...`: passed locally.
- `VNPIPE_DISABLE_LIVE=1 python -m unittest discover -s tests -v`: 15 offline tests passed locally, including JSONL main(), oversized input, broken pipe, vendored stdout print, CLI errors and route exceptions.
- `tests/sql/test_migration.sh`: checked into CI, runs migration twice and tests constraints, trigger canonicalization, PIT dates, rollback and connection failure against PostgreSQL 16. **Not run locally (PostgreSQL unavailable). Do not claim green CI until the hosted run completes.**
- `VNPIPE_DISABLE_LIVE=1` is enforced by both the Go quota gateway and Python adapter in CI. The active probe is now a Go-only metered sequence; direct Python `probe(active=True)` fails closed.
- Default config is validated on CLI probes/budget requests; invalid risk cap, timezone, unknown keys and exchange limits are rejected.
- The current CLI has no scheduler, SQLite serving or training. Active OHLCV and company-profile ingestion use `Gateway.CallRecorded`; the remaining `Gateway.Call` in the CLI is the metered probe path. Scheduler, serving and training failure paths cannot be signed off yet.
- Live quota usage API shapes, account entitlements, Postgres outage during migrations, and cross-source real-price data were not exercised. No actual API/device quota was consumed by tests.

## CI repair and next Phase 1 increment (2026-10-16)

- Reproduced hosted Go failure by running `VNPIPE_DISABLE_LIVE=1 go -C go test -race -count=1 ./...`. Four injected gateway tests inherited the hosted CI live-disable flag; added `t.Setenv(..., "0")` only inside those tests. The `TestDisabledInCI` safety test retains the disabling flag and still passes.
- New `ingest.NormalizeBars` validates saved vendor OHLCV frames, refuses unknown/invalid columns, duplicates, non-chronological dates, and numeric invalidity, and never synthesizes missing prices.
- `preview-backfill` generates an offline, budget-capped deterministic plan only from a verified active probe and absolute quota readings. It cannot call the market API.
- `sql/migrations/002_ingest_state.sql` adds backfill jobs and per-attempt reservations for future Postgres integration; CI migration tests now apply both numbered migrations twice, with new invalid-completion and duplicate-reservation assertions.
- Historical note: this section predates the transactional PostgreSQL store added below. Remaining: live source verification, stock-listing import, full historical backfill, models and desktop app. No Phase 0/1 exit claimed.

### Backfill execution boundary (work in progress)

`go/internal/ingest/runner.go` now defines `Runner.RunBarsBackfill`. Offline tests confirm a successful worker response gets validated and committed once, repeated completed jobs consume no additional quota, storage errors fail closed, and hosted CI cannot call the vendor. Every market call goes through `live.Gateway`, never directly through the Python worker.

`LandingStore` was initially an interface; the PostgreSQL implementation and explicitly authorized tagged `backfill` command have now been added, as described below.


## Phase 1 continuation — transactional ingest boundary (2026-10-16)

Implemented and committed on main:

- New database transaction store (`go/internal/ingest/postgres.go`) records a per-attempt reservation before invoking vnstock, records dispatch and result status, and writes raw landing, canonical `core.bars_daily`, and `COMPLETED` marker together. Duplicate/completed job IDs do not request data twice.
- A new singleton `ops.quota_guard` (migration 003) enforces an absolute, durable, cross-process allowance; verifies short-lived vendor readings; retains cross-process pacing after restart; and never returns calls previously counted as spent. A reservation is spent even on a canceled or failed request.
- `live.CallRecorded` refuses absent/failing audit hooks and records failures/cancellation, and the runner quarantines frames that do not match the requested symbol/period/ID. Vendor rate limits remain retryable with a renewed verified quota and expired lease; entitlement errors and invalid frames block the affected job.
- A Windows/Linux native migration command with checksum registry and PostgreSQL dollar-string-aware parser replaces a shell-only runtime process.
- Tagged PostgreSQL integration tests cover real transaction commit/resume, absent-symbol rollback, and durable quota exhaustion across store instances. CI now runs PostgreSQL 16, the native migration command twice, and the tagged driver tests. These **have not been executed locally**, because PostgreSQL and the pinned pgx dependency are not available in this offline build environment.
- A narrowly scoped opt-in `backfill --active` path is wired only for PGX-tagged binaries, current verified absolute quota, a previous successful active probe, and already-known listed symbols. It intentionally does not infer missing symbol metadata or schedule itself.

Historical 2026-10-16 offline evidence recorded a passing Windows race run on an earlier checkout; that result is superseded for current sources. On 2026-10-18, `go -C go test -race ./...` failed before test execution because Windows ThreadSanitizer could not allocate its shadow region (error 87); no current-source race pass is claimed. No live price calls were made. **Phase 1 remains PARTIAL** until full listed-universe coverage, lifecycle and quality exclusions, DQ gates, PostgreSQL 16 CI and runtime operation are verified. No Phase 2–6 exit milestones are claimed.

## Point-in-time equity listings and exact raw bytes (2026-10-16)

- Implemented and pushed strict v5 `equity_list` normalization using documented `symbol`, `exchange`, `icb_code_lv2` fields. Go active probe now saves the complete frame it already requested, alongside its summary, without an extra API call.
- Added `vnpipe import-listings --probe FILE`, requiring a complete active-probe frame with at least 1,000 symbols across HOSE/HNX/UPCOM. PostgreSQL importer preserves original rows and SHA-256, upserts `core.symbols`, appends dated `core.listing_snapshots`, and marks absent names inactive rather than deleting them. Transaction, advisory lock, idempotency, backdate rejection and >5% shrinkage guard enforce safe state changes.
- Migration `004_raw_bytes.sql` records the original vendor JSON bytes as `bytea`, because JSONB canonicalization prevents reliable original-byte SHA comparison; legacy rows remain nullable. Both listing and OHLCV landings write bytes. Added SQL and tagged PostgreSQL tests for exact-byte parity.
- **Verification:** new listing parser and store code passed isolated stdlib Go race/unit tests and vet locally. The full repository Go test suite, PostgreSQL 16 integration, GitHub push workflow result, installed vnstock v5 probe and actual listing import were **not** executed or observed in this environment. All Phase 0/1 exit gates remain open until these are verified on CI and the registered machine.

## Database-derived historical backfill queue (2026-10-16)

- The live `backfill --active` command now selects its candidates directly from the latest verified PostgreSQL `core.listing_snapshots` and `core.symbols`, with no manually maintained `--symbols` file.
- A repeatable-read transaction validates at least 1,000 active symbols across HOSE/HNX/UPCOM, equal listing/active sets, no future or older-than-seven-day snapshot, and SHA-256 parity of the original `raw.landings.payload_bytes` for the corresponding equity listing response. Any mismatch blocks dispatch.
- Completed and blocked jobs are excluded **before** quota-capped planning. Recent RESERVEd/RUNNING job leases are skipped, and leases older than 15 minutes can be retried through the existing durable reservation code. This fixes repeated first-batch starvation.
- The command refreshes passive vendor status/absolute usage, builds its plan using **fresh** quota figures rather than stale quantities embedded in the active probe, and records progress counts. A future date, absent provenance, stale listing, or percentage-only quota fails closed. Repeating exactly the same date range keeps job idempotency.
- Offline coverage: `go test -race -count=1 universe.go universe_test.go universe_driver_test.go` and `go vet` passed in an isolated standard-library test harness. A tagged PostgreSQL 16 test now covers real snapshot import, completed/blocked/leased resume, raw-byte tampering and partial active flags; that tagged test **has not been executed here**.
- **Phase 1 still incomplete:** GitHub-hosted CI result was not returned by the connected tool; installed vnstock probe, PostgreSQL 16 integration, actual ingest/backfill, row throughput, full history coverage and cross-source/data-quality validation remain unverified. Phases 2–6 are still not ready to enter.

## Source-to-universe parity and read-only progress (2026-10-16)

- Hardened `LoadVerifiedBackfillUniverse`: checksum-only integrity was insufficient. It now parses the exact archived vendor listing frame and cross-checks each symbol, exchange and ICB code with the latest PostgreSQL listing state in a consistent transaction. Coordinated relational metadata tampering cannot pass by retaining the same row counts.
- Expanded the offline `database/sql` fake-driver tests to use a **valid** three-exchange, 1,002-symbol listing frame and cover a checksum-valid but membership-tampered database. Added a PostgreSQL integration regression test for coordinated symbol metadata changes.
- Added the read-only `backfill-status --from DATE --to DATE [--source vci]` CLI, returning backfill status counters and at most ten pending symbols without requesting market data or spending quota.
- Verified isolated Go tests with `-race` and `go vet` in a reconstructed standard-library module containing these components. Full repo/PGX CI and the real PostgreSQL 16 integration are not verified in this environment. **Phase 1 is not complete**; no live backfill or recommendation is claimed.

## Quota freshness during long backfills (2026-10-16)

- The five-minute PostgreSQL quota-guard expiry no longer forces every lengthy backfill to stop at the first expiry. `Runner.BeforeCall` now invokes a fail-closed refresh check **only for unfinished jobs, before the local pacer and durable reservation**.
- When less than 90 seconds remain, the runner obtains a new **passive** vnstock status/usage report. It accepts only authenticated Community status (reported internally as `free`) and exact usage limits/counters, deriving remaining daily/monthly calls and using the reported per-minute rate. Missing, Guest, percentage-only, mismatched-worker-ID, or changed-tier readings stop the run before a new market call.
- The refreshed observation is installed through `PostgresStore.InstallQuota`, which retains the lesser of verified remaining allowance and previously unspent budget, preserving all historical reservation records. The new preflight refuses to roll an old Vietnam trading-day quota into a later day; starting the next day's run requires fresh explicit authorization.
- Added Go standard-library unit/race tests for quota guard expiry, database failure, missing observations, tier changes, worker response validation and the no-reservation-on-refresh-failure invariant. Corrected the existing injected storage-failure test to exercise the actual commit path instead of an earlier response-ID mismatch.
- Added a tagged PostgreSQL 16 regression test proving refresh does not replenish three already-consumed reservations. **This tagged test has been committed but has not been executed in this container.** Isolated local Go tests with `-race` and `go vet` passed; the full repository suite and GitHub Actions push checks remain unverified.
- The live historical backfill is still opt-in; there is no automatic unattended overnight/day-boundary daemon. **Phase 1 remains partial.** No real market calls were made here and no model, signals or production serving were enabled.

## CI triage and Phase 1 continuation (2026-10-16)

- GitHub Actions run 66 on `e42516e` exposed two independent regressions: the CI guard test still passed the removed `--symbols` flag, and one raw-byte SQL assertion used an invalid `DO $ ... END $` block. The Go failure also kept the tagged PostgreSQL job from reaching compilation.
- Updated the CI guard test to use supported arguments and added a check that caller-supplied symbols remain rejected. Fixed the PL/pgSQL block to use `$$` delimiters. The tagged integration helper is now named `installVerifiedQuota` to avoid colliding with the `verified` fixture in `planner_test.go`.
- Added `go.sum` and pinned transitive pgx module requirements in `go.mod`; `go mod verify` passes.
- Local checks on Go 1.23.0: `go test -race -count=1 ./...`, `go vet ./...`, and a tagged PostgreSQL build-only run all pass. All 15 Python worker tests pass; Python compilation and TOML parsing pass.
- PostgreSQL 16 service execution is not available in this container because service setup requires privilege transitions the runtime blocks. GitHub Actions run 67 on `a43f0a9` passed the PostgreSQL 16 migration assertions, native migration twice, and tagged database integration tests; it also passed the Go race/vet and Python jobs. The local tagged run compiled the PostgreSQL code but did not execute database tests.
- **Phase 1 remains PARTIAL.** The installed vnstock v5 probe, real listings import, quota-capped historical bars backfill, full coverage, throughput, and end-to-end quality gates still require the user's single registered machine and its local PostgreSQL database. No live market call was made here; no Phase 0/1 exit is claimed.

## 2026-10-16 — authenticated local passive vendor report

- The user registered vnstock 5.0.3 successfully. The CLI status reports `tier=free` (the Community account tier) and `authenticated=true`; the passive probe supplies exact usage limits and counters.
- The fresh report shows 60 requests/minute, 3,600/hour, 10,000/day and 100,000/month, with zero used in each bucket. The report root has `active=false`; no market-data route was called.
- This confirms local authentication and the v5 quota JSON shape only. The active capability probe, listings import, and historical backfill remain unverified. Credentials and device identifiers are intentionally omitted.


## 2026-10-16 — registered-device listing probe

- The user ran the active `equity_list` route from `docs/probe/retry6/2026-10-16.json`. It returned 1,754 rows with columns `symbol`, `exchange`, `organ_name`, `organ_short_name`, and `icb_code_lv2`: HOSE 406, HNX 299, UPCOM 814, and DELISTED 235.
- The initial importer accepted only the three trading exchanges. The live probe proved the provider also returns a `DELISTED` category, with no original exchange. The importer now preserves the complete frame and exact source bytes in `raw.landings`, excludes those 235 rows from `core.symbols`, `core.listing_snapshots`, and backfill candidates, and reports provider/current/excluded counts. It does not infer their prior exchange.
- The Windows Unicode transport fix is in `d04bba5`; Go, Python, and PostgreSQL CI passed. The DELISTED-aware importer is in `1407695`; its Go race/vet, Python, and PostgreSQL 16 migration/integration jobs all passed. No probe JSON containing company rows is committed.
- **Phase 1 remains partial:** the local PostgreSQL migration/import, quota-capped daily-bar backfill, queue resumption, coverage and end-to-end quality gates still need to run on the registered machine.

## 2026-10-17 — Observed historical securities master (Phase 1 still PARTIAL)

- Added migration 008, an offline `vnpipe rebuild-security-master` command, and transactional integration into future verified listing imports. Replays existing `equity_list` raw landing bytes, verifies SHA-256 and full HOSE/HNX/UPCOM membership against dated imported listing snapshots, then preserves the entire provider frame including `DELISTED` category.
- CI run https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/38987359951 passed Go, Python and PostgreSQL integration, including delisted-symbol retention, byte corruption rejection and replay idempotency. **Local registered-device migration/rebuild is not yet reported as executed.**
- The October 16 archived listing should produce 1,754 observed symbols (1,519 currently exchange-listed + 235 provider DELISTED) after local migration/rebuild, with **no additional vnstock request or changed OHLCV job state**.
- Delisted effective dates, first-ever public trading, exchange-transfer history and the pre-2026 investable universe remain **UNKNOWN** until independently evidenced. This is not full historical membership reconstruction. Phase 2–6 are not begun or declared complete.

## 2026-10-17 — Local Phase 1 database audit

- The initial audit verified all 10 recorded migrations. Migrations 011–013 were subsequently applied locally; all 13 recorded SHA-256 checksums matched.
- The verified current listing contains 1,519 active HOSE/HNX/UPCoM symbols; the observed security master contains 1,754 tickers. `ops.company_profile_jobs` reports 1,742 `IMPORTED` and 12 `ERROR`; 1,742 profile observations are archived. Error states remain explicit and are not filled with placeholders.
- The exact existing OHLCV range is 2018-10-01 through 2026-10-16. Read-only `backfill-status` reports 362 `COMPLETED`, 180 `PARTIAL`, 975 pending, 2 deferred prior `InvalidFrame` jobs, 0 blocked and 0 active leases. The expired HMD lease is eligible for normal quota-guarded resume. `core.bars_daily` currently contains 627,164 rows across 538 symbols.
- The quality ledger contains 309,528 `ZERO_VOLUME_UNVERIFIED`, 625 `INVALID_OHLC` and 2 `INVALID_PRICE` observations. These are retained as quality findings; zero-volume rows are not treated as executed trades. Reprocessing already archived OHLCV frames was a no-op (0 inspected), so these counts were unchanged.
- Queue detail audit: all 180 `PARTIAL` jobs have `last_error_type=PartialInvalidTradedBars`, source VCI, one attempt each, and cover 201,383 canonical rows (20–1,994 rows per symbol). Their first bars range from 2018-10-01 to 2022-11-08 and last bars from 2023-12-08 to 2026-10-16. Their retained quality findings are 625 `INVALID_OHLC` across 178 jobs, 2 `INVALID_PRICE` across 2 jobs, and 132,068 `ZERO_VOLUME_UNVERIFIED` across 176 jobs. The two deferred `InvalidFrame` jobs (`A32`, `ABC`) remain pending after one attempt each and have no bars in the requested range.
- A fresh passive probe (`active=false`) through the project `.venv`, reconfirmed on 2026-10-17, reported `tier=guest`, `authenticated=false`, `limit_source=policy_v1` for usage. These policy figures are not valid registered-account quota evidence. No live data route was called during this audit; live ingestion must wait for a fresh authenticated absolute quota report.
- Replayed the PostgreSQL CI migration checks on an isolated PostgreSQL 18.3 `vnsignal_test` database: all 13 migrations applied twice; schema assertions, the injected rollback fault and the connection-failure check passed. Tagged PostgreSQL tests for `internal/ingest` and `internal/dq` passed, including the one-reservation profile audit transitions and persisted DQ blocking result. The disposable database was dropped after verification. This does not replace the hosted PostgreSQL 16 run.
- Offline verification on this revision passed `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...` (with `VNPIPE_PYTHON` set to the project `.venv`), `go -C go vet -p 1 ./...`, and all 23 Python worker tests. The first Go test attempt used the blocked Windows Store Python alias; rerunning with the project interpreter passed. GCC 16.2.0 exists at `C:\msys64\ucrt64\bin\gcc.exe`, but Go starts with `CGO_ENABLED=0`; the explicit cgo race build failed in `runtime/cgo` with exit status 2 before tests ran. The race suite is not verified on this machine; this is not a missing-GCC finding.
- Migration 013 records observed bar dates in `core.calendar`; the local union now has 2,008 observed dates from 2018-10-01 through 2026-10-16. `vnpipe dq-run --date 2026-10-16` persisted a newer `STALE` run (`cc804e57-47c8-4aef-86a3-d5c1d479aa89`). Calendar lookup now finds the expected and preceding observed dates, but Tier A membership and all 30 independent cross-source pairs are absent, so the gate remains blocking. No fabricated samples were added. This proves fail-closed reporting, not full-coverage validation or a passing gate.
- Phase 1 exit is **not met**: 975 jobs remain pending, 180 remain partial, two legacy invalid frames are deferred, the passive vnstock report is Guest/unauthenticated, and Tier A plus independent cross-source evidence is absent. Phases 2–6 remain unstarted.

## 2026-10-17 — Phase 1 calendar and DQ gate increments

- Added migration 014 to make bar-derived calendar evidence reversible. Inserted dates are added; moving a bar removes the old date only after its final bar leaves; deleting the final bar removes only the `observed_bars` source and note while preserving other calendar sources, notes, and session status.
- The disposable `vnsignal_test` database applied migrations 001–014 twice and passed schema assertions, including date move/delete and merged-provenance cases, injected transaction rollback, and unavailable-connection checks. Tagged PostgreSQL integration tests passed for `internal/ingest` and `internal/dq`. The test database was created after confirming it was absent and dropped after verification. The local `vnsignal` migration runner verified prior SHA-256 records and applied migration 014; post-migration checks found 2,008 observed-bar dates for 2,008 distinct bar dates and no stale `observed_bars` calendar rows.
- `RunPostgresGate` now loads previous/current traded bars for exchange-limit action checks, allows a listing-day exemption only with unambiguous archived `FIRST_EVER_PUBLIC_TRADE` evidence, and blocks dated Tier A quality issues (`INVALID_OHLC`, `INVALID_PRICE`, `INVALID_VOLUME`) plus matching `PARTIAL`/`BLOCKED` OHLCV jobs. `ZERO_VOLUME_UNVERIFIED` observations are quarantined and reported as warnings, not treated as executed trades.
- PostgreSQL fault-injection coverage confirmed that an over-limit HOSE move produces the specified warning and quarantine, a Tier A invalid-bar issue plus a partial OHLCV job both block the gate, and 30 selected source-name pairs without landing/row lineage still block. These fixtures ran only in disposable `vnsignal_test`; they are not production market data.
- Latest offline checks passed: `go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, all 23 Python tests, the migration script, and tagged PostgreSQL integration tests. Live routes remained disabled; no vnstock market-data call was made.
- GCC 16.2.0 is installed at `C:\msys64\ucrt64\bin\gcc.exe`, but is not on this shell's default `PATH`; Go therefore defaults to `CGO_ENABLED=0`. With `CGO_ENABLED=1`, explicit `CC`, GCC on `PATH`, and a workspace-local Go cache, the full `go -C go test -race -p 1 -count=1 ./...` run fails while building Go's `runtime/cgo` (`cgo.exe: exit status 2`) before package tests. A direct C syntax-only check using the installed GCC succeeds (exit 0); this does not clear the Go/cgo failure. Visual Studio 2022 Build Tools and `cl.exe` are also installed; a targeted race build using that compiler likewise stalled without output and was interrupted. WSL distro enumeration returns `E_ACCESSDENIED`. Race coverage remains unverified. Do not claim it passed.
- After migration 014, `vnpipe dq-run --date 2026-10-16` persisted STALE run `d309013e-1c37-45f9-8935-4726bf7dccf3`: Tier A membership is unavailable, there are 0 of 30 selected cross-source pairs, and the scoped bar/staleness/session-count checks cannot pass. This is fail-closed evidence, not full-coverage validation.
- Phase 1 remains **PARTIAL**. The registered-device passive report is still Guest/unauthenticated, so no fresh verified absolute quota exists to safely resume the 975 pending jobs or retry the 180 partial and two deferred invalid-frame jobs. There is still no dated Tier A membership or independent second-source OHLCV evidence. No usable production cross-source sample has verified source-landing/row lineage, and no feature-snapshot table exists for a database drift measurement. No Phase 1 exit is claimed.

## 2026-10-17 — source-attributed ingestion and lineaged cross-source DQ

- The worker now preserves an allowlist of vnstock source/provider attribution fields. Live OHLCV ingestion and archived-frame recovery require `attributes.source` to match the explicitly requested source; missing or mismatched attribution is quarantined. The frame remains within the 400-line adapter limit.
- Migration 015 adds nullable primary/secondary landing IDs and zero-based row indexes to DQ samples. Existing rows remain unlineaged and do not count as ready. Readiness counts only selected Tier A pairs with all four lineage fields.
- `RunPostgresGate` now replays exact `payload_bytes`, verifies SHA-256, route, symbol, frame shape/order, selected session, traded OHLCV and provider source/organisation attribution, confirms stored-close parity, and requires distinct provider organisations. Only validated pairs reach the 0.5% close comparison.
- PostgreSQL 18.3 disposable `vnsignal_test` applied migrations 001–015 twice; schema assertions, injected rollback and unavailable-connection checks passed. The app migration runner applied 15 migrations and then verified a zero-change second run. Tagged `internal/dq` and `internal/ingest` integration tests passed: a healthy 30-pair fixture passed, while missing lineage, mismatched provider attribution, same-organisation sources, tampered payload bytes, and a real close mismatch failed as required. All fixture rows and the disposable database were removed.
- The local `vnsignal` database applied migration 015. A new local `dq-run` for 2026-10-16 persisted STALE run `9a5b1467-73df-4a14-b62c-b7e74f95c81d`: Tier A membership is unavailable, 0 of 30 selected lineaged pairs exist, and the scoped bar/staleness/session-count checks cannot pass. No production cross-source values were added.
- Offline checks passed: `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, all 24 Python tests, the migration script, and tagged PostgreSQL integration tests. No live vnstock data route was called. The explicit race build used installed GCC 16.2.0 with `CGO_ENABLED=1` and failed inside Go `runtime/cgo` before package tests (`cgo.exe: exit status 2`); direct GCC C syntax checking passed. Race coverage remains unverified; this is not a missing-GCC finding.
- Phase 1 remains **PARTIAL**. Passive vnstock status is Guest/unauthenticated, so full backfill cannot safely resume; there are still 975 pending jobs, 180 partial histories, and 2 deferred invalid frames. The new schema and validator make cross-source evidence auditable, but no verified Tier A universe or independent second-source OHLCV evidence currently exists. Phases 2–6 remain unstarted.

## 2026-10-18 — Phase 1 remains PARTIAL

- The latest local audit remains anchored at 2026-10-16 market data: 627,164 daily bars across 538 symbols, with bars on 2026-10-16 for 324 symbols. The OHLCV queue has 362 `COMPLETED`, 180 `PARTIAL` (`PartialInvalidTradedBars`), two deferred `PENDING` invalid-frame jobs (`A32`, `ABC`), and one `RUNNING` job (`HMD`); 974 currently listed symbols have no job. Company-profile coverage remains 1,742 archived observations and 12 explicit errors.
- The latest dated PostgreSQL DQ result remains `STALE` (`9a5b1467-73df-4a14-b62c-b7e74f95c81d`): dated Tier A membership is empty, and there are zero selected lineaged cross-source samples. Verified first-public-trade lifecycle evidence is still absent, so the strict Tier A builder correctly fails closed. No production Tier A membership or cross-source values were fabricated.
- Migration 016 adds append-only enforcement to `raw.landings`. PostgreSQL 18.3 disposable migration/schema checks and tagged `internal/ingest` and `internal/dq` integration tests passed through migration 016; the disposable test database was removed. PostgreSQL 16 CI remains unavailable locally because the Docker daemon is not running.
- Offline verification on this checkout passed `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, and all 24 Python JSONL tests. The full race run again stopped in Go `runtime/cgo` (`cgo.exe: exit status 2`) despite installed GCC at `C:\msys64\ucrt64\bin\gcc.exe`; race coverage is unverified. No live market-data route was called.
- The 2026-10-18 vnstock status command returned `authenticated=false`, `tier=guest`, and an error that it could not retrieve the current client policy from vnstocks.com. This does not establish whether the user's prior registration/key entry succeeded, but it provides no valid authenticated absolute-quota evidence. The saved active probe is dated 2026-10-16 and is stale for the 24-hour index-backfill preflight. Full equity backfill and the VNINDEX/KBS one-call path therefore remain gated. Phase 1 exit criteria are not met; Phases 2–6 remain unstarted.

## 2026-10-18 — Phase 1 latest verification

- The guest status above came from the project-local vnstock state directory. The registered Community account is under the Windows profile `.vnstock`; setting `VNSTOCK_HOME` to that authenticated state directory makes the Go worker's passive preflight report authenticated absolute limits. The latest snapshot at 05:11 +07 shows 6,105 daily and 96,092 monthly calls remaining, with zero pending reports. The profile path, not the API key, is passed to the worker; the key remains in vnstock's encrypted local state.
- VCI history remains 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`; canonical traded value remains NULL in every bar. A SHA-verified source-link count shows 1,321 of 1,505 bar-backed current symbols have at least 250 positive-volume pre-as-of VCI sessions. The Tier A builder accepts that tenure evidence but blocks on the absent source traded-value field; no proxy or synthetic value was introduced.
- The 2026-10-15 FPT KBS compact probe and VCI canonical row both report close 58.0. A KBS APF probe for the invalid VCI date returned `AdapterError` and produced no repair row; no retry was made. Compact reports remain probe-only and do not satisfy durable cross-source lineage.
- The existing active `market_calendar` probe returned 355 rows attributed to `source=builtin`, route `reference.events.market`, organisation `Vnstock Project`, spanning 2000-01-01 through 2026-11-24 with event fields rather than a complete exchange-session list. The report did not retain the raw event frame. This does not satisfy the independent exchange-calendar requirement.
- Latest DQ record is still `e13ea9a1-5837-4a63-a061-95689ee19889`, status STALE, with no Tier A membership or selected lineaged pairs. The source route replay bug is fixed, but Phase 1 still lacks a verified full exchange calendar, source traded value, 30 durable pairs, and resolution of partial/blocked histories.
- Offline Go tests, `go vet`, all 26 Python worker tests, and the serial PostgreSQL integration suite passed. Migration/schema checks passed twice on a disposable PostgreSQL 18.3 database; PostgreSQL 16 hosted CI is pending. The migration shell script's final grep step could not run under local Git Bash. The Windows race test remains unavailable because Go `cgo.exe` exits with status 2 even with GCC enabled.

## 2026-10-18 — authenticated registered probe and backfill outcome

- A passive status report from the default sandbox returned Guest; the same local vnstock 5.0.3 installation returned authenticated Community status (`tier=free`) when run in the registered machine's network context. The active report at `docs/probe/backfill-2026-10-18/2026-10-18.json` records seven route schemas. VCI equity OHLCV returned 1,995 rows from 2018-10-18 through 2026-10-16 (observed maximum history 2,920 days); KBS index OHLCV returned 1,000 rows from 2022-10-12 through 2026-10-16. The raw probe remains local because it includes registered-device metadata and source frames.
- The fresh passive report was authenticated and server-sourced: limits 60/minute, 3,600/hour, 10,000/day, 100,000/month; used 3,888/day and 3,901/month; 20 reports pending. It is evidence of the account at that observation time, not an entitlement guarantee for future routes.
- `backfill --active` ran for the verified VCI depth, 2018-10-18–2026-10-16, with a 10-session monthly budget and a 1,519-call cap. Final read-only queue status: current listing 1,519, source provenance verified, 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`, 0 leased, 0 deferred-invalid and 0 pending. All 1,519 requests have durable quota reservations and corresponding raw landing records. The database has 1,807,778 daily bars through 2026-10-16; 1,505 of 1,519 current symbols have at least one bar. The runner recorded 1,590 invalid traded rows and 851,190 zero-volume-unverified rows; partial states and findings were preserved.
- The blocked equity frame was quarantined as `InvalidFrame: missing/invalid source row count`. No retry was issued. A separate one-call KBS index request was also quarantined: the 2023-05-15 frame has `low` above `close`; it committed zero index bars. Do not retry either frame until a source-specific repair or newly verified route is available.
- Latest persisted DQ result `738362b1-6bf6-49c2-bdd1-4a6ca07f6c27` is `STALE` with five blocker categories: Tier A universe unavailable, no selected cross-source sample (0 of 30), bar checks, staleness, and invalid session counts. There are zero `FIRST_EVER_PUBLIC_TRADE` lifecycle records and zero selected cross-source samples. The calendar contains 2,008 `observed_bars` dates but no independently verified exchange calendar. No Tier A membership or cross-source evidence was fabricated.
- Local PostgreSQL 18.3 has migrations 001–016 applied, including append-only triggers on `raw.landings`. Phase 1 remains **PARTIAL**: the queue is exhausted, but the 494 partial histories, one blocked equity frame, 14 current symbols without bars, invalid KBS index frame, and missing calendar/lifecycle/cross-source evidence prevent exit. Phases 2–6 remain unstarted.
- Verification after the run: `go -C go test ./...` and `go -C go vet ./...` passed with `VNPIPE_PYTHON` set to the project `.venv`; all 24 Python JSONL tests passed; `git diff --check` passed. `go -C go test -race ./...` was attempted with `CGO_ENABLED=1` and installed GCC 16.2.0 (`C:\msys64\ucrt64\bin\gcc.exe`), but Go `runtime/cgo` exited with status 2 before package tests. GCC is installed; race coverage is unverified. PostgreSQL 18.3 migration/integration checks passed through 016 in the disposable test database; PostgreSQL 16 CI cannot run locally because Docker is unavailable. Rust/desktop tests are not available for the unstarted later phases.

## 2026-10-18 — registered key recheck and liquidity-route entitlement

- The local registered vnstock profile was used without copying the key into the repository. A fresh passive report at 05:43 +07 (`docs/probe/phase1-authenticated-probes/passive-recheck/2026-10-18.passive.json`, local-only) returned `authenticated=true`, `tier=free`, and server-sourced absolute limits of 60/minute, 3,600/hour, 10,000/day, and 100,000/month; usage was 3,895/day and 3,908/month, with zero pending reports. This is a current account snapshot, not a market-data entitlement for every route.
- The active `equity_trade_history` capability probe at 05:41 +07 (`docs/probe/phase1-authenticated-probes/2026-10-18.json`, local-only) returned `EntitlementError` for the Community account, with no usable daily traded-value rows. Do not retry this route unless the account entitlement changes; a fresh quota snapshot alone does not grant it.
- The one governed retry of the stale HMD job used a fresh quota snapshot and a new durable reservation, then returned `AdapterError`; it committed no landing. The old-range HMD job is now pending at attempt 2. Do not retry without a source-specific repair. The latest read-only status for the verified VCI range 2018-10-18–2026-10-16 remains 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`, and zero pending or leased jobs across 1,519 current symbols.
- The authorized Community key resolves authentication. Phase 1 remains **PARTIAL** because `core.bars_daily.traded_value` is NULL, the exact trade-history route is not entitled under the current Community account, DQ has no eligible Tier A universe or 30 selected lineaged pairs, and the observed-bar union is not an independently verified exchange calendar. No turnover proxy was written or treated as exact. Phases 2–6 remain unstarted.

## 2026-10-18 — registered source probes and Phase 1 liquidity evidence

- The existing local registration was verified as Community tier on the network-enabled machine; the sandboxed status command cannot reach the account policy endpoint and falls back to Guest. No new registration was needed. The last complete passive quota report before the targeted probes supplied absolute limits and counters; the five raw-price requests each passed fresh quota preflight and used the metered Go probe path.
- The compact reports in `docs/probe/phase1-authenticated-probes/` record VCI APF raw-price reads and KBS FPT equity reads. APF on 2018-10-22 is a valid one-row observation; on 2018-10-19 the full-precision source row still has `high=9.19157 < close=9.21682`, so it remains quarantined as a provider inconsistency. KBS FPT returned 1,994 rows for 2018-10-18 through 2026-10-15, one row on 2026-10-15, and zero rows on 2026-10-16; all saved KBS equity reports include matching `kbs` source and KB Securities (KBSV) organisation attribution. These probes establish route/provider capability only; they are not canonical backfill rows or the 30 selected, lineaged cross-source pairs required by DQ.
- All 1,807,778 canonical daily bars still have `traded_value IS NULL`. Vnstock's [market-data documentation](https://www.vnstocks.com/docs/vnstock/thi-truong-market) describes equity prices in thousand VND and notes historical adjustment. `close × volume × 1,000` is therefore an adjusted-close-based estimate, not verified executed turnover. It remains exploratory and is not written into the source `traded_value` field or used to claim Tier A eligibility.
- Phase 1 remains PARTIAL. The registered key resolved the auth blocker, but DQ still lacks an independently verified exchange calendar, valid point-in-time tenure evidence for Tier A, liquidity values under an approved basis, and 30 durable independent cross-source pairs. No production data was fabricated and no recommendation is enabled.
- Offline verification on this checkout: `VNPIPE_DISABLE_LIVE=1 go -C go test ./...`, `go -C go vet ./...`, all 26 Python JSONL tests, `go -C go test -tags postgres_integration -run '^$' ./internal/dq` (compile-only), and `git diff --check` passed. The PostgreSQL-tagged integration was not executed against a database. The race suite remains unverified: with CGO enabled and GCC 16.2.0 installed at `C:\msys64\ucrt64\bin\gcc.exe`, Go `runtime/cgo` exits with status 2 before project package tests.

## 2026-10-18 — KBS raw-only path and current Phase 1 gate

- Added `vnpipe ingest-kbs-cross-source` with explicit `--active`, date range, a default one-call cap and a hard maximum of 30. Candidate symbols come from positive-volume VCI bars. The call uses `Gateway.CallRecorded`; the store verifies KBS attribution, exact response bytes, SHA-256, the running job and its successful reservation before writing append-only `raw.landings`. It does not write `core.bars_daily` or select DQ pairs.
- A fresh passive preflight authenticated the registered profile and installed a local quota guard at 06:02 +07. The one-call FPT/KBS request for 2026-10-15 was durably reserved, then the vendor returned `AdapterError`; job 2067 remains `PENDING` at attempt 1 with reservation outcome `FAILED`. No KBS equity landing or canonical-bar change resulted. A separate metered `probe-ohlcv` recheck also returned `AdapterError`; it saved no frame. No further retries were made.
- A read-only database check after the calls found zero KBS equity landings, 1,807,778 VCI canonical bars, and all 1,807,778 `traded_value` fields still NULL. The verified VCI range remains 1,024 `COMPLETED`, 494 `PARTIAL`, and 1 `BLOCKED` jobs.
- The offline `dq-run --date 2026-10-16` produced `682243a2-f6de-4fba-a959-d852dcacf4a5`, status `STALE`, with blockers for unavailable Tier A, 0/30 selected cross-source pairs, no bars in the DQ sample, invalid staleness, and invalid session counts. Publication remains disabled.
- Verification on this machine: `go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover -s tests -v` passed (27 Python tests). The serial PostgreSQL-tagged integration suite passed against disposable local `vnsignal_test` on PostgreSQL 18.3. `go -C go test -race ./...` remains unverified because Go's Windows `runtime/cgo` exits with status 2 even with GCC installed. PostgreSQL 16 hosted CI remains unverified.

## 2026-10-18 — official closure evidence and worker error redaction

- Added [`docs/probe/phase1-calendar-overrides-2019-2026.sql`](probe/phase1-calendar-overrides-2019-2026.sql) and applied 103 explicit `is_session=false` overrides to the local database for HNX-notified holiday closures and make-up Saturdays spanning 2018-12-31 through 2026-09-02. Sources are the official HNX annual notices for 2019–2026 and the 2019/2026 adjustment notices. A pre-insert audit found no canonical bars on these dates; a post-insert audit found 103 rows and zero overlapping canonical bars.
- A gate run for the explicitly closed 2026-01-02 date recorded run `d5a5c694-053e-478f-bdc2-65f11cd2a986` as `STALE` and reported “expected date is not a verified trading session.” It also remained blocked by missing Tier A membership, 30 cross-source pairs, bars for that date, and valid session counts. This verifies that the override controls the gate; it does not complete the exchange calendar.
- The HNX evidence supplies scheduled closures only. Ad hoc exchange suspensions, a complete list of open sessions, and the full 2018 schedule remain unverified. The DQ result remains blocking.
- Fixed the worker JSONL error frame to use a constant safe message instead of including vendor exception text. Python JSONL tests passed (27); Go tests and `go vet` passed when run with a writable workspace cache and the installed project Python interpreter. The Windows race run and PostgreSQL 16 CI migration check remain to be recorded before Phase 1 sign-off.
- A fresh passive report at 06:35 +07 authenticated the registered Community profile (`tier=free` in the library status field) and returned server-sourced absolute limits/counters. The local `quota_guard` was refreshed before the next call. One new KBS `A32` request for 2026-10-15 was reserved through `CallRecorded`, returned `AdapterError`, and committed no frame or landing; the earlier FPT attempt has the same outcome. Both jobs remain pending at attempt 1, KBS equity landings remain zero, and no retry was made.
- Re-ran `dq-run --date 2026-10-16`: run `4f6b9e3b-6523-47c5-baa5-bf796f70bd50` remains `STALE` with blockers for unavailable Tier A, 0/30 selected cross-source pairs, no bars in the DQ sample, invalid staleness, and invalid session counts. The 2026-01-02 closure check is also persisted as `STALE` because it is explicitly not a verified session.
- Local PostgreSQL 18.3 migration checks passed on a new disposable database: all 16 migrations applied twice, schema assertions and the quarantine diagnostic passed, and injected rollback and unreachable-connection checks behaved correctly. The Bash CI wrapper could not start in this Windows sandbox; its checks were run directly with PowerShell/`psql`. Re-running tagged integration tests against a separately named database was refused by their safety guard; the existing `vnsignal_test` database has stale rows and fails the schema assertion, so it was left untouched. PostgreSQL 16 hosted CI remains unavailable.
- The race run was retried with `CGO_ENABLED=1`, `CC=C:\\msys64\\ucrt64\\bin\\gcc.exe`, and workspace-local Go caches; `runtime/cgo` still exits with status 2 before package tests. GCC is installed, but the Windows race suite is not verified. Phase 1 remains partial: the Community entitlement does not expose exact daily executed turnover, VCI still has 494 partial and one blocked history, and there are zero durable KBS landings or selected cross-source pairs.

## 2026-10-18 — approved research proxy and updated Phase 1 evidence

- Tier wording: the user's registered key is **Community**. Vnstock's internal `status()['tier']` value is `free` for that user-facing tier; it is not the user's account name. The account is authenticated, and the documented Community equity OHLCV sources are VCI and KBS.
- The user's approval supersedes the earlier hold on a liquidity proxy. Migration 017 was applied to the working database and verified on a fresh disposable PostgreSQL 18.3 database with all 17 migrations and `tests/sql/schema_assertions.sql`. `core.bars_daily_with_proxy` exposes `traded_value_proxy_vnd = adjusted close × volume × 1,000`; the source `traded_value` field remains untouched. The working database has 1,807,778 canonical bars, including 1,807,695 non-null proxy values; the remaining 83 are null and are not imputed.
- Tier A was built for 2026-10-16 using 20 checksum-linked VCI sessions and the approved research proxy. The result contains 158 symbols from 1,519 verified listed symbols; 824 candidates without a complete, valid 20-session window were excluded. This enables research ranking/features only; it does not establish execution capacity or enable recommendations/order sizing.
- Supported VCI history spans 2018-10-18 through 2026-10-16: 1,024 jobs `COMPLETED`, 494 `PARTIAL`, and 1 `BLOCKED`. The requested 2018-10-01 start is beyond the observed VCI depth. Targeted HMD/HMG requests for the earlier range and the fresh KBS probe returned `AdapterError` and committed no usable frame/landing; no additional retries were made.
- DQ run `83703cc8-5257-404a-892b-ec8796d3d7bb` for 2026-10-16 is `FAILED` only at the cross-source comparison gate: it has 0 of the required 30 durable, independently attributed same-session pairs. A fresh KBS capability probe returned `AdapterError`; KBS raw equity landings remain zero. Phase 1 therefore remains **PARTIAL**, and DQ publication/recommendations remain disabled.
- After the Tier A code changes, `go -C go test ./...`, `go -C go vet ./...`, `python -m unittest discover -s tests -v` (27 tests), and `git diff --check` passed. The fresh-database migration/schema checks passed on PostgreSQL 18.3. PostgreSQL 16 hosted CI and the Windows race suite remain unverified.

## 2026-10-18 — KBS date coverage and refreshed DQ result

- The registered account is Community; `free` remains the library's internal tier identifier. A fresh passive report collected through the Go worker confirmed authenticated status and server-sourced absolute limits.
- Four one-day KBS equity requests were durably reserved through `Gateway.CallRecorded`: AAA returned `AdapterError`, AAS and ABB returned the sanitized cause `NetworkError`, and ACB returned a frame without a valid source row count and was blocked. None produced an equity landing.
- Two multi-day AAA requests succeeded and wrote append-only raw landings with KBSV organisation attribution: the requested intervals 2026-10-01..2026-10-16 and 2026-10-01..2026-10-17 both returned 11 rows ending 2026-10-15. No Oct 16 KBS row was present; no canonical VCI bars were changed.
- Added an optional `--sample-date` to `ingest-kbs-cross-source` so symbol selection can use the dated Tier A set while the KBS request interval extends beyond it. The selector still requires 30 complete, same-session, independently attributed pairs and writes nothing when fewer than 30 qualify.
- `select-dq-cross-source --date 2026-10-16` found 0 of 30 complete candidates and wrote no samples. DQ run `ca9b7bc4-b781-4568-a87f-a8f6856d67e4` is `FAILED` with the sole reported blocker `cross-source sample unavailable: have 0 explicitly selected rows (0 Tier A), require exactly 30 Tier A pairs`.
- After these Go changes, `go -C go test ./...` passed with the project `.venv` interpreter, `go -C go vet ./...` passed, and `python -m unittest discover -s tests -v` passed all 27 tests. The PostgreSQL-tagged selector packages compiled with `-run '^$'`; no tagged integration test was executed against a database.
- Phase 1 remains **PARTIAL**. The Oct 16 gate result does not close the separate history, invalid-row, and complete-calendar exit criteria; recommendations remain disabled.

## 2026-10-18 — authenticated VCI backfill and KBS session-date check

- The registered Community profile was authenticated on the local machine. An active `equity_ohlcv` capability probe succeeded and reported VCI available with 1,995 rows spanning 2018-10-18 through 2026-10-16. The report is saved at [`docs/probe/phase1-continuation/escalated/2026-10-18.json`](probe/phase1-continuation/escalated/2026-10-18.json); `free` in its status object is the library's internal label for Community.
- The quota-guarded VCI backfill ran for 2018-10-01..2026-10-16 against the verified 2026-10-17 listing snapshot (1,519 symbols). All eligible jobs reached a terminal state: 1,023 `COMPLETED`, 495 `PARTIAL`, 1 `BLOCKED`, 0 pending. The start date predates observed VCI history; no rows were fabricated before 2018-10-18. A separate explicit retry of the two deferred legacy `InvalidFrame` jobs produced one `COMPLETED` and one `PARTIAL`; no deferred invalid-frame jobs remain. The blocked UTT frame still has `InvalidFrame: missing/invalid source row count` and was not promoted.
- A separate metered VCI `probe-ohlcv` request for UTT over 2018-10-01..2026-10-16 returned no usable frame (`available=false`, count 0, no 2026-10-16 target row). Its report is at [`docs/probe/phase1-continuation/utt/2026-10-18-UTT-070950.002524400Z.json`](probe/phase1-continuation/utt/2026-10-18-UTT-070950.002524400Z.json); the blocked job was left unchanged.
- Thirty KBS equity requests for 2026-10-15..2026-10-16 were durably reserved and wrote 30 append-only raw landings only. All 30 frames were attributed to KBS but contained October 15 as their latest row; none contained October 16. One fresh KBS request for 2026-10-16..2026-10-17 returned `InvalidFrame: missing/invalid source row count` and wrote no landing. No KBS response changed canonical VCI bars.
- `select-dq-cross-source --date 2026-10-16` found 0 of 30 fully verified same-session pairs and wrote no samples. DQ run `aee82540-e14f-4a34-9e71-44f2a0b55514` is `FAILED` because the required 30 Tier A pairs are unavailable. October 15 KBS rows cannot be substituted: Tier A membership and VCI bars must match the same session.
- Phase 1 remains **PARTIAL**. The VCI queue is drained, but partial/blocked outcomes and the missing same-day KBS pairs keep the quality gate closed; publication and recommendations remain disabled.

## 2026-10-18 — HNX official schedule reconciled to the full backfill calendar

- The HNX Guide to Trading Stocks states that stock trading runs Monday through Friday except public holidays; HNX's annual trading-holiday notices cover 2018–2026, with later adjustments recorded for 2019, 2024, 2025, and 2026. The source-backed import is docs/probe/phase1-hnx-calendar-2018-2026.sql.
- Applied the schedule to the local PostgreSQL vnsignal database. It records 105 HNX-notified closed dates in core.calendar_overrides and the 2,008 expected weekday sessions in core.calendar, each with the applicable HNX notice URL in its notes. The 2024 correction adds April 29 and May 4 as a non-trading makeup Saturday.
- Reconciliation for 2018-10-01 through 2026-10-16 found 2,008 expected sessions and 2,008 observed canonical bar dates, zero expected sessions without bars, zero bars on an effective closed date, and zero conflicts between closures and observed bars. Thus the calendar gap is closed for this historical window; the current event route remains useful for future notices.
- Re-ran dq-run for 2026-10-16; run d91f0e81-079f-479f-871c-0e453e46fc14 is FAILED solely because 0 of 30 explicitly selected same-session Tier A cross-source pairs are available. The calendar, bar-presence, staleness, and session-count checks no longer block that date.
- Phase 1 remains PARTIAL. The latest full-range VCI batch is 1,023 COMPLETED, 495 PARTIAL, and 1 BLOCKED; KBS frames still end on 2026-10-15 and do not satisfy the 2026-10-16 pair gate. No proxy was written into source-reported traded_value, and no recommendations were enabled.

## 2026-10-18 — KBS full-history probe after HNX calendar import

- The audited `ingest-kbs-invalid-history` path fetched 2018-10-01–2026-10-16 for all 494 remaining partial-VCI symbols. Including the earlier A32 request, the database now has 495/495 completed KBS jobs, 495 succeeded durable reservations, 495 checksum-verified append-only raw landings, and 578,108 archived rows. No KBS rows were written to `core.bars_daily`; canonical bars remain VCI-sourced.
- Reconciliation against 1,593 unique VCI invalid symbol/date observations found same-date KBS rows for 1,519, valid traded KBS OHLCV for 937, closes within the DQ 0.5% tolerance for 646, and both valid KBS bars and close agreement for 174. These are candidates for later explicitly sourced ML use; none were silently promoted or used to rewrite VCI history.
- KBS history reaches 2026-10-15 for 247 symbols and has zero 2026-10-16 rows. DQ run `ccf40583-e83f-449c-9d88-a962070d8bed` for 2026-10-16 is `FAILED` only on the latest-session cross-source gate: zero of the required 30 selected Tier A pairs. Calendar, bar-presence, staleness, and session-count checks pass; an Oct 15 KBS row is not substituted for Oct 16.
- Verification: Go tests passed with `VNPIPE_PYTHON` set to the project `.venv`; `go -C go vet -p 1 ./...` and all 27 Python JSONL tests passed. SQL verified all 495 succeeded reservations and matching raw-payload checksums. Phase 1 remains **PARTIAL** with 495 VCI partial jobs, one blocked job, and the Oct 16 pair gate unresolved. Race coverage remains unverified and PostgreSQL 16 hosted CI is unavailable locally.

## 2026-10-18 — official exchange calendar and auction-aware OHLC recovery

- The HNX Guide to Trading Stocks sets the weekday rule (Monday–Friday except public holidays). The annual HNX exchange notices and specific adjustments provide the actual closure dates, including makeup Saturdays when HNX explicitly did not trade. The source-backed import is `docs/probe/phase1-hnx-calendar-2018-2026.sql`; it records 105 closure overrides and 2,008 expected sessions from 2018-10-01 through 2026-10-16. Local reconciliation found 2,008 observed canonical bar dates, zero expected dates without bars, and zero bars on a recorded closure.
- HOSE establishes open/close in separate ATO/ATC call auctions; its quote-field guide defines High/Low as continuous-matching extrema, so a HOSE open can validly sit outside that interval. This is venue-specific: HNX-listed equities use continuous matching plus a closing auction, while UPCoM stocks use continuous matching throughout the session. SSI's official stream schema reports Open/Close separately from highest/lowest matched prices but does not specify whether its extrema include auction prints. Because the generic bar schema lacks reliable session-phase metadata, migration 019 and the validator require positive finite O/H/L/C, `high >= low`, and nonnegative finite volume without requiring H/L to contain O/C. See the HOSE [order-type rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf), HNX [trading FAQ](https://www.hnx.vn/vi-vn/hoi-dap.html), SSI [stream field definitions](https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage), and HOSE quote-field [guide](https://estock.duytan.edu.vn/kien-thuc-dau-tu/kien-thuc-chung-khoan/bai-3-huong-dan-doc-bang-gia-truc-tuyen-tai-hose-70.html).
- Offline replay reclassified 989 checksum-verified VCI landings under validator `vn-equity-auction-extrema-v1`: 495 in the 2018-10-01 range (including six previously partial quarantine frames) and 494 in the 2018-10-18 range. The two replay audit groups record 3,131 removed stale issue entries. Raw bytes and quota reservations were unchanged. The canonical database now has 1,809,966 bars across 2,008 dates. Remaining quality findings are two copies of one genuine high-below-low row and 50 invalid-open rows.
- Both full VCI history ranges now have 1,502 COMPLETED, 16 PARTIAL and 1 BLOCKED jobs. The remaining two blocked job rows are UTT frames with missing/invalid provider row counts and no canonical 2026-10-16 UTT bar. The existing 158-member 2026-10-16 Tier A snapshot remains recorded; a fresh build attempt correctly failed closed on the two blocked UTT jobs.
- Selection for 2026-10-16 again found 0 of 30 complete durable same-session KBS/VCI pairs and wrote no samples. DQ run `29a134d2-ac69-4ac8-bb5e-ea4deae261bd` is FAILED solely at that cross-source gate. KBS archived equity history still ends at 2026-10-15 for observed symbols; no prior-session rows were substituted.
- Verification: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed with the project `.venv` runtime. Targeted PostgreSQL integration tests passed on the disposable local test database, including recovery of a partial quarantine frame. PostgreSQL migration/schema checks passed earlier on local PostgreSQL 18.3; PostgreSQL 16 hosted CI is unavailable locally. The Windows race run with installed GCC stopped because ThreadSanitizer could not allocate its shadow region (error 87).
- Phase 1 remains PARTIAL. The calendar and auction-aware OHLC checks are reconciled, but unresolved VCI partials, the malformed UTT frame and the 0/30 latest-session KBS pair gate prevent Phase 1 exit. Phase 2–6 work and recommendations remain disabled.

## 2026-10-18 — alternate historical sources and VNDIRECT-backed DQ

- The user authorized alternate providers for static history where vnstock/VCI is incomplete, with vnstock/VCI retained as the intended daily refresh route. Historical data stays source-keyed and independently attributed; no DNSE or VNDIRECT values are relabeled as VCI.
- VNDIRECT now has 2,844,683 rows across all 1,519 current symbols for 2018-10-01 through 2026-10-16. Its requested-range jobs are 1,518 `COMPLETED` and one `PARTIAL` (BCF: 27 foreign `VCBF-BCF` rows are issue-recorded and excluded; valid exact-BCF rows remain stored). 1,823,358 rows have positive normal-market volume; 1,021,325 zero-normal-volume observations remain marked nontraded. No VNDIRECT bar falls on an effective closed date.
- DNSE remains a separately useful historical series: 2,172,122 rows across 1,515 symbols for 2018-10-02 through 2026-10-16; 659 jobs are `COMPLETED`, 856 `PARTIAL`, and four `BLOCKED` with no history. Duplicate-date buckets, invalid prices, and zero-volume rows remain issue-recorded rather than synthesized.
- A span-based calendar reconciliation found 3,225 expected symbol/session observations absent from VNDIRECT across 206 symbols between each series' first and last observed dates. These are calendar-derived missing pairs, not proof that every security traded on each session. The largest cluster is 14 symbols missing on 2021-08-30, 2021-08-31 and 2021-09-01; see the lifecycle follow-up below.
- The offline cross-source selector now accepts VCI/VNDIRECT when KBS has no row for the requested session. It replays exact VNDIRECT response bytes and SHA-256, confirms a successful audited request to `api-finfo.vndirect.com.vn` with matching symbol/date filter/status/row count, and records the exact zero-based row. Selection uses the same generic OHLC rule as ingestion (`high >= low`); it does not reject valid auction open/close values outside high/low.
- For 2026-10-16, the selector stored exactly 30 Tier A VCI/VNDIRECT pairs. All 30 close differences were within 0.5%; DQ run `3cd86137-dec5-4dc3-9e35-ccee9c886f1b` is `PASSED` with no blocking findings, warnings, or quarantined rows. The gate now passes for that session; this is not a Phase 1 completion claim.
- Verification after the selector change: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. No worker or migration changed in this increment. PostgreSQL 16 hosted CI and the Windows race suite remain unverified as recorded above.
- Phase 1 remains **PARTIAL**. The latest DQ gate passed, but VCI still has partial and blocked historical jobs, residual provider-quality issues, unresolved source/lifecycle coverage questions, and no verified common adjusted-price basis for mixing VCI, DNSE and VNDIRECT. Phase 2 work has not started.

## 2026-10-18 — alternate-source gap and security-lifecycle audit

- The user reaffirmed that historical data may come from another provider when vnstock cannot supply it; vnstock/VCI remains the intended daily refresh source. Use independently sourced rows from `core.bars_daily_sources` with original landing and call-audit lineage. Do not relabel them as VCI or silently merge differing adjustment bases.
- HNX's official 2021 transfer notice names 13 of the 14 symbols in the 2021-08-30–2021-09-01 missing-data cluster (ABT, BSI, DXS, HAP, KHG, LAF, NSC, PAN, QBS, SSC, TVB, VFG, VND) and sets 2021-08-27 as their last HNX trading date. VNDIRECT and DNSE audited range requests and CafeF's historical endpoint returned no bars for the cluster. These 39 absent pairs align with that transfer interval; do not synthesize zero-volume bars. The 14th symbol, PTM, is a separate lifecycle case. CafeF's exact-range response for BSI is archived at [`BSI-20210830-20210901.json`](probe/phase1-cafef-gap/BSI-20210830-20210901.json); the folder contains the other 13 symbol responses.
- PTM is resolved by the specific 2018 exchange notice, which names the same automobile issuer and ticker, sets 2018-11-27 as its final HNX trading day, and cancels registration from 2018-11-28. The issuer independently says it left the market at the end of 2018, and HNX records its return on 2025-08-22. The 11 positive-volume VCI observations and 12 positive-volume VNDIRECT observations in 2018 all fall inside the verified trading interval. Retain them in their respective source series; do not exclude them as a lifecycle conflict or merge their different/unknown adjustment bases. Exact notice bytes and lifecycle evidence are archived and recorded below.
- HNX records CTR's last UPCoM trading day as 2022-02-14, cancellation on 2022-02-15, and HOSE's official notice records the first HOSE trading day as 2022-02-23. The canonical VCI series nevertheless contains five identical CTR bars on Feb. 16–22; VNDIRECT and DNSE have none, and the archived CafeF response [`CTR-20220216-20220222.json`](probe/phase1-cafef-gap/CTR-20220216-20220222.json) has `TotalCount=0`. Treat those VCI rows as lifecycle-conflicting provider observations; preserve their raw landing and quarantine them from ML pending a durable correction audit.
- The 50 VCI `INVALID_PRICE` issue records represent 25 distinct symbol/session pairs with unusable open values; these do not arise from open/high/low containment. All 25 dates have valid VNDIRECT rows, and 14 also have DNSE rows. Use the source-specific alternatives for historical research with their basis preserved.
- Official lifecycle sources: HNX's [2021 transfer notice](https://www.hnx.vn/vi-vn/chi-tiet-su-kien-60012723-0-hnx.html?_page=1), [PTM final-trading-day notice](https://owa.hnx.vn/ftp/cims/2018/10_W5/000000007933389_1315tb_20181031_1.PDF), [PTM 2025 first-trading notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2022082025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20San%20xuat%20Thuong%20mai%20va%20Dich%20vu%20O%20to%20PTM%20PTM-60021452-1.html), and [issuer history corroboration](https://otoptm.com.vn/ptm-tam-the-moi-cho-hanh-trinh-tro-lai/); HNX's [CTR cancellation notice](https://static2.vietstock.vn/vietstock/2022/1/19/1.CTR_2022.1.19_acb69f8_89tb_20220117_1.PDF) and the SSC's [CTR first-day HOSE notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/m/thngtinthtrng/thngkthtrng/thongtinhose/tintchose?docType=TinBai&mucHienThi=188&selectedPage=20).
- VNDIRECT rows use `unadjusted`; DNSE and VCI remain `unknown` in the database. The 2026-10-16 VCI/VNDIRECT DQ pass verifies a same-session close comparison for that date only; it does not establish that the histories share an adjustment basis. Keep separate source-homogeneous training series until corporate-action adjustment factors are verified.

## 2026-10-18 — alternative historical source policy and UTT lifecycle probe

- The user confirmed that alternate providers may supply historical ML data where vnstock/VCI cannot, while vnstock/VCI remains the preferred daily refresh route. The local history contains 2,844,683 VNDIRECT rows through 2026-10-16 and 2,172,122 DNSE rows. All 16 symbols with partial VCI histories have positive-volume VNDIRECT history; these rows remain in their own source table with `unadjusted` basis and raw response lineage.
- HNX's official UTT first-trading notice records 2025-10-17. Its exact HTML bytes are archived at [`UTT-first-trading-2025-10-17.html`](probe/phase1-lifecycle/UTT-first-trading-2025-10-17.html), SHA-256 `041a8efa044d1fd6d438bceae7b83f21d86029dae1e5c5b0464cf0f47d756b32`; the source landing and append-only `TRADE_ELIGIBLE` evidence are stored in local PostgreSQL as landing 8398 / evidence 1.
- After a fresh authenticated quota check, one metered VCI probe requested UTT from 2025-10-17 through 2026-10-16 with raw prices. It returned a well-formed frame (`time`, `open`, `high`, `low`, `close`, `volume`) with count 0. The local probe report is [`2026-10-18-UTT-110813.105527700Z.json`](probe/phase1-utt/2026-10-18-UTT-110813.105527700Z.json). VNDIRECT and DNSE have no UTT rows. This establishes no UTT history before its official first-trading date and records the empty VCI response after listing; it does not classify every post-listing date as a confirmed non-trading session.
- The initial CafeF/HNX-only audit did not resolve all omitted sessions and therefore left UTT's activity status open at that point. The subsequent full-period VNDIRECT query, with a positive-volume KAI control, reports zero matched and negotiated volume for UTT across all 248 HNX sessions from 2025-10-17 through 2026-10-16. This supersedes the earlier unresolved classification; no execution date is observed in the audited interval and flat reference-price rows remain excluded from OHLCV. Raw pages, omitted-date list, VNDIRECT responses and hashes are recorded in [`phase1-utt/README.md`](probe/phase1-utt/README.md). Sources: [HNX first-trading notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2017102025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20Moi%20truong%20Do%20thi%20Thanh%20Tri%20UTT-60021665-1.html), [CafeF history](https://cafef.vn/du-lieu/lich-su-giao-dich-utt-1.chn), [VNDIRECT full-period history API](https://api-finfo.vndirect.com.vn/v4/stock_prices?q=code%3AUTT~date%3Agte%3A2025-10-17~date%3Alte%3A2026-10-16&size=1000&page=1&sort=date%3Aasc&fields=code%2Cdate%2CadOpen%2CadHigh%2CadLow%2CadClose%2CnmVolume%2CnmValue%2CptVolume%2CptValue), and [HNX daily trade report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM).
- Historical training data should read one provider/basis series at a time. VNDIRECT supplies the source-attributed historical research series; VCI can continue daily refresh as its own series. VCI/DNSE/VNDIRECT rows are not stitched together until corporate-action treatment and point-in-time adjustment are validated.
- This source policy makes alternate historical rows available for the 32 partial VCI histories without erasing VCI quality findings. At this stage Phase 1 remained PARTIAL: CTR's lifecycle-conflicting rows had not yet been durably excluded; UTT still had no usable post-listing history from the probed sources; source adjustment basis remained unverified; and Windows race / PostgreSQL 16 hosted CI checks were outstanding. The later CTR correction is recorded below.
- Verification after this increment: `go -C go test -count=1 ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. `go -C go test -tags "postgres postgres_integration" -p 1 ./... -count=1` passed against local PostgreSQL 18.3 with the registered virtual-environment interpreter. `tests/sql/test_migration.sh` passed twice-applied migrations, schema assertions, rollback injection, and unreachable-database check against a fresh disposable PostgreSQL 18.3 database. `go -C go test -race ./...` still fails before test execution because Windows ThreadSanitizer cannot allocate its shadow region (error 87); the hosted PostgreSQL 16 CI job has not run.

## 2026-10-18 — PTM lifecycle corrected from HNX final-trading notice

- HNX notice 1315/TB-SGDHN, dated 2018-10-30, names CTCP Sản xuất, Thương mại và Dịch vụ Ôtô PTM (ticker PTM), gives 2018-11-27 as the final HNX trading day, and 2018-11-28 as the deregistration date. HNX's 2025 notice records the same issuer returning to UPCoM on 2025-08-22; the issuer says it left the market at the end of 2018. This resolves the older generic retrospective that had suggested a 2016 cancellation.
- The archived HNX PDF is [`PTM-delisting-2018-11-27.pdf`](probe/phase1-lifecycle/PTM-delisting-2018-11-27.pdf), SHA-256 `DDF3FFB354A7CEE923085B10FFF59FCC2CD4EDEA3825744FDB39C00C50FFE197`; the 2025 first-trading page is [`PTM-first-trading-2025-08-22.html`](probe/phase1-lifecycle/PTM-first-trading-2025-08-22.html), SHA-256 `2385B5965B458AC71012BE7F4F301B8A430BD9FD5F490F507450D444BF14E163`. PostgreSQL stores both exact source landings (8400, 8401) and three append-only lifecycle intervals (evidence 3–5): eligible through 2018-11-27; delisted 2018-11-28–2025-08-21; eligible from 2025-08-22.
- All 11 positive-volume VCI PTM bars and 12 positive-volume VNDIRECT PTM bars from 2018 occur before the confirmed final trading day. Their existence is supported by the exchange lifecycle and same-issuer notices; preserve their original source lineage and separate adjustment-basis series. Remove PTM from the list of lifecycle-conflicting records.
- At the time of this PTM correction, Phase 1 remained PARTIAL. CTR's five VCI rows from 2022-02-16–2022-02-22 still needed durable exclusion; UTT's post-listing VCI probe was empty and no alternate history had been ingested, so no bars were synthesized. The later CTR correction is recorded below; the 32 VCI partial-job findings, unverified cross-source adjustment basis, Windows race execution, and PostgreSQL 16 hosted CI remain open.

## 2026-10-18 — CTR final UPCoM session verified and ML eligibility corrected

- HNX notice 89/TB-SGDHN states that CTR's final UPCoM trading day was 2022-02-14 and registration was canceled effective 2022-02-15. The SSC's official notice records 2022-02-23 as the first HOSE trading day. The five dates 2022-02-16, 17, 18, 21 and 22 therefore fall between the exchange lifecycle events; this conclusion comes from the notices, not from an assumed trading calendar or a missing-bar pattern.
- The HNX notice PDF is archived at [`CTR-delisting-notice-2022-01-17.pdf`](probe/phase1-lifecycle/CTR-delisting-notice-2022-01-17.pdf), SHA-256 `F5A2B2501997B7393DB6715FCEB1AAEF4D1A614F5A0E110A15C730A7059DAF37`. It is HNX notice 89/TB-SGDHN hosted on Vietstock's static CDN. The first-HOSE-day reference is the [SSC notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/m/thngtinthtrng/thngkthtrng/thongtinhose/tintchose?docType=TinBai&mucHienThi=188&selectedPage=20). The HNX source is stored in PostgreSQL as landing 8402 and verified lifecycle evidence 6 (UPCoM delisted 2022-02-15–2022-02-22).
- The five VCI bars map to raw landing 2550, SHA-256 `9631b5e1ea8c48beb69d0dd8915bb81e1926620067b0aa89f51b3e9a8a30d00f`, source rows 829–833 (zero-based), on 2022-02-16, 17, 18, 21 and 22. Migration 022 adds append-only, source-row-linked ML eligibility events, validates each event against its raw response and dated lifecycle evidence, and exposes filtered VCI and alternate-source views. Five `EXCLUDE` events now reference evidence 6; canonical VCI history still contains all five bars, while `core.bars_daily_ml_eligible` returns zero for those dates.
- `import-CTR-lifecycle.sql` and `CTR-lifecycle-landing.csv` preserve the repeatable evidence import. The working database reports five exclusions with their exact raw-row lineage and no canonical row deletion.
- Validation after migration 022: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. `tests/sql/test_migration.sh` passed twice-applied migrations, schema assertions, injected rollback and unreachable-connection checks on a fresh disposable PostgreSQL 18.3 database. A tagged Go integration invocation did not complete after two minutes and was interrupted without an active database session; no tagged integration pass is claimed. The hosted PostgreSQL 16 job remains unverified, and Windows race execution remains unavailable as recorded above.
- Phase 1 remains PARTIAL. CTR is resolved. Open items are the ticker/date audit of partial VCI histories against separate alternate sources, UTT's empty post-listing history, unverified cross-source adjustment basis, and the PostgreSQL 16 / race checks.

## 2026-10-18 — public-source validation of partial-job findings

- The official HNX UPCoM daily report confirms SNC traded 71 shares on 2026-10-15 in continuous matching, with total traded value VND 1,547,800. This matches VNDIRECT landing 8002; StockBiz and Cophieu68 reported zero volume for that session. The HNX response is archived and hashed in `docs/probe/phase1-partial-audit/hnx-snc-2026-10-15.html`. Current VNX rules define 1–99 shares as an odd lot and allow continuous matching or put-through; odd-lot trades do not determine reference price or index. The exchange report resolves the volume discrepancy.
- VNDIRECT's stored import basis is verified as raw/unadjusted: the parser consumes ordinary OHLC fields and the importer stores them as `unadjusted`; archived payloads separately contain adjusted fields. The response comparison and source links are in `docs/probe/phase1-partial-audit/README.md`. VCI/DNSE adjustment basis and point-in-time corporate-action treatment remain open, so provider series stay separate.
- Sources: [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM), [current VNX UPCoM trading rule](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [StockBiz SNC history](https://web.stockbiz.vn/Stocks/SNC/LookupQuote.aspx?Date=16/10/2026), [Cophieu68 SNC history](https://cophieu68.vn/download/historydaily.php?d=2026-10-15), and [VNDIRECT adjustment-basis explanation](https://dstock.vndirect.com.vn/lich-su-gia/VND).

## 2026-10-18 — public historical-source checks and current test status

- Archived EasyStock's public per-symbol JSON feed for all 16 UPCoM tickers in the VCI partial-job audit: 35,684 rows, with 23,893 positive-volume and 11,791 zero-volume rows. It covers 7,447 of 14,492 issue dates and reports zero volume on all 7,447. EasyStock also reports zero for SNC on 2026-10-15, while HNX confirms 71 matched shares. Keep this feed separate; its zero volume is not proof of no execution. The VCI corporate-action sample is adjusted, while the adjustment timestamp is unknown.
- HNX's official public report confirms zero matched volume for SHC on 2026-09-16, 2026-09-18 and 2026-09-21. The report page limits the date picker to one month; an older SNC request returns no rows despite positive VNDIRECT/DNSE records. HNX lists UPCoM EOD and historical data as information services, but public access and fee terms were not verified. Evidence is in `docs/probe/phase1-partial-audit/hnx-recent/`.
- The 2024 VCI 10:3 bonus-share event cross-check shows VNDIRECT raw close 43.80 to 33.40, while VCI/DNSE/CafeF adjusted closes are about 24.24–24.25 to 24.03–24.04. This supports event-level adjustment differences only; VCI/DNSE basis and point-in-time treatment remain unknown. Details and source hashes are in `docs/probe/phase1-adjustment/README.md`.
- Tests on the current dirty checkout this turn: `VNPIPE_DISABLE_LIVE=1 go -C go test -count=1 ./...` passed; `go -C go vet ./...` passed; Python JSONL tests passed (27 tests); `tests/sql/test_migration.sh` passed on disposable PostgreSQL 18.3. GitHub Actions run [39023562253](https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/39023562253) passed against clean HEAD `e8eeef6`, including PostgreSQL 16 and Go race jobs, but does not cover these uncommitted changes. Local Windows `go test -race` fails after enabling CGO/GCC because ThreadSanitizer cannot allocate its shadow mapping (error 87); no local race pass is claimed.

## 2026-10-18 — Cophieu68 terms and row-level cross-check

- The public Cophieu68 SHC page reports zero volume on 2026-09-16, 2026-09-18, and 2026-09-21, matching the three archived HNX no-match reports. Its SNC page reports zero on 2026-10-15, while HNX records 71 continuous-matching shares; keep the HNX/VNDIRECT execution finding authoritative for that date.
- The Cophieu68 download page advertises adjusted history since 2000 through a legacy AmiBroker script, but the current check/download endpoints returned HTTP 404. Its terms prohibit copying or derivatives without explicit consent except for limited internal page copies. No bulk data was retained or imported; no PostgreSQL rows or quality statuses changed. Notes and source links: [`phase1-cophieu68/README.md`](probe/phase1-cophieu68/README.md).

## 2026-10-18 — historical HNX exact-date validation and source coverage

- The HNX page's visible date picker is limited, but targeted POST filters accepted historical dates in 2018–2020. All 26 distinct VCI invalid-price/OHLC ticker/date pairs have an HNX row with positive total matched volume. A read-only query matched every pair to a positive `vndirect` row in `core.bars_daily_sources_ml_eligible` (`is_traded=true`, `adj_basis=unadjusted`). This validates the separate alternate bars; it does not repair, overwrite, or relabel VCI data.
- For each of the 16 tickers in the partial-history audit, the latest positive VNDIRECT source row through 2026-10-16 was confirmed by an HNX report with the same volume. Fifteen were queried on the UPCoM route; SPC was queried on the HNX-listed route. The raw responses, exact filters, row values and hashes are in [`phase1-hnx-last-trade-audit/`](probe/phase1-hnx-last-trade-audit/). These are latest positive VNDIRECT observations with exchange-confirmed executions; HNX did not independently check every later zero-volume session.
- UTT's 16 sessions omitted from CafeF all return an explicit HNX UTT row with zero total matched volume, including first trading day 2025-10-17. VNDIRECT reports zero through all 248 sessions and CafeF through its 232 returned sessions. HNX has not been queried for every UTT session, so report that no positive trade date is observed through 2026-10-16 rather than claiming an all-session exchange audit. Raw reports and hashes are in [`phase1-utt/hnx-daily-reports/`](probe/phase1-utt/hnx-daily-reports/).
- This corrects the earlier statement that historical HNX requests returned no rows: that finding came from the visible page/date-picker route. Exact historical POST queries work. HNX separately lists historical data and data products in its [UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html) and [2026 service catalog/price schedule](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf); targeted public validation is not treated as bulk-reuse permission.
- No database rows, quality statuses, quota records, or lifecycle classifications were changed by these lookups. Phase 1 remains PARTIAL; VCI/DNSE adjustment basis and point-in-time action handling, zero-volume issue coverage, DQ breadth, PostgreSQL 16 validation on this dirty tree, and local Windows race execution remain open.
- Checks after this evidence update passed: `VNPIPE_DISABLE_LIVE=1` with `VNPIPE_PYTHON=.venv\Scripts\python.exe go -C go test -p 1 ./...`; `go -C go vet -p 1 ./...`; `.venv\Scripts\python.exe -m unittest discover -s tests -v` (27 tests); and `tests/sql/test_migration.sh` with migrations applied twice on a disposable PostgreSQL 18.3 database. No current dirty-tree Windows race pass or PostgreSQL 16 hosted run is claimed; the existing race limitation is recorded above.

## 2026-10-18 — verify adjusted price basis using FPT cash dividend

- Internet research found the official VSDC notice for FPT's VND 1,000/share 2024 cash dividend and an HOSE-hosted notice giving the 2024-12-02 ex-right date. The same local source rows show VNDIRECT raw close 144.3→142.2 thousand VND; its adjusted close is 109.658→108.813. VCI is 109.66→108.81 and DNSE 109.65→108.81. These all match the dividend-adjusted return to rounding; raw close return is materially different. Details, source lineage, payload hashes, and a rerunnable classification SQL file are in [`phase1-adjustment/`](probe/phase1-adjustment/).
- Classified all 1,809,966 VCI canonical bars and 2,172,122 DNSE alternate bars as `adj_basis='adjusted'`; VNDIRECT remains `unadjusted`. The Go ingestion paths now preserve this source-specific classification. Only OHLC price basis is covered; volume semantics are unchanged. KBS remains `unknown` pending its own archived event comparison.
- Historical adjustment vintage is still unresolved. The current VCI/DNSE history is restated and cannot be considered point-in-time safe from this label alone. No prices, volume, trade flags, or ML lifecycle events were changed. Phase 1 remains PARTIAL.
- Verification after the importer edit: `VNPIPE_DISABLE_LIVE=1` with the project `.venv` interpreter and `go -C go test -p 1 ./...` passed; `go -C go vet -p 1 ./...` passed; all 27 Python JSONL tests passed; `git diff --check` passed (CRLF warnings only). Two metered KBS exact-date probes timed out without returning a report; no KBS basis is inferred. PostgreSQL 16 hosted CI and dirty-tree race execution were not rerun in this increment.

## 2026-10-19 — HNX latest-week verification and alternative-source research

- Archived ten official HNX reports covering the 16 partial-history symbols from 2026-10-12 through 2026-10-16: 15 UPCoM symbols through the UPCoM daily report and SPC through the HNX-listed report. The extraction yielded 80 rows, 32 with positive total matched volume. Thirteen tickers had a positive session in the window; CDG, VFC, and VNX did not.
- The HNX results agree with the latest positive rows in the source-specific audit for the 13 recently active names. The three with no trades in the five-session window have older positive VNDIRECT observations that HNX confirmed on their exact dates; this new lookup does not rule out a trade between those dates and October 12.
- SSI's official API documentation offers daily history from the start of trading and historical-file downloads, but requires an SSI trading account and approved FastConnect credentials. TCBS documents long-term OHLCV, but its unauthenticated endpoint returned 401. DNSE documents historical OHLC; its local history remains in its own source series. No credentials were submitted and no database changes were made.
- Phase 1 remains PARTIAL. This targeted lookup does not clear the remaining 14,439 zero-volume issue dates or resolve historical adjustment vintages. Evidence and sources are in [`phase1-hnx-latest-week/README.md`](probe/phase1-hnx-latest-week/README.md).

## 2026-10-19 — interpret HNX special-trading status

- HNX issuer profiles for CDG, VFC, and VNX currently display “Giao dịch đặc biệt.” VNX's current UPCoM regulation (Decision 23/QĐ-HĐTV, effective 2026-03-18) defines status code `SNE` as no round-lot trades for more than 25 consecutive trading sessions. This is consistent with recent inactivity; the separate HNX reports independently show zero total matched volume for these three symbols on Oct 12–16. SNE alone does not rule out odd-lot trades.
- The profiles do not expose when the status began. Do not convert this current aggregate status into exact last-trade dates or use it to classify older zero-volume issue rows. Raw profiles and hashes are recorded in [`phase1-hnx-special-status/README.md`](probe/phase1-hnx-special-status/README.md). No database rows or lifecycle statuses changed.
- Sources: [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [current VNX UPCoM regulation](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [CDG HNX profile](https://hnx.vn/vi-vn/ModuleIssuer/UC_Issuer/Details/CDG/UC), [VFC HNX profile](https://hnx.vn/cophieu-etfs/chi-tiet-chung-khoan-uc-VFC.html), and [VNX HNX profile](https://hnx.vn/vi-vn/m-tim-kiem-VNX.html).

## 2026-10-19 — targeted KBS check of a VCI zero-volume issue

- A registered-machine KBS OHLCV probe returned two NAS rows for 2020-10-14–2020-10-15. Its 2020-10-15 row has volume 80 and close 26.93. The same issue date has local VNDIRECT volume 80 (raw close 29) and DNSE volume 80 (close 26.9294); VCI has no positive canonical bar and two `ZERO_VOLUME_UNVERIFIED` issue records. This adds a third provider corroboration for positive activity on this row, but does not establish an HNX exchange result or clear the other issue dates.
- A full-range KBS GGG probe returned 380 rows from 2018-10-12 through 2026-10-09; the exact 2026-10-16 request returned no row. Treat KBS as useful supplemental history with a freshness gap in this sample, not a replacement for the VCI daily refresh.
- Current vnstock documentation lists KBS as a selectable Community source for daily equity OHLCV, with no automatic fallback; it also warns source price histories can differ after corporate actions. Keep KBS source rows separate and do not use adjusted prices for point-in-time training until adjustment timing is validated ([source selection](https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources), [market OHLCV](https://www.vnstocks.com/docs/vnstock/thi-truong-market)).
- Exact-date HNX UPCoM report requests for NAS on 2020-10-15 returned the same zero-record response for quoted and unquoted symbol filters. That empty response is unavailable evidence for this date, not evidence of no execution. HNX lists UPCoM historical data as an information product and advertises a two-week trial; use the registered information-service route for any broad exchange audit ([HNX UPCoM data service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html), [service terms and technical requirements](https://www.upboard.hnx.vn/vi-vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-sgtc.html)).
- Probe summaries and HNX response bytes, including hashes and exact request filters, are in `docs/probe/phase1-current-kbs-verify/` and `docs/probe/phase1-hnx-kbs-reconciliation/`. The KBS calls used the Go probe gateway; no market data was imported, and no PostgreSQL rows, quality statuses, or lifecycle evidence changed.
- HNX issuer price-history queries returned 64 dated rows per symbol from 2026-07-16 through 2026-10-16. VNX has one price-bearing row in this window, 2026-07-28, matched to the existing HNX exact-date report (100 shares); CDG and VFC have none. For VFC, eight exact HNX daily matched-volume reports from 2026-07-06 through 2026-07-15 returned zero volume; the HNX-verified 2026-07-03 observation remains the latest positive execution located. These profile rows do not certify the absence of later odd-lot trades. For CDG, the 2025-05-13 positive observation is corroborated by HNX and Investing.com, but the intervening history is not an all-session exchange audit. Details and raw hashes are in [`phase1-hnx-special-status/README.md`](probe/phase1-hnx-special-status/README.md).

## 2026-10-19 — web-check last matched dates and UPCoM volume fields

- Three targeted taichinh.com pages, each displaying VNDirect as its price/volume source, report the latest matched date for CDG as 2025-05-13 (snapshot 2026-09-18), VFC as 2026-07-03 (snapshot 2026-10-09), and VNX as 2026-07-28 (snapshot 2026-10-12). HNX's exact-date reports independently confirm positive exchange volume on all three dates, recorded in [`phase1-hnx-last-trade-audit/hnx-last-trade-reconciliation.csv`](probe/phase1-hnx-last-trade-audit/hnx-last-trade-reconciliation.csv). HNX also reports zero matched volume for these three on 2026-10-12–16. Treat the older dates as latest matched dates in the VNDirect-derived series, supported by targeted HNX confirmation, rather than a complete official no-trade audit of every later session.
- FiinGroup's official UPCoM API schema distinguishes latest round-lot `MatchVolume`, total round-lot matched `TotalMatchVolume`, negotiated `TotalDealVolume`, and total matched-plus-negotiated volume `TotalVolume`, including round and odd lots. This is a promising licensed source to resolve volume-field semantics and historical zero-volume conflicts, but public API documentation does not establish the available backfill period or usage rights. Do not bulk-query the HNX public report or import FiinGroup data until the historical coverage and internal research terms are established.
- taichinh.com terms permit individual research lookups and citation with source attribution, while asking users to contact FTMI before automated, broad or deep collection. This update used only three individual page lookups and imported no data. See [`phase1-public-activity-check/README.md`](probe/phase1-public-activity-check/README.md).
- Phase 1 remains PARTIAL; the 14,439 zero-volume issue dates are still unverified, and the remaining backfill and current-tree CI gates remain open.

## 2026-10-19 — CafeF full-history cross-check for VCI zero-volume issues

- Used CafeF's public export for the 16 partial-history symbols in nine one-year windows per symbol. All 144 XLSX exports passed ZIP validation and SHA-256 verification; they contain 31,381 daily rows from the 2018 partial year through 2026-10-16. The corrected endpoint date format is `MM/DD/YYYY`; an earlier `DD/MM/YYYY` singleton request silently fell back to a recent default range.
- Across 14,466 VCI `ZERO_VOLUME_UNVERIFIED` dates, CafeF reports 23 positive matched-volume dates, all already positive in VNDIRECT or DNSE; 106 additional dates have negotiated volume only; 14,159 rows report zero matched and negotiated volume; and 178 dates have no CafeF row. The three HNX-confirmed SHC no-match dates also show zero volume in CafeF. Thus 14,333 dates have neither positive matched nor negotiated-volume evidence nor an exact HNX no-match report; the 106 negotiated-only rows remain a separate activity signal and do not supply matched OHLC bars.
- `docs/probe/phase1-cafef-history-audit/` contains the raw annual files, hash manifest, complete daily activity extract, per-issue reconciliation, and rerunnable local scripts. CafeF zero/absent rows do not prove that no trade occurred; no CafeF price or volume was imported into PostgreSQL or canonical bars. Phase 1 remains PARTIAL, and the action-adjustment vintages and current-tree CI gates remain open.

## 2026-10-19 — expand the alternative-source search

- Internet research found an exact-fit FireAnt historical feed: its official Excel documentation exposes OHLC, matched `DealVolume`, negotiated `PutthroughVolume`, and total volume by symbol and date range. Its REST API uses OAuth2, the unauthenticated historical-quotes request returned HTTP 401, and FireAnt's current plan page lists the Excel add-in under Premium. FireAnt is a usable next provider only through authorized access.
- HNX confirms two CafeF false negatives outside the 14,466 issue-date population: 100 CDG shares on 2025-05-13 and one VFC share on 2026-07-03, where the CafeF export reports zero matched and negotiated volume. Keep CafeF zero and absent rows as unknown evidence; do not downgrade them to exchange no-trade findings.
- FiinGroup documents a distinct UPCoM schema for round-lot matched volume, negotiated volume, and odd-lot-inclusive total volume. HNX and FiinGroup both have historical products, but their bulk coverage and internal research rights require an authorized trial or license. SSI FastConnect also documents daily history from first trading date but requires an approved brokerage account. EODHD's public demo does not include Vietnam symbols.
- The 14,333 remaining dates still have no matched/negotiated positive evidence or HNX exact-date no-match report; 106 negotiated-only sessions are tracked separately as activity evidence, not OHLC bars. See [`alternative-source search`](probe/phase1-source-search/README.md) and the [`CafeF/HNX cross-check`](probe/phase1-cafef-history-audit/README.md).

## 2026-10-19 — verify another public history source and refresh the registered route

- EasyStock's public page advertises free market-wide OHLCV history from 2007 onward. Archived 16 symbol histories (35,684 rows, 23,893 positive-volume source rows) with SHA-256 manifests. On 14,466 VCI zero-volume issue dates it reports zero volume on 7,434, has no row on 7,032, and reports no positive volume. It adds no evidence to the existing 14,333 unresolved partition. The source misses HNX-confirmed CDG 100-share and VFC one-share executions, as well as the 80-share NAS observation corroborated by four sources. Keep its zero/absent rows out of no-trade certification; matched/deal volume and adjustment vintage are undocumented. See [`EasyStock audit`](probe/phase1-easystock-history-audit/README.md).
- A fresh registered-machine active VCI OHLCV probe succeeded at 2026-10-19 01:38 +07 with one metered call: 1,995 FPT rows from 2018-10-18 through 2026-10-16, columns `time, open, high, low, close, volume`. The official [HOSE 2026 holiday notice](https://www.hsx.vn/vi/tin-tuc/hose-thong-bao-lich-nghi-giao-dich-nam-2026/2437411) lists no October closure; the explicit probe budget was 10 sessions from October 19–30. The authenticated local CLI reports `tier=free`; vnstock's [official account-tier documentation](https://vnstocks.com/docs/vnstock/tham-khao/cap-quyen-va-gioi-han) maps that API-key state to Community. The response verifies a live route today, not full historical coverage or post-call quota. Report: [`2026-10-19 active probe`](probe/phase1-easystock-history-audit/vnstock-probe-20261019/2026-10-19.json).
- No EasyStock or VCI probe rows were written to PostgreSQL. Phase 1 remains PARTIAL.

Verification update on 2026-10-19 supersedes the earlier interrupted attempt above: `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` (CGO enabled with MSYS2 GCC), all 27 Python JSONL tests, all 26 serialized PostgreSQL ingestion integration tests, and `tests/sql/test_migration.sh` passed. The migration check used disposable PostgreSQL 18.3 and applied all migrations twice; migrations 001–025 were then applied to the working `vnsignal` database, and the three VNX interpretation rows were appended and verified. GitHub Actions run 39023562253 still covers clean HEAD `e8eeef6`, not this dirty tree; PostgreSQL 16 hosted CI remains unverified for this checkout.

## 2026-10-19 — three additional HNX-confirmed VNX executions

- A bounded public-history search surfaced VNX issue dates 2026-01-29, 2026-01-30, and 2026-02-12. The exact-symbol HNX UPCoM reports returned one row each, but the first parser read the `Toàn thị trường` totals (15,100, 4,900, and 4,900 shares) as matched volume. Column review showed all matched-session columns were zero and those totals belonged to `Thỏa thuận` (negotiated volume). BSC independently returned zero matched and the same negotiated amounts. See [`VNX HNX verification`](probe/phase1-simplize-history-audit/README.md) and [`BSC exact-date controls`](probe/phase1-source-search/bsc-controls-20261019.json).
- All three dates were in the unresolved activity partition: VCI had zero-volume issue rows, the prior VNDIRECT/DNSE and CafeF audit had no positive volume or CafeF row, and no exact HNX report was previously archived. Positive negotiated evidence moves them out of that partition, reducing it from 14,317 to 14,314; distinct negotiated-only dates rise from 106 to 109.
- Appended all three exact reports to local `raw.landings` and `ops.exchange_daily_bar_evidence`; the initial parse was retained and corrected through an append-only interpretation. No canonical bars, provider rows, or VCI quality issues were changed. The corrected lifecycle status is `VERIFIED_NEGOTIATED_ONLY`; Phase 1 remains PARTIAL.
- The secondary Simplize history output was used only to identify candidate dates; none was imported into PostgreSQL or canonical bars. Its published terms restrict copying or derivative use without written permission. The temporary snapshot is still untracked locally because the shell rejected its cleanup command; do not commit it.

## 2026-10-19 — expanded web research and four KBS issue probes

- Yahoo's official exchange list assigns Vietnam's `.VN` market suffix to Ho Chi Minh City Stock Exchange, so it does not provide the UPCoM history needed for the open gaps. Simplize has public UPCoM history pages and an Excel export control; its UTT page displays blank OHLC and zero volume on recent rows, and explicitly says its prices are adjusted for dividends and splits. Its page does not document matched-versus-negotiated volume or the adjustment vintage, so it remains a targeted secondary check.
- The registered Community KBS source was queried once each for CDG 2025-05-13, VFC 2026-07-03, NAS 2020-10-15, and UTT 2025-10-17 through 2026-10-16. KBS confirms the CDG 100-share session and NAS 80-share session; it misses the HNX-confirmed VFC one-share session (its latest VFC row is 2026-06-17), and returns no UTT rows. The NAS issue was already positive in CafeF/VNDIRECT/DNSE, and CDG/VFC's sampled positive dates are outside the 14,466 VCI zero-volume issue set; the 14,333 unresolved count is unchanged.
- The KBS reports are in [`phase1-kbs-issue-probes-20261019/`](probe/phase1-kbs-issue-probes-20261019/). UTT's zero-row report is also appended to [`phase1-utt/README.md`](probe/phase1-utt/README.md). Four one-call probes used the explicit metered-probe path after fresh exact-quota checks; no probe rows were imported into PostgreSQL. Phase 1 remains PARTIAL because these checks do not complete the remaining backfill, point-in-time price basis, or current-tree CI exits.

## 2026-10-19 — search public datasets and alternate adapters

- The Kaggle Vietnam stock competition documents genuine OHLCV for 30 tickers from 2021-01-04 through 2021-10-29. The short window, limited universe, and competition-rules download gate make it insufficient for the 16 UPCoM partial-history symbols; no competition files were downloaded.
- Mendeley Data publishes daily closes for 627 HOSE/HNX/UPCoM shares from 2014–2024, but the file is close-only and uses anonymized IDs with no public symbol crosswalk. Its CC BY 4.0 license makes it a possible later close-only research input only if identity and adjustment basis are established; it cannot fill OHLCV or volume gaps. No file was downloaded or imported.
- Broader adapter search found OpenStockAPI and `vn-market-data`, but their documented feeds resolve to provider families already represented here (TCBS/KBS/VCI; DNSE/Vietcap/VNDirect/CafeF). Official vnstock v5 docs do not offer TCBS as an equity OHLCV route; Community access permits the KBS/VCI equity routes, while TCBS OpenAPI and SSI FastConnect require separate API credentials/approval. No new credentials or data were used.
- This search added no symbol/date/volume evidence, so the recorded 14,333 unresolved zero-volume issue dates and 106 negotiated-only sessions are unchanged. Phase 1 remains PARTIAL. Source details and links are in [`phase1-source-search/README.md`](probe/phase1-source-search/README.md).

## 2026-10-19 — further public-source checks and current Phase 1 counts

- A newly inspected public Lich Su Gia page reports zero volume for CDG on 2025-05-13, but the archived official HNX report confirms 100 matched shares. Exclude this site from no-trade evidence. FINCO advertises broad adjusted OHLCV, but its public CDG route returned metadata only and its history preview returned `Not authenticated`; approved export access is required and volume semantics/source lineage remain open. FinLens advertises historical OHLCV but requires a separate API key and remains unvalidated. DNSE OpenAPI offers a trade-history route but uses the same DNSE provider family already represented here and requires separate credentials. The Kaggle VN30 candidate remains unverified and does not cover UPCoM.
- The current unresolved zero-volume issue partition is 14,314 ticker/dates, with 109 distinct negotiated-only sessions (106 CafeF plus three VNX HNX reports) and 22 exact HNX reports persisted (19 zero-total and 3 negotiated-only). This is an evidence-classification count, not a missing-bar count. Stockbiz returned the same single-field VNX total-market volumes, but its field does not distinguish matched from negotiated and was not imported. See [`alternative-source search`](probe/phase1-source-search/README.md) and the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md). Phase 1 remains PARTIAL; point-in-time adjustment basis, remaining activity classification, DQ breadth, and required CI checks are still open.
- Further web checks confirmed FireAnt's official historical Excel functions return matched `DealVolume` and negotiated `PutthroughVolume`; its current plan comparison puts the Excel add-in in Premium, with MetaKit base data from Essential upward. A new Kaggle dataset is only a 26-company HOSE real-estate quarterly research sample (2019–2024), not raw daily OHLCV. Neither source was imported or changed the 14,317 unresolved dates. Details: [`alternative-source search`](probe/phase1-source-search/README.md).
- A one-date request to TCBS's legacy public-code OHLCV endpoint for CDG 2025-05-13 returned HTTP 403 with no data. Current TCBS docs require a registered token. This further search did not find an accessible independent OHLCV feed or change the Phase 1 counts.
- Direct exact-date requests to VNDIRECT's public Finfo API returned matched volumes of 1 for VFC (2026-07-03), 80 for NAS (2020-10-15), and 100 for CDG (2025-05-13), with negotiated volume zero on each. All three values match already archived VNDIRECT/HNX evidence; this validates the route but does not reduce the 14,317 unresolved dates. Payloads, URLs and hashes are in [`VNDIRECT API verification`](probe/phase1-vndirect-api-verification-20261019/README.md). No market rows or database statuses changed.
- Broader provider search found DataPro SmartAPI as a potentially useful paid source: it advertises UPCoM EOD history from 2000 and separate matched/negotiated fields, but requires a subscription, charges separately for initial history, and prohibits redistribution. Upstream provenance and this project's ML retention rights remain unverified. TCBS and Fialda also require account/contract access. No authenticated access was available, no data were requested or imported, and Phase 1 remains PARTIAL; next actionable path is an authorized sample plus written scope/rights confirmation.
- The installed vnstock 5.0.3 Community profile was tested with one active `equity_trade_history` route probe through `vnpipe`; it returned `EntitlementError`, and the server usage counters remained unchanged. The route is documented for Extended accounts, so it cannot supply Community matched/deal history. Report: [`trade-history probe`](probe/phase1-trade-history-probe-20261019/2026-10-19.json). No database rows changed.
- Earlier dirty-tree verification before the VNDIRECT adjustment correction: `go -C go test ./...`, `go -C go vet ./...`, and `go -C go test -race ./...` passed; the race run used `CGO_ENABLED=1` and the installed MSYS2 GCC. All 27 Python JSONL tests, all 26 serialized PostgreSQL ingestion integration tests, and `tests/sql/test_migration.sh` also passed against PostgreSQL 18.3. At that point migration 025 was applied to the working database, and the three VNX interpretations were committed and reported `VERIFIED_NEGOTIATED_ONLY`. PostgreSQL 16 hosted CI had not been rerun for that working tree. The activity-date audit retained 14,314 unresolved zero-volume issue ticker/dates.

## 2026-10-19 — continued public-source search and live queue check

- The read-only `backfill-status --from 2018-10-01 --to 2026-10-16` command was run against the recovered local `vnsignal` database. For the 2026-10-17 listing snapshot it reports 1,502 `COMPLETED`, 16 `PARTIAL`, 1 `BLOCKED`, 0 leased, 0 deferred-invalid, and 0 pending jobs. Phase 1 remains partial while partial/blocked outcomes and other exit criteria are open.
- The additional Internet search tested a public VietstockFinance route against exact HNX controls and found false-zero/missing responses; public OpenStockAPI and `vn-market-data` documentation resolved to upstream providers already represented in the repository. No new eligible bars were found. Existing SSI and FiinGroup routes remain separate-credential leads; HNX's historical data service remains the exchange-authorized bulk option.
- Fresh UTT search results support the already archived conclusion: no positive execution was observed through 2026-10-16 across the queried source histories, but this is not a lifetime exchange-wide no-trade claim. UTT remains excluded from trade-bar training.
- The unresolved zero-volume issue ticker/date count remains 14,314 and the negotiated-only count remains 109. The targeted Vietstock web checks were source research only; they created no vnstock quota reservations and no PostgreSQL writes. Detailed source notes and links are in [`continued public-source search`](probe/phase1-source-search/README.md).

## 2026-10-19 — authenticated history options after expanded search

- The current SSI Developer Portal FAQ says Market Data access has no current service fee but requires an SSI securities account and an API key. The documented UPCOM history schemas expose daily OHLC, matched volume, negotiated volume, and total volume including odd lots. No SSI account key is configured here, so no sample could be authenticated or imported.
- FiinQuant's current free plan is capped at 33 tickers and one year of daily history; online registration is temporarily suspended. It cannot cover the project backfill window and is not an available source in this workspace.
- HNX's official per-security UPCoM EOD package is VND 2,000,000/month and HNX advertises a two-week trial. The public catalog does not specify whether the trial includes archive backfill or ML retention rights; the technical guide places connection details after contract signing.
- The expanded search found no anonymous, licensable full-universe feed that passes the project's source and volume-semantics requirements. The live queue remains 1,502 complete, 16 partial, 1 blocked, and 0 pending; the 14,314 unresolved zero-volume issue ticker/date count is unchanged. No market-data calls, imports, or database/quota writes occurred during this research. Phase 1 remains PARTIAL.

## 2026-10-19 — live source coverage after UTT exclusion

- A fresh read-only `backfill-status` run against local PostgreSQL 18.3 reports 1,502 VCI `COMPLETED`, 16 VCI `PARTIAL`, 1 VCI `BLOCKED` (UTT), 0 leased, 0 deferred-invalid, and 0 pending for the 1,519-symbol listing snapshot. UTT is outside the user-approved active scope, leaving 1,518 symbols: 1,502/1,518 (98.95%) complete through VCI and 16/1,518 (1.05%) with a partial VCI result.
- Exchange breakdown of the VCI queue: HNX 298/299 complete, with SPC partial; HOSE 406/406 complete; UPCoM 798/814 complete, with 15 partial and UTT blocked. Removing UTT from the active UPCoM denominator gives 798/813 complete and 15 source-covered partials.
- All 16 VCI-partial symbols have a `COMPLETED` VNDIRECT full-range job. Their source-keyed VNDIRECT history already contains 14,338 positive-volume observations; 388 symbol/dates have no positive canonical VCI bar. These are present as VNDIRECT source rows with unadjusted basis and raw landing lineage, not missing research data. Keep VNDIRECT separate from VCI and do not splice the two bases.
- The approved 14,314 residual zero-volume assumption, 24 positive matched-volume conflicts, 109 negotiated-only dates, and 19 exact HNX zero-matched reports remain separately classified. Zero-volume sessions are plausible on UPCoM, HNX (including SPC), and HOSE; no OHLC bars are synthesized. The 14,314 count is not a missing-bar count.
- The active historical dataset now has at least one completed source history for every in-scope ticker. The VCI queue's 16 `PARTIAL` outcomes and UTT's retained `BLOCKED` outcome are source-specific audit states, not remaining data-coverage blockers. The injected-fault unit and PostgreSQL integration suites pass locally on this tree. The hosted workflow was not rerun; current-tree PostgreSQL 16.15 migration and integration checks passed locally. The PG16 host used an isolated temporary cluster and database and did not modify the registered PostgreSQL 18 dataset.

## 2026-10-19 — Phase 0/1 exit checks passed on the current tree

- Phase 0 exits are evidenced by the registered-machine vnstock 5.0.3 capability report, verified absolute quota fields, migrations 001–025, and a clean current-tree PostgreSQL 16.15 migration/integration run.
- Phase 1 covers 1,518 in-scope symbols after excluding UTT: 1,502 completed VCI histories and 16 completed source-keyed VNDIRECT histories for the VCI-partial tickers. The 16 VCI `PARTIAL` outcomes and UTT `BLOCKED` audit record remain preserved; they do not represent missing in-scope histories. VCI and VNDIRECT series remain separate.
- Zero-volume handling is no longer a Phase 1 blocker. The user-approved residual classification applies to partial research while raw rows and `ZERO_VOLUME_UNVERIFIED` audit findings remain intact; positive matched-volume conflicts and negotiated-only sessions remain separate, and no OHLC bars are synthesized.
- `tests/sql/test_migration.sh` passed against a clean disposable PostgreSQL 16.15 database: two migration passes, schema assertions, injected-failure rollback, and unreachable-connection detection. `go -C go test -tags "postgres postgres_integration" -p 1 ./... -count=1` passed against PostgreSQL 16.15.
- Current-tree checks passed: `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` with CGO enabled and MSYS2 GCC, and all 27 Python JSONL tests. The migration script now places PostgreSQL client options before the database URL so Windows clients execute the same checks correctly.

**Phase 0 and Phase 1 exit criteria are complete. Phase 2 is the next phase; the overall product remains incomplete.**

## 2026-10-19 — point-in-time price basis prepared for Phase 2

- Migration 027 adds a market-wide `core.vndirect_bars_as_of(date)` overload for querying all same-vintage VNDIRECT price histories through one requested session. It seeds the approved UTT exclusion in `ops.ml_symbol_scope`; both the market-wide and per-symbol functions apply that explicit model scope. They return adjusted-as-of OHLC with source-row lineage and fail closed for incomplete/mixed snapshots; missing ticker sessions are not synthesized.
- The local database has 2,844,683 VNDIRECT rows across all 1,519 symbols, every row has all four adjusted OHLC fields, no ticker has mixed vintages, and every symbol has a VNDIRECT row on 2026-10-16. All 2,172,122 DNSE ticker/dates have VNDIRECT counterparts. Of 1,809,966 VCI canonical rows, the only five without VNDIRECT counterparts are the already excluded CTR lifecycle-invalid dates 2022-02-16–2022-02-22. The registered market-wide Phase 2 query returns 1,518 symbols and 2,844,435 rows through 2026-10-16, all on `adjusted_as_of` basis. UTT's 248 raw rows remain preserved and its Phase 2 query result is empty.
- PRC's 2023-03-29 discrepancy is resolved against CafeF's raw 65/70/63/68 OHLC and VSDC's VND 35,000/share dividend notice. VNDIRECT's March 29/30 adjustment-factor ratio matches the 33/68 theoretical ex-right factor; VCI's adjusted close 9.98 agrees, while the DNSE 20.56 value is corrected by that factor to 9.978. Full source response, calculations, and later PRC action cross-checks are in [`Phase 2 adjustment audit`](probe/phase2-adjustment/README.md).
- Phase 2's price input is now the single full-coverage VNDIRECT point-in-time series; no ticker/date is removed because VCI/DNSE adjustment vintages differ. VCI/DNSE remain intact for DQ comparison. The Phase 2 features, labels, point-in-time fundamentals archive, leakage tests, and feature-parity tests remain to be implemented; this evidence completes the price-adjustment prerequisite, not the Phase 2 exit criteria.
- Final verification on 2026-10-19 passed after the explicit-scope SQL assertion was added: `go -C go test ./...` (with `VNPIPE_PYTHON` resolved through `py`), `go -C go vet ./...`, `py -m unittest discover -s tests -v` (27 tests), and `tests/sql/test_migration.sh` against a clean disposable PostgreSQL 18.3 database. The migration check applied all migrations twice, passed schema and PRC-style point-in-time adjustment/scope assertions, and passed rollback and unreachable-connection checks. The registered database also passed the 1,518-symbol/2,844,435-row coverage query and PRC as-of price checks. Hosted CI was not rerun. These results establish the Phase 2 price-input prerequisite; Phase 2 features, labels, fundamentals, leakage tests, and feature-parity tests remain to be implemented.

## 2026-10-19 — revalidate adjusted-as-of input against registered PostgreSQL

- Restarted the local PostgreSQL 18 service and queried the registered `vnsignal` database. The raw VNDIRECT source has 2,844,683 rows across 1,519 symbols, with complete adjusted snapshots and one vintage per symbol. The market-wide Phase 2 function returned 2,844,435 rows across 1,518 in-scope symbols from 2018-10-01 through 2026-10-16; every row has `price_basis='adjusted_as_of'`. It retains 1,021,077 zero-volume rows as `is_traded=false`. The 248-row difference is exactly the explicit UTT scope exclusion; no price-disagreement ticker/date was dropped.
- Verified event-date function output in the live database: PRC 2023-03-29 close is 68.0000 as of that date and 32.9988 as of 2023-03-30; FPT's 2024-11-29 close is 143.3043 as of its 2024-12-02 VND 1,000/share ex-right date; AGG's 2020-01-09 first-day close is 30.0000 as of that day despite a current retrospective snapshot value of 13.8960. This confirms the as-of function removes later adjustment factors while preserving the raw observations. Full column semantics and results are in [`Phase 2 adjustment audit`](probe/phase2-adjustment/README.md).
- Documentation-only evidence update; no SQL, Go, or Python implementation changed in this recheck. The previously recorded current-tree unit, vet, race, JSONL, and migration checks remain the applicable code verification; hosted CI has not been rerun. Phase 2 feature and label generation is still not implemented.

## 2026-10-19 — resolve all VNDIRECT reference factors for the Phase 2 price input

- VNDIRECT's 684 unresolved factors were all on 2019-01-02, where the source returned `basicPrice=0`. Migration 030 applied through the Go migration runner to the registered PostgreSQL 18.3 database; the migration runner verified existing migration checksums and applied one new migration.
- The override ledger contains 684 rows: 169 HNX, 316 HOSE, and 199 UPCoM by the historical bar's `exchange_code`. It records 661 matched-volume rows and 23 zero-volume UPCoM rows. DSN uses the evidence-backed `59.3/62.9` dividend factor; the other 683 are audited no-action factors of 1.0. Raw VNDIRECT rows and zero `basicPrice` values remain unchanged.
- After migration, the in-scope reference view has zero NULL factors. The registered market-wide function returns 2,844,435 rows for all 1,518 in-scope symbols, dated 2018-10-01 through 2026-10-16, with 1,021,077 zero-volume rows retained and no row on a different price basis. DSN's 2018-12-28 close is 59.3 as of 2019-01-02; its 2019-01-02 close remains 58.5.
- `tests/sql/test_migration.sh` passed against a fresh disposable PostgreSQL 18.3 database, applying the full migration sequence twice and checking schema invariants, rollback, connection failure, no-action factor 1.0, DSN dividend factor, and source-row preservation. `go -C go test ./...`, `go -C go vet ./...`, and `py -m unittest discover -s tests -v` also passed (27 Python tests). Hosted CI was not rerun.
- This completes the Phase 2 point-in-time price input prerequisite. Phase 2 feature and label generation, point-in-time fundamentals, leakage checks, and feature parity remain unimplemented; the full product is not complete. The event evidence and per-symbol resolution are in [`2019-01-02 reference resolution`](probe/phase2-adjustment/2019-01-02-reference-resolution.md).

## 2026-10-19 — resolve the remaining VNDIRECT price candidates

- All 641 flagged ticker/sessions now have documented factors: 42 corporate actions and 599 no-action factors of 1.0. Each resolution links to archived public evidence and its response hash. The five VNDIRECT bars that already carried the next session's adjustment use CafeF-backed model OHLC; their VNDIRECT OHLC, volume, trade flag, and lineage remain intact.
- Applied the forward migrations to the registered PostgreSQL 18.3 database through the Go migration runner. It verified existing hashes and applied two new migrations. The already-applied `031_vndirect_adjustment_episodes_and_logspace.sql` ledger row retains its original hash; the new model layer has a distinct migration filename. No migration ledger entries were rewritten.
- The post-migration full-universe as-of query returned 2,844,435 rows for all 1,518 in-scope symbols, from 2018-10-01 through 2026-10-16. It retained 1,021,077 zero-volume rows and returned zero rows on a different price basis. Since the query fails closed for a symbol with an unresolved factor, all in-scope histories are now usable by the Phase 2 price input.
- A clean PostgreSQL 18.3 replay passed with all 32 migrations applied twice, schema and adjustment assertions, injected-failure rollback, and unreachable-connection detection. `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` (CGO enabled with MSYS2 GCC), and `py -m unittest discover -s tests -v` (27 tests) passed. Hosted CI was not rerun.
- This resolves the Phase 2 price-adjustment prerequisite. Phase 2 feature and label generation, point-in-time fundamentals, leakage checks, and feature parity remain to be implemented; the overall product is not complete.

## 2026-10-23 — Phase 2 acceptance gates passed (historical checkpoint, superseded)

- Phase 2 now has SQL V2/V3 features, next-open-entry labels, an append-only point-in-time fundamentals archive and overlay, resumable scoped builders, and Rust parity coverage. This supersedes the earlier 2026-10-19 status above, which predates the Phase 2 implementation.
- E1 produced the real null-rate report for 2,844,435 rows across 1,518 symbols through 2026-10-16. The audit found 73/88 fields above the report's lookback-only 1 percentage-point expectation, 13 fields still source-unverified, and explained why those flags are not by themselves confirmed defects. The Master Build Spec treats null-rate shifts as warnings and requires a report; it defines no 1-point exit threshold. Detailed cell-level attribution remains open. See [`E1 null-model audit`](evidence/phase2/phase2_e1_null_model_audit_20261022.md) and its linked report artifacts.
- E2 passed against only the disposable `vnsignal_phase2_report_20261019` database. Across the 40%, 70%, and 95% cut dates (2021-12-14, 2024-05-21, 2026-05-27), the point-in-time-stratified 60-symbol cohort had zero pre-cut feature-row differences, zero completed-label differences, and zero label-boundary mismatches. Each branch produced crossing labels and post-cut feature changes; independently perturbed future equity and index inputs changed the full-market support. The test's outer transaction ended with `ROLLBACK`; the registered `vnsignal` database was not modified. Full counts, the selected cohort, perturbation bounds, and SQL output are in [`E2 real leakage log`](evidence/phase2/phase2_e2_real_leakage_20261023.log).
- E3 passed on 20 deterministic real symbol-days with VNDIRECT source lineage and payload hashes checked against the current V3 feature hash. The three sampled dates were 2023-04-04, 2022-10-10, and 2024-09-04; the transaction-local adjusted-price cache contained 2,844,435 rows. See [`E3 real parity log`](evidence/phase2/phase2_e3_real_parity_20261023_retry12.log).
- Current-tree verification after the Rust changes passed: `go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover -s tests -v` (27 tests); the Rust library, integration, and doc-test suites also passed. Hosted CI was not rerun.

At this historical checkpoint, the then-current acceptance gates were reported complete. Later migrations 058, 059, and 064 changed label availability, training eligibility, and the V2 rolling-extrema implementation. The current status at the top of this file supersedes that conclusion: Phase 2 is not ready for sign-off or Phase 3. The later E2, E3, E4, and E5 evidence must be used for the current decision.

### Phase 2 continuation evidence — 2026-10-24
- APP/C92/VIE official HNX source archive: six raw landings committed to report clone; repeat added zero. Exact byte checks and identity checks passed. See `docs/evidence/phase2/hnx_upcom_transfer_sources_20261024/import_retry_20261024.log` and `import_repeat_20261024.log`. This archives evidence only; lifecycle classification remains open.
- Migration 071 fresh two-pass harness passed and was applied to the report clone. Real low-memory feature attempt still stopped before feature generation: measured 15/30/60-symbol probes 827/3495/4544 ms, adjacent exponent 2.079 > 1.3. No guard was weakened and no feature completion is claimed.
- Required 071 Go tests and vet passed. Initial Python run timed out in the five-second health subprocess test; isolated health returned in 1701 ms and an unchanged full 31-test rerun passed (`python_tests_071_isolated_20261024.log`). Initial failure retained.
- Phase 2 remains incomplete; full current feature build, remaining exit evidence, and current candidate CI are outstanding.

### Archived price-band census — 2026-10-24
Read-only census completed successfully on report clone (`docs/evidence/phase2/phase2_price_limit_coverage_20261024.log`). All 2,844,683 VNDIRECT source rows resolve to archived response rows with numeric ceiling/floor pairs; 2,843,396 pairs are positive and ordered, and 1,287 are invalid (1,278 in 2019; nine in 2023). This corrects the earlier implication that raw price-band evidence is absent. It does not establish point-in-time availability, materialized observation coverage, or execution-weight validity. Invalid pairs must remain unusable. No raw/core/feature data was changed by the census.
Migration 072 cache projection accounting: fresh two-pass disposable migration harness exit 0; report-clone apply and rollback-only assertions exit 0. Go tests/vet and Python 31/31 passed with project Python environment. This corrects time estimation only; real scaling guard and E1 remain open.
Isolated full-history build phase2-v3-072-isolated-full-20261024 passed the unchanged preflight: 15/30/60 measured 550/1122/2490 ms, maximum adjacent exponent 1.150 <= 1.3, projected cache 1.06 minutes within 40-minute budget. Full 1518-symbol cache load started. This is preflight evidence only; feature completion remains unproven. Live log: docs/evidence/phase2/phase2_v3_072_isolated_full_20261024.log.
The isolated 072 full-cache attempt was cancelled after exceeding twice its estimate; cancellation arrived during final ANALYZE after all102 batches filled. No feature pass. Migration073 removes unconditional growing-cache DELETE scans on first loads while retaining retry replacement. Targeted scan-counter/uniqueness assertions passed; fresh073 full migration harness and required checks are in progress.
073 verification completed: Go tests/vet and Python31/31 passed; fresh two-pass migration harness exit0; report-clone apply and scan/retry assertions exit0. Corrected full-history feature build phase2-v3-073-isolated-full-20261024 started, with current log docs/evidence/phase2/phase2_v3_073_isolated_full_20261024.log. Previous cancelled072 attempt remains failed.
Corrected073 full build stopped at preflight (552/1718/2115ms, exponent1.638), before cache/feature generation. No repeated-until-green run was attempted. A fixed nine-sample diagnostic retained all measurements: medians619/1239/2911ms (adjacent exponents1.001/1.232), but15-symbol coefficient of variation29.69%, so these medians are not accepted as stable evidence. A fixed90-sample longer diagnostic is now running; it does not change production gates.
Migration074 fixed benchmark: fresh two-pass migration harness exit0, including fixed-sample validation assertions. Final runner readiness change also passed Go tests/vet and Python31/31; report-clone apply/rollback-only assertions succeeded. Full-history build phase2-v3-074-isolated-full-20261024 now running the actual fixed90-sample protocol. No production074 preflight or feature completion is claimed until its results are inspected.
Actual074 benchmark retained all90 samples and correctly rejected unstable block means. Serena processes had restarted automatically and were stopped during that run; local Codex Serena auto-start was then disabled and zero processes verified. Disturbed timing CSV: docs/evidence/phase2/phase2_074_disturbed_samples_20261024.csv. A fresh unchanged-protocol build phase2-v3-074-clean-full-20261024 is running under the corrected local environment; no pass is claimed yet.
Clean074 setup completed: all2844435 cache rows filled in75.336275s and finalized in18.277122s;90-sample aggregate648/1367/2379ms, exponent1.077. Eight quarterly feature chunks committed (2018Q4 through2020Q3), totaling659588 rows. Interactive tool handle/process disappeared afterward; authoritative PostgreSQL inspection found no active build connection and remaining25 chunks pending. Same buildID resumed via hidden background process with persistent status JSON/process start identity and separate resume log; existing done chunks must pass normal hash checks before skipping. See phase2_074_process_loss_audit_20261024.log. No full feature completion claim.
Fundamental analyzer JSON-type checks added to route malformed quoted numeric/order/unit fields through existing quarantine before archival commit. Go tests/vet and Python31/31 passed after formatting; signed32-bit order boundaries and malformed fields covered. Provider capability/row-ID/unit mapping remains open; no live calls or canonical mappings enabled. Evidence: phase2_fundamental_json_types_20261024.md.
Resume1 terminated explicitly with exit1 after90 samples failed block stability; eight committed quarters remain659588rows. The subsequent rollback-only memory diagnostic exited0 and passed sample stability validation, reaching22.3MB backend allocation; it did not invoke the final scaling assertion or build features. Normal function restoration verified. No build is currently running. See phase2_cache_memory_investigation_20261024.md. POM/QBS archived endpoint evidence now supports two further9-session venue-transition explanations (18sessions); manifest hashes/sizes of fivefiles verified and gap_assessment updated. No lifecycle/interval DB classification or bars changed.
075 cache-hash invalidation correction: red regression reproduced stale hashes on074; targeted075 passed; fresh two-pass075 migration harness exit0; Go tests/vet and Python31/31 passed. Report-clone migration and expanded reset/retry/ownership/rollback assertions passed. POM/QBS five source landings committed and repeat addedzero; immutable byte/identity checks passed. Full feature coverage still eightquarters/659588rows; remaining25 feature chunks, label/fundamental/lineage/E4 and CI gates remain open.
After075 and final readiness checks, background resume2 started under the same phase2-v3-074-clean-full-20261024 buildID. Current process9328 start identity verified; log/status use phase2_v3_075_clean_full_resume2_20261024. It must revalidate existing hashes and pass the fixed90-sample guards; no completion claimed. All eight previously committed chunks remain the last proven feature checkpoint.

076 lineage archive: expanded review regression passed (nine source outcomes, strict ISO parsing, append-only including TRUNCATE, scope-sensitive batch fingerprints). Go tests/vet and Python31/31 passed. Fresh two-pass migration harness running; real report-clone lineage and listing-tenure consumption remain unproven. See evidence/phase2/phase2_vci_lineage_archive_076_20261024.md.

076 terminal checkpoint: fresh full two-pass migration harness exit0. Applied report clone; real ABR archive 1426 observations (1424 EXACT, 2 MISSING_LANDING), repeat inserted0. Full-universe lineage remains pending. Fundamental year-zero parser/database mismatch fixed; annual/quarterly boundary regressions and Go tests/vet/Python31 passed. Phase 2 remains incomplete.

Fundamental adapter attribution checkpoint: actual installed5.0.3 quarterly income route returned160rows. Adapter now preserves matching provider/request ticker attribution and rejects conflicts. FPT one-frame durable ingestion committed160managed rows/eightquarters (2024-09-30..2026-06-30), checksum/body and conservative availability verified. Go tests/vet, Python32, explicitCGO UCRT64 Go race, and disposable PostgreSQL fundamental assertions passed. Other statements/yearly capabilities/mappings/coverage remain open. See evidence/phase2/phase2_fundamental_attribution_20261024.md.

12:15 checkpoint:10 quarters through2021-03-31 committed830523rows;23quarters remain (phase2_feature_checkpoint_20261024_1215.log). Migration077 reviewed and targeted/baseline recovery assertions passed; Go/vet/Python32 passed. Its fresh harness/report apply/full lineage are queued behind successful feature completion with process identity and input-hash guards, not yet passed. Current-machine quarterly balance_sheet168rows and cash_flow56rows capability probes also succeeded; source data for those statements is not yet archived. SPI3landings imported, repeat0; no lifecycle classification altered.

12:55 feature checkpoint:12quarters through2021-09-30 committed1007116rows;21quarters remain (phase2_feature_checkpoint_20261024_1255.log). All six FPT statement/frequency archives verified768versions. Observed cash refresh adds56observations, repeat skipped with one reservation (824observations total). Annual capability matching and Vietnam-day observed job keys implemented; Go/vet/Python32 and explicitUCRT64race passed. 078 current-V3 cohort/null-industry corrections passed targeted assertions, including five peers per rank metric. Fresh full harness and report077/078/079/080/081 applications are queued serially in replacement078 process, not passed yet. SPI source-backed gap explanation added to the selected research assessment after three-source archive/repeat verification; this is not a fresh219-interval census.

Migration079 separates parent profit/equity from group totals for P/E and P/B,
persists the operands and versions formula identity. Targeted migration replay
and synthetic overlay assertions pass. The fresh full harness remains queued.
See [valuation evidence](evidence/phase2/phase2_parent_valuation_079_20261024.md).

Migration080 implements explicit legal listing episodes and persisted membership.
Targeted apply/replay, 249/250 boundary, suspension, transfer gap, relisting, PIT
correction and persisted membership assertions pass. Real notice population and
coverage remain open. See [listing tenure evidence](evidence/phase2/phase2_listing_tenure_080_20261024.md).
The latest database checkpoint confirms 14 committed quarters/1,183,092 rows
through 2022-03-31, with 19 quarters pending. PostgreSQL confirms active 2022Q2
computation. See [checkpoint](evidence/phase2/phase2_build_checkpoint_080_completed_quarter_20261024.log).

Migration081 fixes same-day industry availability in the separate fundamental
overlay; targeted apply/replay, overlay and dedicated cutoff/conflict/hash checks
pass, as do Go tests/vet and Python32. See
[industry evidence](evidence/phase2/phase2_industry_availability_081_20261024.md).
The latest checkpoint is 15 committed quarters/1,271,759 rows through 2022-06-30,
with18 quarters pending and active2022Q3 computation. See
[checkpoint](evidence/phase2/phase2_build_checkpoint_081_20261024.log).

# Decisions

## 2026-10-24 — validate symbol-first V3 eligibility and bound recovery to the last 400 sessions

- Migration 068 rewrites only `eligible_symbols` in the shared V3 builder. It
  preserves the exact VNDIRECT, positive-finite-factor, selected-session
  predicate and drives it from each requested symbol through the existing
  `(symbol_id, trade_date)` cache index, stopping at the first eligible row.
  The fresh two-pass PostgreSQL migration harness passed, including production
  feature assertions. The migration was also applied to the disposable report
  clone; the V3 feature-set hash remains
  `775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`.
- The prior full-cache Q1 run was canceled at the eligibility query after
  1m53s based on a 60-symbol cache sample. That sample contained only about
  17.9K matching cache rows, versus 2,844,435 rows in the production-scope
  cache; its 4.58-second query was not comparable. The cancellation was early
  relative to a full-scope linear estimate. Record this correction rather than
  treating that stop as a measured 2x overrun. The new full-cache probe passes:
  15/30/60-symbol eligibility queries took 56.064/87.732/160.823 ms, with
  `b=0.760` overall and an index scan per requested symbol. The plans, timings,
  and probe SQL are in
  `docs/evidence/phase2/phase2_symbol_first_eligibility_full_cache_probe_20261024.psql/.log`.
- The known current-hash 2019 feature chunk produced 326,456 rows in 884.2 s.
  Linear projection for the remaining approximately 2.44 million V2 rows is
  about 110 minutes, above the recovery budget's approximately 84-minute
  feature-build allowance (203 minutes remaining at the recovery checkpoint,
  less the 90-minute downstream reserve and 15-minute margin). Follow the
  recovery prompt's fallback instead of starting a full-history run: build the
  full-universe slice of the latest 400 effective sessions, 2025-03-11 through
  2026-10-16, and label all slice evidence explicitly. Full-history V3, full
  labels, and full-history E1 remain open for Phase 3.
- The approximate remaining-time calculation uses the last failed-build log
  timestamp, 04:18, as the recovery checkpoint. It is a planning estimate, not
  a completion claim. The selected fallback is bounded and recorded in
  `docs/evidence/phase2/scaling_probe.md`.
- The first bounded last-400 build did not enter a feature chunk: the 32 MB
  cache preflight returned `b=1.304`; a repeat returned `b=1.672`. Keep the
  threshold unchanged. The 15-symbol plan completed in 628 ms. A nested-plan
  capture for 60 symbols showed the wide adjustment `ordered` work table spilled
  4,047 temp blocks (33,147,574 bytes); cache populate/finalize took 2.133/0.514
  s. Host telemetry was 3.83 GiB total RAM and 0.42 GiB free. Raising the
  single-session query setting to 64 MB cleared the spill without raising any
  application guard: the runner-equivalent 15/30/60 probe passed at
  566/1,134/2,786 ms, `b=1.150` overall, with no increase in PostgreSQL temp
  counters. Its 1,518-symbol cache projection was 1.48 min. At that checkpoint,
  the next step was to rerun the bounded build at 64 MB while preserving the
  1.3 exponent limit. Evidence is in
  `docs/evidence/phase2/phase2_cache_scale_plan_15_20261024.psql/.log`,
  `phase2_cache_stage_components_60_20261024.psql/.log`, and
  `phase2_cache_scale_retry_64mb_20261024.psql/.log`.
- Follow-up: the 64 MB build preflight passed, loaded 2,844,435 adjustment
  rows, then exceeded its hash-step checkpoint before any feature SQL ran.
  The first feature chunk requested 1,206 price dates from 2021-03-09 through
  2025-12-31. A comparable 374-date hash took 2m43s, so the estimated step was
  8m43s and the 2x stop point was 17m26s. PostgreSQL still showed the builder
  backend waiting on `IO:DataFileRead` at 26m49s. Stopping the psql client had
  not stopped that backend; an explicit `pg_cancel_backend` returned true, and
  a subsequent targeted activity query found no remaining backend. The runner
  recorded failure at 05:00:30, while server cleanup completed later. No V3
  feature statement or output rows were produced by this attempt. Do not rerun
  the same wide hash step. Replan its exact canonical per-day aggregate and
  reusable staging, preserve input-hash equivalence, then measure a bounded
  hash before resuming the last-400 slice. Full-history V3 and current-hash E1
  remain open. See `docs/evidence/phase2/phase2_last400_hash_overrun_20261024.md`
  and `phase2_build_phase2-e1-e5-v3-068-20261024-last400.failed.20261024-050030.log`.

## 2026-10-24 — keep E1 scaling guard closed under unstable cache timings

- The full current-hash V3 rebuild was attempted only on disposable clone
  `vnsignal_phase2_report_20261019`, confirmed as PostgreSQL 18.3 with V2 dates
  2018-10-01 through 2026-10-16. The run stopped in its adjustment-cache
  preflight before any feature-builder statement ran; the source, core, V2 and
  V3 market rows were not changed.
- The original 128 MB probe recorded 15/30/60 timings of
  10.560/22.084/7.581 seconds and failed the adjacent-sample stability guard.
  A rollback-only 128 MB warm-up/recheck then recorded 4.225/4.609/41.475
  seconds and failed with exponent 3.170. A 32 MB recheck recorded
  45.899/44.967/13.040 seconds and again failed stability. Keep the existing
  20% stability and 1.3 scaling thresholds; these inconsistent samples do not
  establish either passing scale or a reproducible superlinear regression.
  The commands and complete outputs are in the paired
  `phase2_e1_cache_probe_*_20261024.psql/.log` files and the failed build log
  under `docs/evidence/phase2/`.
- Host evidence recorded 3.83 GiB total RAM with 342–344 MiB available during
  the follow-up. This makes host pressure plausible, but it does not prove the
  cause; a separate probe-stage timing/plan capture is required before the
  full build. Do not infer that lowering `work_mem` fixes the observed
  variance. The build runner's failure handler also labels the first pending
  feature chunk failed when a shared preflight fails before a chunk starts;
  preserve that run record as a preflight failure and do not interpret it as a
  feature-chunk runtime failure.
- The isolated 60-symbol run at 32 MB separated initialization (0.664 s),
  population (2.989 s), and finalization (0.437 s). The captured nested plan
  returned 108,331 rows, used a hash left join, and read/wrote 4,047 temporary
  blocks during population. Its estimate for the final join was 2 rows versus
  108,331 actual rows, so retain this plan as a cardinality-estimation follow-
  up; it does not show a nested-loop regression. After warming the same data,
  the standard rollback-only scale assertion passed at 1.323/1.720/2.475
  seconds with exponent 0.525 and a 1.19-minute projected cache stage. Start
  the full annual feature chunks at 32 MB on a new build ID, retaining the
  existing 30-minute statement timeout and per-year checkpoints. The pass is
  only the cache preflight; E1 remains open until all feature chunks and the
  refreshed null-rate report are complete.
- Follow-up recovery checkpoint: the 2018 and 2019 annual chunks completed with
  82,218 rows in 202.8 s and 326,456 rows in 884.2 s. The annual 2020 chunk was
  canceled before commit when its third 60-symbol feature batch crossed the
  recovery checkpoint projection; annual chunks are too large for this host.
  Migration 067 now records the exact distinct date set during adjustment
  cache fills, and its fresh PostgreSQL migration harness passed. Date planning
  fell to 0.164 s for 2020, but hashing historical price rows remains I/O-bound.
  The attempted standalone prehash for 2018-10-01 through 2019-12-31 was
  canceled after 16m07s, beyond twice the comparable 6m22s hash step. The
  quarterly Q1 2020 chunk is recorded failed only because that shared prehash
  was canceled before the feature statement; no Q1 feature rows committed and
  later quarters remain pending. Removed the standalone prehash from the
  runner, retained quarterly chunking, and will retry the first quarter with
  hashing inside its bounded chunk transaction. Evidence:
  `phase2_build_phase2-e1-v3-067-20261024-quarterly.failed.20261024-033546.log`,
  `phase2_e1_cache_probe_warmup_20261024.log`, and the migration harness log in
  `docs/evidence/phase2/`.
- Official HNX/issuer sources additionally establish DNM's HNX-to-UPCoM
  transition (10 missing sessions) and MIC's UPCoM-to-HNX transition (11
  sessions). The lifecycle packet now supports 17 of 219 continuity intervals
  (128 sessions); 202 remain unsupported. Keep all 17 as research evidence
  until exact ticker-matched lifecycle events are imported through the
  append-only path and real eligibility counts are recomputed. Do not infer
  suspensions or synthesize bars.

## 2026-10-24 — preserve rank semantics while closing E2

- Replace the three repeated V2 `percent_rank` branches with one narrow
  long-form rank window and pivot in forward migration 066. Keep separate
  non-null populations for 20-session return and turnover, and require
  `return_n20=20` for volatility ranks. The SQL assertion compares exact ranks
  against independent per-metric windows; do not alter the feature-set hash
  because output semantics are unchanged. Refresh the E2 projection's shared
  builder hash guard.
- The exact branch-schema profile passed at 15/30/60 symbols in 3.02/5.82/12.61
  seconds, zero temp files/bytes, and `b=1.03` from 15 to 60. The plan computes
  the rank window once and hashes back to the picked rows. Record adjustment
  cache preparation separately from V2 builder time.
- E2 passed at the 40%, 70%, and 95% cutoffs for the same PIT-stratified
  60-symbol cohort: zero pre-cut feature differences, completed-label
  differences, and boundary mismatches, with crossing labels and changed
  future equity/index inputs. The E2 test is rollback-only and uses the
  disposable report clone. Select its cohort before preparing adjustment
  inputs, and cache only those 60 symbols; do not change the cohort,
  perturbations, comparisons, or cutoff requirements.
- The stored V3 hash guard in E2 now applies after its immutable branch baseline
  has been rebuilt with the current builder. This keeps the E2 output check
  strict while allowing the stale stored V3 rows to remain a separately
  recorded E1 rebuild gap; it does not certify them.
- The final fresh two-pass migration harness passed with the production-builder
  recursive SQL golden (320 fixture rows), including exact V2 rank assertions;
  the complete current E2 run remains rollback-only. Go tests/vet, 29 Python
  tests, Rust fmt/clippy/workspace tests, and `git diff --check` passed after
  these edits. The Windows race run still cannot start tests because
  ThreadSanitizer cannot reserve shadow memory (error 87); hosted CI has not
  run.
- E3 passes the recovery prompt's defined scope: 20 current-hash real-data
  symbol-days passed non-recursive SQL/Rust parity at `1e-9`; a 320-row
  independent golden exercises every recursive feature currently in
  production (EMA/MACD) through both Rust and the SQL production builder.
  Existing RSI/ATR are rolling-window features, V3 ADX is explicitly a simple
  average, and EWMA variance is absent. Do not add those features solely to
  expand the golden. Keep the small real `ema_100_ratio` recursive comparison
  disclosed as a diagnostic; the recovery E3 gate does not require recursive
  real-data SQL/Rust parity.
- Phase 2 remains open: refresh E1 after a full current-hash V3 rebuild;
  reconcile 204 unsupported E4 intervals; complete the current-hash E5
  repeated-output hash; verify the added PIT label outputs and fundamental
  coverage; and run hosted CI with `VNPIPE_DISABLE_LIVE=1`. No commit or Phase 2
  sign-off until those gates pass.

## 2026-10-23 — apply Master Build Spec Phase 2 exit gates and carry recovery findings forward

- The authoritative Phase 2 exit criteria in `docs/MASTER_BUILD_SPEC.md` §13 are a produced null-rate report, a passing leakage test, and passing feature parity. E1's real V3 report exists for the prior `f4d61dd5…` hash, but migration 065 advances the V3 hash; the null-rate report still needs a full current-hash V3 rebuild. E3's non-recursive slice passed at `1e-9` on 20 deterministic, source-attributed real symbol-days across three dates under current hash `775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`; only those date partitions, not the full history, were rebuilt. E3 remains incomplete because the independent goldens do not yet cover Wilder RSI, ATR/ADX or EWMA variance, and the SQL fixture does not exercise the production V3 builder end-to-end. The latest current-tree E2 run did not complete its 40% cutoff comparison, so E2 is NOT PASS and Phase 2 is not ready for sign-off. The earlier three-cut E2 log predates migration 058 and is historical only; see the recovery recheck at the top of `docs/BUILD_STATUS.md`.
- The current-state audit on the disposable report clone found no active PostgreSQL build. V3 contains 2,844,435 rows, of which 4,349 use current hash `775b9bd5…` across only the three E3 sample dates; 2,840,086 still carry pre-065 hash `f4d61dd5…`. The clone has no derived label-target or liquidity-tier tables and no label-target builder function. There is no current V3 job to keep/cancel or estimate; the full-hash rebuild and derived-label build remain open. Evidence: `docs/evidence/phase2/phase2_v3_current_state_20261023.md` and its captured SQL log.
- A first broader real-data E3 comparison found `ema_100_ratio` differed for symbol 824 on 2023-04-04 (`SQL=0.004010006674335`, Rust `0.004010006740238`). The recovery prompt specifies independent golden checks for recursive EMA/MACD features, so retain the failed log and validate recursive behavior with a 430-row pandas 3.0.1 golden fixture (`tests/golden/phase2_recursive_ema.csv`) exercised by both Rust and PostgreSQL. The non-recursive real-data parity tolerance remains `1e-9`; no claim is made that recursive SQL↔Rust values match on real history.
- Preserve the recovery prompt's 1 percentage-point E1 flags as diagnostics without changing its structural expectation formula or treating the threshold as an added Master Spec exit gate. Keep the 13 source-unverified fields NULL and retain row-level availability follow-up.
- E5 current-hash reproducibility is inconclusive: the post-migration-058 2023 label chunk completed once, while its forced repeat was interrupted before a second output hash. Earlier pre-migration-058 hash matches do not satisfy the current recovery gate. E4's report passes row-count, key, session-membership and rank checks, but 219 continuity gaps across 1,539 expected sessions remain unattributed. Do not call them suspensions or synthesize bars. Phase 3 must exclude affected rows from training until the gaps are reconciled or a separate, documented eligibility policy covers them.
- The point-in-time fundamentals archive and builder exist, but its historical data coverage remains partial; the 13 source-unverified feature inputs remain NULL. These are visible follow-ups for later model eligibility and overlay coverage, not evidence that the three §13 Phase 2 exit tests failed.
- Migration 065 replaces cancellation-prone prefix subtraction for paired VNINDEX regression moments with rolling `var_samp`/`covar_samp`. Preserve the `1e-9` parity tolerance, require the same non-null stock/index pair population in all moments, and retain both the independent-rank and inherited VNINDEX-return hash tokens. The fresh two-pass PostgreSQL harness, strict synthetic parity test, real non-recursive E3 slice, and EMA/MACD golden checks pass. The full E3 gate remains open because independent golden coverage for other recursive families and production-builder fixture coverage are missing. Go tests/vet, 29 Python tests, Rust fmt/clippy/workspace tests pass; Windows race testing is unavailable because ThreadSanitizer cannot reserve shadow memory (error 87) with UCRT64 GCC. E1, E2, E3, E4 and E5 remain open as recorded in `docs/BUILD_STATUS.md`; do not commit or claim Phase 2 sign-off. The hosted workflow disables live vnstock access with `VNPIPE_DISABLE_LIVE=1`; hosted CI has not run.

## 2026-10-22 — upgrade installed rank definitions and preserve real-evidence integrity

- Runtime inspection of the disposable report clone showed that V2's installed
  rank expression omits the full-return-count guard now present in the source.
  Preserve migration history and add migration 053 for existing installations.
  Require V2 rank/input eligibility consistency after builds and current,
  rank-consistent V2 inputs before V3 builds. Change feature hashes when changing
  rank populations; rebuild historical outputs before calling them current.
- Gaussian ranks use separate non-null populations for each metric, with average
  tie ordinals and singleton score zero. A missing turnover value must not
  suppress an otherwise valid momentum or volatility rank. Test disjoint nulls,
  ties, singleton/empty populations, and stale-input rejection in the production
  builder and independent Rust reference.
- E2 cannot use October 2026 listing snapshots at its 2021 first cut. Use the
  source-row-linked venue on the latest historical VNDIRECT bar dated by the
  cut; retain venue date/landing/row in evidence and reject unknown latest venues.
  Keep the existing cohort-size, stratum and bit-identical pre-cut assertions.
- Real parity selects its 20 observations before hashing source payloads, then
  requires every selected observation's exact lineage and payload hash to pass.
  Do not silently filter corrupt samples. This removes the all-history payload
  scan while retaining the production rebuild and 1e-9 comparison requirement.
- The canceled real parity attempt, installed-function diagnosis, and pending
  verification are recorded in
  `docs/evidence/phase2/phase2_rank_recovery_checkpoint_20261022.md`.
- Preserve the shared-builder fixture's outer transaction, row-byte equality,
  labels, boundaries, counts and injection guards, while making its four
  independent build passes separate statements. The existing 180-second
  statement limit previously covered their cumulative work inside one `DO`;
  neither a missing endpoint index nor missing endpoint statistics explains
  the cancellation. Retain the 180-second setting for each pass. The complete
  remaining SQL assertion sequence passes after this change. Keep the earlier
  timed-out full replay recorded as incomplete.
- Stop the Serena server tree started by this recovery run after its use,
  including its background language servers. Ignore local vnstock state,
  Serena state and generated compiler caches so they are not indexed or staged
  as source changes. No cache or market-data directory was deleted.

## 2026-10-22 — scope the label factor-scan planner and finish label coverage

- Keep the bad-factor validation query's result semantics unchanged and scope `enable_nestloop=off` only around that query. The 2022 plans showed nested-loop scans lasting 181–189 seconds; a rollback-only full-year probe used a sequential scan and hash joins and completed in 1.57 seconds. Migration 051 adds exact anchor checks and the fixture assertion verifies both the scope and restoration order.
- Capture `ROW_COUNT` immediately after the CTAS and restore `enable_nestloop` afterward. The first patch restored the GUC before reading diagnostics, causing a notice of one from the restore call; the `phase2_label_first_bad_factor` temp table and label results were unaffected. The final 2023 runner log reports zero bad-factor rows.
- Keep the 2022 annual failure in history, covered by its two successful half-year chunks. Complete the remaining yearly label chunks under `phase2-vci-labels-rechunk-20261022`; the 2023 forced rebuild reproduced the same input and output hashes. See `docs/evidence/phase2/phase2_label_recovery_20261022.md` and `docs/evidence/phase2/phase2_label_chunk_status_20261022.csv`.
- E5 is now satisfied for the repeated 2023 chunk. E1–E4, PIT-fundamentals coverage, final local checks, and hosted CI remain required; Phase 2 stays open.

## 2026-10-22 — preserve the E1 failure after availability analysis

- Keep the specified E1 one-percentage-point threshold and full-row denominator unchanged. The current 2,844,435-row V3 report has 73/88 measured features outside tolerance, 15 within tolerance, and 13 source-unverified. Corrected VCI fields now pass their comparisons, but this is not enough to pass E1.
- Record the availability breakdown as root-cause evidence only: 1,021,077 rows are untraded and all have `ret_1` and `close_sma200_ratio` null; additional traded rows also have these fields null. Do not silently redefine the expected-null formula or mark E1 passed. Decide on any eligibility-aware formula only through a documented spec decision after diagnosing the remaining traded-row and feature-specific gaps.
- The fresh PostgreSQL 18.3 v9 harness passed fixture migrations/assertions, but it does not substitute for real E2–E4 or hosted CI. See `docs/evidence/phase2/null_rates_full_20261022.md` and `docs/evidence/phase2/phase2-migration-harness-v9-20261022.md`.
- Keep Phase 2 open: E1 fails; real E2 and E3 have no completed result; E4 timed out without metrics; E5 passes for the repeated 2023 label chunk; local Go/Python/Rust/harness checks pass; hosted CI and complete PIT-fundamentals coverage are not evidenced. The current gate table is `docs/evidence/phase2/phase2_gate_status_20261022.md`.

## 2026-10-22 — split the timed-out 2022 label build

- Preserve the original failed annual chunk as failure evidence. Do not mark it done: its `DO` transaction exceeded the 30-minute statement timeout while the final insert was active. The context identifies the active nested SQL command, not the duration attributable to that insert alone.
- Recover the 2022 output with separate H1 and H2 label chunks under build `phase2-vci-labels-rechunk-20261022`. Both completed on the disposable report clone with 342,614 and 370,978 rows, total 713,592, and recorded input/output hashes. Preserve the durable status in `docs/evidence/phase2/phase2_label_chunk_status_20261022.csv`.
- Capture nested PostgreSQL plans before treating the split as a diagnosis. The final inserts measured 37.7 s and 31.7 s with zero conflicts. The first-bad-factor scan measured 189.1 s and 181.1 s and returned zero rows; H1's plan shows per-symbol index scans with high local-buffer traffic. Keep that scan as a performance follow-up, not as a proven cause of the annual timeout. Evidence: `docs/evidence/phase2/phase2_labels_2022_autorun_plans_20261022.log` and `docs/evidence/phase2/phase2_labels_2022_split_checkpoint_20261022.md`.
- At this decision point, continue labels for 2023–2026. The later full-label checkpoint above supersedes that pending status; E1–E4, PIT-fundamentals coverage, final local gates, and hosted CI remain open.

## 2026-10-22 — use set-based V3 symbol eligibility and time-box the real backfill

- The full-history build `phase2-vci-full-rebuild-20261021` saved eight feature chunks through 2025 (2,552,145 rows), then its 2026 chunk reached the temporary symbol-batch population query and was canceled at the 30-minute step limit. The latest build's nine label chunks are pending. The durable status is [`phase2_feature_chunk_state_20261022.csv`](evidence/phase2/phase2_feature_chunk_state_20261022.csv); the failed chunk details are in `docs/evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021.failed.20261021-235301.log`.
- Replace per-symbol correlated cache probes with a set-based join driven by the effective-session dates and the temporary cache's `(trade_date, symbol_id)` index. Update migration 037 for fresh databases and add migration 045 for existing databases. The two-pass PostgreSQL 18.3 migration/fixture harness passed; migration 045 also patched the old function on the disposable report clone. Evidence: [`migration harness`](evidence/phase2/phase2-migration-harness-v4-20261022.log) and [`045 upgrade`](evidence/phase2/phase2_apply_045_symbol_eligibility_20261022.log).
- Migration 044's historical VCI-field backfill was attempted twice on the disposable report clone and canceled, with the longer attempt stopped at 10 minutes. `EXPLAIN` showed a hash join with a sequential scan of about 2.88 million feature rows; the table's total size was 3.55 GB. Cancellation rolled back the transaction. Do not treat the clone as corrected or run E1 against it as final evidence; resume with a bounded backfill plan. No registered database or live vnstock calls were used. Evidence: [`044 retry log`](evidence/phase2/phase2_apply_044_vci_retry_20261022.log); the read-only integrity report also timed out at its five-minute limit.
- Do not claim the recovery prompt's fallback as complete: the full-universe 400-session slice and 60-symbol real-data subset were not run because corrected VCI fields are not materialized. Phase 2 remains open, not conditionally complete.
- Keep Phase 2 open. The prior null-rate report is stale and failed its tolerance count; real-data E2/E3, current E1, E4 metrics, E5 repeated-hash evidence, label chunks, PIT fundamentals coverage, and hosted CI are still required. Local Go/Python/Rust gates and the PostgreSQL 18.3 fixture harness passed; details are in `docs/evidence/phase2/phase2_recovery_checkpoint_20261022.md`.

## 2026-10-21 — use the registered VCI history for V3 VNINDEX context

- The disposable full-history report contains 1,995 VNINDEX bars from `vci` and no VNINDEX bars from `vndirect`; the registered VCI history covers the local exchange-calendar sessions from 2018-10-18 through 2026-10-16. V3 feature and V3 label benchmark context must read `core.index_bars.source='vci'` so the available evidence is used. Keep VNDIRECT as the equity price basis and leave the V2 benchmark logic unchanged.
- The correction changes the V3 feature-set hash and is installed by migration 043 for existing databases. Rebuild V3 features and labels before interpreting outputs created under the former mapping. The two-pass fixture harness passed after the lag positive control was updated to check V3's `vnindex_realized_vol60`, rather than the inherited V2 `vnindex_realized_vol20` field. Evidence: `docs/evidence/phase2/null_rates_full_20261021.md`, `docs/evidence/phase2/vci_migration_harness2_20261021.log`.

## 2026-10-21 — bound the adjusted-price cache in the feature layer

- Preserve `core.vndirect_reference_adjustment_details` unchanged. Migration 042 discovers eligible securities from the one-row-per-security `core.symbols` directory and uses a symbol-indexed `EXISTS` for VNDIRECT history, avoiding the former full scan of all source-bar rows followed by MD5 ranking of distinct symbols. It does not filter on `active`, so delisted names with historical data stay in scope; only explicit `ops.ml_symbol_scope` exclusions are omitted. The cache fills one symbol batch per SQL statement, replaces only the selected batch on retry, and must be finalized before reuse. A readiness row tracks finalization; reuse checks every batch and both valid lookup indexes.
- Keep one `REPEATABLE READ` transaction across the 15/30/60 probes and all cache batches so concurrent source writes cannot mix snapshots. Each SQL statement remains subject to the configured timeout, and the projected full-universe cache time must fit the 40-minute budget with an adjacent scaling exponent no greater than 1.3. The temporary cache is not durably resumable after session loss; the cache prelude must be rerun.
- Limit the convenience preparation path to 60 in-scope symbols. A small-fixture fallback still builds when `p_refresh=false` and no cache exists, but a partial cache fails closed and a market-wide direct call must use staged `begin`/`populate` calls through the runner.
- The updated two-pass fixture replay passed exact parity against the existing adjustment view for 2,282 fixture rows, idempotent batch retry, cache persistence across committed year chunks, feature/leakage/chunk assertions, and the harness rollback/connection checks. It proves fixture mechanics only. It does not establish real-history query-plan pushdown or acceptable full-history time. The first real 15-symbol probe hit the old manifest scan; the corrected code still needs 15/30/60 timings and a representative full-history chunk on the disposable market-history clone. Evidence: `docs/evidence/phase2/phase2_cache_migration_final_pg18_20261021.log`.

1. **Initial commit is an honest bootstrap, not an invented working full stack.** No external market-data credentials are available in the build environment. A real v5 entitlement probe and multi-day quota backfill must happen on the designated user's machine.
2. **Keep API interaction strictly isolated** inside a single Python adapter (target <400 lines); Go calls a JSON-lines protocol. The adapter never learns model logic, and credentials never travel in the JSON protocol.
3. **No quota guessing.** The scheduler and future backfill must consume absolute available budgets from real reports or stop. Remaining *percentages* are not interchangeable with remaining API *calls*.
4. **No seed recommendations.** Until risk, cost, leakage and quality gates pass, no demo/mock rows should appear as a genuine BUY or SELL signal.
5. **No unnecessary infrastructure.** PostgreSQL wrangling plus SQLite serving as specified. No Docker, Redis, Celery, hosted VN API CI jobs, auth, or cloud DB.
6. **Raw PIT timestamps are never rewritten.** Earlier data published in later financial reports must be conservatively availability-stamped and identified as assumptions, not proven historical publication timestamps.


## 2026-10-16 P0 hardening

- A worker frame is valid only if it is the sole JSONL frame, has the matching request ID, a coherent success/failure envelope, and exits zero. A 45-second default deadline and one-worker semaphore bound hangs and process explosions. Python library stdout is redirected to stderr and stderr collection is capped; the subprocess receives only whitelisted local runtime environment keys.
- The Python adapter deliberately refuses `probe(active=True)`; Go's `live.Gateway` is the only metered API route gateway. Live calls require an authenticated `free`/`community` status, matching usage tier, and exact per-minute, per-day, and per-month limits plus used counters. Remaining calls are computed as limit minus used; Guest, percentage-only, inconsistent, or unknown reports block. There is no automated full ingestion yet.
- `source=` remains on `.ohlcv()` / statement methods as specified by vnstock v5's published API. It is **not** moved to `Market()` or `.equity()` constructor absent contrary evidence from a local Phase-0 probe.
- Exchange spelling is canonicalized to `UPCOM` by PostgreSQL before-insert/update triggers, so upstream `UPCoM` inputs are accepted without polluting downstream joins. Financial period-end timestamp comparison explicitly uses `Asia/Ho_Chi_Minh`.
- Checkpoint writers take an exclusive directory lock. A crash leaving the `.lock` behind blocks automatic writes until manually inspected; this is safer than racing a prior writer. Crash orphan temp files are removed under this lock; previous checkpoint remains readable after failed fsync/rename. Unix directory entry sync is attempted; Windows uses native rename guarantees, and durability remains filesystem-dependent.
- The Go configuration parser intentionally supports only the simple committed TOML subset; it rejects unknown/missing keys instead of silently accepting unexpected constructs. Python 3.12 `tomllib` also checks syntax in CI.
- Hardening tests do not turn absent components into implemented features. Scheduler recovery, SQLite swapping/inference parity, seven unattended runs and PostgreSQL disk-exhaustion recovery are future implementation gates.

### Phase 1: do not enable live backfill before transactional storage

The implementation introduces an offline-tested `LandingStore` boundary instead of publishing an unmetered backfill command. `RunBarsBackfill` always invokes routes through `live.Gateway`, and a failed validation or storage operation never marks a job complete. This still does **not** guarantee crash-safe quota accounting: before any production integration, implement durable reservations written *prior to* the API call in PostgreSQL (`ops.api_reservations`), with outcome updates and resumable job state. Neither a JSON checkpoint nor a memory-only pacer is acceptable as the sole source of quota truth.


## 2026-10-16 — Phase 1 PostgreSQL execution boundary

- Go uses `database/sql` for a transactionally tested store API; the explicitly tagged `postgres` binary registers the pinned `pgx/v5/stdlib` driver. This allows the offline standard-library tests to run without downloading third-party modules while hosted PostgreSQL CI verifies the real connection. The full `pgx.CopyFrom` fast path is not yet implemented; correctness and failure isolation take precedence over bulk throughput at this stage.
- An `ops.quota_guard` singleton serializes reservations across processes, tracks irrevocable spent calls, enforces min spacing and a five-minute freshness deadline, and retains prior pacing across restarts. Refreshing the guard within the same Vietnam date cannot increase the previous remaining allowance, even if the vendor returned stale absolute usage. This is deliberately conservative.
- `Gateway.CallRecorded` requires durable reserve, dispatch, and finish hooks. A failed hook cannot result in successful ingestion, and unknown quota always blocks. Temporary rate limits consume a reservation and require a new preflight; entitlement failures block the job, and malformed source frames are quarantined.
- A `PostgresStore` transaction writes the unmodified vendor JSON, its SHA-256, the canonical OHLCV rows, and job completion together; unknown symbols are not automatically assigned fictitious exchange/industry metadata. Listing import must be completed before a full-universe backfill.
- Tagged backfill is opt-in only. There is no automatic scheduler, no live calls from CI, no daily trading recommendations, no charting app, and no claim that Phase 1 is finished without PostgreSQL CI and a local vnstock probe. The native Go migration runner replaces shell-only runtime instructions and supports both Windows and Linux.

## 2026-10-16 — equity universe provenance

- Only an already-metered, successful v5 `Reference().equity.list_by_exchange()` probe with a complete embedded response is eligible for offline import. `symbol` and `exchange` are required; `icb_code_lv2` is an industry code, not an English/Vietnamese name. No guessed metadata.
- The CLI requires at least 1,000 equities and all three exchanges before changing the current listed universe. A drop of more than 5%, out-of-order input or same-day conflict blocks the whole transaction instead of silently mass-delisting stocks. This threshold is a protective heuristic, not an external free-tier limit.
- Keep inactive names and daily listing snapshots for future survivorship analysis. Store exact vendor response bytes alongside JSONB (migration 004): comparing SHA-256 with reserialized JSONB is invalid because its canonical representation need not match the input bytes.

## 2026-10-16 — verified queue before quota cap

- Historical backfill candidates are always derived from the latest complete local PostgreSQL listing snapshot. No live CLI-provided ticker array; the preview-only tool can still accept a file without authorizing API calls.
- The source frame's stored bytes must verify against `payload_sha256`; membership must match current active flags exactly and cover all three exchanges. A seven-day age limit is a conservative local operating guard, not a vnstock entitlement claim.
- Resume keys are exact `(route,symbol,source,from,to)`. Exclude already completed and blocked keys before applying the current absolute quota cap; otherwise the same first N alphabetical symbols starve later symbols. A new `--to` date creates different jobs and must not be treated as an automatic incremental 5-session refresh.
- Read membership/provenance/jobs in one repeatable-read PostgreSQL transaction. Existing per-attempt durable quota reservations, cross-process pacing and 15-minute recovery leases remain mandatory. Do not auto-enable background ingestion or financial suggestions before vendor/CI validation.

## 2026-10-16 — verify membership against immutable vendor data

- A SHA-256 match on `raw.landings.payload_bytes` alone **does not** show that `core.symbols` and the latest `core.listing_snapshots` still match the source. A coordinated mutation of both relational tables could satisfy previous count/active-flag guards.
- The backfill-universe read now reparses the archived, signed listing frame and compares every symbol, exchange and level-two ICB industry code against its latest database snapshot in sorted order, inside the existing repeatable-read transaction. Any mismatch disables ingestion.
- `vnpipe backfill-status` is a read-only reporting entry point using this same verified queue. Unlike `backfill --active`, it never contacts vnstock or mutates the PostgreSQL quota guard.

## 2026-10-16 — renewable, fail-closed short-lived quota proof

- A quota snapshot valid for five minutes is not a valid reason to abort all long-running historical jobs after five minutes; but extending its lifetime without a fresh absolute vendor observation would risk the account/device quota. Before **each pending** market job, check the durable guard; when it will expire in 90 seconds, fetch a fresh *passive* status/usage report and atomically install the lower permitted remaining allowance.
- Do not reset spent calls on renewal. `InstallQuota` already carries the minimum of prior remaining budget and newly observed account capacity forward; `ops.api_reservations` is append-only. The initial local Go pacer is not enlarged by a renewal.
- A tier/RPM change mid-run is a reason to stop and restart explicitly, not silently increase throughput. Errors from the CLI, status parsing, PostgreSQL, or date change block all further market calls. New trading-day quota is handled by a new explicitly authorized run, not unattended renewal.

7. **Provider `DELISTED` rows are archived but not backfilled.** The registered-device `equity_list` probe on 2026-10-16 returned a `DELISTED` exchange category. Preserve the complete exact provider frame in raw storage, but do not invent former exchange membership or treat those rows as currently listed. Active snapshots and history jobs use HOSE/HNX/UPCOM rows only; a name previously observed as listed is retained inactive when it disappears.


## 2026-10-17 — Historical securities master is Phase 1 data provenance, not Phase 2/3 execution

- Extend Phase 1 with `core.security_master` (observed ticker codes) and append-only `core.security_observations` (exact source landing, row index, observation day, provider category and reported exchange). Backfill the registry entirely from previously imported, SHA-256-verified complete VCI listing frames; future listing imports update the same registry transactionally.
- All 235 provider-`DELISTED` rows from the 2026-10-16 frame may be recovered as **observed provider symbols**. They are not automatically active, investable, formerly listed on any asserted exchange, or eligible for a historical price request. The provider's `DELISTED` label is **not** an effective delisting date.
- Avoid coalescing ticker renames/reuse as one legal issuer without independent corporate-action evidence. `core.security_master.first_observed_at` means first available local provider observation, not date of founding, IPO, first trading, exchange admission or delisting.
- Exact-dated `core.security_observed_days` reports only what the source observed on that date, with explicit same-day conflict status. Historical gaps and unverified periods stay unknown; the current 1,519-stock backfill queue is intentionally unchanged.
- The specification §4.2 explicitly accepts the survivorship caveat and a disclosed backtest haircut while daily snapshots accumulate. Phase 2 owns PIT investable-universe joins; Phase 3 owns historical walk-forward backtesting. This change cannot silently train, score or backtest.
- No undocumented vnstock route is introduced: obtaining historical first-ever trading dates, exchange transfer intervals and delisting effective dates requires new validated evidence and an entitlement/absolute-quota check, not guesses from an adjusted OHLCV row or company-profile `listing_date`.

## 2026-10-17 — do not blindly retry invalid OHLCV frames

- Keep the 180 `PartialInvalidTradedBars` jobs and the two deferred `InvalidFrame` jobs in their recorded states until a source-frame-specific repair path can classify the invalid rows without discarding provenance. The 180 partials already contain canonical rows and 627 `INVALID_OHLC`/`INVALID_PRICE` findings; blind refetches would spend fresh vendor quota without establishing whether those rows are recoverable. `A32` and `ABC` have no canonical bars, but their deferred frames still require explicit diagnosis before retry.
- A retry is a new metered attempt and must first pass authenticated absolute-quota preflight and acquire a fresh durable reservation. No job is marked complete to clear the pending queue.

## 2026-10-17 — DQ evidence must be explicit and persisted

- The PostgreSQL DQ runner consumes dated Tier A membership, an effective exchange calendar, and exactly 30 explicitly selected same-session cross-source pairs. It does not infer Tier A membership from incomplete bars or select VCI-only prices as a second source. Missing prerequisites are recorded as `STALE`/`FAILED` in `ops.pipeline_runs` and `ops.dq_gate_results`.
- `vnpipe dq-run --date YYYY-MM-DD` requires an explicit expected date and validates it against `core.calendar` with `core.calendar_overrides`. Do not populate the new evidence tables with synthetic production data; synthetic fixtures are confined to the disposable PostgreSQL integration database.
- Active company-profile ingestion uses `Gateway.CallRecorded`; its existing profile attempt is the only account quota reservation, while migration 011 links that attempt to the durable call audit.

## 2026-10-17 — calendar is the union of observed bars and verified event evidence

- Migration 013 seeds `core.calendar` from distinct dates already present in canonical bars and records `source='observed_bars'`; a trigger adds future canonical bar dates idempotently. This follows the specification's observed-session union without inventing sessions.
- Observed bar dates do not establish why an absent date has no bars. The vnstock events feed and explicit `core.calendar_overrides` remain separate evidence, and overrides control gate-time session decisions. Do not synthesize holiday rows or claim the observed-bar calendar alone proves full session coverage.
- Local DQ verification therefore records a blocking `STALE` outcome when Tier A membership or independent cross-source evidence is absent, even when expected and prior dates are present in the observed-bar calendar.

## 2026-10-17 — reversible calendar evidence and fail-closed Phase 1 checks

- Migration 014 removes only the `observed_bars` contribution after the last canonical bar for a date is moved or deleted. Keep independently recorded calendar source labels and notes intact; manual overrides remain separate and authoritative at gate time.
- The DQ runner uses only traded bars on the previous verified session for exchange-limit comparisons. A listing-day exemption requires one unambiguous, source-verified `FIRST_EVER_PUBLIC_TRADE` date. Dated invalid source observations and incomplete OHLCV jobs for the selected Tier A universe block the gate; unverified zero-volume observations stay quarantined and are not counted as executed trades.
- Do not infer cross-source independence from distinct source-name strings alone. Migration 015 adds raw-landing and source-row lineage plus runtime replay checks, but no production sample currently has verified lineage or an independent second OHLCV source. Feature drift also remains unavailable until dated feature-distribution snapshots exist. Keep these inputs blocking or explicitly unavailable; do not fill them with synthetic production rows.

## 2026-10-17 — cross-source DQ requires exact provider attribution and row lineage

- The worker preserves only allowlisted vnstock attribution fields (`source`, route/access identity, provider name and organisation) from `DataFrame.attrs`; the Go ingestion path requires the returned source to match the explicitly requested provider before importing or archiving OHLCV.
- Migration 015 records each selected cross-source close's raw landing and zero-based frame row. Existing samples remain unlineaged and do not count as ready. The DQ runner rechecks payload SHA-256, route, symbol, frame count/order, selected session and traded OHLCV, source attribution, stored close parity, and distinct nonempty provider organisations before passing any pair into the 0.5% comparison.
- A source label or table close is not evidence by itself. Invalid or missing attribution/lineage blocks the gate and its values are excluded from comparison. Synthetic evidence stays inside the disposable PostgreSQL integration database.

## 2026-10-18 — keep live backfill gated on fresh registration evidence

- Do not reuse the 2026-10-16 probe for a live backfill: the index path requires a fresh active probe (no more than 24 hours old) and authenticated absolute quota. Until both are verified, keep market-data calls disabled; no retry receives an implicit reservation.
- Keep Tier A empty and the DQ result blocking until verified 250-session point-in-time tenure, source-attributed complete bars, and 30 independent lineaged cross-source pairs exist. Exact first-public-trade evidence remains required only for rules such as listing-day exemptions; do not infer tenure or source independence from current OHLCV coverage.
- Migration 016 makes `raw.landings` append-only. Apply it through the numbered migration runner and retain its update/delete/truncate rejection checks; do not edit or remove landing bytes to repair an ingestion result.

## 2026-10-18 — use the registered quota within observed VCI history

- The registered local vnstock 5.0.3 account was authenticated, and the active VCI probe observed a maximum daily-bar range of 2018-10-18 through 2026-10-16. Use that measured depth for the equity backfill; do not request the older 2018-10-01 start against a route that currently returns 2018-10-18 as its first row.
- The full 1,519-symbol run used `Gateway.CallRecorded`, fresh absolute server quota, and durable per-call reservations. Final states are 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`, and 0 pending. Keep partial and invalid results visible; never mark them complete to clear the queue.
- The one-call KBS index frame failed OHLC validation (`low` above `close` on 2023-05-15) and was quarantined with no committed index data. Do not repeat the metered request without a source-specific repair or a fresh probe validating an alternate provider.
- DQ remains `STALE` until an independently verified exchange calendar, source-backed traded-value inputs, and 30 distinct, independently attributed, fully lineaged cross-source pairs exist. Exact first-public-trade dates are needed for listing-day exemptions, not as a universal Tier A requirement. The KBS index source is not an equity OHLCV provider.
- The latest server usage report records 3,888 calls used today, 3,901 this month, and 20 reports pending. Each later attempt must obtain a new absolute quota snapshot and a fresh durable reservation.

## 2026-10-18 — align Tier A evidence with the specification

- This supersedes the earlier requirement that every active ticker have a unique `FIRST_EVER_PUBLIC_TRADE` record before any Tier A build. `docs/MASTER_BUILD_SPEC.md` §4.2 requires at least 250 sessions listed; it does not require an exact first-trade date for every current listing. Keep exact lifecycle dates when verified for point-in-time universe history, but do not use their absence as a universal daily gate.
- A symbol may enter Tier A only when available, point-in-time evidence proves at least 250 listed exchange sessions by the as-of date. Unknown tenure excludes that symbol; missing exact IPO/first-trade date by itself does not. The builder still needs a verified session calendar and source-backed tenure evidence. It must not infer tenure from the current listing snapshot alone.
- The liquidity policy in §4.2 uses median 20-session traded value and a 20-session average floor of 5 billion VND. All 1,807,778 canonical bars currently have null `traded_value`. Vnstock documents equity prices in thousand VND and historically adjusted prices; `close × volume × 1,000` is an adjusted-price proxy, not exact executed turnover. Do not store it as source traded value or claim it satisfies the policy until a documented proxy basis is approved.
- The KBS index probe and the new KBS equity probes attribute their frames to KB Securities (KBSV), establishing an independent equity route for the rows returned. They do not provide 30 durable same-session, independently attributed and fully lineaged cross-source pairs. The existing APF full-precision OHLC violation remains quarantined.

## 2026-10-18 — KBS equity attribution is verified; durable pairs remain required

- Fresh one-call KBS equity probes for FPT returned zero rows on 2026-10-16 and one row on 2026-10-15; a historical probe returned 1,994 rows through 2026-10-15. Each compact report contains `source=kbs`, route `market.equity.ohlcv`, source name `KB Securities (KBS)` and organisation `Công ty TNHH Chứng khoán KB Việt Nam (KBSV)`.
- This verifies the KBS equity route's returned provider attribution for the observed frames. The compact probes are not durable raw landings and provide only one same-session pair candidate; they do not count toward the 30-pair DQ gate. Future cross-source ingestion still requires `Gateway.CallRecorded`, exact raw-byte and row lineage, matching session dates, and the existing provider/close checks.

## 2026-10-18 — implement point-in-time tenure and accept provider route attribution

- Tier A tenure counts distinct positive-volume VCI bars strictly before `asOf`, joined to the exact raw landing through `ingest_id` and a valid SHA-256. Each counted traded date proves the security was listed on that session, so this is a conservative lower bound; the complete, integrity-checked as-of listing snapshot still defines candidate membership. A local query found 1,321 of 1,505 bar-backed current symbols with at least 250 such dates. The 2026-10-16 build passed tenure and then blocked because the source `traded_value` field is NULL for A32 on 2026-09-18. Do not replace it with an unapproved adjusted-price proxy.
- Both VCI and KBS identify the vendor OHLCV route as `market.equity.ohlcv`; the DQ replay accepts that provider route and the internal `equity_ohlcv` alias while continuing to require source, exact raw landing/row lineage, checksum, session, and organisation attribution. The PostgreSQL fixture now uses the observed provider route.
- The active `market_calendar` probe is not a verified exchange-session calendar: it returned 355 built-in Vnstock Project event rows on `reference.events.market`, not a complete daily session schedule, and the report did not retain the raw event frame. Keep calendar-dependent DQ blocked until independent session evidence exists.
- This route correction makes verified provider payloads replayable; it does not create a durable KBS landing or satisfy the 30-pair gate. The 2026-10-15 FPT compact KBS row matches the VCI close at 58.0, but remains probe-only evidence. A targeted KBS APF/2018-10-19 probe returned `AdapterError` and produced no repair row; it was not retried.
- The local worker needs `VNSTOCK_HOME` set to the authenticated state directory when Go changes its working directory. Allow this path through the worker's narrow environment allowlist; continue excluding unrelated secrets. Do not copy the API key into the repository.
- Go unit tests, `go vet`, Python JSONL tests, and the serial PostgreSQL-tagged integration suite passed locally. PostgreSQL migrations and schema assertions passed twice on a disposable PostgreSQL 18 database; the local shell wrapper could not find `grep`, so rollback and connection-failure assertions were verified directly. The Phase 1 gate remains blocked by missing source-backed inputs.

## 2026-10-18 — Community-tier trade history does not supply Phase 1 turnover

- Use the already registered local vnstock Community profile; never paste or save its API key in project files. Vnstock's internal status reports `tier=free` for this Community tier. The fresh passive report confirmed authenticated status and current absolute server quota, so authentication is resolved.
- The metered `equity_trade_history` capability probe returned `EntitlementError`. Do not retry that route unless the account's tier changes. A quota refresh cannot override a route entitlement.
- Keep `traded_value` NULL until an entitled source provides verified executed turnover or the user explicitly approves a separately labeled proxy and the spec is revised. Never populate it as `close × volume × 1,000` and describe that as source turnover.
- The HMD retry returned `AdapterError` after a durable reservation and committed no landing. Keep it visible as pending; every later retry needs a fresh reservation and a source-specific reason to expect recovery.

## 2026-10-18 — KBS comparisons remain raw-only and fail closed

- KBS equity OHLCV is an independent comparison source, not canonical VCI history. The audited `ingest-kbs-cross-source` path stores checksum-verified KBS responses in append-only `raw.landings`; it never writes `core.bars_daily` or selects DQ pairs.
- A one-call FPT/KBS request for 2026-10-15 returned `AdapterError` after a durable reservation. The job remains pending and no landing was committed. A separate metered capability recheck returned the same error. Do not repeat this route without new source evidence; any later ingestion attempt must obtain a fresh quota reading and new reservation.
- After a fresh absolute quota refresh, one distinct A32/KBS request for the same date also returned `AdapterError` after a durable reservation. Both exact-range jobs remain pending at attempt 1 and KBS raw equity landings remain zero. Treat this as a route/provider failure across symbols; do not retry without new provider evidence and a new quota reservation.
- Superseded by the explicit user approval recorded below: the close-volume proxy can support research ranking/features, with a distinct schema field and explicit limitations.

## 2026-10-18 — scheduled closure overrides remain partial calendar evidence

- Import only the explicitly closed dates in [`docs/probe/phase1-calendar-overrides-2019-2026.sql`](probe/phase1-calendar-overrides-2019-2026.sql), with HNX source URLs retained in each reason. The 103 dates come from official HNX annual schedules (2019–2026) and specific make-up-day notices. Do not treat holiday lists as a full session calendar; closures from ad hoc outages and all open sessions still require evidence.
- `core.calendar_overrides` takes precedence over observed-bar dates in DQ. A DQ run on 2026-01-02 must fail closed because HNX explicitly records that date as a no-trading holiday. Do not populate synthetic open sessions to make other dates pass.
 This closure-only state was superseded on 2026-10-18 by the official HNX schedule-derived calendar documented below. Use the newer combined weekday-and-closure import for the 2018-10-01–2026-10-16 history.

## 2026-10-18 — vendor exception messages are not worker output

- The worker returns a fixed generic `error.message`, a sanitized exception class, and only allowlisted structured diagnostics. Never return, log, or persist arbitrary vendor exception text, which may contain URLs, credentials, private arguments, or response data.
- The exception redaction test asserts that a private URL/token in a vendor exception is absent from the complete JSONL error frame, not only from its structured diagnostics.

## 2026-10-18 — user approves a separately labeled liquidity proxy

- The user explicitly approved using VCI close × reported volume × 1,000 as an adjusted-close-based estimate for ML/research data, despite the Community account's lack of entitlement to the exact executed-turnover route. This resolves the earlier scope question and supersedes the prior hold on proxy-based Tier A ranking.
- Migration 017 creates `core.bars_daily_with_proxy`, exposing `traded_value_proxy_vnd` for valid positive-volume bars without rewriting canonical history. The exact source field `traded_value` remains unchanged and NULL unless the vendor reports it. The proxy is never to be described as executed turnover or as reliable order capacity.
- Tier A's 20-session median rank and average liquidity floor use the explicitly named proxy. Model features may use it with the basis retained. Recommendation/order sizing remains disabled until later-phase execution-quality checks validate an appropriate capacity source.
- A historical job marked `PARTIAL` can still establish a specific valid bar when the exact landing checksum and ingest ID match and that bar's session has no date-local quality issue. Keep incomplete history visibly `PARTIAL`; this rule only prevents an unrelated defective date from invalidating an independently validated session in the 20-session ranking window.
- Exclude a candidate from Tier A when any of its 20 ranking sessions lacks a checksum-linked, positive-volume valid bar or has a date-local quality issue. A `PARTIAL` historical job alone does not invalidate its separately validated bars; unresolved `BLOCKED` jobs covering as-of still stop selection.
- This approval does not waive history completeness, point-in-time, calendar, source attribution, raw lineage, or DQ requirements. Record only actual VCI response rows; preserve partial and blocked results.
- Tier terminology is user-facing **Community**. Vnstock's `status()['tier'] == "free"` is only the library's internal identifier for that tier; project reports and user-facing messages must call the account Community. Vnstock's account-tier documentation confirms this mapping.
- The 2026-10-16 Tier A build now uses the approved research proxy and selected 158 symbols after excluding candidates missing any of the 20 valid, checksum-linked ranking sessions. This resolves the earlier liquidity-basis hold, not the independent 30-pair DQ requirement; the latest DQ run remains blocked at 0/30 durable KBS comparisons.

## 2026-10-18 — KBS data must match the Tier A session

- The Vnstock documentation lists KBS equity OHLCV for Community accounts. KBS returned no row for 2026-10-16 even when the requested interval ended on 2026-10-17; the successful AAA frames ended on 2026-10-15. Retain the raw KBS landings with source attribution and checksums, but do not use a prior-session close as an Oct 16 pair.
- Keep cross-source selection date-matched to Tier A membership and the VCI bar. `--sample-date` may differ from the request interval end to test provider date coverage; it does not relax the same-session requirement.
- Current offline selection found 0 of 30 valid candidates and inserted no samples. DQ run `ca9b7bc4-b781-4568-a87f-a8f6856d67e4` remains failed solely on the 0/30 cross-source requirement for 2026-10-16. Any later request must first obtain fresh Community quota and a durable reservation, and must have new source evidence that it can return the required session.

## 2026-10-18 — build historical sessions from official HNX rules and holidays

- The HNX stock trading guide specifies a Monday-Friday schedule except public holidays; HNX's annual notices specify the closure dates and later schedule adjustments. The derived historical calendar combines both kinds of primary evidence and records source URLs in the database.
- The repeatable local import is docs/probe/phase1-hnx-calendar-2018-2026.sql. It covers 2018-10-01 through 2026-10-16, adds only dates supported by the official weekday schedule, and gives every published closure precedence through core.calendar_overrides.
- Reconciliation found 2,008 expected sessions, all 2,008 represented by observed canonical bar dates, zero bars on official closures, and no conflicting session evidence. This resolves the historical calendar gap for that range; future dates still need current HNX event/holiday updates.
- The refreshed Oct 16 DQ result is blocked only by the required 30 same-session, lineaged, independently sourced close pairs. The calendar decision does not relax cross-source lineage or the incomplete VCI history requirement.

## 2026-10-18 — KBS full histories stay separately sourced raw evidence

- The user authorized broad data collection for the ML project. The registered Community profile was used through the quota-checked Go gateway, with a fresh quota check and durable reservation for each symbol.
- KBS returned 578,108 rows across 495 checksum-verified raw landings. Of 1,593 VCI invalid symbol/date observations, 174 have a valid traded KBS bar and a close within 0.5% of the VCI source close. Retain these as source-linked reconciliation candidates; do not rewrite VCI history or relabel KBS observations as VCI.
- KBS coverage reaches 2026-10-15 for 247 symbols and has no Oct 16 rows. Cross-source evidence remains strictly same-session: the Oct 16 DQ gate is still 0/30, and a prior-session KBS observation cannot satisfy it.

## 2026-10-18 — Vietnamese OHLC validation respects auction session fields

- HOSE determines opening and closing prices in separate ATO/ATC call auctions. Its quote-field guide defines that board's open/close from those auctions and high/low from continuous-matching executions; a valid HOSE open may therefore be below the continuous-session low (or above its high). This session explanation is venue-specific: HNX-listed equities use continuous matching followed by a closing auction, while UPCoM equities use continuous matching through the session. SSI's official stream schema exposes Open/Close separately from highest/lowest matched prices for the report date, but does not state whether those extrema include auction prints. Preserve provider semantics and attribution; do not require generic OHLC fields to form a nested range without venue/session definitions. The prior `high >= max(open,close)` and `low <= min(open,close)` checks created false `INVALID_OHLC` issues and partial jobs.
- Require positive finite O/H/L/C, `high >= low`, and nonnegative finite volume. Preserve source values and raw bytes. Migration 019 replaces the matching PostgreSQL check so the database accepts auction prices outside continuous-session extrema. Migration 018 records each offline projection rebuild. The current generic bar schema does not carry enough session-phase metadata to impose tighter venue-specific constraints.
- Sources: HOSE order types (ATO entered during opening call auction to determine the opening price): https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf; HNX FAQ on HNX-listed and UPCoM session methods: https://www.hnx.vn/vi-vn/hoi-dap.html; SSI market-data streaming field definitions (Open/Close and date High/Low matched-price fields): https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage. HOSE quote-field guide with explicit continuous-session High/Low definitions: https://estock.duytan.edu.vn/kien-thuc-dau-tu/kien-thuc-chung-khoan/bai-3-huong-dan-doc-bang-gia-truc-tuyen-tai-hose-70.html. HOSE 2025 regulation: https://staticfile.hsx.vn/Uploads/News/437a3bc734a845fc853283b0c627a593/20250429_20250429%20-%20HOSE%20-%20Quy%20dinh%20giao%20dich%20dang%20website%20HOSE.pdf.
- Reclassify already landed VCI frames offline under the corrected rule, retaining raw landings and a durable transition audit. Any remaining true inversions or invalid prices keep their jobs partial and remain visible.

## 2026-10-18 — user-authorized alternate sources for historical OHLCV

- The user explicitly authorized using another source when vnstock cannot supply needed historical data, and clarified that vnstock remains the preferred daily refresh path. This scope decision overrides the Master Build Spec's external-source exclusion for the requested historical research dataset only.
- DNSE and VNDIRECT observations stay in `core.bars_daily_sources`, linked to immutable raw response landings and durable `ops.external_market_calls`; they are never relabeled as VCI, merged into canonical VCI bars, or treated as the same adjustment basis. Historical ML work must preserve source/basis and use a source-homogeneous series unless a documented reconciliation or corporate-action adjustment supports a join.
- VNDIRECT's tested response exposes separate normal-market (`nmVolume`) and put-through (`ptVolume`) volumes. The stored volume uses `nmVolume`; exact raw JSON retains both. Zero-normal-volume rows remain explicitly `is_traded=false`. Returned ticker mismatches are retained in raw evidence, issue-recorded, and excluded from the requested symbol's projection.
- DNSE responses can contain multiple intraday timestamps for one Vietnam date. Keep the raw frame and issue records; omit only ambiguous duplicate-date daily projections rather than fabricate an aggregate.
- VNDIRECT's Finfo endpoint was tested directly without authentication, but first-party API terms and historical data licensing have not been verified. Keep its use local and source-attributed, and do not present it as an official exchange feed.

## 2026-10-18 — audited VNDIRECT can satisfy same-session VCI comparison

- When KBS has no bar for a Tier A session, the DQ sample selector may pair VCI with VNDIRECT. It only counts VNDIRECT if the exact raw bytes and SHA-256 replay, the successful `ops.external_market_calls` record matches source/symbol/date range/HTTP status/row count and the configured HTTPS Finfo endpoint/filter, and the selected unique exact-ticker row has positive normal-market volume and valid OHLC.
- The gate still compares exactly 30 same-session pairs and applies the existing 0.5% close tolerance. This is independent-source quality evidence; it neither promotes VNDIRECT into canonical VCI bars nor certifies the historical endpoint's licensing terms.
- The selector's canonical OHLC eligibility now matches the project validator: positive finite prices, `high >= low`, and nonnegative finite volume. Open/close containment is not required because HOSE auction prices can sit outside continuous-session extrema.
- Local evidence for 2026-10-16: 30 VCI/VNDIRECT pairs selected and replayed; DQ run `3cd86137-dec5-4dc3-9e35-ccee9c886f1b` passed. VNStock/VCI remains the intended daily refresh source; the daily scheduler is future Phase 6 work.

## 2026-10-18 — classify missing symbol sessions with lifecycle evidence

- A date on the exchange calendar does not imply that every listed symbol traded that day. The 3,225 VNDIRECT span gaps are candidate absences; never fill them with repeated close, zero volume, or another fabricated bar.
- HNX's 2021 transfer notice covers 13 symbols in the Aug. 30–Sep. 1 cluster and sets Aug. 27 as their last HNX trading day. The remaining PTM gap is not part of that cohort. Keep those symbols' bars absent for the transfer interval unless a source returns an actual bar and a valid listing/trading event supports it.
- HNX records CTR's UPCoM trading ending Feb. 14, 2022, followed by HOSE trading beginning Feb. 23. The five VCI rows for Feb. 16–22 conflict with that lifecycle and have no VNDIRECT, DNSE or CafeF counterpart. Preserve their raw landing, but exclude them from any ML series pending a source-backed quarantine/reprocessing audit.
- The previously cited HNX retrospective implied a 2016 PTM cancellation, but the specific HNX notice 1315/TB-SGDHN identifies the same PTM automobile issuer and gives 2018-11-27 as its final trading day, with deregistration on 2018-11-28. HNX records that issuer's return on 2025-08-22, and the issuer says it left the market at the end of 2018. Therefore the 2018 PTM rows are lifecycle-eligible; preserve their source-specific lineage and keep their adjustment-basis series separate.
- The invalid-open VCI issue set has 25 distinct symbol/session keys. Same-session VNDIRECT data exist for all 25 and DNSE data for 14; those observations remain independently attributed. The auction-aware rule remains `high >= low` and does not require open/close to be inside that interval.
- VNDIRECT is explicitly `unadjusted`; VCI and DNSE remain `unknown` in the database. Compare independent same-session values for DQ, but train each source as a homogeneous series until a point-in-time corporate-action adjustment method is validated.

## 2026-10-18 — historical ML source and vnstock refresh

- Use the source-attributed VNDIRECT series as the alternate historical research dataset where vnstock/VCI bars are unavailable or invalid. Keep the VNDIRECT `unadjusted` basis and original landing/row lineage. Use vnstock/VCI for the intended daily refresh as a separately stored series; do not overwrite VNDIRECT rows or combine the series until adjustment behavior is verified.
- UTT's full-range historical request started before the security was first eligible to trade. [HNX's official notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2017102025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20Moi%20truong%20Do%20thi%20Thanh%20Tri%20UTT-60021665-1.html) records its first trading date as 2025-10-17 (raw landing 8398, lifecycle evidence 1). A fresh, metered VCI probe limited to 2025-10-17–2026-10-16 returned a valid empty frame. This is an observed zero-row response, not proof that every post-listing session had no trades; retain the result and do not synthesize bars.
- The compact UTT probe report is [`2026-10-18-UTT-110813.105527700Z.json`](probe/phase1-utt/2026-10-18-UTT-110813.105527700Z.json); the exact HNX notice bytes are [`UTT-first-trading-2025-10-17.html`](probe/phase1-lifecycle/UTT-first-trading-2025-10-17.html). The first-trade evidence is append-only in PostgreSQL and SHA-verified against the archived bytes.
- A public CafeF history export returned 232 distinct dates through 2026-10-16, all with zero matched and negotiated volume and flat 9.2 price fields, but omitted 16 of 248 HNX calendar sessions. The official HNX detail report returned zero UTT records for 2026-10-16. These sources do not establish an exact last executed-trade date; singleton-date CafeF probes were inconsistent and discarded. Keep UTT uncovered in ML and do not turn reference fields or missing sessions into trade bars. Archived responses, hashes and the missing-date list are in [`phase1-utt/README.md`](probe/phase1-utt/README.md).
- A subsequent VNDIRECT Finfo query used `nmVolume` and `ptVolume` and returned 248 session rows for UTT from 2025-10-17 through 2026-10-16, with both volumes and their values equal to zero on every row. A same-endpoint KAI positive control returned `nmVolume=62,800` and `nmValue=711,900,000` on 2026-10-16. Together with CafeF's 232 zero-volume rows, this supports classifying UTT as having no recorded executions during the audited period; there is no last-trade date to assign within that period. Keep it out of ML OHLCV and do not import repeated 9.2 reference prices. Preserve both raw VNDIRECT responses and SHA-256 hashes in `docs/probe/phase1-utt/`.

## 2026-10-18 — PTM lifecycle correction from specific exchange notice

- Use HNX notice 1315/TB-SGDHN dated 2018-10-30 as the controlling PTM delisting evidence: it names CTCP Sản xuất, Thương mại và Dịch vụ Ôtô PTM (PTM), specifies the last HNX trading day as 2018-11-27, and makes deregistration effective 2018-11-28. HNX's 2025 notice records the same issuer's first return session on 2025-08-22. The issuer's own account of a seven-year absence and delisting at end-2018 independently corroborates identity continuity.
- Preserve the exact archived exchange documents and SHA-verified raw landings in `docs/probe/phase1-lifecycle/` and local PostgreSQL. The recorded intervals are `TRADE_ELIGIBLE` through 2018-11-27, `DELISTED` from 2018-11-28 through 2025-08-21, and `TRADE_ELIGIBLE` from 2025-08-22.
- The 11 positive-volume VCI rows and 12 positive-volume VNDIRECT rows observed for PTM in 2018 are within that verified trading interval. Do not quarantine these rows for lifecycle conflict. Keep their source attributions and adjustment bases separate, and do not join them until price-basis and point-in-time behavior are established.
- The older general HNX history entry that appeared to place cancellation in 2016 is superseded for this specific 2018 security episode by the dated final-trading notice and issuer corroboration. At the time of that PTM decision, CTR's 2022-02-16–2022-02-22 VCI bars still needed a durable lifecycle exclusion; that is resolved below.

## 2026-10-18 — CTR transfer gap uses exchange notices and append-only ML exclusions

- Resolve CTR's final UPCoM date from HNX notice 89/TB-SGDHN: last trading day 2022-02-14, deregistration effective 2022-02-15. The SSC records 2022-02-23 as CTR's first HOSE trading day. Do not infer a last day from provider gaps when an exchange notice is available.
- Preserve the HNX notice bytes in `docs/probe/phase1-lifecycle/CTR-delisting-notice-2022-01-17.pdf` (SHA-256 `F5A2B2501997B7393DB6715FCEB1AAEF4D1A614F5A0E110A15C730A7059DAF37`); the PDF is HNX's notice hosted on Vietstock's static CDN. Preserve the first-HOSE-day source link to the [SSC notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/m/thngtinthtrng/thngkthtrng/thongtinhose/tintchose?docType=TinBai&mucHienThi=188&selectedPage=20).
- Do not delete or rewrite the five repeated VCI bars. The source rows are 829–833 (zero-based) in VCI landing 2550, and lifecycle evidence is landing 8402 / evidence 6. Migration 022 records append-only `EXCLUDE` events keyed by source, security and trade date, validates them against raw landing rows and lifecycle evidence, and filters both canonical and alternate bars through ML-eligible views.
- Historical bars stay source-attributed and immutable. `core.bars_daily` retains five CTR rows for 2022-02-16–2022-02-22; `core.bars_daily_ml_eligible` exposes none. If a later official correction reverses an eligibility decision, append an `ALLOW` event backed by dated `TRADE_ELIGIBLE` evidence instead of mutating the exclusion history.
- This resolves CTR and classifies UTT's audited listing-to-2026-10-16 interval as having no recorded executed volume, so UTT contributes no trade bars and is not a missing-history blocker. The exact date-level audit of VCI PARTIAL jobs is now recorded in `docs/probe/phase1-partial-audit/`; Phase 1 remains open for unresolved zero-volume eligibility, price-adjustment basis, and PostgreSQL 16 / race checks.

## 2026-10-18 — reconcile VCI partial jobs against alternate-source bars

- Audit the 32 VCI `PARTIAL` `equity_ohlcv` jobs as 16 unique tickers with two overlapping requests each. Deduplicate issue and coverage counts by ticker/date; retain the exact job, landing, source-row and raw-response-hash links in `docs/probe/phase1-partial-audit/`.
- The 16 symbols have 13,955 positive canonical VCI bars and 14,492 distinct quality-issue ticker/dates: 14,466 zero-volume, 25 invalid-price and one invalid-OHLC. VNDIRECT has positive bars on all 26 invalid-price/OHLC dates, and DNSE on 15. Only 24 zero-volume issue dates have a positive same-session bar in either alternate source; do not treat the remaining 14,442 as confirmed non-trades or synthesize bars.
- For those symbols, VNDIRECT has 14,338 positive ticker/dates, including 388 without a positive canonical VCI bar. Of these 388, 50 correspond to an existing VCI quality issue and 338 have no VCI canonical bar or quality issue. DNSE has 13,485 positive dates, including 100 without VCI; all 100 also occur in the VNDIRECT series. Preserve these as source-attributed supplemental history. Do not merge or relabel them as VCI.
- HNX profile pages were searched for all 16 securities and the date/URL references are in `docs/probe/phase1-partial-audit/hnx-profile-dates.csv`. A current-exchange profile date is not necessarily a first-ever public trading date: XMC's current UPCoM page reports 2019-06-28 while the issuer's 2012 annual report records its HNX debut in 2007. Do not insert these lookups into the lifecycle evidence table without archived, checksum-verified official source bytes and complete venue-transfer/suspension history. The zero-volume view remains `LISTING_STATUS_UNVERIFIED` until those requirements are met.
- VNDIRECT's imported history basis is verified as `unadjusted`; DNSE and VCI remain `unknown` for adjustment basis. Keep each series source-homogeneous for ML until VCI/DNSE basis and the point-in-time corporate-action adjustment method are verified.

## 2026-10-18 — verify VNDIRECT basis and SNC odd-lot activity

- This updates the adjustment and SNC findings in the preceding partial-job audit. The VNDIRECT importer reads `open/high/low/close`, not the response's separate adjusted OHLC fields, and writes the stored basis as `unadjusted`. In 31,931 rows across the 16 archived VNDIRECT responses, raw OHLC differed from adjusted OHLC on 15,773 rows and raw close differed from adjusted close on 15,777 rows. The public VNDIRECT page likewise distinguishes ordinary close from adjusted close and describes split/dividend adjustments. VNDIRECT's imported history basis is therefore verified; VCI and DNSE remain unknown.
- HNX's official UPCoM daily report for SNC on 2026-10-15 records 71 shares in continuous matching, worth VND 1,547,800. This matches VNDIRECT landing 8002, source row 2006 (`nmVolume=71`, close 21.8; raw-payload SHA-256 `2b94dba13615420cb69216bcf2b96746ecf2921774507eca112446ca4168c3e1`). It is one of the positive VNDIRECT rows without positive canonical VCI history or a VCI quality issue. StockBiz and Cophieu68 report zero for the same date; the exchange report resolves the discrepancy in favor of a real execution. The HNX response, search parameters and SHA-256 are archived in `docs/probe/phase1-partial-audit/hnx-snc-2026-10-15.html`. The current VNX UPCoM rule (Decision 23/QD-HDTV, effective 2026-03-18) defines odd lots as 1–99 shares and permits continuous matching or put-through; it also excludes odd-lot trades from reference-price and index calculations.
- Keep VNDIRECT, VCI and DNSE in separate source series. The VNDIRECT stored-price basis is known, but a point-in-time corporate-action adjustment workflow is not yet validated, and VCI/DNSE basis remains unknown. No rows were changed, spliced, or relabelled.
- Sources: [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM), [current VNX UPCoM trading rule](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [StockBiz SNC history](https://web.stockbiz.vn/Stocks/SNC/LookupQuote.aspx?Date=16/10/2026), [Cophieu68 SNC history](https://cophieu68.vn/download/historydaily.php?d=2026-10-15), and [VNDIRECT adjustment-basis explanation](https://dstock.vndirect.com.vn/lich-su-gia/VND).

## 2026-10-18 — use public sources without assuming volume or adjustment semantics

- Keep EasyStock as a separately archived candidate historical source: its public feed returned 35,684 rows for the 16 audited UPCoM symbols and matched 7,447 VCI zero-volume issue dates. It reports zero volume on every matched date, but also reports zero for SNC on 2026-10-15, when HNX confirms a 71-share matched odd-lot execution. Do not use EasyStock zero-volume rows to classify no-trade dates. Its VCI price sample is corporate-action adjusted, so do not use it for point-in-time training until adjustment timing is known.
- Accept the HNX official daily UPCoM report as evidence of matched/no-matched volume for dates it returns. The public page limits its date picker to the latest month; empty historical responses cannot be treated as evidence of no trade. Archive the three recent SHC reports, but do not change the database's zero-volume lifecycle statuses until the source evidence is ingested and the quality view is reprocessed.
- The VCI 2024 10:3 bonus-share event shows VNDIRECT ordinary OHLC at raw prices and VCI/DNSE/CafeF adjusted closes around 24.24–24.25 before and 24.03–24.04 after the event. Keep provider price series and volume semantics separate; one event does not authorize changing global `adj_basis` values or joining series.
- HNX's official guide lists UPCoM EOD and historical trading data as information products; public access/price terms were not verified. SSI documents a daily OHLC API but requires ConsumerID/ConsumerSecret to obtain an access token and notes access depends on the account. These are follow-up routes if public sources leave gaps, not proof that this checkout has those entitlements. Sources: [HNX guide](https://owa.hnx.vn/ftp/PORTALNEW/PUBLICFACTBOOK_FA/20161202/Guide%20to%20HNX.pdf), [HNX UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html), [SSI FastConnect API specs](https://guide.ssi.com.vn/ssi-products/fastconnect-data/api-specs), and [EasyStock download page](https://easystock.vn/easystock-download-en.html).

## 2026-10-18 — Cophieu68 is a limited cross-check, not a bulk ML source

- Its public SHC page agrees with HNX's zero matched-volume reports for 2026-09-16, 2026-09-18 and 2026-09-21. Its SNC page reports zero on 2026-10-15, although HNX records 71 matched shares. This confirms Cophieu68 zeroes cannot clear a date as no-trade.
- Cophieu68's page advertises an all-adjusted-history AmiBroker download, but its current script endpoints returned 404. Its terms prohibit copying, republication, distribution, or derivatives without explicit consent, with only a limited exception for a small number of internal-use pages. Do not bulk scrape, ingest, or train on this source without written permission. The limited source review is documented in `docs/probe/phase1-cophieu68/README.md`; no Cophieu68 dataset is retained and PostgreSQL was not changed.
- Sources: [SHC history](https://cophieu68.vn/quote/history.php?id=SHC), [SNC history](https://cophieu68.vn/quote/history.php?id=SNC), [download page](https://cophieu68.vn/download/ami.php), and [terms](https://cophieu68.vn/terms.php).

## 2026-10-18 — use venue-correct HNX reports for targeted historical checks

- The HNX report's visible date picker is limited, but the official POST endpoint accepted exact historical dates back to the 2018–2020 audit window. Use it for targeted row-level validation; do not infer that an empty result from the wrong venue or a date-picker-limited request proves no execution.
- All 26 VCI invalid-price/OHLC pairs in the 16-ticker partial-history audit have positive HNX total matched volume. The same 26 dates have positive, `is_traded` VNDIRECT rows in `core.bars_daily_sources_ml_eligible`. These are valid alternate-source executions; retain them as VNDIRECT and leave the VCI quality findings intact.
- The latest positive VNDIRECT date through 2026-10-16 for each of the 16 audited tickers has an exact matching HNX report volume. Use the UPCoM report for the UPCoM observations and the listed-market report for SPC. VSDC records SPC's market transfer effective 2022-01-21, and HNX lists its first HNX session as 2022-01-27; a 2026 no-row response from the UPCoM route must not be read as a no-trade result for SPC.
- UTT's 16 sessions omitted by CafeF, including its first listed session, all return an explicit HNX report row with zero total matched volume. VNDIRECT reports zero volume across all 248 HNX sessions and CafeF reports zero on its 232 returned dates. No positive last-trade date is observed through 2026-10-16, but HNX has not been queried for all 248 sessions; keep the phrasing source-bounded and UTT out of ML OHLCV.
- These are targeted checks, not permission for bulk extraction. HNX lists historical data and data packages in the [UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html) and the [2026 information-service catalog and price schedule](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf). Preserve the VNDIRECT/VCI/DNSE source separation, and do not change database lifecycle statuses unless evidence is imported through the approved append-only route and the quality view is reprocessed.

## 2026-10-18 — classify VCI and DNSE OHLC price basis

- Official Vnstock v5 documentation says historical stock prices are adjusted for rights. A source-row-linked FPT 2024 cash-dividend check independently matches VCI and DNSE returns to VNDIRECT's separate `ad*` price fields and the dividend-adjusted reference, while VNDIRECT ordinary OHLC remains raw. The earlier VCI bonus-share event supplies a second action type. Full event inputs and exact raw hashes are in `docs/probe/phase1-adjustment/`.
- Set `adj_basis='adjusted'` for existing VCI canonical bars and DNSE alternate bars; new rows from those two providers receive the same classification. This field describes OHLC price columns only. Keep VNDIRECT at `unadjusted`; leave KBS `unknown` until its own archived event comparison is recorded.
- Retrospective adjustment timing is unresolved. Do not treat VCI/DNSE historical rows as point-in-time safe or join price histories across providers until adjustment vintages and corporate-action availability are reconstructed. This metadata change does not alter OHLCV values, volumes, trade status, or eligibility events.

## 2026-10-18 — use the registered VCI index route and preserve source histories

- Official vnstock v5 documentation lists `Market().index(s).ohlcv()` in the Community tier and permits the domestic sources `vci` and `kbs`. The registered machine's active VCI route probe confirmed the exact response schema. A wide history request returned only 1,000 recent rows, so use bounded windows for index backfill rather than assuming a wide response is complete. The official [market API](https://www.vnstocks.com/docs/vnstock/thi-truong-market) documents explicit start/end dates; the [access and limits page](https://www.vnstocks.com/docs/vnstock/tham-khao/cap-quyen-va-gioi-han) documents the source and row caps.
- Eight audited, non-overlapping VCI requests populated 1,995 VNINDEX bars from 2018-10-18 through 2026-10-16. They match all 1,995 local exchange-calendar sessions in that interval, with zero missing or unexpected dates. Each response has an append-only raw landing and each request has a successful durable reservation. The route summaries are in `docs/probe/phase1-vnstock-core-route-probe/`.
- Keep `core.index_bars` keyed by `(index_symbol, trade_date, source)` under migration 024. This preserves independent KBS/VCI histories if both are stored later and prevents one provider's refresh from replacing the other's same-date row.
- Official vnstock documentation also lists the VCI/KBS income statement, balance sheet and cash flow routes in Community, with up to eight report periods per call. The registered route probes confirmed these endpoints, but this repository still has no durable, point-in-time statement ingestion path. A current report response is not an archived historical vintage; do not use it as if its values were available at past signal dates. See the [fundamental API](https://www.vnstocks.com/docs/vnstock/co-ban-fundamental) and [access limits](https://www.vnstocks.com/docs/vnstock/tham-khao/cap-quyen-va-gioi-han).
- SSI's official FastConnect documentation says daily OHLCV can start at a security's first trading date, but access requires an SSI trading account and approved FastConnect registration. HNX likewise lists HNX/UPCoM EOD and historical data as information products. These are researched alternate paths if a documented VCI gap remains; neither is treated as locally provisioned access. Sources: [SSI access and daily history terms](https://developers.ssi.com.vn/docs/getting-started/terms-and-environments), [HNX UPCoM data service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html), and [HNX 2026 catalog](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf).

## 2026-10-18 — persist exact HNX execution evidence for SHC

- Archive the three historical HNX report HTML responses, verify SHA-256 against the exact bytes, and import them idempotently through the source-row evidence table introduced in migration 023. The report rows show zero matched volume for SHC on 2026-09-16, 2026-09-18 and 2026-09-21. The lifecycle view now classifies only those exact symbol/session pairs as `VERIFIED_ELIGIBLE_NO_MATCH`; it does not synthesize OHLCV bars.
- The 16-symbol partial-history audit has 24 unique VCI zero-volume issue dates with positive alternate-source bars (`CONFLICTING_EVIDENCE`), three exchange-confirmed no-match dates, and 14,439 unresolved `LISTING_STATUS_UNVERIFIED` dates. Do not turn the remaining zero-volume prices into executable observations or infer a last trading date from an unrelated provider's empty response.

## 2026-10-19 — latest-session HNX checks and alternative-source research

- Queried the official HNX matched-volume report for the 16 partial-history tickers on 2026-10-12 through 2026-10-16. The selected-symbol report returned 75 UPCoM rows; SPC was queried on the HNX-listed route for its five rows. All 80 requested symbol/session pairs returned. HNX reports positive volume for 13 tickers within the window; CDG, VFC, and VNX have zero total matched volume on all five queried dates.
- The latest positive date within this five-session window is saved in [`phase1-hnx-latest-week/README.md`](probe/phase1-hnx-latest-week/README.md). This bounded check does not certify last-ever dates for CDG, VFC, or VNX and does not resolve the older 14,439 VCI zero-volume issue dates. No database rows or lifecycle statuses changed.
- SSI's official documentation offers daily OHLC history from a security's first trading date and historical-file downloads, but API access requires an SSI brokerage account and approved FastConnect registration ([market-data FAQ](https://developers.ssi.com.vn/docs/faq/market-data), [usage terms](https://developers.ssi.com.vn/docs/getting-started/terms-and-environments)). TCBS documents a long-term daily OHLCV endpoint, but an unauthenticated request returned HTTP 401; its documented endpoint uses a bearer token ([TCBS API](https://developers.tcbs.com.vn/docs/v1.0.0/stock/bars-long-term/)). DNSE documents historical OHLC market data ([DNSE docs](https://developers.dnse.com.vn/docs/dnse/market-data/)); the local database already contains its separately attributed history. No external credentials were submitted and no data were imported from these researched routes.
- HNX separately lists historical UPCoM data as an information service. This work used the public daily report for a small recent validation only, not a bulk download. Sources: [HNX UPCoM report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM), [HNX listed-market report](https://www.hnx.vn/vi-vn/co-phieu-etfs/du-lieu-thi-truong-ny-quy-mo.html), [HNX information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html).

## 2026-10-19 — interpret current HNX special-trading status

- HNX currently labels CDG, VFC, and VNX “Giao dịch đặc biệt.” Under current VNX UPCoM Decision 23/QĐ-HĐTV, status code `SNE` means no round-lot trades for more than 25 consecutive trading sessions. Treat it as evidence of a recent no-round-lot state, not proof that no odd-lot execution occurred.
- HNX issuer price-history pages cover 64 dated rows from 2026-07-16 through 2026-10-16. VNX's sole price-bearing row in this window is 2026-07-28 (100 shares, confirmed by the exact-date HNX report); CDG and VFC have no price-bearing rows in the window. Eight exact-date HNX reports show zero VFC matched volume for 2026-07-06 through 2026-07-15, after the 2026-07-03 one-share execution. This makes July 3 the latest VFC execution located through Oct 16, while preserving the limitation that the profile table does not log every possible odd-lot execution.
- Investing.com's history page lists CDG's 2025-05-13 100-share session as its latest positive row in its data window ending 2026-05-17; HNX confirms that positive date. We have not exchange-audited all later CDG sessions, so keep the exact last-trade date unverified. Do not apply current status retroactively to the older 14,439 VCI zero-volume issue dates or synthesize zero-volume OHLC bars. Raw profile and targeted report responses with hashes are in `docs/probe/phase1-hnx-special-status/`.
- Sources: [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [current regulation](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [CDG profile](https://hnx.vn/vi-vn/ModuleIssuer/UC_Issuer/Details/CDG/UC), [VFC profile](https://hnx.vn/cophieu-etfs/chi-tiet-chung-khoan-uc-VFC.html), and [VNX profile](https://hnx.vn/vi-vn/m-tim-kiem-VNX.html).

## 2026-10-19 — use VNDirect-attributed pages for targeted last-match corroboration

- Use taichinh.com only as a secondary research lookup for the latest matched date it displays, and cite its source attribution and snapshot date. It currently reports CDG 2025-05-13, VFC 2026-07-03, and VNX 2026-07-28; archived HNX exact-date reports confirm positive execution on each date. These pages are derived from VNDirect and do not replace a complete official exchange audit of every later session. Do not use this evidence to classify the separate 14,439 historical zero-volume issue dates.
- taichinh.com permits individual research lookups and source-attributed citation, but requires contacting FTMI before automated broad or deep collection. Limit use to individual lookups unless terms change; do not scrape its history pages in bulk.
- For bulk UPCoM volume reconciliation, treat FiinGroup's official `/Market/GetUpcomStockv2` schema as a candidate source because it distinguishes round-lot matching, negotiated volume, and total matched-plus-negotiated volume including odd lots. Before ingestion, establish trial coverage, historical depth, adjustment vintages, and internal ML research rights. Do not bypass HNX's listed historical-data service by bulk-querying its public report endpoint.
- No database rows or quota records changed during this web research.

## 2026-10-19 — use KBS as a supplemental volume cross-check

- Use the registered KBS daily OHLCV route to check selected VCI zero-volume issue dates and retain responses through the existing audited raw-landing path when appropriate. KBS is available through the Community source set, and a targeted NAS probe returned the same 80-share volume as the existing VNDIRECT and DNSE rows for 2020-10-15.
- Keep KBS prices and bars in a source-specific series. Its adjusted price differs from raw VNDIRECT on the sampled date, and retrospective adjustment timing is not yet validated for point-in-time training. A positive KBS volume can corroborate activity; a missing KBS row cannot prove no trade.
- For a complete historical UPCoM exchange audit, use HNX's information-service trial/product. Do not bulk-query the public daily report endpoint; its exact-date response for the NAS sample returned no rows and cannot adjudicate that historical date.
- Evidence is in `docs/probe/phase1-current-kbs-verify/README.md` and `docs/probe/phase1-hnx-kbs-reconciliation/`. No KBS data were imported to PostgreSQL in this check.

## 2026-10-19 — classify default KBS OHLC as adjusted

- A targeted KBS request around FPT's 2024-12-02 cash-dividend date returned a close-to-close return matching the dividend-adjusted branch. Treat KBS `raw_prices=false` default OHLC price columns as adjusted when materialized in a source-keyed series. This classifies prices only; it does not change volume semantics or establish the adjustment vintage available at historical signal dates.
- Preserve KBS as a separate source. Its 495 completed full-range histories remain archived in `raw.landings` and are not materialized in `core.bars_daily_sources`. The exact probe reports, row values, and hashes are in `docs/probe/phase1-current-kbs-verify/README.md` and `docs/probe/phase1-adjustment/README.md`.

## 2026-10-19 — use CafeF matched and negotiated volume as separate evidence

- The public CafeF historical export was retrieved for the 16 VCI partial-history symbols in annual windows. Its 31,381 rows and 144 SHA-256-verified workbooks are preserved in `docs/probe/phase1-cafef-history-audit/`.
- On the 14,466 VCI zero-volume issue dates, CafeF reports positive matched volume on 23 dates, all already covered by positive VNDIRECT or DNSE bars. It reports 106 additional dates with negotiated volume only. Keep those as distinct negotiated-activity evidence; do not create matched OHLC bars or merge the field into a matched-volume price series.
- CafeF zero or absent rows do not prove no trade. No CafeF prices or volumes were imported into PostgreSQL, and no VCI quality/lifecycle status was changed. Use the row-level reconciliation and daily source extract for later Phase 2 decisions; keep point-in-time adjustment vintages open.

## 2026-10-19 — keep public source checks targeted and source-specific

- Use CafeF's annual export as separately attributed activity evidence, but do not treat zero/absent volume as proof of no trade. HNX exact-date reports confirm two executions that CafeF reports as zero: CDG 100 shares on 2025-05-13 and VFC one share on 2026-07-03.
- Use the HNX public report for bounded exact-date validation. For broad UPCoM backfill, establish access to FireAnt's authenticated historical feed or an authorized HNX/FiinGroup historical product; do not turn a public report endpoint into a bulk feed.
- Preserve matched and negotiated volume as separate fields, and keep each provider's prices in a source-keyed series until its adjustment basis and historical adjustment vintage are documented. No database records changed in this source search.
- Evidence and official documentation are listed in `docs/probe/phase1-source-search/README.md`.

## 2026-10-19 — keep EasyStock as a secondary check, not a no-trade authority

- The public EasyStock download page advertises free market-wide OHLCV history from 2007 onward. Archived its public histories for the 16 VCI partial-history symbols and recorded response hashes.
- The histories have no positive-volume row on any of the 14,466 VCI zero-volume issue dates. They also miss HNX-confirmed CDG 100-share and VFC one-share executions, plus the 80-share NAS date confirmed by CafeF, VNDIRECT, DNSE, and KBS. Positive VNX 100-share activity on 2026-07-28 is reported correctly.
- The source page does not define matched-versus-negotiated volume or historical adjustment vintage. Keep its zero/absent rows out of no-trade certification and do not merge its prices into an existing series without adjustment validation. It does not close the 14,333-date unresolved partition. Evidence: `docs/probe/phase1-easystock-history-audit/`.

## 2026-10-19 — map the registered API status value to its published tier

- The authenticated local CLI reports `tier=free`. vnstock's official account documentation identifies the API-key, non-sponsored Community tier as `free` in the status field. Refer to the user's account as Community; `free` is the CLI field value, not evidence of a Guest key or account downgrade. The 2026-10-19 active VCI OHLCV probe is archived under `docs/probe/phase1-easystock-history-audit/vnstock-probe-20261019/`.

## 2026-10-19 — keep Yahoo and Simplize as bounded secondary references

- Yahoo Finance's official exchange list gives Vietnam `.VN` coverage for HOSE and does not list UPCoM; do not count it toward UPCoM completeness.
- Simplize publicly exposes per-symbol history and an Excel export control, but its history page labels prices as dividend/split adjusted and exposes one volume field without a matched/negotiated split. Use it for targeted review only until adjustment vintage, volume semantics, and internal ML rights are verified. Do not promote its zero or absent rows to no-trade evidence.
- KBS remains an actual OHLCV alternative on the registered Community account. The four targeted reports confirm positive CDG/NAS observations, miss VFC's known 2026-07-03 execution, and show no UTT rows. Keep KBS separate, do not infer no-trade from missing rows, and do not materialize adjusted prices for point-in-time training without a validated vintage.
- No database records or canonical bars changed during these probes and page checks. Evidence is in `docs/probe/phase1-kbs-issue-probes-20261019/` and `docs/probe/phase1-utt/`.

## 2026-10-19 — disposition of newly found public datasets and adapters

- The Kaggle Vietnam competition's OHLCV bundle is limited to 30 tickers and 2021-01-04–2021-10-29, and is subject to competition rules. Do not use it to claim broad UPCoM coverage or treat it as the project backfill.
- The Mendeley CC BY 4.0 dataset has 627 symbols across HOSE/HNX/UPCoM for 2014–2024 but only close prices under anonymized IDs. Keep it out of symbol-keyed bars and volume classification until an independently reproducible ticker crosswalk and price-basis validation exist. A separate close-only experiment may be considered after those checks.
- Treat OpenStockAPI and `vn-market-data` as adapter/code leads, not independent evidence: their published source graphs overlap providers already represented in the project. For registered Community access, the current vnstock v5 docs permit KBS/VCI for equity OHLCV; TCBS is not a v5 equity OHLCV route. Separate TCBS/SSI access would require their own documented credentials or approval.
- No new historical OHLCV source available in this search clears the remaining gap. Continue with already authorized targeted HNX checks and source-specific raw evidence; do not bulk-query HNX's public report endpoint in place of its historical data product. No database rows, canonical bars, or quota records changed.
- Evidence and URLs are archived in [`docs/probe/phase1-source-search/README.md`](probe/phase1-source-search/README.md).

## 2026-10-19 — disposition of additional public source leads

- Reject Lich Su Gia's inspected CDG 2025-05-13 zero-volume row for activity classification: the official HNX exact-date report confirms 100 matched shares. Its inspected page does not disclose its source feed, so do not treat its zero or absent rows as no-trade evidence.
- Keep FINCO and FinLens as access-gated leads. FINCO's unauthenticated CDG API returned company metadata only and the historical export preview returned `Not authenticated`; it requires approved research export access and describes retrospectively adjusted prices without publishing volume semantics or the upstream history provider. FinLens documents a separate API key requirement, adjusted default prices, an unadjusted option, and volume in shares; verify source lineage and a known HNX trade before ingestion.
- DNSE OpenAPI documents historical executions and OHLC, but requires separately registered credentials and shares the same provider family as the DNSE histories already in the project. It may add trade-level detail, but it is not an independent OHLCV source.
- Do not use the Kaggle VN30 candidate until its actual files, license, and data basis are verified; its described 30-stock universe does not address the UPCoM gaps. No new source data was downloaded or imported in these checks. The 16 HNX sample reports remain the only new market records in this follow-up; evidence and URLs are in `docs/probe/phase1-source-search/README.md`.

## 2026-10-19 — disposition of further web-search leads

- The Kaggle Vietnam Stock Returns with Efficiency Scores (DEA) dataset is a small (46 KB) CC BY-SA 4.0 quarterly research sample for 26 HOSE real-estate companies from 2019–2024, with engineered inputs and next-quarter returns. It is not raw daily OHLCV and cannot close the UPCoM history gaps. Do not use its precomputed return field as a substitute for the project's point-in-time label construction. No archive was downloaded or imported.
- FireAnt's current official Excel docs distinguish historical matched `DealVolume` from negotiated `PutthroughVolume`; its current plan table includes the Excel add-in only in Premium, while MetaKit base data are available from Essential upward. Keep FireAnt as the strongest documented next feed for an authorized validation, but require a known-trade probe, coverage-depth check, and ML-use terms before ingestion.
- A direct request to the publicly documented legacy TCBS `apipubaws` daily OHLCV endpoint for HNX-confirmed CDG 2025-05-13 returned HTTP 403 and no data. The current TCBS API path requires registered credentials/token exchange. Do not count the legacy route as an accessible source; the official route remains a candidate only after separate TCBS access is obtained.
- No market-data rows or PostgreSQL records changed in this web-search follow-up. Source URLs and evidence are recorded in `docs/probe/phase1-source-search/README.md`.

## 2026-10-19 — verify VNDIRECT's public matched-volume endpoint

- The public VNDIRECT Finfo endpoint returned `nmVolume` / `ptVolume` of 1 / 0 for VFC on 2026-07-03, 80 / 0 for NAS on 2020-10-15, and 100 / 0 for CDG on 2025-05-13. The DStock page identifies these as matched and negotiated volume separately. All three exact-date observations match existing VNDIRECT rows and archived HNX evidence; they add no coverage to the 14,317 unresolved issue dates.
- Finfo accepts `date` and `sort=date:asc`; the DStock browser key `tradingDate` produced HTTP 500 when used as the Finfo filter. Preserve `nmVolume` as matched-volume evidence and keep `ptVolume` separate. Do not count the repeated observations as new data or change source rows.
- The raw responses, exact URLs and SHA-256 hashes are in `docs/probe/phase1-vndirect-api-verification-20261019/`. The query did not call vnstock, change quota, or write to PostgreSQL.

## 2026-10-19 — disposition of additional provider leads

- DataPro SmartAPI is a credible paid UPCoM EOD candidate with documented matched and negotiated volume fields and a one-time historical backfill. Its published terms prohibit redistribution; this project's ML storage/use rights, upstream lineage, adjustment definition, and odd-lot treatment have not been confirmed. Do not ingest until authorized access is available and vendor scope/rights are validated against known HNX dates.
- TCBS documents historical daily OHLCV but requires a separately registered API key plus OTP exchange; its `volume` field does not specify matched versus negotiated scope or adjustment basis. Fialda offers historical HOSE/HNX/UPCoM through a contract-defined API but does not publish the exact volume split or scope. Keep both as authorized-access leads only.
- The additional web search found no new anonymous endpoint that closes the 14,317-date partition. No requests were made to these gated providers and no market-data or quota records changed. Source details are in `docs/probe/phase1-source-search/README.md`.
- One metered `vnpipe` probe for `equity_trade_history` on the registered Community profile returned `EntitlementError`; the exact server quota counters were unchanged. Official vnstock documentation classifies daily trade history as Extended-only and states that the unsupported-tier route does not send a provider query. Do not build this route into a Community backfill fallback. Probe report: `docs/probe/phase1-trade-history-probe-20261019/2026-10-19.json`.

## 2026-10-19 — record three exact HNX negotiated-activity reports

- Keep HNX's exact-date UPCoM reports as the source of truth for VNX on 2026-01-29, 2026-01-30, and 2026-02-12. They report zero matched volume and negotiated volumes of 15,100, 4,900, and 4,900 shares, respectively; preserve each raw response and hash through `raw.landings` and `ops.exchange_daily_bar_evidence`.
- These observations resolve three dates from the 14,317 unresolved activity-date partition, reducing it to 14,314. They create positive exchange evidence against the zero-volume VCI observations; do not overwrite or repair VCI bars and do not call these sessions no-trade.
- A temporary Simplize history lookup was only used to select candidate dates. The site's terms restrict copying and derivative products without written permission. Do not import or train on Simplize rows; do not commit the temporary local snapshot. HNX reports and import evidence are documented in `docs/probe/phase1-simplize-history-audit/README.md`.

## 2026-10-19 — use Stockbiz only to corroborate exact HNX volumes

- Direct Stockbiz date lookups returned VNX volume values of 15,100 (2026-01-29), 4,900 (2026-01-30), and 4,900 (2026-02-12), matching the archived HNX reports. Stockbiz's data-method page says its price and trading data come from FireAnt. Control lookups return zero for HNX-confirmed NAS (80), VFC (1), and SNC (71) odd-lot sessions, even though CDG's 100-share matched session is returned correctly. The page has one `Khối lượng` field; treat it only as targeted corroboration and do not import its price or volume values.
- The SHS archive advertises separate matched and negotiated columns, but its legacy callback returned empty content in the exact-date and broad-range requests tried here. It produced no additional evidence. Keep the existing HNX reports as the stored market evidence; the research notes and links are in `docs/probe/phase1-source-search/README.md`.

## 2026-10-19 — prioritize exchange-authorized UPCoM volume feeds

- HNX's 2026 InfoFile catalogue identifies `DKGD.DLCN 2.1` as per-stock end-of-day UPCoM data with separate matched/put-through volume and value, at VND 2,000,000 per month. HNX's information-service guide advertises a two-week trial. Ask the provider to confirm whether the trial includes retrospective files and internal ML retention rights before using it; no trial or feed is currently active.
- FiinGroup's published UPCoM schema defines `TotalMatchVolume` as round-lot only, but `TotalVolume` and `TotalDealVolume` include both round and odd lots. Treat `TotalVolume - TotalDealVolume` as a candidate all-lot matched volume only after a credentialed probe matches known HNX dates, including odd-lot positive controls. No FiinGroup access or import is currently active.
- ICE lists HNX/UPCoM historical and end-of-day coverage from February 2020; treat it as a licensed alternative pending scope, volume semantics, price, and retention/ML terms. No licensed feed's availability constitutes data obtained. Keep Phase 1 partial and the current 14,314-date activity gap unchanged until source responses are persisted with audit lineage and pass controls.
- Evidence and links are in `docs/probe/phase1-source-search/README.md`.
- VNDIRECT's public chart endpoint matched HNX-positive NAS, VFC, and SNC controls but returned zero on the three HNX-positive VNX dates; treat it as same-family corroboration with known false-zero coverage. VPS's undocumented chart endpoint found only the CDG control among those probes and also returned zero/no-row for known trades. Never convert these endpoints' zeros or missing rows to no-trade facts. FPTS documents a client UI for historical past-session price/quantity, but no bulk API/export scope; use it only for manual checks unless authorized machine-readable access is established.
- Exact targeted request windows, returned bars, raw JSON, and SHA-256 digests are in `docs/probe/phase1-source-search/public-chart-controls/manifest.json`; the probes did not write any market data to PostgreSQL.

## 2026-10-19 — interpret HNX matched and negotiated report columns separately

- HNX's UPCoM daily report groups `Khớp lệnh liên tục`, `Khớp lệnh định kỳ đóng cửa`, and `Phiên sau giờ` separately from `Thỏa thuận`; `Toàn thị trường` is their combined total. Parse matched volume/value by summing the three matching-session components, preserve negotiated volume/value separately, and do not place total-market volume in an OHLCV bar's matched `volume` field.
- The first parse of VNX reports for 2026-01-29, 2026-01-30, and 2026-02-12 incorrectly treated total-market amounts as matched. The raw report bytes and first interpretation remain immutable. Migration 025 and `ops.exchange_daily_bar_evidence_interpretations` append the corrected component values, and `ops.exchange_daily_bar_evidence_current` exposes the latest interpretation to the lifecycle gate. These dates are `VERIFIED_NEGOTIATED_ONLY`; preserve them as activity evidence while keeping them out of matched-volume bars.
- The public BSC history page independently returned matched volumes for CDG, NAS, VFC, and SNC controls and zero matched / positive negotiated volumes for the three VNX dates. It is suitable for targeted corroboration only: its history table omits high/low fields, and bulk storage/ML-use terms are not established. No BSC rows or prices were imported.
- Evidence, raw BSC responses and hashes, and the corrected HNX parser are in `docs/probe/phase1-source-search/README.md` and `docs/probe/phase1-simplize-history-audit/README.md`. The unresolved activity partition remains 14,314 dates; the distinct negotiated-only tally is 109.

## 2026-10-19 — use BSC's public historical page for a bounded activity cross-check

- Retrieve 2018-10-01 through 2026-10-16 for the 16 VCI partial-history tickers from BSC's public historical page. Preserve all 31,935 rows across 47 response pages with per-page hashes and keep matched and negotiated volumes separate.
- Validate all 23 prior exact HNX controls, 12 per-symbol negotiated-volume samples, and each of the 16 last positive BSC activity dates against the matching HNX report. All checked amounts match. BSC's latest positive dates for CDG (2025-05-15) and VNX (2026-08-26) are negotiated-only and later than their latest matched-volume dates; keep the two concepts distinct.
- The BSC rows add no activity date beyond the existing evidence: its 24 matched-volume issue rows equal existing VNDIRECT/DNSE values, 106 negotiated-only rows equal CafeF, and three negotiated-only VNX rows equal the existing HNX-confirmed reports. Its 14,333 zero issue rows do not prove no trade.
- BSC's page omits high/low, and its public page does not establish bulk storage or internal ML-use terms. Keep this as a BSC-attributed local evidence set; do not use its partial prices to construct OHLC or import its rows into canonical bars. Flag XMC 2019-06-27 (27,000 matched shares) as venue-attribution unresolved because the current HNX UPCoM profile date is 2019-06-28.
- Reconciliation, raw responses, page hashes, and per-symbol summaries are in `docs/probe/phase1-bsc-history-audit/`, `docs/probe/phase1-bsc-hnx-positive-audit/`, and `docs/probe/phase1-bsc-hnx-last-activity-audit/`. Phase 1 remains partial; the 14,314 activity-date gap is unchanged.

## 2026-10-19 — qualify SSI FastConnect as the next backfill probe

- Current official SSI documentation describes online API-key creation for existing SSI brokerage customers, free Market Data API access, UPCOM daily OHLC, historical coverage from each security's first trading date, and bulk file/ZIP downloads. The OHLC endpoint defines volume as normal matched volume; a separate daily stock-price endpoint publishes matched, negotiated, and total traded volume including odd lots. The service overview says there is no manual approval, but the separate Terms & Environments page still says registration requires approval; confirm the live portal flow.
- No SSI credentials are configured in this project environment. Keep SSI as the next authorized source to probe; do not claim data obtained. Before ingestion, compare known HNX matched and odd-lot controls, establish adjustment behavior and matched odd-lot semantics, and confirm internal ML retention terms. The separate iData free trial is login-gated and its public terms do not establish extractable or ML-usable rights.
- FiinGroup's per-security UPCoM schema defines `TotalMatchVolume` as round-lot matched volume, `TotalDealVolume` as negotiated round+odd-lot volume, and `TotalVolume` as matched+negotiated round+odd-lot volume. Treat `TotalVolume - TotalDealVolume` only as an inferred all-lot matched candidate until an authorized sample matches known HNX round-lot and odd-lot controls. History depth, trial scope, adjusted-price vintage, and ML retention rights remain open.
- Source details are in `docs/probe/phase1-source-search/README.md`. No rows were imported and the Phase 1 activity gap remains 14,314 dates.

## 2026-10-19 — close the latest public-feed search with no source promotion

- The live read-only VCI queue status is 1,502 `COMPLETED`, 16 `PARTIAL`, 1 `BLOCKED`, and no pending, leased, or deferred jobs for the 1,519-symbol listing snapshot dated 2026-10-17. Do not count a zero-pending queue as a complete data backfill while the partial and blocked records remain.
- VietstockFinance returned a false zero for the HNX-confirmed SNC odd-lot trade and no row for the HNX-confirmed CDG matched trade; its historical market-wide request returned current-date records. Do not import its history or use its zero/missing rows to classify activity.
- OpenStockAPI requires a login for the free plan and its documented Vietnam chain uses TCBS, KBS, and VCI. The MIT `vn-market-data` package calls provider endpoints already represented in this repository; its software license does not license the feeds. Keep both as connector leads only, not independent evidence.
- Public UTT pages with recent zero-volume rows do not identify a last positive trade. The audited evidence remains source-bounded: no positive UTT volume was observed from its HNX first-trading date through 2026-10-16 across VNDIRECT/CafeF, with HNX covering the CafeF-omitted dates and KBS returning no rows. Keep UTT out of OHLCV training and do not claim an exchange-wide lifetime no-trade finding.
- The expanded source search yielded no eligible bars and did not change the 14,314 unresolved activity dates. Archive the provider notes and current queue evidence in `docs/probe/phase1-source-search/README.md`; the targeted Vietstock web requests created no vnstock quota reservation or PostgreSQL write.

## 2026-10-19 — select next authorized Phase 1 history path

- SSI is the first no-fee route to validate if an SSI brokerage account is already available. Its current V3 FAQ requires an SSI securities account, says Market Data has no current service fee, and describes online key creation with per-key rate-limit headers. The older V2 registration guide conflicts on manual approval; use the live Developer Portal flow as the current source of truth.
- The published V2 schemas cover UPCOM, distinguish matched and negotiated totals, and expose raw and adjusted close fields. An older official FCData specification mentions analysis through customers' own applications, but does not settle ML dataset retention or license scope. They are promising enough for an authenticated control probe, but not for ingestion until HNX positive matched and odd-lot controls, adjustment behavior, V2/V3 compatibility, and local ML retention terms are checked. No SSI credentials or sample data are present in this workspace.
- Do not plan a full backfill around FiinQuant's free plan: current published limits are one year and 33 tickers, and online registration is temporarily suspended. Keep FiinGroup's direct API as a vendor-contact lead because its history depth and use rights remain contract-specific.
- HNX's official `DKGD.DLCN 2.1` UPCoM EOD package costs VND 2,000,000/month and HNX advertises a two-week trial. It is the exchange-authorized fallback if SSI access is unavailable, after HNX confirms historical archive delivery and internal ML retention. Do not bulk-query the public report endpoint to bypass the licensed product.
- The source review found no newly eligible open dataset or independent anonymous feed. Keep the current 14,314 activity dates unresolved and Phase 1 PARTIAL until authorized records are preserved through the source-audited ingestion path. Details and official links are in `docs/probe/phase1-source-search/README.md`.

## 2026-10-19 — classify zero-volume sessions across exchanges

- A zero-volume observation for an individual security on an exchange session is plausible on any venue, including UPCoM and HNX-listed names such as SPC. Do not infer a missing trade bar from low liquidity, consecutive zero-volume dates, or an exchange calendar alone. A positive independent matched-volume record establishes a candidate missing VCI bar, negotiated-only volume is separate activity, and an exact exchange report with zero matched volume is a confirmed no-match observation. Do not synthesize carried-forward OHLC bars. The later user-approved working classification for partial research is recorded below.

## 2026-10-19 — user-approved partial zero-volume classification and UTT exclusion

- For partial research, treat the 14,314 residual VCI source observations with volume zero and no conflicting positive matched-volume evidence as zero-volume/no-matched-trade observations. This is an explicit analysis assumption based on the source's observed zero value and the user's acceptance of this small residual; it does not certify every date through an independent exchange report or establish listing, suspension, or delisting status.
- Keep the 24 positive alternate matched-volume dates as conflicts, the 109 negotiated-only dates as a separate activity category, and the 19 exact HNX zero-matched reports as exchange-confirmed no-match evidence. Preserve all raw source rows and quality issues. Do not synthesize OHLC bars or create records for absent source dates. The VietstockFinance endpoint was tested against HNX-known trades and returned a false zero and a missing row; it cannot certify the remaining dates.
- Exclude UTT from future per-symbol active data collection and model candidate inputs. The audited first year from its official 2025-10-17 UPCoM start through 2026-10-16 produced no positive executed-volume observation across the checked VNDIRECT/CafeF histories; HNX confirmed the CafeF-omitted dates. Its flat 9.2 reference values are not trade bars. Keep its listing and raw historical evidence for survivorship/audit work, and do not claim it has been formally delisted.
- The current rules distinguish listed shares from UPCoM-registered shares: Decree 155/2020 Article 120 provides a 12-month no-trade ground for mandatory delisting of listed shares, while Article 137's UPCoM registration-cancellation grounds do not make inactivity alone an automatic cancellation. Current VNX Decision 23/QĐ-HĐTV (2026) ties UPCoM cancellation to those Article 137 grounds. Its more-than-25-session provisions change reopening mechanics (including the first-day price band and accepted order types); they are not an automatic cancellation timer. Sources: [Government Gazette, Decree 155/2020](https://congbaocdn.chinhphu.vn/CongBaoCP/CongBao/2021/1/32881/34091-1-47-48.pdf), [Decree 245/2025 amendment](https://xaydungchinhsach.chinhphu.vn/toan-van-nghi-dinh-245-2025-nd-cp-sua-doi-bo-sung-nghi-dinh-155-2020-nd-cp-quy-dinh-chi-tiet-thi-hanh-mot-so-dieu-cua-luat-chung-khoan-119250913083126401.htm), [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), and [Decision 23/2026 text](https://thuvienphapluat.vn/van-ban/Chung-khoan/Quyet-dinh-23-QD-HDTV-2026-Quy-che-Dang-ky-va-quan-ly-giao-dich-chung-khoan-chua-niem-yet-699113.aspx).
- UTT is added to `config/ignored_symbols.txt`; this prevents future per-symbol profile, VCI/VNDIRECT/DNSE backfill, one-off OHLCV probe, preview-backfill, and company-info calls before provider requests or quota reservation. Existing UTT records, listings, and audit evidence are preserved. Phase 1 remains PARTIAL; this disposition allows use of the current partial research data without claiming the phase exit criteria are complete.

## 2026-10-19 — source-keyed completion for the approved historical dataset

- For Phase 1 coverage, a symbol is historically covered when a complete, source-attributed backfill exists from VCI or an explicitly approved, auditable alternate within that provider's returned history. Keep each source's raw rows, adjustment basis, and job status intact; a partial VCI job stays `PARTIAL` even when a separate source supplies usable history. Do not copy alternate bars into canonical VCI rows or splice price bases within a ticker history.
- The user's approved scope excludes UTT from active collection and model candidates. Preserve its old VCI `BLOCKED` job as audit evidence; it does not count against the 1,518-symbol active research scope.
- A fresh read-only queue audit on 2026-10-19 found 1,502 VCI `COMPLETED`, 16 VCI `PARTIAL`, 1 VCI `BLOCKED` (UTT), and no pending or leased jobs. The 16 partial VCI symbols are CDG, GGG, HPI, NAS, SBD, SDD, SHC, SNC, SPC, SVG, TNB, VFC, VNI, VNX, XMC, and XPH; all 16 have `COMPLETED` VNDIRECT backfill jobs and source-keyed rows already stored. Thus all 1,518 in-scope symbols have at least one completed audited history. The 388 positive VNDIRECT symbol/dates without a positive canonical VCI bar remain in VNDIRECT's separate series.
- By exchange, VCI status is HNX 298/299 complete (SPC partial), HOSE 406/406 complete, and UPCoM 798/814 complete (15 partial plus UTT blocked). After the approved UTT exclusion, UPCoM's active scope is 798/813 complete with 15 VNDIRECT-covered VCI partials.
- This source-completion rule does not waive the Phase 1 injected-fault gate or its current-tree CI qualification. No market-data rows or quota records were changed by this audit.

## 2026-10-19 — preserve and use VNDIRECT adjusted OHLC point in time

- The earlier Phase 1 completion note did not make the VNDIRECT adjustment fields visible to downstream price work: raw `open/high/low/close` had been imported while the exact same archived responses also contained `adOpen/adHigh/adLow/adClose`. Keep the raw columns unchanged and materialize the separate adjusted snapshot with its `fetched_at` vintage through migration 026.
- Use `core.vndirect_bars_as_of(symbol_id, as_of_date)` for VNDIRECT point-in-time prices. It divides the snapshot OHLC by the adjusted-close/raw-close factor on the requested session, removing actions effective after that session. It returns no history if rows through the requested date are incomplete or have mixed adjustment vintages.
- VNDIRECT's official DStock history page states that its adjusted close accounts for splits and dividends on ex-right dates and is used in its technical charts. The HOSE-hosted FPT warrant disclosure records the 2024-12-02 ex-right date and underlying reference move 144.300 to 143.300; the archived VNDIRECT `adClose` values follow the same cash-dividend-adjusted branch. Sources and archived comparisons are recorded in `docs/probe/phase1-adjustment/README.md`.
- Phase 2 must use the as-of function for VNDIRECT features (as-of the signal session) and label endpoints (as-of the label end session). Migration 027 adds a market-wide overload for a single-date, full-universe query. Keep VCI and DNSE source rows for independent DQ checks; do not join their adjusted snapshots into the Phase 2 price series.

## 2026-10-19 — use a full-coverage point-in-time price series for Phase 2

- The user asked to resolve historical price disagreements rather than drop unresolved ticker/dates from ML. Use the complete VNDIRECT history and `core.vndirect_bars_as_of(symbol_id, as_of_date)` or its market-wide overload as the single Phase 2 price basis. The functions preserve raw prices and lineage in storage, and return adjusted OHLC on the requested date's basis; they fail closed for incomplete/mixed vintages and do not fabricate a bar when a ticker has no row on the as-of session.
- Local PostgreSQL audit: 2,844,683 VNDIRECT rows for 1,519 symbols have complete adjusted OHLC snapshots, with one snapshot vintage per symbol; all 1,519 symbols have a bar on 2026-10-16. All 2,172,122 DNSE source rows have same-symbol/same-date VNDIRECT counterparts. Of 1,809,966 VCI canonical bars, 1,809,961 have a VNDIRECT counterpart; the other five are CTR rows dated 2022-02-16 through 2022-02-22, already excluded on the exchange-transfer evidence in the lifecycle decision above. Excluding the user's already approved UTT scope leaves all 1,518 active symbols covered.
- PRC resolves the large adjusted-close disagreement. CafeF's exact 2023-03-29 API row independently reports raw OHLC 65/70/63/68 and 36,000 matched shares. VSDC records a VND 35,000/share cash dividend for 2022 with 2023-03-31 record date. The ex-right reference is 68-35=33 thousand VND. VNDIRECT's snapshot factor changes from 10.01/68=0.147206 on March 29 to 9.161/30.2=0.303344 on March 30; their ratio is 0.4853, matching 33/68. VCI's adjusted close 9.98 agrees with VNDIRECT's 10.01, while DNSE's 20.56 is explained by the missing dividend factor: 20.56*(33/68)=9.978. This is a provider adjustment error/vintage mismatch, not a reason to remove PRC's valid ticker/date.
- The VNDIRECT factor also tracks the later PRC actions: the 1,000/share 2023 dividend in May 2024; the 12:19 bonus issue effective in May 2025; and the 1:1 rights issue at 11,500/share in October 2025. The 2024 cash-dividend factor matches the 21.5/22.5 reference ratio; the May 2025 factor shift is within 0.3% of the 12/31 bonus-share scale; and the October 2025 rights factor matches the 14.8/18.1 theoretical reference. CafeF's raw OHLC is retained as an independent price check; its adjusted field is not used as a training basis because its adjustment vintage differs.
- For forward labels, call the as-of function once at the label end date and read both the signal-date and label-end prices from that same result. This makes both prices share the actions effective through the label end. The Phase 2 input does not omit VCI/DNSE ticker-dates based on those providers' adjustment mismatch: the full VNDIRECT series supplies the aligned price history for the in-scope sessions. Zero-volume rows remain identified by `is_traded=false`; they are not promoted to executed prices.
- Migration 027 applies the existing user-approved UTT exclusion directly through `ops.ml_symbol_scope`; both the per-symbol and market-wide VNDIRECT Phase 2 functions filter explicitly excluded symbols. Raw UTT source history remains stored. SQL assertions verify that a scope exclusion suppresses the ticker from both functions without deleting or altering its data.
- Evidence and the exact CafeF response hash are in `docs/probe/phase2-adjustment/README.md` and `cafef-prc-2023-03-29.json`. Sources: [VSDC PRC 2022 cash dividend](https://vsdc.vn/vi/ad/156913), [VSDC PRC 2023 cash dividend](https://vsdc.vn/vi/ad1/170365), [VSDC PRC 2025 bonus issue](https://vsdc.vn/vi/ad/182393), [VSDC PRC 2025 rights issue](https://vsdc.vn/vi/ad1/188281), and [CafeF PRC historical prices](https://cafef.vn/du-lieu/lich-su-giao-dich/hnx/prc-1.chn).

## 2026-10-19 — distinguish raw VNDIRECT fields from Phase 2 adjusted prices

- Keep `core.bars_daily_sources.o/h/l/c` and `adj_basis='unadjusted'` as the truthful raw-source representation. Keep VNDIRECT's separate `ad*` snapshot and `adjustment_vintage_at` intact; do not overwrite or relabel raw history.
- Phase 2 must read `core.vndirect_bars_as_of(symbol_id, as_of_date)` or the market-wide overload, and assert `price_basis='adjusted_as_of_reference'`. For a forward label, read both endpoints from one query as of the label end. The source's raw `unadjusted` label is not the model series' basis.
- The 2026-10-19 registered-database query returned 2,844,435 adjusted-as-of rows for all 1,518 in-scope symbols, including 1,021,077 zero-volume rows marked `is_traded=false`. No in-scope row was removed because VCI/DNSE prices differed; the 248-row raw/model difference is solely UTT's explicit user-approved scope exclusion. Event-level checks for PRC, FPT, and AGG are recorded in `docs/probe/phase2-adjustment/README.md`.

## 2026-10-19 — resolve the 2019-01-02 VNDIRECT reference gap

- Keep all 684 affected VNDIRECT bars in the Phase 2 history. Their source `basicPrice=0` values remain unchanged; migration 030 records a separate, evidence-linked reference factor in `core.vndirect_reference_adjustment_overrides`.
- The VSDC rights-exercise calendar for 2019-01-03 lists DSN's cash dividend, HCB's cash dividend, and FTV/PCN shareholder meetings. DSN is the only reference-price action in the current VNDIRECT symbol universe; HCB is absent from `core.symbols`.
- For DSN, the official VSD notice records VND 3,600/share and a 2019-01-03 record date. Its prior close 62.9 thousand VND gives a 59.3 reference and a `59.3/62.9` ratio. The valid 58.5 close and 3,860-share volume remain intact. The other 683 affected in-scope symbol/dates are documented `NO_ACTION` factors of 1.0; the 23 zero-volume UPCoM observations remain in the series.
- The exact row counts, venue classification, source links, and snapshot-rounding cross-check are in `docs/probe/phase2-adjustment/2019-01-02-reference-resolution.md`. Do not filter unresolved price rows from Phase 2; the factor audit must be complete before model features use the as-of series.
- Evidence: [VSDC record-date calendar](https://vsdc.vn/en/lich-giao-dich?date=03%2F01%2F2019&tab=LICH_THQ), [VSDC DSN notice](https://vsdc.vn/en/ad/125616), and [DSN ex-right reference calculation](https://cophieu68.vn/quote/event_calc.php?id=dsn).

## 2026-10-19 — resolve every flagged VNDIRECT price before Phase 2

- Retract the earlier suggestion to keep unresolved valid price rows out of Phase 2. Resolve the full 641-session candidate set using archived public source evidence and include the resulting bars in the Phase 2 series. Keep true zero-volume rows, including UPCoM and SPC observations; only the separately approved UTT scope exclusion remains excluded.
- Migration 032 records 42 corporate-action factors and 599 documented no-action factors of 1.0, each with VSDC/Cophieu68 URLs and response hashes. Compute action factors from official event terms and the theoretical reference-price formula. Use the previous close for HOSE/HNX and the last matched VWAP for UPCoM; carry reference prices across zero-volume sessions. The CH5 factor uses the last traded VWAP 15.0 across two no-match sessions, not the stale carried `basicPrice` 13.7. CTS includes all three VSDC share distributions.
- Five VNDIRECT 2025-05-13 bars (FMC, FTS, GEX, VNM, VNS) already include the following day's event adjustment in the source OHLC. Migration 031 adds evidence-linked CafeF model-OHLC overrides, leaving raw VNDIRECT OHLC, volume, trade status, and landing lineage unchanged. The same migration resets cumulative factors at documented delist/relist episodes and uses log-space accumulation. Migration 033 adds 20 traded HOSE close corrections with exact CafeF agreement on open/high/low/matched volume, an off-tick VNDIRECT close, and an on-tick CafeF close; the combined override count is 25.
- The registered database already contains `031_vndirect_adjustment_episodes_and_logspace.sql` at SHA-256 `b935d64edc09e2a9da4c1879b839f592717cb78b5cce81bc22499e904a3bda52`. Preserve that applied migration record. The forward model migration uses the distinct filename `031_vndirect_model_price_and_episode_api.sql`; `032_vndirect_reference_factor_resolution.sql` seeds the candidate decisions. The Go runner checked the existing hashes and applied both new migration names without editing the ledger.
- `docs/probe/phase2-adjustment/reference-factor-resolution-ledger.csv` is the complete candidate-level audit; `vndirect-model-bar-overrides.csv` documents the five action-related OHLC corrections, while `ohlc-discrepancy-audit-20261019/vndirect-close-tick-corrections.csv` documents 20 CafeF-confirmed close corrections. Tests verify model corrections and preservation of original source rows. This resolves the price-input blocker; Phase 2 features, labels, fundamentals archive, leakage checks, and feature parity remain outstanding.
- Official references: [VSDC ex-right guidance](https://vsdc.vn/vi/ad/195688), [HOSE reference-price rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372202/5.Gia%20tran%20san%2C%20gia%20tham%20chieu%2C%20gia%20dong%20cua.pdf), [HNX UPCoM reference FAQ](https://cbtd.hnx.vn/vi-vn/hoi-dap.html), and [VSDC AAM 2019 dividend notice](https://vsdc.vn/vi/ad/57234).

## 2026-10-19 — resolve VNDIRECT close conflicts and retain valid openings

- Do not apply a generic `low <= open <= high` rejection rule to the VNDIRECT daily series. The user confirmed that an opening field can sit outside the separately reported matched-price extrema in Vietnamese market data. Preserve the raw OHLC, volume, and landing lineage; do not drop those rows or synthesize replacement opens.
- The local raw OHLC audit contains 374 rows (214 symbols, 35 dates): 347 opens and 33 closes fall outside high/low, with six overlaps. A public Cophieu68 history lookup matched the exact date and volume for all 374; its price basis differs, so those prices are not copied into the model series.
- Of the 33 close conflicts, five action-related positive-volume bars were already corrected. Migration 033 applies CafeF closes to the remaining 20 positive-volume HOSE model bars because CafeF's same-day open/high/low and matched volume exactly match VNDIRECT, its close is inside the shared range and on the official HOSE tick, and VNDIRECT's close is both outside the range and off-tick. Eight other close conflicts have zero volume and `is_traded=false`; retain them as non-traded observations without synthesizing an executed price. No source row or date is excluded.
- All 374 audit rows remain in the Phase 2 adjusted-as-of series. The full series contains 2,844,435 rows across 1,518 in-scope symbols, including 1,021,077 zero-volume observations. UTT remains the only separately user-approved model-scope exclusion.
- The source rule is [VNDIRECT's HSX trading guide](https://support.vndirect.com.vn/hc/vi/articles/360002192174-Quy-%C4%91%E1%BB%8Bnh-giao-d%E1%BB%8Bch-t%E1%BA%A1i-s%C3%A0n-HSX), which specifies tick increments of 10 VND below 10,000 VND, 50 VND from 10,000 through 49,950 VND, and 100 VND from 50,000 VND. [SSI's field definitions](https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage) and [HOSE order types](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf) separately document opening/closing auctions and matched-price extrema.
- The full dispositions, CafeF response hashes, reproducible collector, and reconciliation script are recorded in `docs/probe/phase2-adjustment/ohlc-discrepancy-audit-20261019/README.md`. The model-series correction is applied through an append-only migration; raw source observations remain available for source audit and refresh.

## 2026-10-19 — run the local VCI market refresh at 06:00

- Use Windows Task Scheduler on the registered machine at 06:00 local time (Asia/Ho_Chi_Minh). VCI is refreshed into the canonical series, and VNDIRECT is refreshed as a separately attributed source series with its existing point-in-time adjustment view. The task also refreshes the current listing snapshot.
- Every VCI OHLCV request must continue through the existing Go gateway with a fresh absolute quota observation and durable call reservation. A daily round-robin order prevents a capped run from repeatedly favoring alphabetically early symbols. Unknown or percentage-only quota stops the VCI branch; the separately audited VNDIRECT source may still refresh.
- The task keeps a 14-calendar-day request window to cover the last five sessions across weekends and long closures, writes logs and probe reports under the current user's LocalAppData, and stores the local PostgreSQL credential only in user-bound Windows DPAPI-encrypted form.
- The task stores VNDIRECT observations separately and does not relabel them as VCI or combine adjustment bases. KBS remains comparison-only for this scheduled refresh.
- Registering the task starts Phase 6 but does not satisfy its exit criteria. Keep Phase 6 in progress until seven unattended trading-day runs, backup checks, and recovery evidence pass.
- A source-attributed VCI frame with count 0 and an explicit empty rows array is an empty response for the requested window, not a zero-volume bar. Archive its exact bytes and complete the request without creating OHLC rows or zero-volume classifications; malformed frames remain quarantined and subject to the existing circuit breaker.

## 2026-10-20 — Phase 2 feature and source guardrails

- Keep the VNDIRECT adjusted-as-of series as the Phase 2 price basis and keep the fundamentals overlay separate from the core feature/model path. Migrations 034–038 define the Phase 2 archive, labels, feature set, verified source-input map, and optional overlay.
- Populate a source-dependent field only after its underlying route/field semantics, row identifier, units, and point-in-time availability are evidenced. Until then, retain NULL; do not substitute a guessed proxy or synthetic observation.
- Do not make live fundamentals calls until the registered machine has a fresh absolute quota observation and a durable reservation through `live.Gateway.CallRecorded`. A missing or percentage-only quota blocks ingestion. No live calls or quota probes were used for the current offline implementation checks.
- A synthetic null-rate fixture is not the required production-data null-rate report. Phase 2 remains open until SQL/Rust feature parity passes and the report is generated from actual materialized feature rows; no recommendation becomes active without a later Phase 3 champion.

## 2026-10-20 — bound V3 feature work by symbol batch

- Compute index/market context and full-universe daily ranks once, then process the symbol-local ordered EMA, return windows, beta, ADX, and stochastic features in deterministic batches. Keep every effective-session gap and each symbol's full episode/session ordering inside its batch.
- Use 50 symbols per batch by default, with a local session setting bounded to 1–250 for machine tuning and synthetic parity checks. The PostgreSQL acceptance fixture compared one 250-symbol batch with batches of two and found identical v3 rows and feature values; cross-sectional ranks and lagged market context stayed global.
- The prior full-history v3 statement timed out before producing a report. The first measured symbol-batch scaling probe passed with exponent 1.025 for 15–60 symbols. Full-history rebuild, labels, and null-rate evidence remain pending; do not call Phase 2 complete until those runs and gates finish.

## 2026-10-20 — remove V3 row JSON conversion and rolling-frame recomputation

- `auto_explain` on a rollback-only real-data sample measured 87.55 seconds in the V3 feature statement. The outer output projection consumed 85.67 seconds while its joined feature rows were ready in about 2.32 seconds; the projection serialized each wide V2 row to JSONB and reparsed the composite row. Treat that timing gap as evidence for the JSON conversion cost, not as proof from a single plan node alone.
- Copy the original V2 row directly into a transaction-local V3 output table, update only the V3 columns from a narrow computed table, and insert the completed composite row. Synthetic acceptance checks confirm inherited V2 fields and cross-batch equality.
- PostgreSQL 18 has no moving inverse transition for the float8 rolling regression and variance aggregates used by V3. Replace the 20/60/250-session floating windows with cumulative sums and fixed-offset differences. The synthetic assertion compares beta, idiosyncratic volatility, and Amihud outputs with the direct rolling aggregate reference.
- The 15-symbol feature batch fell from 87.63 seconds to 2.58 seconds. The 15/30/60 scaling exponent is 1.025. Evidence is in [`docs/evidence/phase2/v3_build_diagnosis.md`](evidence/phase2/v3_build_diagnosis.md) and [`docs/evidence/phase2/scaling_probe.md`](evidence/phase2/scaling_probe.md). The full-history V3 chunk run is now in progress on the disposable report clone.

## 2026-10-20 — stop the 2020 full-universe chunk at its timeout

- The retry of build `phase2-full-20261020` hit its 30-minute statement timeout while the full-universe symbol-batch map was being inserted. The error context identifies `SELECT DISTINCT r.symbol_id` joined across the 2.84M-row point-in-time cache and the 567-session temporary table; it does not establish that this inner operation consumed the full 30 minutes. Earlier notices in the same call report 8m17.8s for adjustment-cache creation and 14m42.5s for market context, far above the rollback probe's roughly 80s and 36–38s. The durable chunk record is `failed`; the transaction committed no 2020 V3 rows. Keep previously completed 2018/2019 chunks.
- The 15/30/60 exponent of 1.025 measured downstream feature batches with an explicit probe limit; it did not measure the no-limit symbol-population query and is not a full-build ETA. One `pg_stat_activity` sample saw `IO:DataFileRead`. The earlier cache plan shows about 3.34 GiB of temp reads and 3.42 GiB of temp writes; its excerpt is `docs/evidence/phase2/cache_plan_excerpt.md`. A cache-backed `EXPLAIN` attempt also exceeded twice the prior 80s cache estimate and was stopped before returning a plan. The exact full-run slow plan node remains unconfirmed.
- Do not retry full-history V3 until the cache, market-context, and no-limit population operations have bounded timings under representative conditions. The detailed run output and zero-row check are in [`docs/evidence/phase2/v3_build_diagnosis.md`](evidence/phase2/v3_build_diagnosis.md) and [`docs/evidence/phase2/full_history_retry_2020.log`](evidence/phase2/full_history_retry_2020.log). This re-plan keeps Phase 2 open; no success or ETA is claimed.

## 2026-10-21 — defer real-data E3 until history loading is batched

- The Rust offline suite passed six unit tests, including the independent seeded EMA golden vector. Its PostgreSQL integration test was skipped in that offline run. Evidence: [`docs/evidence/phase2/rust_tests_20261021.log`](evidence/phase2/rust_tests_20261021.log).
- A real-data parity attempt against the disposable clone sampled 20 rows across at most three dates but ran for 772.65 seconds without producing a comparison. The reference loader executes a separate `core.vndirect_bars_as_of_with_episodes` history query per market symbol/date. Two read-only test backends were canceled; follow-up found neither active. No database rows were modified and no mismatches were assessed. Record E3 as NOT RUN, not PASS or a feature mismatch; see [`docs/evidence/phase2/parity_real_20261021.md`](evidence/phase2/parity_real_20261021.md).
- Batch the as-of input history load before rerunning E3. The 20-symbol-day target still requires the full universe for ranks and market features, so the optimization must preserve those full cross-sectional inputs.

## 2026-10-21 — null-rate report attempt timed out

- The read-only `sql/diagnostics/phase2_feature_null_rates.sql` query ran against disposable database `vnsignal_phase2_report_20261019` with a five-minute statement timeout. PostgreSQL canceled it at line 327; the cause within the aggregate plan is not established. The output contains only the session `SET` and the timeout error, so it provides no null-rate measurements. The captured output and status note are `docs/evidence/phase2/null_rates_attempt_20261021.log` and `docs/evidence/phase2/null_rates_attempt_20261021.md`.
- E1 remains NOT RUN. This is not a full or partial null-rate report and must not be used as one. The query reads `feat.features_daily` rows with `feature_version='phase2-v3'`; no production database was used and no data writes were made.

## 2026-10-21 — stop local verification after environment overruns

- The two-pass migration harness was run against newly created disposable database `vnsignal_phase2_ci_20261021`. It completed migration 023 on the first pass, then a PostgreSQL client connection timed out before later migrations and assertions could run. The attempt log is `docs/evidence/phase2/phase2_migration_ci_20261021.log`. After confirming the database had no active sessions, the disposable test database was dropped. This is NOT RUN to completion, not a SQL test failure or pass.
- `go -C go test ./...` was started with UCRT64 GCC available and interrupted after more than five minutes without package results. No output artifact was flushed. Go vet, Python, the current-tree Rust clippy/tests, race checks, and hosted CI were not run in this verification pass. The test overrun is recorded as incomplete; it does not establish a code failure.
- Details and the remaining current-tree gates are in `docs/evidence/phase2/phase2_local_verification_20261021.md`. Do not push or sign off on Phase 2 while these gates and the real-data E1–E5 criteria remain incomplete.

## 2026-10-22 — make the VCI repair bounded and resumable

- Do not perform a table-wide V3 rewrite inside migration 044. Install durable run, frozen-context, and chunk state first; take one SHA-256-identified session-level VCI context snapshot; then repair at most 30 calendar days per transaction. Each chunk records attempts, row and changed-row counts, and an output hash. Resume by skipping `done` chunks, and keep failure updates in the same run-then-chunk lock order used by repair. This preserves the one-effective-session lag at chunk edges while keeping interrupted work recoverable.
- The fresh PostgreSQL 18.3 two-pass harness v7 passed the interruption/resume and idempotent completed-chunk assertions. The DDL-only migration was applied to disposable `vnsignal_phase2_report_20261019`; it did not touch registered `vnsignal`. Repair build `phase2-vci-repair-bounded-20261022` has committed 35/98 chunks (962,024 rows) through 2021-08-15, with 63 pending. The per-chunk state and hashes are recorded in `docs/evidence/phase2/phase2_vci_backfill_status_20261022.csv`.
- A concurrent autovacuum began cleaning estimated pre-existing dead tuples plus rows changed by the repair. It scanned all 448,516 heap blocks, completed index/heap cleanup, and one overlapping 30-day chunk took 323.74 seconds. The 63 chunks after that vacuum averaged 7.32 seconds (maximum 12.68). Autovacuum was temporarily disabled on `feat.features_daily` in the disposable clone during the remaining writes, then `VACUUM (ANALYZE)` completed in 520.92 seconds, reported zero estimated dead tuples, and the table's default autovacuum setting was restored. This table-local tuning was not a migration or production change. Repair build `phase2-vci-repair-bounded-20261022` is complete: all 98/98 chunks and output hashes cover 2,844,435 rows from 2018-10-01 through 2026-10-16, with one consistent context hash. Do not claim Phase 2 complete: one current V3 feature chunk, all labels, real-data E1–E5, and PIT fundamentals remain open.

## 2026-10-22 — repair the V3 selected-symbol CTE reference

- The real 2026 V3 chunk failed after its input hash, adjustment cache, market context, and rank stages completed. The stored error was `relation "symbols" does not exist`; `ops.feature_chunks` records the attempt as failed with a 139,501 ms duration and no committed row count. Runtime function inspection found that migration 045 replaced the `symbols` CTE with `eligible_symbols` but retained `SELECT symbol_id FROM symbols` in `selected_symbols`. Fresh migration tests did not catch the upgrade-only mismatch because migration 037 already contained the renamed CTE.
- Preserve migration 045 and add migration 046 to rewrite the old downstream reference idempotently. Add a function-definition assertion and retain the existing synthetic multi-batch builder test. The fresh PostgreSQL 18.3 two-pass migration harness v8 passed in `vnsignal_phase2_ci_20261022_v8_test`; evidence is `docs/evidence/phase2/phase2-migration-harness-v8-20261022.md`.
- The report-clone runner refuses to proceed because the clone has a stale checksum for migration 034. Do not rewrite migration history to bypass that check. No ledger entries were changed; apply only the new additive 046 SQL directly to the disposable clone and verify its function definition. This does not modify registered `vnsignal`. The real 2026 retry and all label/E1–E5/PIT gates remain open until measured.
## 2026-10-22 — corrected 2026 V3 feature chunk completed

- The additive migration 046 CTE repair completed the previously failed `2026-01-01`–`2026-10-16` chunk on disposable report clone `vnsignal_phase2_report_20261019`. Durable state is `done`, 292,290 rows, 730,650 ms, output SHA-256 `5ff467f883e607634c0630ef5458d569d077a8ee6e967b5d7760a0ff1d0c46b2`; all nine feature chunks sum to 2,844,435 rows. V2 and V3 each cover 2018-10-01–2026-10-16 with 2,844,435 rows.
- The chunk log shows all 26 symbol batches had equal base and computed row counts. The 1,194-session market context took 2m07.262s, ranks took 2.906s, and feature batches mostly took 12.7–21.8s. The current stage no longer fails at `selected_symbols`; the repaired function reached the final batch and committed.
- The cache probes were 50.730s, 50.870s, and 47.290s for 15/30/60 symbols (exponent 0.004; full-cache projection 22.10 minutes). The cache loaded 2,844,435 rows in 25 reported fills. Runtime and live-database observations are captured in `docs/evidence/phase2/phase2_v3_2026_feature_recovery_20261022.md`; full runner output is preserved in `docs/evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021_features_20261022.log`.
- Labels remain pending. Do not close Phase 2 until label construction, availability-aware E1, real E2–E5, PIT coverage review, current-tree tests, and hosted CI are complete.
# 2026-10-22: repair probe transaction boundaries and full-market E2 inputs

The first rank recovery probe passed the 30- and 60-session samples, but its
120-session sample timed out in a later chunk's non-rank hash. PostgreSQL
reported disk-read waits; the host has 4,017,764 KiB visible RAM and only
311,516 KiB free at inspection. No trial repair rows or completion records
committed. The actual hash plan uses the date/version bitmap index, rather than
a per-row archive expansion. The failed probe is evidence of an unresolved
runtime problem, not acceptable scaling evidence.

The probe originally held every chunk for an N-session sample in one outer
transaction. Real repair commits each bounded chunk independently. The probe
now uses the same one-chunk transaction boundary, rolling each chunk back and
verifying its output/audit rollback before moving on. Its total measured
repair time is summed across those chunks; the 30/60/120 sizes and b<=1.3 gate
are unchanged. Default work_mem is 16 MiB for this 4 GiB machine. The repair
certificate pins memory, timeout, transaction policy, database, build ID, and
SQL definitions, and is invalidated before a new probe begins. Vacuum of the
report-clone feature table is recorded separately. See the rank probe log,
`phase2_rank_hash_plan_before_vacuum_20261022.log`, and
`phase2_rank_probe_vacuum_20261022.log` under `docs/evidence/phase2/`.

E2 previously used unchanged persisted non-cohort V2 rows as full-market
context. That could hide future dependence outside the 60-symbol cohort.
Migration 055 generates a narrow market-input function from the canonical
production V2 CTE chain and its exact final expressions, including session,
episode, first-invalid-factor, and null guards. It rejects production-definition
drift. No alternate feature equations are maintained in the fixture. Both E2
branches now use full-universe branch-specific raw rows; every post-cut equity
and index input is perturbed in the modified branch. The identical baseline
projection is materialized once across cuts; every perturbed projection is
recomputed. The selected output and rank cohort remains 60 symbols.

The projection fixture passes exact binary comparison against freshly rebuilt
production V2 output, pre-cut binary invariance, changed non-cohort post-cut
support, and rejection of production-definition drift. Its evidence is
`phase2_market_projection_assertions_20261022.log`. This is fixture evidence;
the corrected real E2 has not yet passed. Phase 2 remains open.

### 2026-10-22 — Measure S2 rank scaling without repair writes

The Phase 2 recovery prompt defines S2 as market-wide ranks over 30, 60, and
120 dates. The previous probe timed the full repair function and rolled it back.
That comparison is contaminated: PostgreSQL retains dead tuple versions after
an update is rolled back. The report clone then showed 393,406 estimated dead
tuples and 396,278 updates, while the 30/60 repair timings were 34.303442 and
151.062488 seconds (apparent exponent 2.138720). The 120 sample was stopped
after one verified chunk and one cancelled chunk; there are no committed probe
audit rows or active probe sessions. These timings are retained as diagnostic
evidence, not accepted as the S2 scaling result.

The S2 gate now warms the largest date window once and times only
`feat.phase2_cross_sectional_ranks` in read-only transactions at 30/60/120
effective sessions. The 1.3 exponent limit is unchanged. Full repair is
measured and executed separately in bounded monthly transactions, so its
rollback side effects cannot alter later S2 samples. The report clone is
vacuumed before remeasurement; the registered `vnsignal` database is not used.
Evidence: `docs/evidence/phase2/phase2_rank_probe_methodology_20261022.md`.

### 2026-10-22 — constrain rank repair updates to the monthly slice

The first 2025-03 repair attempt reached 139.483 seconds with PostgreSQL
waiting on `IO:DataFileRead`, so it was cancelled and durably recorded as a
failed attempt. Read-only component profiles took 2.749 seconds for ranks and
2.568 seconds for the panel hash. The original update plan scanned the small
expected-row table and performed about 31,000 primary-key lookups against the
full feature table. An `EXPLAIN` of the same update with the already-known month
bound on the target selected a bitmap heap scan using
`features_daily_date_version_idx` followed by a hash join. This bounds the
target rows without changing rank values or eligibility.

Migration 056 applies that date predicate to both V2 and V3 updates, and the
fixture assertion requires both predicates to remain. The PostgreSQL migration
harness passed on a new disposable test database. The report-clone March retry
committed in 36.354 seconds after a fresh passing S2 certificate was recorded.
Subsequent repairs resume from the next durable month. Evidence includes
`phase2_rank_update_plan_2025-03_date_default_20261022.log`,
`phase2_rank_update_plan_2025-03_alternatives_20261022.log`,
`phase2_rank_component_profile_2025-03_20261022_retry.log`, and
`phase2_rank_probe_phase2-rank-repair-055-20261022.json` under
`docs/evidence/phase2/`.

### 2026-10-22 — lifecycle identity diagnostic correction during E4

**Correction:** The KTL→PTM and TSB→CTR mismatch claims below came from a
diagnostic join between `core.symbols.symbol_id` and the separate
`core.security_master.security_id` domain. The source-attribution CSV and TSB
bar check were stale and incorrect. The corrected queries join lifecycle
evidence, bars, and features through `core.symbols`; security observations are
crosswalked through the ticker. They show that CTR evidence references CTR
landings and PTM evidence references PTM landings. The apparent five TSB bars
are five CTR VCI rows inside CTR's UPCoM-to-HOSE transition. This correction
supersedes the factual findings in this decision entry. E4 remains open because
219 other continuity gaps are still unresolved. See
`docs/evidence/phase2/phase2_e4_id_domain_correction_20261022.md`.

The decision to require matching ticker identity between a lifecycle event and
its source landing remains valid. Keep these source-identity and cross-ID
domain checks in diagnostics; do not classify any gap from a direct join of
`symbol_id` to `security_id`.

### 2026-10-22 — fail closed on mismatched lifecycle evidence during E4 (superseded)

This historical entry records the initial finding, which is superseded by the
correction immediately above. Do not rely on its KTL/TSB attribution or its
TSB bar-check result. The general rule remains: do not attribute a feature-session gap to a delisting, relisting, or
suspension unless the evidence is keyed to the same security as its source
landing. The read-only report-clone review found 219 of 221 gaps with no daily
bars or archived source rows. The two apparent lifecycle matches are
mismatched: KTL evidence references PTM source landings, and TSB evidence
references a CTR source landing. TSB also has five identical VCI-traded bars
inside the alleged delisting interval, without source-archive rows or feature
rows. Keep E4 open and reconcile source identity and bar lineage before
reclassifying these gaps. The registered database was not changed. Evidence:
`docs/evidence/phase2/phase2_integrity_gap_attribution_20261022.csv`,
`phase2_lifecycle_source_attribution_20261022.csv`, and
`phase2_tsb_lifecycle_bar_check_20261022.csv`.

### 2026-10-22 — split real E2 into bounded cut checkpoints

Do not accept partial leakage evidence. The real E2 SQL currently runs the
40%, 70%, and 95% cut cases inside one statement and repeats full-history
market-support projection for perturbed branches. The report-clone attempt
materialized 2,844,683 VNDIRECT adjustment rows, passed cohort selection, and
reached the first cut's perturbed V3 rebuild, but produced no cut comparison
before cancellation at 1,710.475 seconds. The transaction rolled back and no
branch schemas remain. Before retrying, split the cases into bounded
checkpoints and reuse a verified baseline projection where raw inputs are
unchanged; retain the 60-symbol, separate-branch inputs, three cut dates,
bit-identical pre-cut outputs, changed post-cut outputs, and label-boundary
assertions. Evidence: `docs/evidence/phase2/phase2_e2_real_attempt_20261022.md`
and `phase2_e2_real_20261022_retry2.log`.

### 2026-10-23 — Phase 2 real-gate scope and disposition

Use a point-in-time-stratified 60-symbol cohort (five symbols per exchange and
liquidity stratum) for real-data feature and label comparisons, while retaining
the full-market support projection so cross-sectional and market inputs remain
in scope. Exercise independent 40%, 70%, and 95% future cutoffs; perturb future
equity and index prices and positive volume in both directions by at most 20%;
require byte-identical pre-cut features, completed labels, and label boundaries,
plus crossing labels and changed post-cut features. Run the branches in one
outer transaction on the disposable report database and roll it back. All three
cutoffs passed on 2026-10-23; the durable evidence is the E2 log cited in
`docs/BUILD_STATUS.md`. This sampled real-data gate is not a claim of exhaustive
per-symbol parity; E3 separately passed 20 deterministic symbol-days.

Interpret the Phase 2 null-rate exit as “report produced,” as specified in
`docs/MASTER_BUILD_SPEC.md` §13. Do not convert the diagnostic's 1-point
lookback deviation into a blocking threshold: the spec calls null-rate shifts
warnings and does not set that limit. Keep the unverified-field and cell-level
availability attribution work visible as data-quality follow-up; a passing E1
report does not certify every NULL as expected.

### 2026-10-23 — current-tree E2 and E5 recovery recheck

Re-run real E2 after migrations 058 and 059 changed label availability and
training eligibility. The old three-cut pass is not evidence for the current
label definition. Preserve the 60-symbol cohort, full-market support, separate
future-perturbation branches, and all three cutoff checks. The final V2
candidate keeps native averages and standard deviations while computing exact
250-session extrema with block prefix/suffix windows. A five-run synthetic
probe at 15/30/60 symbols × 2,000 rows measured integrated medians 25–31% below
direct windows and a 0.952 scaling exponent, but that synthetic gain does not
establish real E2 performance.

Migration 064's first report-clone replay exposed stale aggregate dependencies;
after cleanup, the first real retry exposed an incomplete CTE replacement
because PostgreSQL's `n` regular-expression flag would not cross line breaks.
The migration now uses `s`, rejects an unmatched rewrite, and verifies that
the projection retains `session_no`, `is_traded`, and extrema fields. The
corrected function projection check and numerical extrema fixture passed on
the disposable clone. In the corrected E2 run, the current-hash baseline's
V2/V3 build took 1:40.811 and the whole baseline stage took 4:00.206. The 40%
branch setup copied and perturbed inputs successfully, then the V2 rebuild
remained CPU-active for 12:45.856 without reaching a feature/label comparison.
It was canceled and the outer transaction rolled back. E2 is still **NOT
PASS**; no 70% or 95% cut ran. Do not weaken the pre-cut invariance,
crossing-label, changed-post-cut, or label-boundary checks. Further production
profiling or optimization is required before another full E2 attempt. Evidence:
`docs/evidence/phase2/phase2_e2_real_20261023_103110_365.txt`,
`docs/evidence/phase2/phase2_v2_window_scaling_final_20261023.txt`, and
`docs/evidence/phase2/phase2_e2_performance_gate_20261023.md`.

Rebuild the 2023 E5 label chunk under the current hash. The first run completed
720,718 rows in 367.240 seconds. An initial forced repeat was interrupted
early; a clean retry was allowed to run until the label-build statement
reached 753 seconds, just over twice the first step duration, without
completing. After the local interrupt, the backend ended before a follow-up
`pg_cancel_backend` could target it. The original `ops.feature_chunks` row
remains `done`; the repeat row is `pending`, with no repeat `ops.step_runs` row
or output hash and zero Phase 2 database sessions. Classify current-hash
reproducibility as **inconclusive**; the historical pre-058 repeat does not
satisfy it. Preserve both run outcomes in
`docs/evidence/phase2/phase2_e5_m058_rebuilds_20261023.md`.

The missing-session guard and training-gap eligibility fixture assertions now
pass through migration 059 on a clean two-pass PostgreSQL harness. The policy
excludes affected labels from training while leaving raw feature/label lineage
intact; it does not resolve the 219 real unexplained gaps. Keep those gaps
unclassified until source evidence exists, and do not claim recovery complete
until the current E2, E5 reproducibility, and recovery-prompt label outputs are
closed. At the time of this entry, the date-wise winsorization, volatility
scaling/floor, PIT liquidity tiers/ranks, and price-limit execution weights
were not implemented; their subsequent authored-but-unverified status is
recorded in the later derived-label decision below.

### 2026-10-23 — bounded raw-source census for unresolved E4 gaps

On the disposable report clone, inspect only the 1,539 effective sessions
listed in the corrected 219-gap attribution CSV. The exact-date census found
12 valid-OHLC row occurrences across six dates and four symbols, represented
by eight VCI `equity_ohlcv` landings. All rows have zero volume; there are no
VNDIRECT rows or positive-volume observations. Their OHLCV fingerprints are
duplicates. No matching canonical/alternate-source bars or historical listing
snapshots were found. Do not merge these VCI records into the VNDIRECT adjusted
feature series or classify the intervals as suspensions. Keep all 219 intervals
unresolved and E4 **NOT PASS** until source or ticker-matched lifecycle evidence
supports a classification. The input and output hashes, scope, and counts are
recorded in `docs/evidence/phase2/phase2_e4_raw_census_20261023.md` and its CSV.

### 2026-10-23 — derived label ranks and eligibility

Keep `feat.labels_daily` raw rows and their existing hashes unchanged. Store
recovery-prompt derived outputs in the durable, bounded
`feat.phase2_label_targets_v3` chunk table, with a separate attempt ledger and
deterministic derived-target chunk hash. The Master membership rank is
median-20 `turnover_proxy_vnd` over 20 valid sessions, gated by at least 250
strictly prior positive-volume VCI sessions and average-20 proxy of at least
VND 5 billion. Enter at rank 400 and retain an existing member through rank
500. The canonical VCI `core.bars_daily` schema stores `ingest_id` and
`fetched_at`, but no source landing ID or row ordinal. A disposable-clone audit
reconstructed exact row provenance for 1,810,727 of 1,810,729 canonical VCI
bars by matching the same ingest, ticker and date, exact OHLCV, and the SHA-256
of the archived response bytes. It found two unmatched positive ABR bars on
2018-10-16 and 2018-10-17, with no corresponding rows in the archived ABR VCI
payloads; no bar had ambiguous exact matches. Of 1,505 symbols, 1,321 have at
least 250 unique exact, positive-volume VCI sessions before 2026-10-17; ABR is
the only symbol with unmatched positive sessions, and those rows are excluded
from its count. See the [lineage audit](evidence/phase2/phase2_vci_source_row_lineage_audit_20261023.md)
and its [`SQL`](evidence/phase2/phase2_vci_source_row_lineage_audit_20261023.sql).
This establishes that exact tenure evidence can be derived for the matched
bars, but migration 061 still hardcodes `verified_listed_sessions` to NULL.
Until the builder consumes a durable, hashed lineage materialization, real
membership and tier outputs remain unverified; keep the two ABR rows unknown
and do not infer tenure from first observed bars.
Membership rank20 and recovery tier rank60 are separate fields. Tier rank60
uses the 60-session median among eligible top-400 members, with L1 1–100,
L2 101–250 and L3 251–400. Retained membership ranks 401–500 remain in scope
but have no tier label/rank. The rank input remains adjusted-close ×
reported-volume research estimate `turnover_proxy_vnd`; it is not
source-reported or executed turnover.

Keep the recovery target rank distinct from the liquidity position rank. For
each signal date, horizon and L1/L2/L3 tier, order non-NULL volatility-scaled
scores from highest to lowest, break exact score ties by ascending
`symbol_id`, and store `(target_rank_in_tier - 0.5) / target_tier_count`.
`tier_uniform_rank` remains the within-tier liquidity position; the new
`target_uniform_rank` is the score-based Phase 3 rank target. Raw winsorized
excess return remains available separately for quantile heads.

Rebuilding a prior derived-label chunk invalidates all later target and
membership-state rows because hysteresis carries forward; matching completed
derived-chunk ledger records are marked invalidated, and later chunks must be
rebuilt chronologically from a complete immediate-prior state checkpoint.
The production E5 runner includes derived-target inputs in its input hash and
compares a combined raw-label/derived-target output hash before skipping a
completed chunk. Exact execution weights are available only where every effective
session in the inclusive entry-to-exit interval has a source-row-linked
unadjusted VNDIRECT bar and exact archived ceiling/floor observation. Entry
open at ceiling yields 0; a fully locked OHLC row at either exact limit on at
least two sessions yields 0.5; otherwise complete evidence yields 1. Missing
exact evidence yields NULL. No configured percentage or generic band is
substituted. The migration harness and fixture assertions pass on a fresh
disposable PostgreSQL database, but real-data derived-target chunk outputs
remain **NOT VERIFIED**. The report clone has no archived price-limit or
listed-share observations needed to verify execution weights. VNDIRECT Finfo
does not expose listed shares in the inspected row contract; no listed-share
history is inferred.

### 2026-10-23 — official-source findings for E4 transfer windows

The archived evidence packet in
`docs/evidence/phase2/hose_transfer_sources_20261023/` contains the HNX
cohort notice and ticker-specific HOSE first-trading-day notices for all 13
HNX-to-HOSE transfer candidates in the E4 gap report. These notices support
transfer-window explanations for 40 missing effective sessions: 12 symbols
from 2021-08-30 through 2021-09-01, and PAN through 2021-09-06 before its
2021-09-07 HOSE first-trading day. The manifest records source URLs, hashes,
and byte counts. This supersedes the earlier research entry that had only four
paired endpoints.

The files are saved in the repository but have not been imported into
`raw.landings`; the lifecycle schema also lacks a transfer event type. Do not
encode these notices as `TRADING_SUSPENDED`. Keep the 13 intervals
unclassified until the event semantics and ticker-matched archive path are
implemented and the report-clone attribution query is rerun. The other 206
intervals, covering 1,499 effective sessions, remain without supporting
evidence. E4 is **NOT PASS**. See
`docs/evidence/phase2/phase2_e4_hnx_hose_transfer_research_20261023.md` and
`docs/evidence/phase2/hose_transfer_sources_20261023/README.md`.

### 2026-10-23 — bounded 40% E2 performance diagnostic

Repeat only the 40% future-perturbation branch on the disposable report clone
with `work_mem=128MB` and JIT disabled. The current-hash baseline completed in
3:58.300, including a 1:41.652 V2/V3 rebuild and the label rebuild. The branch
setup copied 117,551 cohort equity rows and perturbed 72,208 equity and 1,204
index rows. Its V2 rebuild then ran for 20:10.797 without reaching a stage
completion notice or comparison. Cancel the diagnostic at that bound; the
`psql` process exited after cancellation, the transaction rolled back, and a
follow-up check found no active database sessions. Temporary-byte accounting
increased by 568,762,368 bytes, but no analyzed plan was emitted. This setting
reduced spill relative to the 16 MB/JIT-on probe yet did not solve the CPU-heavy
V2 rebuild. Current E2 remains **NOT PASS**; do not run all three cuts until a
parity-checked production fix is established. The exact diagnostic inputs and
output are preserved in
`docs/evidence/phase2/phase2_e2_40_profile_128mb_jit_off_second_20261023.sql`
and `.log`.

### 2026-10-24 — canceled full-cache date-order diagnostic

The corrected staged-cache plan and 12-session aggregate show that price-day
hashing can issue many local heap reads from the current symbol-batch cache
layout. A rollback-only attempt to copy the full 2,844,435-row cache in date
order was still waiting on `IO:DataFileRead` after 3:29, while the host had
237 MiB free of 3.83 GiB. The copy was canceled, its transaction rolled back,
and the backend exited. The attempt produced no reordered hash comparison and
did not change persistent data. Keep the existing hash semantics; do not adopt
whole-cache physical reordering based on this result. A separate per-batch
probe instead inserted the same 2,844,435 rows ordered by date and symbol
within each 60-symbol batch. On 60 effective sessions this reduced the hash
query from 23.855s to 1.855s and local block reads from 82,419 to 1,864; all 60
day hashes matched exactly. Cache insertion increased from 75.04s to 99.09s
across 26 calls, while finalization remained about 15s. Adopt this bounded
date-local insert order in a forward-only migration, then rerun the fresh
two-pass harness and full 1,206-date hash checkpoint before retrying E1. This
probe does not complete E1. Evidence is in
`docs/evidence/phase2/phase2_hash_date_order_probe_20261024.md` and its paired
`.psql`/`.log` files, plus
`docs/evidence/phase2/phase2_hash_batch_order_probe_60d_20261024.md` and its
paired `.psql`/`.log` files.
### 2026-10-24 — bounded memory and configured label execution policy

The full 1,206-date canonical hash checkpoint passed with 15-symbol insertion
batches, 8 MB work memory, and 16 MB maintenance memory. Preserve these measured
settings for the report-clone recovery; the runner now exposes maintenance
memory explicitly. This changes execution strategy and preserves source and
hash semantics. Full V3 and E1 are still open.

Execution weights are now explicit configuration. The runner reads the strict
TOML profile through vnpipe label-policy, captures it once per run, and applies
transaction-local SQL settings before input hashing. Standalone SQL callers
read an explicit configurable defaults row seeded to the existing 0/0.5 policy.
The effective canonical JSON policy enters the label input hash and durable
chunk/step metadata. Missing evidence remains NULL; entry-ceiling precedence
is preserved. Targeted SQL, replay, default-label and CLI override checks pass;
fresh full migration replay and real runner metadata remain unverified.

## Cache probe accounting audit — 2026-10-24
Migration 071 changed the 15/30/60 samples to use the selected production batch size. The assertion inherited from 042 still projects each sample as if its total time were one batch. At configured size 15, t60 already contains four fills plus one finalization; multiplying its scaled duration by the universe batch count double-counts work. This is a projection defect, separate from the observed exponent failure. The failed preflight remains failed; neither threshold nor sample timings have been altered. A correction must distinguish setup, fill, and finalization measurements and match the chosen production strategy, preserve the 1.3 exponent and budget guards, retain raw samples, and fail closed on incomplete or unstable evidence. No performance pass is inferred from the helper-only plans.

### Cache projection correction (migration 072)
Whole-strategy samples now normalize to complete production batches before multiplying by the universe batch count. A sample with a partial final batch divides by floor(sample_symbols / batch_size), attributing all partial-batch and setup/finalization cost to complete batches; this is conservative. A production batch larger than a sample extrapolates at least linearly. The maximum normalized sample cost is used. The 1.3 adjacent exponent guard, inconsistent-timing rejection, configuration matching, universe minimum, and configured budget rejection remain unchanged. This corrects arithmetic only; it does not establish stable benchmark evidence or fix the current exponent failure. Full-universe index/finalization cost still needs measured runtime evidence; the estimate is not a guarantee.

## Growing-cache delete scans (migration 073) — 2026-10-24
The isolated 072 preflight passed (550/1122/2490 ms, exponent1.150, projected1.06min), but full-cache fills accumulated164.287 seconds by batch95, exceeding twice the estimate. Cancellation was requested; by delivery all102 batches had loaded and the backend was in final ANALYZE. The cache transaction rolled back; no feature result is claimed. The log preserves this failure.

Inspection found an unconditional DELETE against the unindexed growing temp cache before every first load. Disjoint manifest symbol batches and statement-atomic insert/loaded updates make this deletion unnecessary for never-loaded batches. Migration073 performs deletion only when that batch was already loaded. Retries still replace their prior rows and date manifest. This removes quadratic cumulative first-load delete scans; it does not prove that every observed slowdown had that cause or that finalization is fast enough. A new runtime assertion uses transaction scan counters to prove two first-load batches scan no cache rows, and a retry does scan/delete its old rows; final unique-index creation and duplicate checks also pass. Existing full row parity and date-manifest retry assertions remain in the harness.

### Cache benchmark reproducibility investigation — 2026-10-24
PostgreSQL18 pgbench Good Practices (https://www.postgresql.org/docs/18/pgbench.html) recommends longer runs and checking repeatability because second-scale runs can be dominated by noise. The isolated073 preflight still failed exponent1.638, with a30-symbol finalization696ms versus367ms for60. A fixed balanced nine-sample diagnostic yielded acceptable median exponents but29.69% CV for15-symbol timings; this is not taken as a pass. A fixed90-sample rollback-only diagnostic now retains all raw timings and three blocks with ten samples per size. Its purpose is to distinguish stable scaling from measurement noise before changing the protocol. Production thresholds are unchanged. No result is inferred until terminal output is inspected.

## Fixed cache measurement protocol (migration074) — 2026-10-24
Use90 predetermined balanced measurements after fixed warmups, all retained with configuration. Each size contributes30 timings to an arithmetic mean (rounded up), with three10-sample blocks checked for stability (CV<=20%). This replaces a single noisy observation; it does not change the1.3 exponent limit or time-budget guard. Reject inconsistent counts/configuration and unstable blocks. This protocol was selected after the fixed long diagnostic showed block reproducibility; no repeated-until-pass selection is allowed. The diagnostic itself had a trailing file-read error after rollback caused by editing a comment during execution; retain its nonzero outcome. Required command success must come from the tested implementation, not that diagnostic. See evidence/phase2/phase2_cache_repetitions_074_20261024.md.

### Local Serena cleanup persistence — 2026-10-24
A five-process Serena launcher/server/Python chain reappeared without an explicit Serena tool call during the fixed benchmark. It was stopped per user instruction. Local Codex config C:\Users\HP\.codex\config.toml had an automatically enabled mcp_servers.serena entry; enabled=false was added (backup retained beside config), parsed successfully, and zero Serena processes remained. This is a reversible local preference change, not a repository dependency change. Official config reference supports disabling a server without removing its configuration: https://learn.chatgpt.com/docs/config-file/config-reference. The active074 benchmark was disturbed by process cleanup and must retain that environmental fact; do not represent it as an undisturbed measurement.

## Invalidate cached input hashes on cache mutation (075)
The074 schema retained day hashes/coverage after refill and batch-date manifests after reinitialization. A red regression reproduced stale evidence. Resetting the cache generation must invalidate all derived hash evidence; a batch refill does likewise. 075 clears only owned session-local hash/coverage tables and resets the date manifest on begin. This is a correctness correction, not a performance-guard change. No feature equation or source-market table is changed.

## VCI lineage observations (076)
Persist versioned exact-row provenance with byte integrity and explicit unresolved outcomes. Include sorted requested scope and algorithm in batch fingerprints, including empty scopes. Enforce append-only observations and batches for row mutations and truncation. These snapshots are provenance evidence only; continuous legal identity, listing tenure and historical availability require separate contracts and current-input validation.

### Serialize heavy real-data work on this machine
Concurrent full-lineage archival and feature building produced sharp feature-batch delays. Stop the lineage statement with PostgreSQL cancellation, preserve each prior committed bounded batch, verify backend termination, and resume serially after the feature workload. Cancellation is retained as exit3 evidence, never reported as a full archive pass.

### Fundamental ticker attribution from provider and request
The generic adapter whitelist discarded provider symbol metadata needed by the archive. Fundamental responses now retain a normalized symbol bound to the exact equity request, record requested_symbol/requested_period and symbol_basis, and reject any supplied provider ticker that conflicts. Provider absence is explicitly request-based, never a provider claim. Actual FPT ingestion used provider_and_request attribution. No statement IDs, units or financial values are inferred.

### Accepted offline-replay provenance (077)
Immutable quarantine routes survive legitimate offline recovery. Extend lineage through the exact recorded job/landing and latest reviewed recovery audit, preserving original route and recovery snapshot in versioned input evidence. Never blanket-accept quarantine. Keep v1 observations and create v2 observations; legal listing tenure remains separate. Run fresh full SQL checks and archival serially after the feature workload; queued inputs are fingerprinted to prevent silent drift.

### Actual frequency evidence and refresh idempotence
A statement-family probe must verify requested quarter/year frequency and nonempty bounded rows; annual permission is not inferred from quarterly success. Observed jobs are keyed by Vietnam observation day so weekly collection can continue after a completed run, with same-day retries spending no second vendor request. Actual fetch timestamps retain financial availability; historical backfill keys remain stable.
### Fundamental overlay population (078)
Use the current-hash V3 cohort in both signal and event-date selection, and include its hash in overlay mapping identity. Unknown industries cannot become a synthetic peer group. Source IDs, accounting basis, valuation numerator/denominator treatment and industry mappings still require explicit evidence before activation.

## 2026-10-24: durable local continuation and parent valuation inputs

An execution-host interruption killed both child processes while their status
files said running. OS process identity and PostgreSQL activity establish actual
liveness; committed quarters are reused only after input-hash validation. A
triggerless temporary Windows task owns the feature run and synchronous database
follow-up. Its encrypted handoff file is Git-excluded with a user-only ACL;
remove it and the task after completion.

P/E and P/B require explicit parent profit and equity mappings. Group PAT/equity
remain consolidated ratio operands and cannot replace missing parent inputs.
Migration079 persists the valuation inputs and adds a formula identity tag.
Real mappings require verified source semantics before activation.

## 2026-10-24: explicit legal listing episodes, migration 080

The exact VCI row archive proves price provenance, not legal listing tenure.
Membership tenure now has its own reviewed legal notice ledger, with explicit
admission identity, cessation and documented transfer continuity. A suspension
remains legally listed. Counts use true sessions strictly before signal; known
closed episodes/gaps are ineligible and unresolved evidence remains indeterminate.
PIT corrections are append-only and do not revise earlier knowledge. Original
PDF/HTML bytes and separately reviewed metadata remain distinct; verified
historical publication requires source review. No current-profile or first-bar
backfill is authorized by this change. No real events have been populated.
Indexed session prefixes avoid full calendar scans per candidate, and all prior
calendar/event/correction history invalidates label checkpoints. This replaces
the provisional expectation that exact VCI bars alone could unlock tenure.

Migration080 review additionally covers same-day closure/readmission and isolates
prefix optimization to an explicit internal builder call. A captured historical
issuer article is raw source evidence; its displayed old date alone is not proof
of original-page vintage or complete subsequent legal continuity. The FPT2015
article was archived idempotently but did not create a real listing event.

## 2026-10-24: timestamped overlay classification, migration 081

A date-only listing snapshot cannot establish pre-close availability. Fundamental
bank classification and industry ranks now consume latest timestamped security
observations visible by15:00, with conflicts and unknowns left NULL. Observation
IDs, availability and original landings are retained in overlay lineage and its
input manifest. The running V3 price build has no such snapshot lookup and is
unaffected. Dedicated synthetic cutoff/conflict/hash checks and existing overlay
assertions pass; full fresh harness remains queued.

## 2026-10-24: branch candidate and evidence byte preservation

A three-day-old zero-byte Git index lock had no active Git owner; it was removed
after process/mtime verification. All CI-required Rust, SQL, Python, Go and ops
sources are included in the candidate. Runtime credential state and scratch
outputs are excluded. Archived evidence uses `-text -whitespace` attributes so
Git preserves original source line endings and database output padding; source
whitespace errors were corrected. An original FPT HTML blob was checked against
the staged raw blob before commit. A local scan found no database password text
in candidate source/evidence directories.

Commit68f44cb60f2f4231df4418365ea8773c6dadc8b5 was pushed to phase2-evidence and
draft PR1 opened. The offline workflow is queued; main merge still requires
complete real-data exit evidence and green CI. No readiness claim is made from
this dispatch.

## 2026-10-24: correct the tenure proof scope

Review found that080 made a legal admission ledger mandatory beyond the Master
Spec and the18October sufficient lower-bound decision. Retain its exact/legal
path and known-conflict protections, but implement an alternative qualified
execution lower-bound path. >=250 verified positive public-market dates can
prove the minimum; fewer cannot prove ineligibility. VCI rows lack dated venue
metadata in this archive; native VNDIRECT rows have code/date/type/floor and
matched volume, empirically reflecting ACB's historical exchange change. Require
exact immutable source/canonical checks and an explicit identity/conflict
contract; never invent publisher guarantees or use unknown source attributes.
This correction is planned, not yet a successful gate. Full tests, real coverage
and CI must prove it before Phase2 signoff.

### 2026-10-24 — Public execution minimum tenure evidence

Restore the accepted sufficient >=250 prior public-execution lower bound alongside 080 exact legal episodes. Require intact native VNDIRECT bytes and exact canonical code/date/pointer/raw OHLC/matched volume, STOCK type and dated public venue agreement. Keep fewer-than-250 observations unknown, fence known lifecycle contradictions, and identify the persisted proof basis. Do not promise an ISIN identity absent from the provider contract. Reconstruct public event availability at next local midnight while preserving later capture/observation timestamps; this is not contemporaneously archived vendor-vintage evidence. Final approval requires full synthetic and real-source validation and new green CI. See the 082 review evidence.

Enforce LF for SQL source with .gitattributes: function-body migration anchors must replay identically on Windows and hosted CI.

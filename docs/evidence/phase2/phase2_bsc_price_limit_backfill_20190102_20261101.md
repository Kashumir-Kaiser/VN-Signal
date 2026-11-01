# BSC historical price-limit backfill — 2019-01-02

## Result

Migration 106 and its batch-refresh overload were applied to the disposable
report clone `vnsignal_phase2_report_20261019`. The import contains 834 exact
BSC/VNDIRECT matches for 2019-01-02. Their close, matched volume, source rows,
landing payload hashes, and price-limit fields passed the migration's source
and lineage checks. BSC price limits are used only to materialize execution
labels; they are not feature inputs and do not replace VNDIRECT bars.

The current-hash label windows whose entry-to-exit window contains 2019-01-02
number 14,866. Batched recomputation populated exact execution weights for all
14,641 windows whose symbol has an imported BSC observation. No window with a
matching BSC observation remains null, and no window without that observation
received a non-null weight.

The remaining 225 windows are 31 symbols whose BSC responses were quarantined
because their reported close conflicts with the archived VNDIRECT bar. For all
31, BSC matching volume equals VNDIRECT volume and BSC reference price equals
the VNDIRECT close, but the BSC closing price differs. BSC reports zero
matched volume for 28 symbols; the other three (BSL, DND, and SGP) have positive
matched volume and still have conflicting closes. KHP's BSC close is zero and
therefore invalid. Reference-price agreement does not reconcile these close
conflicts: the execution label uses the VNDIRECT OHLC path, so these BSC limits
cannot safely establish whether that path touched a limit. No rows were
imported and the affected execution weights remain null. This is an evidence
gap, not a zero weight or a claim that execution was impossible. The
ticker-level residuals are in the post-refresh audit log.

The quarantine also retains an earlier timeout for BTW, but BTW is already in
the validated 834-row capture. The timeout-retry helper previously selected
that stale quarantine entry, skipped its completed capture, and then failed a
zero-row count check. The helper now removes already-captured symbols before
counting retries and exits cleanly when none remain; the [no-op retry check](bsc_price_limits_20190102/bsc_timeout_retry_noop_fix_20261101.log)
confirmed the capture and quarantine hashes stayed unchanged. The original
false-failure log is preserved at
[`bsc_timeout_retry_20261101.log`](bsc_price_limits_20190102/bsc_timeout_retry_20261101.log).

## 2026-11-02 official HNX/HSX source review

The official HNX UPCoM price-fluctuation report returned one exact-date row for
each of the 27 UPCoM residual symbols. The archived comparison shows reference,
ceiling, floor, and close match the quarantined BSC rows for all 27. BSC volume
is zero for 24 and positive for BSL, DND, and SGP; the HNX report has no volume
field and reports open, high, and low as unavailable for all 27. HNX corroborates
the price bands but cannot verify the VNDIRECT executable OHLC path or traded
volume.

The official HSX VNUTI quote report includes KHP and confirms its reference,
ceiling, floor, and zero matched volume. Its open, high, low, and close fields
are zero. The tested HSX report returned no rows for AFX, PVP, or TCI, but the
Swagger contract does not define the tradingBy field as a ticker parameter;
those empty results do not prove that no official historical row exists.

No HNX/HSX observations were imported. The current execution-weight function
requires complete source-row-linked OHLC on every expected session. Keep all
225 weights null until evidence satisfies that requirement or a separately
tested policy handles non-traded and synthetic bars. Raw exchange responses,
the HNX/BSC comparison, the HSX Swagger file, hashes, and a reproducible
capture script are in
official_price_limit_source_review_20261102/.

## Reproduction and evidence

- Capture summary, target manifest, raw matched/quarantined responses, and
  import stage are in
  [`bsc_price_limits_20190102`](bsc_price_limits_20190102/).
- The 834-row import committed on the report clone; its import log is
  [`phase2_bsc_import_reportclone_retry1_20261031.log`](phase2_bsc_import_reportclone_retry1_20261031.log).
- Migration 106 and batch-refresh assertions passed on the clone; see
  [`migration apply`](phase2_bsc_migration_apply_symbol_batches_20261101.log)
  and [`SQL regressions`](phase2_bsc_regressions_symbol_batches_20261101.log).
- The clean two-pass PostgreSQL 18 migration harness, including migration 106
  and all SQL fixtures, passed on test database
  `vnsignal_phase2_20261101_post106r2_disposable`; see the
  [harness log](phase2_20261101_post106_migration_harness_clean_final.log).
- `go -C go test ./...`, `go -C go test -race ./...`, `go -C go vet ./...`,
  all 45 Python unit tests, Python compile/config checks, Rust formatting,
  Clippy, and workspace tests passed. The Go worker tests used the repository's
  Python 3.12.10 virtual environment; see the [Go test](phase2_20261101_post106_go_test_final.log),
  [Go race](phase2_20261101_ci_go_race.log),
  [Go vet](phase2_20261101_post106_go_vet_final.log),
  [Python test](phase2_20261101_post106_python_unittest_final2.log),
  [Python static checks](phase2_20261101_ci_python_static.log),
  [Rust format](phase2_20261101_ci_rustfmt.log),
  [Clippy](phase2_20261101_ci_cargo_clippy.log), and
  [Rust tests](phase2_20261101_ci_cargo_test.log) logs.
- The read-only E5 repeatability verifier was rerun after the BSC refresh. All
  12 monthly outputs and the canonical 2023 year hash matched; see
  [E5 recheck](phase2_e5_repeatability_after_bsc_20261101.log).
- GitHub Actions run 162 passed its PostgreSQL 16 job on committed SHA
  `c65adf6edc2b722999d38aa1dcc23c8832875faa`. The current checkout's
  uncommitted migration 106 and evidence are not included in that run, so
  hosted CI on the actual candidate tree remains an acceptance gate; see the
  [run record](phase2_github_actions_run_162_20261101.md).
- Recompute batches are recorded under
  [`bsc_price_limits_20190102`](bsc_price_limits_20190102/), alongside the
  scoped batch runner. The first eight signal dates refreshed 3,295 targets;
  2018-12-10 through 2018-12-18 refreshed 3,752; and 2018-12-19 through
  2018-12-28 refreshed 7,594.
- The read-only coverage query and full output are
  [`weight_refresh_audit.sql`](bsc_price_limits_20190102/weight_refresh_audit.sql)
  and [`weight_refresh_audit_20261101.log`](bsc_price_limits_20190102/weight_refresh_audit_20261101.log).

The database work was limited to the disposable report clone. The registered
`vnsignal` database was not modified. Phase 2 remains open: the remaining 225
execution windows need acceptable source evidence, and the full acceptance
gates for PIT fundamentals, E1–E5, hosted PostgreSQL 16 CI, and final exact-tree
verification are still required. Suggestions remain disabled.

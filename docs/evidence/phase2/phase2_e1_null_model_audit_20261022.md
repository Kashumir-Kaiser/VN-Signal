# E1 null-rate expectation audit — 2026-10-22

This source audit reviews the null-rate report for the disposable report clone
`vnsignal_phase2_report_20261019`. It changes neither the report denominator nor
the diagnostic threshold, and it does not modify feature values.

## What the existing report measures

The refreshed V3 report covers 2,844,435 rows, 1,518 symbols, and
2018-10-01 through 2026-10-16. Its lookback-only structural expectation marks
73 of 88 measured fields above a 1 percentage-point deviation, 15 within that
deviation, and 13 source-unverified. The original CSV and run log remain the
measured output: [`null-rate CSV`](null_rates_full_rank_repaired_20261022.csv),
[`report`](null_rates_full_rank_repaired_20261022.md), and
[`run log`](phase2_null_rates_rank_repaired_20261022.log).

The expected-null calculation counts a feature's first `L` rows per symbol.
That is not the full availability contract for many production expressions,
so the 73 flags do not by themselves establish 73 implementation defects.
The Master Build Spec describes null-rate shifts as a warning and requires a
report; it does not specify a one-percentage-point Phase 2 exit gate.

## Source-level causes present in the feature definitions

- **Traded-row gates:** current-bar returns, intraday values, and turnover
  fields require a traded bar. The report-clone audit has 1,021,077
  nontraded rows; all have NULL `ret_1` and `close_sma200_ratio`. See the
  V2 expressions in
  [`migration 035`](../../../sql/migrations/035_phase2_features_labels.sql)
  and the [`availability breakdown`](null_rate_availability_breakdown_20261022.log).
- **Complete windows and valid samples:** moving averages, extrema,
  volatility, oscillators, and market-model features require enough valid
  observations in their full windows. A count of only the first `L` rows does
  not include missing or nontraded observations inside a window.
- **Adjustment episodes:** V3 rolling and recursive features reset at
  adjustment-episode boundaries and require valid episode-local warm-up.
  The lookback-only expectation counts from a symbol's first row instead.
  See the episode and rolling stages in
  [`migration 037`](../../../sql/migrations/037_phase2_price_features.sql).
- **Shared date-level inputs:** breadth and index features are date-level
  series shared by symbols, then lagged onto feature rows. Counting each
  symbol as if it had an independent lookback overstates expected NULLs for
  some of these fields.
- **Rank inputs:** six verified ranks inherit NULLs from their mapped inputs.
  E4 found zero rank/input mismatches across the audited slices. The rank
  repair did not create these input nulls.

## Remaining work and status

The source audit identifies availability conditions but does not attribute
each NULL cell to a specific prerequisite. Do not label every flag expected
until a feature-by-feature availability query and fixture assertions cover
nontraded rows, short or interrupted windows, episode resets, missing paired
index sessions, and shared date-level inputs. Source-unverified features remain
NULL. E1's real null-rate report is produced; detailed null attribution remains
open. No tolerance was changed to obtain this conclusion.

The diagnostic preserves its lookback-only expectation for every measured
feature: `sum(min(L, T_s)) / sum(T_s)`, with the existing `abs(deviation) > 1pp`
flag. It appends `rank_input_feature` and `rank_input_null_mismatch_count` as a
separate alignment diagnostic for six verified rank/input pairs. The mismatch
count compares NULL eligibility row by row, so equal aggregate null counts
cannot hide offsetting mismatches. The read-only report was rerun on
2026-10-23; its current CSV and Markdown report are
[`null_rates.csv`](null_rates.csv) and [`null_rates.md`](null_rates.md), with
zero NULL-eligibility mismatches across the six rank/input pairs. This does not
resolve attribution for the other measured features.

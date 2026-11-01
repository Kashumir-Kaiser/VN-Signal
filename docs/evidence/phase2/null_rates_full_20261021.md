# E1 real-data feature null-rate report — 2026-10-21

**Status: FAIL.** The full V3 feature table was measured; the one-percentage-point tolerance is exceeded by 79 of 88 measured features. The remaining 13 source-dependent features are explicitly classified as source-unverified and were expected to be NULL.

## Coverage

- Table: `feat.features_daily`, `feature_version='phase2-v3'`
- Rows: 2,844,435 across 1,518 symbols
- Dates: 2018-10-01 through 2026-10-16
- Feature rows in the report: 101 (79 flagged, 9 within tolerance, 13 source-unverified)
- Expected structural nulls use `sum(min(L, T_s)) / sum(T_s)` as specified. Per-feature counts, percentages, and deviations are in [`null_rates_full_20261021.csv`](null_rates_full_20261021.csv).

## Findings

The VNINDEX context columns are 100% NULL. The report clone contains 1,995 `core.index_bars` rows for VNINDEX from source `vci`, dated 2018-10-18 through 2026-10-16, and no VNINDEX rows from `vndirect`. The current Phase 2 feature and label SQL filters benchmark rows to `source='vndirect'`, so it cannot see the registered VCI index history. This explains the 100% NULL results for VNINDEX returns, regime features, beta, and idiosyncratic volatility; the SQL source mapping must be corrected to VCI and the feature/label outputs rebuilt before E1 can pass.

Other measured null rates also exceed the structural expectation and remain unexplained. Examples include `ret_1` at 43.228% versus 0.053% expected, `close_sma200_ratio` at 73.182% versus 10.543%, and `adx_14_sma` at 61.504% versus 1.441%. These require separate diagnosis; this report does not attribute them to a specific cause.

## Reproduction

The report was generated read-only from disposable database `vnsignal_phase2_report_20261019` using `sql/diagnostics/phase2_feature_null_rates.sql` with a five-minute statement timeout. It does not modify market or feature rows.

# Phase 2 E1 null-rate audit — 2026-10-22

## Result

**E1 fails the stated one-percentage-point rule.** The audit covers the current
V3 feature set on the disposable report clone, with 2,844,435 rows, 1,518
symbols, and dates from 2018-10-01 through 2026-10-16. Its feature-set hash is
`397fec9c226e5c8d1ad9742ac264bb07f2012f43f71f29fe67499d835444f11c`.

Of 101 report rows, 73 measured features are `FLAG_GT_1PP`, 15 are
`WITHIN_1PP`, and 13 are `SOURCE_UNVERIFIED`. The 13 unverified fields are
`correlation_vn30_60`, `distance_to_price_limit`, `intraday_closing_auction_share`,
`intraday_realized_variance`, `intraday_vwap_gap`, `limit_down_hit`,
`limit_down_streak`, `limit_up_hit`, `limit_up_streak`,
`rank_gaussian_momentum20_industry`, `sessions_from_tet`, `sessions_to_tet`,
and `turnover_listed_shares`. The complete per-feature results are in
[`null_rates_full_20261022.csv`](null_rates_full_20261022.csv); the query is
[`phase2_feature_null_rates.sql`](../../../sql/diagnostics/phase2_feature_null_rates.sql).
It completed in 200,682 ms; stderr is empty.

## Availability diagnostic

A read-only grouping of the same feature rows found 1,823,358 traded rows and
1,021,077 rows with `is_traded=false`; `is_traded` and `bar_landing_id` are
non-null for all rows. Every one of the 1,021,077 untraded rows has `ret_1` and
`close_sma200_ratio` null. Among traded rows, another 208,515 rows have `ret_1`
null and 1,060,539 have `close_sma200_ratio` null. The feature contract
requires current and prior traded sessions for returns and 200 traded
observations for `close_sma200_ratio`, so non-trading explains a material part
of these raw nulls. It does not yet explain all measured deviations, including
the traded-row gaps.

Reproduce this breakdown with the read-only
[`SQL`](null_rate_availability_breakdown_20261022.sql); the captured result is
[`null_rate_availability_breakdown_20261022.log`](null_rate_availability_breakdown_20261022.log).

This diagnostic does **not** change the E1 denominator, tolerance, or result.
The gate's current calculation counts every V3 row and expects only structural
cold-start nulls. The availability relationship is root-cause evidence for
follow-up; it is not a pass or an approved alternative eligibility formula.

## Corrected benchmark fields

The repaired VCI-derived fields are now populated and pass the 1pp comparison:
`vnindex_return_20s` observed 1.5041% vs expected 1.0672%;
`vnindex_return_60s` 3.2951% vs 3.1955%;
`vnindex_realized_vol20` 1.5041% vs 1.0672%; and
`vnindex_realized_vol60` 3.2951% vs 3.1955%. The previous all-null VCI failure is
resolved, but it does not resolve the other E1 flags.

No feature values or acceptance thresholds were changed to obtain this report.
E1 remains failed pending diagnosis of measured deviations and an explicit,
spec-approved decision about availability-aware expectations, if warranted.

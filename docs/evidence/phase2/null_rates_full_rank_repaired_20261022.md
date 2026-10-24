# Phase 2 E1 null-rate audit after rank repair — 2026-10-22

> Historical report generated before the row-level rank/input alignment
> columns were added. It labels the 1pp diagnostic as an E1 failure, but the
> authoritative Master Build Spec does not make that threshold a Phase 2 exit
> gate. The current report is [`null_rates.md`](null_rates.md), with matching
> detail in [`null_rates.csv`](null_rates.csv).

## Result

**E1 fails the specified one-percentage-point rule.** This current report covers
the disposable report clone's V3 table: 2,844,435 rows, 1,518 symbols, and dates
from 2018-10-01 through 2026-10-16. The V3 feature-set hash is
`f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.

Of 101 report rows, 73 of 88 source-measured features are `FLAG_GT_1PP`, 15 are
`WITHIN_1PP`, and 13 are `SOURCE_UNVERIFIED`. The unverified fields are
`correlation_vn30_60`, `distance_to_price_limit`, `intraday_closing_auction_share`,
`intraday_realized_variance`, `intraday_vwap_gap`, `limit_down_hit`,
`limit_down_streak`, `limit_up_hit`, `limit_up_streak`,
`rank_gaussian_momentum20_industry`, `sessions_from_tet`, `sessions_to_tet`,
and `turnover_listed_shares`.

The complete output is
[`null_rates_full_rank_repaired_20261022.csv`](null_rates_full_rank_repaired_20261022.csv).
The query completed successfully in 399,991 ms; see
[`the run log`](phase2_null_rates_rank_repaired_20261022.log) and
[`the query`](../../../sql/diagnostics/phase2_feature_null_rates.sql).
The expectation model is a lookback-only approximation; a source-level audit
of its known availability omissions is in
[`the E1 null-model audit`](phase2_e1_null_model_audit_20261022.md).

## Rank-field results

The rank repair removed all rank/input null mismatches, as independently checked
by E4. E1 still flags the measured rank columns because its expected-null model
counts structural lookback only across all feature rows:

| Feature | Observed null rate | Expected null rate | Status |
| --- | ---: | ---: | --- |
| `rank_gaussian_realized_vol20` | 59.9174% | 1.0672% | `FLAG_GT_1PP` |
| `rank_gaussian_return20` | 44.7693% | 1.0672% | `FLAG_GT_1PP` |
| `rank_gaussian_turnover_proxy` | 35.8974% | 0.0000% | `FLAG_GT_1PP` |
| `rank_momentum_20s` | 44.7693% | 1.0672% | `FLAG_GT_1PP` |
| `rank_realized_vol20` | 59.9174% | 1.0672% | `FLAG_GT_1PP` |
| `rank_turnover_proxy` | 35.8974% | 0.0000% | `FLAG_GT_1PP` |

The earlier availability breakdown remains valid for fields untouched by rank
repair: 1,021,077 rows are `is_traded=false`, and every such row has `ret_1` and
`close_sma200_ratio` NULL. Among traded rows, another 208,515 have `ret_1` NULL
and 1,060,539 have `close_sma200_ratio` NULL. See the
[`availability query`](null_rate_availability_breakdown_20261022.sql) and
[`captured results`](null_rate_availability_breakdown_20261022.log).

This breakdown does not change E1's denominator, threshold, or result. The
untraded rows and other availability gaps explain part of the excess nulls, but
the remaining differences still need feature-by-feature diagnosis. No feature
values or acceptance tolerances were changed to obtain this report.

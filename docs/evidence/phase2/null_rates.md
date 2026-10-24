# Phase 2 E1 null-rate report — 2026-10-23

> **Superseded for current-hash acceptance:** this report covers hash `f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`, before migration 065. Current hash `775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e` has only three refreshed sample dates; regenerate E1 after the full current-hash V3 build. See [`BUILD_STATUS.md`](../../BUILD_STATUS.md).

Target: the disposable PostgreSQL report clone `vnsignal_phase2_report_20261019`, queried read-only. No registered market database or live vnstock route was used.

V3 table: 2,844,435 rows, 1,518 symbols, 2018-10-01 through 2026-10-16; feature-set hash `f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.

The CSV reports 101 feature fields: 88 source-measured fields, 73 flagged over 1 percentage point, 15 within 1 point, and 13 source-unverified.

For source-measured fields, expected structural NULL rate is `sum(min(L, T_s)) / sum(T_s)`, where `T_s` is each symbol's row count. The report preserves the all-row denominator and flags absolute observed-minus-expected deviations greater than 1 percentage point. `SOURCE_UNVERIFIED` fields remain NULL and are not assigned a lookback expectation. This threshold is the recovery prompt's diagnostic; Master Build Spec §13 requires the report and does not make a 1-point deviation a Phase 2 exit gate.

Six verified rank/input pairs were checked row by row: 0 mismatched NULL eligibilities.

The lookback-only model does not account for traded-row gates, full-window validity, adjustment-episode warm-up, missing paired index sessions, or shared date-level features. The 1-point flags therefore identify follow-up diagnostics, not proven builder defects. Cell-level attribution remains open; do not mark every NULL expected without a row-level prerequisite check.

The complete per-feature values and statuses are in [`null_rates.csv`](null_rates.csv). The report came from [`phase2_feature_null_rates.sql`](../../../sql/diagnostics/phase2_feature_null_rates.sql); rank/input consistency has an independent full-slice report in [`the rank-repaired E4 summary`](phase2_integrity_report_rank_repaired_summary_20261022.md).

## Per-feature results

| Feature | Lookback L | Observed NULL | Expected structural NULL | Deviation (pp) | Status | Rank input | Rank/input NULL mismatches |
| --- | ---: | ---: | ---: | ---: | --- | --- | ---: |
| `adx_14_sma` | 27 | 61.50% | 1.44% | 60.064 | `FLAG_GT_1PP` | — | — |
| `amihud_proxy_20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | — | — |
| `atr_pct_14` | 14 | 58.04% | 0.75% | 57.298 | `FLAG_GT_1PP` | — | — |
| `beta_vnindex_250` | 250 | 75.04% | 13.22% | 61.824 | `FLAG_GT_1PP` | — | — |
| `beta_vnindex_60` | 60 | 65.83% | 3.20% | 62.636 | `FLAG_GT_1PP` | — | — |
| `bollinger_bandwidth_20` | 19 | 59.65% | 1.01% | 58.638 | `FLAG_GT_1PP` | — | — |
| `bollinger_pct_b_20` | 19 | 59.65% | 1.01% | 58.638 | `FLAG_GT_1PP` | — | — |
| `close_location` | 0 | 49.25% | 0.00% | 49.254 | `FLAG_GT_1PP` | — | — |
| `close_sma100_ratio` | 99 | 68.53% | 5.26% | 63.267 | `FLAG_GT_1PP` | — | — |
| `close_sma20_ratio` | 19 | 59.65% | 1.01% | 58.638 | `FLAG_GT_1PP` | — | — |
| `close_sma200_ratio` | 199 | 73.18% | 10.54% | 62.639 | `FLAG_GT_1PP` | — | — |
| `close_sma5_ratio` | 4 | 50.85% | 0.21% | 50.636 | `FLAG_GT_1PP` | — | — |
| `close_sma50_ratio` | 49 | 64.58% | 2.61% | 61.973 | `FLAG_GT_1PP` | — | — |
| `close_sma60_ratio` | 59 | 65.58% | 3.14% | 62.441 | `FLAG_GT_1PP` | — | — |
| `correlation_vn30_60` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `day_of_week` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `distance_52w_high` | 251 | 74.89% | 13.27% | 61.619 | `FLAG_GT_1PP` | — | — |
| `distance_52w_low` | 251 | 74.89% | 13.27% | 61.619 | `FLAG_GT_1PP` | — | — |
| `distance_to_price_limit` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `downside_vol20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | — | — |
| `downside_vol5` | 5 | 52.18% | 0.27% | 51.916 | `FLAG_GT_1PP` | — | — |
| `downside_vol60` | 60 | 65.68% | 3.20% | 62.480 | `FLAG_GT_1PP` | — | — |
| `ema_10_ratio` | 9 | 36.37% | 0.48% | 35.892 | `FLAG_GT_1PP` | — | — |
| `ema_100_ratio` | 99 | 40.98% | 5.26% | 35.716 | `FLAG_GT_1PP` | — | — |
| `ema_20_ratio` | 19 | 36.89% | 1.01% | 35.881 | `FLAG_GT_1PP` | — | — |
| `ema_200_ratio` | 199 | 45.94% | 10.54% | 35.401 | `FLAG_GT_1PP` | — | — |
| `ema_5_ratio` | 4 | 36.11% | 0.21% | 35.896 | `FLAG_GT_1PP` | — | — |
| `ema_50_ratio` | 49 | 38.45% | 2.61% | 35.837 | `FLAG_GT_1PP` | — | — |
| `gap_mean20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | — | — |
| `gap_open_1d` | 1 | 43.23% | 0.05% | 43.175 | `FLAG_GT_1PP` | — | — |
| `gap_std20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | — | — |
| `idio_vol_vnindex_250` | 250 | 75.04% | 13.22% | 61.824 | `FLAG_GT_1PP` | — | — |
| `idio_vol_vnindex_60` | 60 | 65.83% | 3.20% | 62.636 | `FLAG_GT_1PP` | — | — |
| `intraday_closing_auction_share` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `intraday_range_pct` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | — | — |
| `intraday_realized_variance` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `intraday_return` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | — | — |
| `intraday_vwap_gap` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `is_traded` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `large_move_approx` | 1 | 43.23% | 0.05% | 43.175 | `FLAG_GT_1PP` | — | — |
| `limit_down_hit` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `limit_down_streak` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `limit_up_hit` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `limit_up_streak` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `log_turnover_proxy_vnd` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | — | — |
| `macd_histogram_pct` | 33 | 37.62% | 1.76% | 35.862 | `FLAG_GT_1PP` | — | — |
| `market_advance_minus_decline` | 1 | 0.04% | 0.05% | -0.010 | `WITHIN_1PP` | — | — |
| `market_breadth_above_sma50` | 49 | 0.04% | 2.61% | -2.568 | `FLAG_GT_1PP` | — | — |
| `market_new_high_minus_low` | 251 | 0.04% | 13.27% | -13.225 | `FLAG_GT_1PP` | — | — |
| `market_return_dispersion` | 1 | 0.09% | 0.05% | 0.034 | `WITHIN_1PP` | — | — |
| `market_turnover_z20` | 20 | 0.88% | 1.07% | -0.186 | `WITHIN_1PP` | — | — |
| `momentum_12_1s` | 252 | 74.62% | 13.32% | 61.295 | `FLAG_GT_1PP` | — | — |
| `momentum_20s` | 20 | 44.77% | 1.07% | 43.702 | `FLAG_GT_1PP` | — | — |
| `momentum_60s` | 60 | 46.79% | 3.20% | 43.597 | `FLAG_GT_1PP` | — | — |
| `month_of_year` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `obv_slope_20` | 20 | 2.54% | 1.07% | 1.475 | `FLAG_GT_1PP` | — | — |
| `quarter_end_proximity_days` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `rank_gaussian_momentum20_industry` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `rank_gaussian_realized_vol20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | realized_vol20 | 0 |
| `rank_gaussian_return20` | 20 | 44.77% | 1.07% | 43.702 | `FLAG_GT_1PP` | return_20s | 0 |
| `rank_gaussian_turnover_proxy` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | turnover_proxy_vnd | 0 |
| `rank_momentum_20s` | 20 | 44.77% | 1.07% | 43.702 | `FLAG_GT_1PP` | momentum_20s | 0 |
| `rank_realized_vol20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | realized_vol20 | 0 |
| `rank_turnover_proxy` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | turnover_proxy_vnd | 0 |
| `realized_vol20` | 20 | 59.92% | 1.07% | 58.850 | `FLAG_GT_1PP` | — | — |
| `realized_vol60` | 60 | 65.68% | 3.20% | 62.480 | `FLAG_GT_1PP` | — | — |
| `residual_momentum_12_1s` | 252 | 74.74% | 13.32% | 61.418 | `FLAG_GT_1PP` | — | — |
| `ret_1` | 1 | 43.23% | 0.05% | 43.175 | `FLAG_GT_1PP` | — | — |
| `ret_5` | 5 | 43.46% | 0.27% | 43.191 | `FLAG_GT_1PP` | — | — |
| `return_10s` | 10 | 44.02% | 0.53% | 43.489 | `FLAG_GT_1PP` | — | — |
| `return_120s` | 120 | 48.93% | 6.38% | 42.555 | `FLAG_GT_1PP` | — | — |
| `return_1d` | 1 | 43.23% | 0.05% | 43.175 | `FLAG_GT_1PP` | — | — |
| `return_20s` | 20 | 44.77% | 1.07% | 43.702 | `FLAG_GT_1PP` | — | — |
| `return_250s` | 250 | 53.19% | 13.22% | 39.969 | `FLAG_GT_1PP` | — | — |
| `return_2s` | 2 | 43.66% | 0.11% | 43.553 | `FLAG_GT_1PP` | — | — |
| `return_3s` | 3 | 43.81% | 0.16% | 43.654 | `FLAG_GT_1PP` | — | — |
| `return_5s` | 5 | 43.46% | 0.27% | 43.191 | `FLAG_GT_1PP` | — | — |
| `return_60s` | 60 | 46.79% | 3.20% | 43.597 | `FLAG_GT_1PP` | — | — |
| `return_excess_kurtosis_pop60` | 60 | 65.68% | 3.20% | 62.480 | `FLAG_GT_1PP` | — | — |
| `return_skew_pop60` | 60 | 65.68% | 3.20% | 62.480 | `FLAG_GT_1PP` | — | — |
| `rsi_14` | 14 | 58.04% | 0.75% | 57.298 | `FLAG_GT_1PP` | — | — |
| `session_ordinal` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `sessions_from_tet` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `sessions_to_tet` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `sma_5_ratio` | 4 | 50.85% | 0.21% | 50.636 | `FLAG_GT_1PP` | — | — |
| `stochastic_d_3` | 15 | 58.41% | 0.80% | 57.614 | `FLAG_GT_1PP` | — | — |
| `stochastic_k_14` | 13 | 57.65% | 0.69% | 56.955 | `FLAG_GT_1PP` | — | — |
| `turnover_listed_shares` | — | 100.00% | 100.00% | 0.000 | `SOURCE_UNVERIFIED` | — | — |
| `turnover_proxy_vnd` | 0 | 35.90% | 0.00% | 35.897 | `FLAG_GT_1PP` | — | — |
| `turnover_sma20_vnd` | 19 | 11.26% | 1.01% | 10.241 | `FLAG_GT_1PP` | — | — |
| `vnindex_drawdown252` | 251 | 12.04% | 13.27% | -1.228 | `FLAG_GT_1PP` | — | — |
| `vnindex_realized_vol20` | 20 | 1.50% | 1.07% | 0.437 | `WITHIN_1PP` | — | — |
| `vnindex_realized_vol60` | 60 | 3.30% | 3.20% | 0.100 | `WITHIN_1PP` | — | — |
| `vnindex_return_20s` | 20 | 1.50% | 1.07% | 0.437 | `WITHIN_1PP` | — | — |
| `vnindex_return_60s` | 60 | 3.30% | 3.20% | 0.100 | `WITHIN_1PP` | — | — |
| `vnindex_sma200_ratio` | 199 | 9.63% | 10.54% | -0.908 | `WITHIN_1PP` | — | — |
| `vnindex_sma50_ratio` | 49 | 2.80% | 2.61% | 0.189 | `WITHIN_1PP` | — | — |
| `vol_5` | 5 | 52.18% | 0.27% | 51.916 | `FLAG_GT_1PP` | — | — |
| `volume` | 0 | 0.00% | 0.00% | 0.000 | `WITHIN_1PP` | — | — |
| `volume_sma20` | 19 | 11.26% | 1.01% | 10.241 | `FLAG_GT_1PP` | — | — |
| `volume_zscore_20` | 19 | 36.30% | 1.01% | 35.289 | `FLAG_GT_1PP` | — | — |

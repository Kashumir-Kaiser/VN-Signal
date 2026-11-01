# E1 full-range null-rate report — 2026-10-29

**Result: report produced for the completed current-hash V3 feature table.** This meets E1's report-production requirement. The 1 percentage-point flags are recorded as measured; they are not individually classified as implementation defects. Phase 2 remains open pending the other acceptance gates and PIT archive coverage.

The read-only query ran against disposable report clone `vnsignal_phase2_report_20261019`, in a read-only transaction, with an 8 MB `work_mem` setting, parallel workers disabled, and a 15-minute statement limit. The registered `vnsignal` database was not modified.

## Scope and status

- Feature version: `phase2-v3`
- Current feature-set hash: 28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b
- Rows: 2,844,435 across 1,518 symbols
- Date coverage: 2018-10-01 through 2026-10-16
- Fields: 101 total (88 measured, 13 source-unverified)
- Observed statuses: `FLAG_GT_1PP` = 73; `WITHIN_1PP` = 15; `SOURCE_UNVERIFIED` = 13
- Six rank/input NULL-alignment counters: 0 mismatches

The expected-null rate is `sum(min(L, T_s)) / sum(T_s)`, where `T_s` is the number of feature rows for the symbol, and a measured feature is flagged when its absolute deviation exceeds 1 percentage point. The report uses the structural lookback model as specified; it does not attribute each NULL to traded-bar availability, interrupted windows, adjustment-episode boundaries, or shared date-level input gates.

## Largest measured deviations

| Feature | Structural lookback | Observed NULLs | Expected NULLs | Difference (pp) |
| --- | ---: | ---: | ---: | ---: |
| close_sma100_ratio | 99 | 1949318 | 149719 | 63.267 |
| close_sma200_ratio | 199 | 2081616 | 299877 | 62.639 |
| beta_vnindex_60 | 60 | 1872529 | 90894 | 62.636 |
| idio_vol_vnindex_60 | 60 | 1872529 | 90894 | 62.636 |
| return_skew_pop60 | 60 | 1868089 | 90894 | 62.480 |
| return_excess_kurtosis_pop60 | 60 | 1868089 | 90894 | 62.480 |
| downside_vol60 | 60 | 1868089 | 90894 | 62.480 |
| realized_vol60 | 60 | 1868089 | 90894 | 62.480 |
| close_sma60_ratio | 59 | 1865490 | 89384 | 62.441 |
| close_sma50_ratio | 49 | 1837055 | 74284 | 61.973 |
| idio_vol_vnindex_250 | 250 | 2134477 | 375935 | 61.824 |
| beta_vnindex_250 | 250 | 2134477 | 375935 | 61.824 |

## Source-unverified fields

correlation_vn30_60, distance_to_price_limit, intraday_closing_auction_share, intraday_realized_variance, intraday_vwap_gap, limit_down_hit, limit_down_streak, limit_up_hit, limit_up_streak, rank_gaussian_momentum20_industry, sessions_from_tet, sessions_to_tet, turnover_listed_shares

These fields remain NULL throughout this dataset and are explicitly marked `SOURCE_UNVERIFIED`; they are not treated as measured-feature passes.

## Evidence

- Clean CSV: [phase2_current_hash_null_rates_full_20261029.csv](phase2_current_hash_null_rates_full_20261029.csv)
- Read-only SQL: [phase2_current_hash_null_rates_full_20261029.sql](phase2_current_hash_null_rates_full_20261029.sql)
- Raw psql result with its seven setup lines: [phase2_current_hash_null_rates_full_20261029_raw.psql.csv](phase2_current_hash_null_rates_full_20261029_raw.psql.csv)
- Run log: [phase2_current_hash_null_rates_full_20261029.log](phase2_current_hash_null_rates_full_20261029.log)

Clean CSV SHA-256: eee0771afa17156356aae968b1adf484bf4d60de09dce53bfd8014e8f4e32b0f

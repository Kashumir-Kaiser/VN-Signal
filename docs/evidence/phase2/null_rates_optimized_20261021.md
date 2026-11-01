# E1 null-rate diagnostic — 2026-10-21

**Result: diagnostic completed; the E1 acceptance criteria are not met.**

The optimized read-only diagnostic ran against the disposable report clone `vnsignal_phase2_report_20261019` with a five-minute statement timeout. It returned 101 feature rows in [`null_rates_optimized_20261021.csv`](null_rates_optimized_20261021.csv). The report covers 408,924 V3 rows for 1,346 symbols over 320 trade dates, from 2018-10-01 through 2026-10-16.

The underlying V3 history is incomplete: it contains 82,218 rows over 65 dates in 2018, 326,456 rows over 250 dates in 2019, and 250 rows over five dates in 2026; it has no rows for 2020–2025. Many measured features exceed the expected-null-rate tolerance of one percentage point. For example, `ret_1` is 53.161% null against an expected 0.329%. Therefore this output is diagnostic evidence, not a passing E1 result or a full-history acceptance report.

This run was read-only. The earlier canceled attempt remains documented separately in [`null_rates_attempt_20261021.md`](null_rates_attempt_20261021.md). The registered `vnsignal` database was not used.

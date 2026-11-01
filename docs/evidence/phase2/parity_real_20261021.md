# E3 real-data parity attempt

**Status: NOT RUN to completion; no real-data parity result.** The offline Rust tests pass, including the seeded recursive EMA golden test; see [`rust_tests_20261021.log`](rust_tests_20261021.log). That run had no database URL, so its PostgreSQL integration case was skipped.

A read-only parity attempt against disposable database `vnsignal_phase2_report_20261019` sampled 20 `phase2-v3` symbol-days across at most three dates. It ran for 772.65 seconds and was interrupted after a PostgreSQL point-in-time history query remained active. The failure output is preserved in [`parity_real_20261021.log`](parity_real_20261021.log). No feature values were reported as mismatched and the test made no database writes.

The current reference loader reconstructs the full market history by calling `core.vndirect_bars_as_of_with_episodes` once per symbol for each sampled date. The activity check found one earlier query waiting on `IO:BuffileRead` for 38m34s and the current query waiting on `IO:DataFileRead` for 1m37s. Both test backends were canceled and a follow-up confirmed they had exited. Batch the as-of history load before attempting real-data E3 again; keep the independent EMA golden test as the recursive-feature check.

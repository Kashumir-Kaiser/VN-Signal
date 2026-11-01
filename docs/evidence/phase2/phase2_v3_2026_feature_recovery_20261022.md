# Corrected 2026 V3 feature chunk — 2026-10-22

Database: disposable report clone `vnsignal_phase2_report_20261019` only. The registered `vnsignal` database and vnstock live routes were not used.

## Result

- Build: `phase2-vci-full-rebuild-20261021`, stage `features`, chunk `20260101-20261016`.
- Durable status: `done`; rows: 292,290; duration: 730,650 ms; error: NULL.
- Input SHA-256: `ef0633d1a1a651ff33829b81725c4b44b8785ad58c3d17b271fc2380bcd92977`.
- Output SHA-256: `5ff467f883e607634c0630ef5458d569d077a8ee6e967b5d7760a0ff1d0c46b2`.
- The log shows the repaired path completed the 1,194-session context, 113,572 rank rows, and all 26 symbol batches. Batch base/computed counts matched in each notice.
- Final aggregate: `phase2-v3` has 2,844,435 rows from 2018-10-01 through 2026-10-16, equal to the `phase2-v2` source count. All nine feature chunks are `done`; all nine label chunks remain pending at this checkpoint.

## Runtime observations

The adjustment cache was rebuilt before the feature transaction in 25 reported fill batches and finalized at 2,844,435 rows. The measured 15/30/60-symbol probes were 50,730/50,870/47,290 ms (scaling exponent 0.004; projected full cache about 22.10 minutes). The feature chunk itself took 12m10.650s. Its notices report market context 2m07.262s, ranks 2.906s, and symbol-batch feature steps mostly 12.7–21.8s (final partial batch 5.196s).

While the feature function was active, `pg_stat_activity` showed no lock wait; sampled states were CPU-bound or `IO:DataFileRead`. The observed database-wide temp counters remained at 206 files / 15,063,862,570 bytes across multiple samples. This is cumulative database state, not a per-query counter; no temp-counter growth was observed during the feature function. `feat.features_daily` grew from 4,022 MB to 4,497 MB during the transaction.

## Captured runner output

The full runner output is in [`stage log`](phase2_build_phase2-vci-full-rebuild-20261021_features_20261022.log). The durable chunk rows and total counts were queried from `ops.feature_chunks`, `ops.step_runs`, and `feat.features_daily` on the report clone after commit.
# Current V3 execution state

Date: 2026-10-23

The read-only audit ran against the disposable `vnsignal_phase2_report_20261019`
clone. Its SQL is [`phase2_v3_current_state_20261023.sql`](phase2_v3_current_state_20261023.sql)
and the captured PostgreSQL output is [`phase2_v3_current_state_20261023.log`](phase2_v3_current_state_20261023.log).

No non-idle PostgreSQL statement was active at the time of the audit, so there
was no running V3 build to keep or cancel and no meaningful current-job ETA.
`feat.features_daily` contains 2,844,435 V2 rows and 2,844,435 V3 rows over
2018-10-01 through 2026-10-16. The V3 rows are mixed by feature hash:

| V3 hash | Rows | Date coverage |
| --- | ---: | --- |
| `f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1` (pre-065) | 2,840,086 | 2018-10-01 to 2026-10-16 |
| `775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e` (current) | 4,349 | 2022-10-10, 2023-04-04, 2024-09-04 |

Thus the current-hash rows cover only the three real E3 sample dates; the full
current-hash V3 rebuild and current-hash E1 null-rate report remain NOT RUN.
The report clone also has no `feat.phase2_label_targets_v3` table,
`feat.phase2_liquidity_tiers_v3` table, or
`feat.build_phase2_label_targets_v3(date,date)` function. The recovery prompt's
derived-label outputs have not been installed or built in this clone.

PostgreSQL reports 326 temporary files totaling 17,689,915,048 bytes. The
reported statistics-reset timestamp is NULL, so this cumulative counter cannot
be attributed to the current build. No raw, core, or V2 data was changed by
this audit.

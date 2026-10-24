# E1 null-rate report attempt

**Status: NOT RUN to completion; no null-rate result.**

The read-only `sql/diagnostics/phase2_feature_null_rates.sql` query was run against disposable database `vnsignal_phase2_report_20261019` with a five-minute statement timeout. PostgreSQL canceled the query at line 327. The saved output in [`null_rates_attempt_20261021.log`](null_rates_attempt_20261021.log) contains only the session setting and the timeout error; no report rows or null percentages were returned.

The diagnostic targets `feat.features_daily` for `feature_version='phase2-v3'`. The timeout does not identify which aggregate-plan operation was slow, so no root cause is claimed. The query made no data writes, and the registered `vnsignal` database was not used. E1 remains NOT RUN until a valid report is produced from materialized feature rows.

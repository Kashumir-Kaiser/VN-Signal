# Cache probe strategy correction — verification pending

The real last-400 build stopped at its unchanged 1.3 scaling threshold before
feature SQL ran. Inspection found that the probe always used one 15-, 30-, or
60-symbol batch even when the builder selected 15-symbol batches. Migration
071 measures the selected batch strategy at the same 15/30/60 total sample
sizes. It preserves thresholds, source selection, and the time-budget guard.
Measurements record configured batch size, work memory, and maintenance memory;
the assertion rejects configuration mismatches.

The targeted fixture check loaded exactly 30 symbols in two 15-symbol batches,
with every batch marked loaded. See `phase2_probe_batches_071_targeted_20261024.log`.
The strategy assertion is now included in the full migration harness.

The first full 071 harness and Go verification processes disappeared before
completion. No active corresponding OS/database work remained when checked.
Their partial logs are not passes; the harness log is preserved with the
`_interrupted` suffix. Fresh verification is running on
`vnsignal_phase2_071_retry_20261024_disposable`. The report clone has not yet
received migration 071, and the real feature rebuild remains stopped.

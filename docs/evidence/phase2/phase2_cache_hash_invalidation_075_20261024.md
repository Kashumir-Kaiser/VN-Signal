# Cache hash invalidation — migration075 (2026-10-24)

A regression test against074 reproduced stale price-day hashes after a batch refill (exit3, `batch refill retained stale price-day hash evidence`). The same cache may also be initialized with a different symbol selection while old batch-date manifests and covered-day hashes survive. Those are correctness defects even when the replacement source rows are accurate.

075 invalidates session-local day hashes and date coverage before any refill and before reinitialization. Reinitialization also clears the old batch-date manifest. Reserved-table ownership comments are checked before clearing; errors roll back atomically. Hash serialization and feature equations do not change. The main run's already committed chunks used one frozen cache generation; no assertion is made that this defect corrupted those chunks.

The initial regression passed after the migration (phase2_cache_reset_after_075_20261024.log). Expanded assertions verify unchanged retry hashes, rejection of unowned temp relations, atomic rollback and clean subset reset. Required checks and a fresh two-pass migration harness are in progress. No real full-build completion is claimed.
Fresh two-pass075 migration harness completed exit0, including expanded assertions. Required Go tests/vet and all31 Python tests passed. Report-clone apply plus expanded regression assertions passed (phase2_apply_075_20261024.log). No thresholds or feature equations changed.

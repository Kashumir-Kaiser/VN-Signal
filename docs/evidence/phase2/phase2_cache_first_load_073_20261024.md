# Cache first-load scan elimination — migration 073 (2026-10-24)

The 072 isolated preflight passed with exponent1.150; production fills exceeded twice the projected time. The run was cancelled during final ANALYZE after102 fills. Source inspection found a growing-table DELETE on every first-load batch. With B batches and N cache rows this introduces cumulative scans proportional to B*N, even though symbol batches are disjoint.

073 conditions the cache DELETE on the manifest's loaded flag. A statement that fails rolls back both insertion and loaded state, so a never-loaded batch cannot retain committed rows. A successful retry continues to delete and replace its own symbols. Date-manifest replacement remains unconditional.

Targeted test passed on the disposable072 database: transaction scan counters were zero after two first-load fills; retry scanned its prior rows; final unique indexes and duplicate checks passed. Existing session-cache assertions continue to compare complete rows and date manifests against the canonical view after a retry. Log: phase2_first_load_073_targeted_20261024.log.

Required Go tests, vet, and all31 Python tests passed (go_test_073_20261024.log, go_vet_073_20261024.log, python_tests_073_20261024.log). Fresh two-pass073 migration replay is running; its terminal status must be checked before signoff. No real073 performance pass is claimed. No thresholds or feature definitions changed.
Fresh073 two-pass migration harness completed with exit0, including complete-row/date-manifest parity and retry assertions plus the new scan-counter assertions. Report-clone apply and rollback-only assertions passed (phase2_apply_073_20261024.log). The corrected full-history build is running as phase2-v3-073-isolated-full-20261024; no completion claim until terminal evidence.

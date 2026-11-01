# Cache projection accounting — migration 072 (2026-10-24)

Corrects a projection mismatch introduced when migration 071 made the sample use production batch sizes. Example: a 60-symbol sample at batch size 15 contains four fills; its total is divided by four before projection, rather than treated as one fill. Partial final batches conservatively retain their cost in the complete-batch estimate. Larger unsampled batch sizes use at least linear extrapolation. Setup/finalization overhead stays included.

Targeted migration/assertions passed on the prior disposable database. Required Go tests and vet passed with the repository Python environment selected; all 31 Python tests passed. Initial runs using the inactive Windows Python alias failed and are retained as *_072_20261024.log; passing runs are *_072_venv_20261024.log. Fresh two-pass migration replay is in phase2_migration_harness_072_20261024.log; inspect its terminal result before claiming success.

No real build pass or feature completion is inferred. The previous 071 scaling failure remains recorded. Exponent limit 1.3 and time budget remain enforced.
Fresh two-pass migration replay completed with exit 0, including the final projection assertions. Migration 072 and its rollback-only assertions then applied to the report clone with exit 0 (phase2_apply_072_20261024.log). The success marker in the harness was moved after the new assertion call so it represents all assertions.

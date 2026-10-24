# Bounded execution proof hashing — 2026-10-24

Migration 083 hashes ordered exact proof rows per security, then hashes the ordered security digests. A flat 3-million-row concatenation would allocate roughly 190 MB just for its 64-character digests, beyond the configured 8 MB sort/work budget. Ordered per-security aggregation bounds each aggregate transition to one security's daily history. The versioned dependency changes to execution_proof=v2, intentionally invalidating prior label chunk input hashes. Price feature definitions and their hash are unchanged.

Targeted apply/replay and the execution-proof assertions passed. Reapplying migration 082 after 083 must preserve exactly one bounded proof dependency; an explicit assertion checks that invariant. A fresh full two-pass harness and required Go/Python checks are running; no final pass is claimed yet.

The real ACB pilot independently qualified 2,003 current canonical rows from original report landing 6870: 545 HNX executions (2018-10-01 through 2020-12-01) and 1,458 HOSE executions (2020-12-09 through 2026-10-16). Exact original raw payload and source rows were copied to the disposable review database with only database-local foreign keys remapped; archive repeat inserted zero. The entire pilot transaction rolled back. No market vendor was called and no real report source row was changed. This proves that sample's source qualification, not full-universe eligibility or identity coverage. See phase2_public_execution_082_real_acb_20261024.log and archived export/pilot SQL.

## Remaining real-data signoff work after the live build

Master section 13 requires a produced null-rate report, green leakage and green parity evidence. The recovery prompt additionally requests current integrity/scaling and repeated-chunk output hashes. The user's persistent objective requires full Phase 3 readiness; the prompt's conditional last-400-session fallback is not being used as full completion.

After all 33 quarters: assert zero stale V3 hashes, generate current E1 outputs, rerun real E2/E3 with the final production definitions, build complete labels/targets, repeat a completed chunk with equal input/output hashes, and run current E4 census/attribution and cooldown-boundary checks. Existing gap classification packets explain specific legal/venue intervals; they do not fabricate missing bars or prove suspension. The curated CSV currently marks 24 named intervals supported and HNA unresolved, but those counts are not a fresh exhaustive current-hash census. Do not subtract them from older unsupported-only totals. Retain unexplained windows under the existing 250-session training cooldown and missing-forward-session label guard.

The training key view is intentionally the gap/READY-label filter. DATA_CONTRACT now explicitly requires joining final targets and applying membership/tier gates and sample-weight policy; its raw excess_return is not the full model sample matrix. Missing PIT sources limit the optional fundamental model, rather than fabricating values or blocking the price-only research path.

Final local result: the complete fresh two-pass SQL migration harness passed, including migration 083 and all existing assertions. Required Go test/vet and Python 32 also passed. Real-data full-universe gates and a new CI run for the 083 commit remain open.

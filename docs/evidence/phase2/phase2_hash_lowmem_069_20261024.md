# Full-range canonical hash checkpoint — PASS

The rollback-only probe on `vnsignal_phase2_report_20261019` completed with
15-symbol cache batches, 8 MB work memory, and 16 MB maintenance memory.
All 2,844,435 adjustment rows loaded; finalization took 25.090 seconds.

The unchanged canonical hash expression processed all 1,206 requested dates
from 2021-03-09 through 2025-12-31 in 73.943 seconds. Both hash and coverage
tables contained 1,206 dates. A repeated request reported zero uncovered dates
and finished in 129.107 ms. The client exited zero after ROLLBACK.

This passes the full-range hash checkpoint that previously exceeded 26 minutes.
It verifies hash-stage completion and reuse, not a V3 feature build or E1.
Exact script and output: `phase2_hash_lowmem_069_20261024.psql` and `.log`.

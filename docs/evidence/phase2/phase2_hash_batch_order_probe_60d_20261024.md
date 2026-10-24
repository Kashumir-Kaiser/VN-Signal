# Date-local cache insertion probe — 2026-10-24

This rollback-only diagnostic ran against disposable database
`vnsignal_phase2_report_20261019` with a 64 MB work memory setting. It loaded
all 2,844,435 adjustment-cache rows in 26 batches of up to 60 symbols. The
baseline and candidate used the same source helper and rows; the candidate
added `ORDER BY trade_date, symbol_id` to each batch's `INSERT ... SELECT`.

For the first 60 effective sessions from 2021-03-09, both paths hashed 83,629
cache rows with the same canonical JSON serialization, newline delimiter,
symbol ordering, and SHA-256 function. The baseline plan took 23.855 seconds and
read 82,419 local blocks. The date-local plan took 1.855 seconds and read 1,864
local blocks, with 78,988 local blocks served from buffers. All 60 per-day
hashes matched; the mismatch count was zero.

Across the 26 cache-fill calls, baseline batch insertion took 75.04 seconds;
date-local insertion took 99.09 seconds. Finalization took 15.65 seconds for
the baseline and 14.30 seconds for the candidate. This measures an estimated
24-second cache-fill cost for the 2.84-million-row cache and a 12.9x faster
60-session hash query. It does not yet establish full-range E1 runtime or
current-hash V3 output.

The candidate function definition existed only inside the diagnostic
transaction. `ROLLBACK` restored the clone function and discarded all temp
tables. No persistent market or feature rows changed. The exact script and
output are in
[`phase2_hash_batch_order_probe_60d_20261024.psql`](phase2_hash_batch_order_probe_60d_20261024.psql)
and
[`phase2_hash_batch_order_probe_60d_20261024.log`](phase2_hash_batch_order_probe_60d_20261024.log).

This result supports a forward-only cache-loader migration. Before rerunning
the V3 build, apply the migration through the fresh two-pass harness and verify
the full 1,206-date hash stage under the existing time and memory checkpoints.

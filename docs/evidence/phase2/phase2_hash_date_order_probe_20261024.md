# Date-ordered price-hash probe — 2026-10-24

Target was the disposable report clone
`vnsignal_phase2_report_20261019`. The probe began a rollback-only transaction,
loaded the full 2,844,435-row adjustment cache, and selected 12 effective
sessions. The current physical cache layout's unchanged per-day aggregate took
6.345 seconds in this sample and read 16,606 local blocks. A prior 12-session
sample took 0.493 seconds with the same block-read count, so wall time varied
with cache warmth; neither sample establishes full-range runtime.

The next step attempted a temp-table copy ordered by `(trade_date, symbol_id)`.
At 3:29 elapsed it was still running and waiting on `IO:DataFileRead`. Available
RAM was 237 MiB of 3.83 GiB. The copy was canceled to avoid adding load during
the memory constraint. The PostgreSQL backend exited, the open transaction
rolled back, and no persistent market or feature data changed. The copy did
not complete, so there is no reordered-query timing or hash-parity result.

The script and complete output are preserved in
[`phase2_hash_date_order_probe_12d_20261024.psql`](phase2_hash_date_order_probe_12d_20261024.psql)
and
[`phase2_hash_date_order_probe_12d_20261024.log`](phase2_hash_date_order_probe_12d_20261024.log).
The next diagnostic should test date locality with bounded per-symbol-batch
ordering or date-range hash batches under a memory checkpoint. Do not promote
physical reordering or claim the hash path fixed until equal day hashes and a
measured end-to-end time demonstrate it.

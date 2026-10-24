# Resource failure and recovery — 2026-10-22

Phase 2 remains incomplete. This records a resource recovery, not full-history
feature certification.

## Observed failure

- The first rank probe completed 30/60-session rollback samples but its
  120-session sample timed out. No repair completion rows committed.
- Vacuum removed 460,129 dead tuples, then its ANALYZE failed reading a block.
  The server log records Windows error 1450 immediately before the misleading
  `Invalid argument` message, and error 1455 while reattaching shared memory.
- A shell also failed with `System.OutOfMemoryException`. The host reports
  4,017,764 KiB visible RAM. PostgreSQL later reported interruption and recovery;
  its current postmaster started at 17:41:01.974001+07 and recovery is finished.
- A targeted four-page read around the first failed block subsequently returned
  90 rows successfully. This alone is not an all-table integrity check.

The meanings of Windows errors 1450 and 1455 are documented by
[Microsoft](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--1300-1699-).
These observations support resource exhaustion; they do not prove a PostgreSQL
AIO defect or disk corruption. No server configuration or paging-file setting
was changed.

## Actions and verified results

- Verified the resumed run's Serena root PID 10272, parent Codex PID 13112,
  creation second 17:50:17, executable name, and command before terminating that
  process tree. The termination reported success for the root and 12 descendants.
  Free physical memory afterward was 616,968 KiB, compared with 311,540 KiB at
  the preceding inspection. Earlier PIDs were not reused as termination targets.
- Ran Python tests without a concurrent large database job: all 27 passed in
  0.248 seconds, including the unchanged five-second health timeout. The prior
  resource-contended failure remains in its separate log.
- Standalone ANALYZE with 16 MiB work_mem, no parallel query/maintenance worker,
  and zero session I/O concurrency completed in 10.05 seconds. It sampled
  30,000 pages and reported no dead rows in that sample. This is a statistics
  refresh, not an exact count or full integrity certificate.
- The revised rank probe uses one rollback transaction per bounded chunk,
  matching repair's transaction boundary. Its 30/60/120 sizes, rollback checks,
  non-rank checks, and b<=1.3 gate remain mandatory. Memory, I/O concurrency,
  parallel workers, timeout, database, and SQL definitions are pinned in its
  certificate. A complete passing replacement probe is still required.

## Evidence

- `phase2_rank_probe_vacuum_20261022.log` — vacuum output and failed ANALYZE.
- `phase2_rank_failed_block_read_20261022.log` — targeted readable page range.
- `phase2_rank_analyze_serial_io_20261022.log` — connection loss, not a pass.
- `phase2_rank_analyze_after_cleanup_20261022.log` — successful 10.05-second ANALYZE.
- `phase2_python_market_projection_20261022.log` — contended Python failure.
- `phase2_python_market_projection_quiet_20261022.log` — quiet 27-test pass.
- `phase2_rank_repair_phase2-rank-repair-053-20261022.log` — probe checkpoints.

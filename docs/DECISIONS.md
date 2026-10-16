# Decisions

1. **Initial commit is an honest bootstrap, not an invented working full stack.** No external market-data credentials are available in the build environment. A real v5 entitlement probe and multi-day quota backfill must happen on the designated user's machine.
2. **Keep API interaction strictly isolated** inside a single Python adapter (target <400 lines); Go calls a JSON-lines protocol. The adapter never learns model logic, and credentials never travel in the JSON protocol.
3. **No quota guessing.** The scheduler and future backfill must consume absolute available budgets from real reports or stop. Remaining *percentages* are not interchangeable with remaining API *calls*.
4. **No seed recommendations.** Until risk, cost, leakage and quality gates pass, no demo/mock rows should appear as a genuine BUY or SELL signal.
5. **No unnecessary infrastructure.** PostgreSQL wrangling plus SQLite serving as specified. No Docker, Redis, Celery, hosted VN API CI jobs, auth, or cloud DB.
6. **Raw PIT timestamps are never rewritten.** Earlier data published in later financial reports must be conservatively availability-stamped and identified as assumptions, not proven historical publication timestamps.


## 2026-10-16 P0 hardening

- A worker frame is valid only if it is the sole JSONL frame, has the matching request ID, a coherent success/failure envelope, and exits zero. A 45-second default deadline and one-worker semaphore bound hangs and process explosions. Python library stdout is redirected to stderr and stderr collection is capped; the subprocess receives only whitelisted local runtime environment keys.
- The Python adapter deliberately refuses `probe(active=True)`; Go's `live.Gateway` is the only metered API route gateway. The CLI requires *both* recognized tier and absolute integer remaining daily/monthly calls in `vnstock --json` reports. If the actual installed v5 CLI returns percentages only, active probing stops rather than guessing quotas. There is no automated full ingestion yet.
- `source=` remains on `.ohlcv()` / statement methods as specified by vnstock v5's published API. It is **not** moved to `Market()` or `.equity()` constructor absent contrary evidence from a local Phase-0 probe.
- Exchange spelling is canonicalized to `UPCOM` by PostgreSQL before-insert/update triggers, so upstream `UPCoM` inputs are accepted without polluting downstream joins. Financial period-end timestamp comparison explicitly uses `Asia/Ho_Chi_Minh`.
- Checkpoint writers take an exclusive directory lock. A crash leaving the `.lock` behind blocks automatic writes until manually inspected; this is safer than racing a prior writer. Crash orphan temp files are removed under this lock; previous checkpoint remains readable after failed fsync/rename. Unix directory entry sync is attempted; Windows uses native rename guarantees, and durability remains filesystem-dependent.
- The Go configuration parser intentionally supports only the simple committed TOML subset; it rejects unknown/missing keys instead of silently accepting unexpected constructs. Python 3.12 `tomllib` also checks syntax in CI.
- Hardening tests do not turn absent components into implemented features. Scheduler recovery, SQLite swapping/inference parity, seven unattended runs and PostgreSQL disk-exhaustion recovery are future implementation gates.

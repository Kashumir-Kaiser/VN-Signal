# Decisions

1. **Initial commit is an honest bootstrap, not an invented working full stack.** No external market-data credentials are available in the build environment. A real v5 entitlement probe and multi-day quota backfill must happen on the designated user's machine.
2. **Keep API interaction strictly isolated** inside a single Python adapter (target <400 lines); Go calls a JSON-lines protocol. The adapter never learns model logic, and credentials never travel in the JSON protocol.
3. **No quota guessing.** The scheduler and future backfill must consume absolute available budgets from real reports or stop. Remaining *percentages* are not interchangeable with remaining API *calls*.
4. **No seed recommendations.** Until risk, cost, leakage and quality gates pass, no demo/mock rows should appear as a genuine BUY or SELL signal.
5. **No unnecessary infrastructure.** PostgreSQL wrangling plus SQLite serving as specified. No Docker, Redis, Celery, hosted VN API CI jobs, auth, or cloud DB.
6. **Raw PIT timestamps are never rewritten.** Earlier data published in later financial reports must be conservatively availability-stamped and identified as assumptions, not proven historical publication timestamps.

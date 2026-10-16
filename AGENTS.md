# VN-Signal contributor instructions

The authoritative specification is [docs/MASTER_BUILD_SPEC.md](docs/MASTER_BUILD_SPEC.md), not a generic stock-screener template.

1. Validate the actual installed vnstock v5 capabilities on the **single user's** registered machine before implementing data endpoints. This repository may be built offline but must never consume account/device quota in hosted CI.
2. Follow Phase 0 through Phase 6 sequentially, and mark exit criteria complete only with recorded evidence in `docs/BUILD_STATUS.md`. Record scope decisions in `docs/DECISIONS.md`.
3. Correctness comes before model complexity: strict point-in-time availability, leave-future-out tests, true trade-day calendars, one-session cross-asset lag, and purged walk-forward evaluation.
4. No fictional market data, financial performance, tier quotas, forward returns, predictions, or success reports. If no valid champion exists, disable suggestions instead of showing placeholders as trades.
5. Keep adapter in `py/vnstock_worker.py` under 400 lines, and keep it free of financial/business logic. Do not add Redis, message queues, authentication, Kubernetes, or cloud ingestion.
6. Run `go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover -s tests -v` after each relevant edit. Document unavailable PostgreSQL/Rust/desktop tests rather than claiming success.
7. Preserve the proprietary license and vendor attribution. Commit to main only after checks; avoid creating feature branches unless explicitly requested.

8. Only call vnstock data routes through Go `internal/live.Gateway.Call`, never by a raw `worker.Invoke` for market data. Unknown or percentage quota must block; each retry requires a fresh reservation. `VNPIPE_DISABLE_LIVE=1` is required in hosted CI.
9. Changes to the worker must preserve exactly one JSON-line frame, stdout isolation, bounded responses and the one-process concurrency bound. Run `go -C go test -race ./...`, the Python JSONL tests, and the PostgreSQL CI migration check before signing off on Phase 0/1.

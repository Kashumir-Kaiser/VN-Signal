# Phase 2 local validation after migration 109 — 2026-11-01

All commands ran against the current `phase2-evidence` working tree. Go
live-data routes were disabled; worker tests used the repository virtual
environment. The race run used the installed MSYS2 UCRT64 GCC with one Go
build job to fit the host's available memory.

| Check | Result | Evidence |
| --- | --- | --- |
| `go -C go test ./...` | PASS, exit code 0 | [Go test log](phase2_20261101_post109_go_test.log) |
| `go -C go test -race -p=1 -count=1 ./...` | PASS, exit code 0 | [Go race log](phase2_20261101_post109_go_test_race.log) |
| `go -C go vet ./...` | PASS, exit code 0; no diagnostics | [Go vet log](phase2_20261101_post109_go_vet.log) |
| `python -m unittest discover -s tests -v` | PASS; 47 tests | [Python test log](phase2_20261101_post109_python_unittest.log) |
| `python -m py_compile py/vnstock_worker.py` and default TOML parse | PASS, exit code 0 | [Python static-check log](phase2_20261101_post109_python_static.log) |
| `cargo fmt --manifest-path rust/Cargo.toml -- --check` | PASS, exit code 0 | [Rust format log](phase2_20261101_post109_rust_fmt.log) |
| `cargo test --manifest-path rust/Cargo.toml --workspace --all-targets` | PASS; 21 tests | [Rust test log](phase2_20261101_post109_rust_test.log) |
| `cargo clippy --manifest-path rust/Cargo.toml --workspace --all-targets -- -D warnings` | PASS, exit code 0 | [Rust Clippy log](phase2_20261101_post109_rust_clippy.log) |
| Fresh two-pass PostgreSQL migration harness through migration 109 | PASS, exit code 0; includes migration and execution-weight assertions | [Migration harness log](phase2_109_full_migration_harness_20261101.log) |

The PostgreSQL harness used a disposable PostgreSQL 18 database. The real-data
E2 perturbation ran in a transaction and rolled back. No market-data endpoint
was called during these checks.

These local results do not cover hosted CI for the uncommitted candidate tree,
and do not close the documented PIT fundamentals, E4 continuity, or execution
weight evidence gaps.

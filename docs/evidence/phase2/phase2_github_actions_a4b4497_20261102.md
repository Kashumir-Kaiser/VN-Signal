# Hosted CI — Phase 2 candidate `a4b4497` — 2026-11-02

Both event-triggered runs completed successfully for exact commit
`a4b4497a10459f852e7a499e1e3f0a03686f7374` on branch `phase2-evidence`:

- [Run 165 — push](https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/41335871809): `go`, `python`, and `postgres` all passed.
- [Run 166 — pull request](https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/41335878890): `python`, `postgres`, and `go` all passed.

The Go job ran `go test -race ./...` and `go vet ./...`. The Python job ran
the unit suite, worker compile check, and TOML parse. The PostgreSQL job passed
the SQL migration harness, Rust formatting/Clippy/workspace tests, PostgreSQL
diagnostic SQL, both forward migration passes, and the PostgreSQL-tagged Go
integration race suite. These runs cover the exact candidate tree before the
GDW evidence-only documentation/source capture updates; CI must be rerun for
the later commit.

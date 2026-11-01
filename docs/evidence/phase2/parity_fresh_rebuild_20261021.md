# E3 fresh SQL rebuild attempt — 2026-10-21

## Result

**E3 did not complete. No parity conclusion can be drawn.** The SQL parity test compiled and started against the disposable database `vnsignal_phase2_e3_20261021_disposable`, but PostgreSQL canceled `feat.prepare_phase2_adjustment_rows(true)` at the 30-minute statement timeout. The failing statement was constructing the transaction-local `phase2_adjustment_rows` table from `core.vndirect_reference_adjustment_details`. The v2/v3 feature rebuild and the 20 symbol-day comparisons were never reached.

The test ran for 2,015.05 seconds. It used an explicit transaction and had not invoked either feature builder when the timeout occurred. The failed statement was rolled back when the client disconnected; a subsequent PostgreSQL check found zero connections with application name `phase2_sql_parity`. No registered database was used.

## Evidence

- [`parity_fresh_rebuild_20261021.log`](parity_fresh_rebuild_20261021.log) records the real-data run and PostgreSQL timeout.
- [`parity_fresh_rebuild_connection_failed_20261021.log`](parity_fresh_rebuild_connection_failed_20261021.log) preserves the earlier connection-configuration attempt, which failed before issuing a database query.
- `cargo fmt --manifest-path rust/Cargo.toml -- --check` passed.
- `cargo test --manifest-path rust/Cargo.toml -p vn-signal-phase2-parity --test sql_parity --no-run --locked` compiled the test successfully.

## Interpretation

The run identifies a production-path performance blocker: building the full point-in-time adjustment cache for a bounded E3 sample exceeded 30 minutes on the disposable clone. It does not establish whether the Rust implementation matches freshly built SQL. E1 independently remains unmet because the measured feature null rates exceed tolerance and the clone has sparse date coverage. Phase 2 is therefore not ready for sign-off.

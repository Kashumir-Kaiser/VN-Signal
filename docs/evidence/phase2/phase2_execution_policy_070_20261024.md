# Configured execution weights — current verification

The TOML label profile now contains validated `entry_ceiling_weight` and
`multiple_locked_weight` values. `vnpipe label-policy` uses the existing strict
parser and `VNPIPE_CONFIG` selection. The runner captures that policy once,
sets transaction-local SQL values before checking input hashes, and records
the effective JSON policy on label chunks and step runs.

Migration 070 provides explicit configurable SQL defaults for standalone SQL
callers. TOML-driven builds override those defaults for their own transactions.
The canonical effective policy is included in the derived-label input hash,
so changed weights invalidate resume decisions. Missing evidence still yields
NULL; entry-at-ceiling retains precedence over multiple locked sessions.

Targeted SQL checks and migration replay passed on disposable fixture database
`vnsignal_phase2_069_20261024_disposable`. They covered configured weights,
missing evidence, precedence, rejection of NaN, changed-policy hash invalidation,
and identical hashes for equivalent numeric spelling. Existing label-output
assertions passed under the default policy. Logs:
`phase2_policy_070_targeted_20261024.log` and
`phase2_policy_070_replay_20261024.log`.

Go tests, vet, and 31 Python tests passed after the runner integration; logs use
the `policy_runner_20261024` suffix. Full fresh migration replay, a real runner
label build with recorded policy metadata, and hosted CI remain unverified.

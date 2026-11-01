# E3 parity audit — updated 2026-10-26

## Status: incomplete

The recovery prompt's real-data non-recursive parity slice passed for 20
source-attributed symbol-days across 2022-10-10, 2023-04-04, and 2024-09-04 at
the required `1e-9` relative tolerance and sampled feature hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`. Evidence
is in [`phase2_e3_real_parity_065_nonrecursive_20261023.log`](phase2_e3_real_parity_065_nonrecursive_20261023.log).
That hash predates migration 089, so this result does not validate the current
candidate.

The broader historical real-data diagnostic did not pass recursive parity:
for symbol 824 on 2023-04-04, `ema_100_ratio` was
`0.004010006674335` in SQL and `0.004010006740238` in Rust, about `1.64e-8`
relative. The difference remains visible in
[`phase2_e3_real_parity_065_20261023.log`](phase2_e3_real_parity_065_20261023.log);
the tolerance was not changed.

## Rollback-only golden fixture update

The earlier note described a 430-row EMA/MACD-only fixture and said the SQL
assertion did not exercise the production builder. That description is stale.
The current checked-in golden has 320 rows for a synthetic `P2GOLD` series. It
uses non-linear OHLC values and includes one zero-volume session whose carried
close is checked as an input. The independent pandas generator and Rust test
compare six EMA ratios, MACD histogram, RSI(14), ATR%, and ADX(14), including
their NULL masks. The rollback-only SQL assertion creates this symbol inside
its transaction, calls public `feat.build_features`, compares the source OHLC
and trade state to the golden, then checks full-range output against annual,
monthly, and quarterly rebuilds.

The fixture is test wiring, not execution evidence: the Rust golden test and
PostgreSQL migration harness still need to run on the updated tree. The master
spec lists RSI, MACD, ADX, ATR%, and realised volatility but does not require
Wilder smoothing or EWMA variance. Do not add either as a new requirement or
change the existing SQL/Rust indicator formulas under this fixture update.
Intraday realised variance remains source-dependent and must stay NULL without
audited intraday input evidence.

## Remaining E3 evidence

After a uniform full-history 089 feature build, run the 20-point real-data
SQL/Rust parity slice against that candidate, preserve the `1e-9` tolerance,
and record its feature hash and source attribution. Run the updated Rust golden
test and the PostgreSQL fixture harness, including the chunk-invariance checks.
Until those checks pass on the current candidate, E3 remains incomplete.

# E3 parity audit — 2026-10-23

## Status: incomplete

The recovery prompt's real-data non-recursive parity slice passed for 20
source-attributed symbol-days across 2022-10-10, 2023-04-04, and 2024-09-04 at
the required `1e-9` relative tolerance and current sampled feature hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`. Evidence
is in [`phase2_e3_real_parity_065_nonrecursive_20261023.log`](phase2_e3_real_parity_065_nonrecursive_20261023.log).

The broader real-data diagnostic did not pass recursive parity: for symbol 824
on 2023-04-04, `ema_100_ratio` was `0.004010006674335` in SQL and
`0.004010006740238` in Rust, about `1.64e-8` relative. The difference remains
visible in [`phase2_e3_real_parity_065_20261023.log`](phase2_e3_real_parity_065_20261023.log);
the tolerance was not changed.

The independent 430-row pandas 3.0.1 golden fixture currently covers the EMA
periods and MACD, including seed and NULL-mask behavior, and is checked by the
Rust tests and SQL feature assertions. It does not independently cover the
other recursive families named by the recovery prompt (Wilder RSI, ATR/ADX,
and EWMA variance), and the SQL fixture assertion does not run the production
V3 builder end-to-end on the fixture rows. Therefore the current evidence
supports a non-recursive real-data pass plus partial recursive golden
coverage, not full E3 completion. Do not use the superseded broad-pass claim
from the earlier version of this file.

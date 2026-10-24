"""Generate a pandas golden for the synthetic P2READY production-builder series.

The SQL fixture uses close[t] = 101 + 2*t for 320 consecutive traded sessions.
Every EMA is independently computed with pandas EWM using the same first-value
seed and NULL-skipping convention as the recovery specification.  The output
is consumed by the focused Rust and SQL builder tests.
"""

from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "phase2_recursive_builder_golden.csv"
ROWS = 320
PERIODS = (5, 10, 20, 50, 100, 200)


def main() -> None:
    frame = pd.DataFrame(
        {
            "step": range(1, ROWS + 1),
            "close": [101.0 + 2.0 * step for step in range(ROWS)],
            "traded": [True] * ROWS,
        }
    )
    ema: dict[int, pd.Series] = {}
    for period in (*PERIODS, 12, 26):
        state = frame["close"].ewm(
            alpha=2.0 / (period + 1.0), adjust=False, ignore_na=True
        ).mean()
        ema[period] = state
        ratio = (frame["close"] / state - 1.0).where(frame["step"] >= period)
        frame[f"ema_{period}_ratio"] = ratio

    macd_line = (ema[12] - ema[26]).where(frame["step"] >= 26)
    macd_signal = macd_line.ewm(alpha=0.2, adjust=False, ignore_na=True).mean()
    frame["macd_histogram_pct"] = ((macd_line - macd_signal) / frame["close"]).where(
        frame["step"] >= 34
    )
    frame["traded"] = frame["traded"].map(lambda value: "true" if value else "false")

    columns = [
        "step",
        "close",
        "traded",
        "ema_5_ratio",
        "ema_10_ratio",
        "ema_20_ratio",
        "ema_50_ratio",
        "ema_100_ratio",
        "ema_200_ratio",
        "macd_histogram_pct",
    ]
    frame[columns].to_csv(OUTPUT, index=False, float_format="%.17g", na_rep="")
    print(f"wrote {ROWS} rows to {OUTPUT}; pandas {pd.__version__}")


if __name__ == "__main__":
    main()

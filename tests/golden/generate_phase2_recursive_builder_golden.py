"""Generate pandas goldens for the synthetic P2GOLD production-builder series.

The SQL fixture mirrors the exact binary-fraction OHLC formulas below for 320
weekday sessions, including one zero-volume carried-price session.  Indicators
are calculated independently with pandas rolling/EWM operations matching the
specified simple-average and NULL-mask semantics.  The fixture is consumed by
the focused Rust and production SQL-builder tests.
"""

from pathlib import Path

import pandas as pd


ROOT = Path(__file__).resolve().parent
OUTPUT = ROOT / "phase2_recursive_builder_golden.csv"
ROWS = 320
PERIODS = (5, 10, 20, 50, 100, 200)
FIRST_SESSION = pd.Timestamp("2098-01-05")


def main() -> None:
    steps = list(range(ROWS))
    traded = [step != 40 for step in steps]
    raw_close = [
        100.0 + step * 0.25 + ((step % 9) - 4) * 0.5 + (step % 5) * 0.125
        for step in steps
    ]
    close = [raw_close[step] if traded[step] else raw_close[step - 1] for step in steps]
    raw_open = [
        raw_close[step]
        - ((step % 5) - 2) * 0.25
        + ((step % 3) - 1) * 0.125
        for step in steps
    ]
    open_price = [raw_open[step] if traded[step] else raw_close[step - 1] for step in steps]
    high = [
        max(open_price[step], close[step]) + ((step % 4) + 1) * 0.125
        for step in steps
    ]
    low = [
        min(open_price[step], close[step]) - ((step % 3) + 1) * 0.25
        for step in steps
    ]
    frame = pd.DataFrame(
        {
            "step": [step + 1 for step in steps],
            # This weekday-only axis exactly matches phase2_feature_fixture.sql.
            "trade_date": pd.bdate_range(FIRST_SESSION, periods=ROWS).strftime("%Y-%m-%d"),
            "open": open_price,
            "high": high,
            "low": low,
            "close": close,
            "traded": traded,
        }
    )
    ema: dict[int, pd.Series] = {}
    for period in (*PERIODS, 12, 26):
        state = frame["close"].where(frame["traded"]).ewm(
            alpha=2.0 / (period + 1.0), adjust=False, ignore_na=True
        ).mean()
        ema[period] = state
        traded_count = frame["traded"].astype(int).cumsum()
        ratio = (frame["close"] / state - 1.0).where(
            frame["traded"] & (traded_count >= period)
        )
        frame[f"ema_{period}_ratio"] = ratio

    traded_count = frame["traded"].astype(int).cumsum()
    macd_line = (ema[12] - ema[26]).where(traded_count >= 26)
    macd_signal = macd_line.where(frame["traded"]).ewm(
        alpha=0.2, adjust=False, ignore_na=True
    ).mean()
    signal_count = (frame["traded"] & (traded_count >= 26)).astype(int).cumsum()
    frame["macd_histogram_pct"] = ((macd_line - macd_signal) / frame["close"]).where(
        frame["traded"] & (traded_count >= 26) & (signal_count >= 9)
    )

    traded_pair = frame["traded"] & frame["traded"].shift(1, fill_value=False)
    returns = frame["close"].pct_change().where(traded_pair)
    avg_gain = returns.clip(lower=0.0).rolling(14, min_periods=14).mean()
    avg_loss = (-returns.clip(upper=0.0)).rolling(14, min_periods=14).mean()
    frame["rsi_14"] = (100.0 - 100.0 / (1.0 + avg_gain / avg_loss)).where(
        frame["traded"]
    )
    frame.loc[frame["traded"] & (avg_loss == 0.0) & avg_gain.notna(), "rsi_14"] = 100.0

    previous_close = frame["close"].shift(1)
    true_range = pd.concat(
        [
            frame["high"] - frame["low"],
            (frame["high"] - previous_close).abs(),
            (frame["low"] - previous_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    eligible_true_range = (true_range / frame["close"]).where(traded_pair)
    frame["atr_pct_14"] = eligible_true_range.rolling(14, min_periods=14).mean().where(
        frame["traded"]
    )

    previous_high = frame["high"].shift(1)
    previous_low = frame["low"].shift(1)
    plus_dm = (frame["high"] - previous_high).clip(lower=0.0).where(traded_pair)
    minus_dm = (previous_low - frame["low"]).clip(lower=0.0).where(traded_pair)
    tr14 = true_range.where(traded_pair).rolling(14, min_periods=14).mean()
    plus14 = plus_dm.rolling(14, min_periods=14).mean()
    minus14 = minus_dm.rolling(14, min_periods=14).mean()
    dx14 = (100.0 * (plus14 - minus14).abs() / (plus14 + minus14)).where(
        (tr14 > 0.0) & ((plus14 + minus14) > 0.0)
    )
    frame["adx_14_sma"] = dx14.rolling(14, min_periods=14).mean().where(
        frame["traded"]
    )
    frame["traded"] = frame["traded"].map(lambda value: "true" if value else "false")

    columns = [
        "step",
        "open",
        "high",
        "low",
        "close",
        "traded",
        "ema_5_ratio",
        "ema_10_ratio",
        "ema_20_ratio",
        "ema_50_ratio",
        "ema_100_ratio",
        "ema_200_ratio",
        "macd_histogram_pct",
        "rsi_14",
        "atr_pct_14",
        "adx_14_sma",
        "trade_date",
    ]
    frame[columns].to_csv(OUTPUT, index=False, float_format="%.17g", na_rep="")
    print(f"wrote {ROWS} rows to {OUTPUT}; pandas {pd.__version__}")


if __name__ == "__main__":
    main()

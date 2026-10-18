# KBS targeted history probes — 2026-10-19

Four explicit, one-call KBS OHLCV probes checked dates where public sources
disagreed or where VCI history was empty. Each request ran through
`vnpipe probe-ohlcv --active`, refreshed authenticated absolute quota before
the call, requested `raw_prices=true`, and wrote only a compact report. The
probe path is intentionally metered but does not ingest rows into PostgreSQL.
No retries were made.

The preflight snapshot [`2026-10-19.passive.json` (local evidence file `../2026-10-19.passive.json`; not published)
reported 3,076/10,000 daily and 5,450/100,000 monthly calls used before these
samples. The authenticated key is the Community tier; vnstock's CLI status
field calls this `free`. KBS is listed as an allowed Community OHLCV source in
the [official source documentation](https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources).

| Symbol/date | KBS response | Cross-check | Finding |
| --- | --- | --- | --- |
| CDG, 2025-05-13 | 21 rows from 2018-10-25 through 2025-05-13; close 2.4, volume 100 | HNX exact-date report and VNDirect both report 100 | Confirms the execution. This date is outside the current VCI zero-volume issue set. |
| VFC, 2026-07-03 | 795 rows from 2018-10-03 through 2026-06-17; no requested-date row | HNX exact-date report and VNDirect report one share on 2026-07-03 | KBS misses a known execution. Its missing row is not no-trade evidence. |
| NAS, 2020-10-15 | 262 rows from 2018-10-01 through 2020-10-15; close 26.9294, volume 80 | VNDirect, DNSE and CafeF report volume 80; VCI has `ZERO_VOLUME_UNVERIFIED` | KBS independently confirms this issue date, already classified as positive activity by existing alternate sources. It does not reduce the 14,333 unresolved-date count. |
| UTT, 2026-10-16 | zero rows over 2025-10-17 through 2026-10-16 | VCI has no OHLCV rows; CafeF and VNDirect have zero-volume histories; HNX reports cover the 16 dates omitted by CafeF | No KBS OHLCV history was available for the period. Do not make flat reference-price bars. |

KBS NAS close 26.9294 matches the saved DNSE close but differs from the
VNDirect raw close of 29.0. The request's `raw_prices=true` flag does not by
itself establish the historical adjustment basis or vintage. Keep the KBS
series separate and use its positive volume only as activity evidence.

## Reports and hashes

| Report | SHA-256 |
| --- | --- |
| `2026-10-18-CDG-184937.835352200Z.json` | `B8D0BD6116D0E26EB5F9A310A708E397349C25D6BA5DDBC6F4B59C3402913117` |
| `2026-10-18-VFC-184951.270865800Z.json` | `FDF81259C26371074905A9945A713A697946BC5919367E3E324DA84BCE8172A7` |
| `2026-10-18-NAS-185005.875129200Z.json` | `B15AA70478098F9BC5B8059D7C5CA751A841D363ACCEBDD1E35DE1DE774A490E` |
| [`UTT report` (local evidence file `../phase1-utt/2026-10-18-UTT-185217.232605400Z.json`; not published) | `8E4E118F42D0E59C396B0DFA80BFF7FB77C97C4BFE39C89C348B6185EEBE7B48` |

The UTT report was placed alongside the existing UTT source audit. No KBS
response was imported into `raw.landings` or canonical bars by these probes.

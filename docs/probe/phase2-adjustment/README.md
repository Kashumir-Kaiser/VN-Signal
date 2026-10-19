# Phase 2 price adjustment audit

Audit date: 2026-10-19. This audit resolves the Phase 2 historical-price basis. It keeps the source landings immutable and routes model prices through the VNDIRECT point-in-time series.

## Coverage and source choice

The local PostgreSQL `vnsignal` audit found:

| Series | Rows | Tickers | Same-date VNDIRECT coverage |
| --- | ---: | ---: | ---: |
| VNDIRECT raw OHLC plus adjusted snapshot | 2,844,683 | 1,519 | — |
| DNSE adjusted OHLC | 2,172,122 | 1,515 | 2,172,122 / 2,172,122 |
| VCI canonical adjusted OHLC | 1,809,966 | 1,502 | 1,809,961 / 1,809,966 |

All 2,844,683 VNDIRECT rows have complete adjusted OHLC and a fetch vintage. No symbol has more than one VNDIRECT adjustment vintage. All 1,519 symbols have a bar on 2026-10-16. The five VCI sessions without a VNDIRECT counterpart are CTR on 2022-02-16 through 2022-02-22; the lifecycle audit documents those repeated rows as invalid after its UPCoM trading ended and before its first HOSE session. Migration 027 records UTT in `ops.ml_symbol_scope` as explicitly excluded, so the market-wide Phase 2 function returns the other 1,518 symbols. UTT's source rows remain preserved for audit and survivorship work.

Migration 027 adds a set-based overload, `core.vndirect_bars_as_of(as_of_date)`, alongside the existing per-symbol function. Both apply `ops.ml_symbol_scope` exclusions and return the full history through the requested session, re-scaled to the adjustment factor effective on that session. The bulk function requires an exact-date anchor and a complete, single-vintage history per symbol; it never fills missing ticker sessions. Its `price_basis` is `adjusted_as_of`, and it retains VNDIRECT landing and row lineage. Phase 2 uses this single full-coverage price series for all in-scope training dates. VCI and DNSE remain in the database as source-attributed quality cross-checks; their adjusted snapshots are not spliced into the training price series. The historical market dates are still present through VNDIRECT, so the provider adjustment conflicts do not remove ticker/dates from Phase 2.

For a feature window ending on signal date `D`, query the VNDIRECT function as of `D`. For a forward label ending on `T`, query it once as of `T`, then read both the signal-date and target-date prices from that returned series. This keeps both label endpoints on the same adjustment basis. Zero-volume bars retain `is_traded=false`; they are not treated as executed prices or silently filled.

## PRC conflict resolved against public records

CafeF's historical endpoint returned a single PRC row for 2023-03-29. The archived response is [`cafef-prc-2023-03-29.json`](cafef-prc-2023-03-29.json), SHA-256 `87E842F9885D9944401969E95403EEFFA02B974D3D051CDAF7E2065254DB5E7D`. It reports raw open/high/low/close of 65/70/63/68 thousand VND and matched volume 36,000. The same response's adjusted field is 25.62; that field is not used as the ML basis because it does not match the validated current adjustment snapshot.

VSDC's [2022 PRC cash-dividend notice](https://vsdc.vn/vi/ad/156913) records VND 35,000/share with a 2023-03-31 record date. On the 2023-03-30 ex-right session, the theoretical reference based on the prior 68.0 close is 33.0. The database shows:

| 2023-03-29 value | Price |
| --- | ---: |
| CafeF raw close | 68.00 |
| VNDIRECT raw close | 68.00 |
| VCI adjusted close | 9.98 |
| DNSE adjusted close | 20.56 |
| VNDIRECT latest adjusted close | 10.010 |

VNDIRECT's latest snapshot factor changes from `10.010 / 68 = 0.147206` on March 29 to `9.161 / 30.2 = 0.303344` on March 30. The pre/post factor ratio is 0.4853, matching the ex-right reference ratio `(68 - 35) / 68 = 0.4853`. DNSE's value is missing that factor: `20.56 * 0.485294 = 9.978`, matching VCI's 9.98 to provider rounding. The underlying trade is valid; the discrepancy is resolved through the point-in-time VNDIRECT series, not by dropping PRC or mutating the DNSE landing.

The same VNDIRECT snapshot also follows later PRC actions: the 1,000 VND/share 2023 dividend recorded by VSDC for May 2024, the [12:19 bonus-share issue](https://vsdc.vn/vi/ad/182393) with a 2025-05-15 record date, and the [1:1 rights issue at VND 11,500/share](https://vsdc.vn/vi/ad1/188281) with a 2025-10-30 record date. Its factor shifts on those windows are consistent with the respective cash, bonus, and subscription-price adjustments; VCI and VNDIRECT adjusted closes match at the May 14 and October 29 checks; the May 13 pre-event closes differ by 0.3%.

The new fixture-backed SQL assertions exercise the same dividend math: before the ex-right session the March 29 close stays at 68; as of March 30 that prior close becomes approximately 33; and the latest snapshot's March 29 close is 10.01. The raw CafeF API response is preserved here for repeatable verification.

The corresponding VSDC HTML notices are archived in this folder: `vsdc-prc-2022-cash-dividend.html` (SHA-256 `887961F0DF3208290FAFF8D3E11750D4889F03CA245D47859A1C7388010F87AE`), `vsdc-prc-2023-cash-dividend.html` (`9BD779C0394B541D8C28113B7486F20C56AA102E9106602BB5544DCDAB04BB12`), `vsdc-prc-2025-bonus.html` (`3CC7B0547D374C6973DF4DC222012D02EBFE8D4279AA9F047650F71ACE482A05`), and `vsdc-prc-2025-rights.html` (`2B388F8C7DB0E78FB714F2F51B19D4BB4FCFEDA5DD402405A3D3093C6E05D911`).

## Sources

- [VSDC PRC 2022 cash dividend](https://vsdc.vn/vi/ad/156913)
- [VSDC PRC 2023 cash dividend](https://vsdc.vn/vi/ad1/170365)
- [VSDC PRC 2025 bonus issue](https://vsdc.vn/vi/ad/182393)
- [VSDC PRC 2025 rights issue](https://vsdc.vn/vi/ad1/188281)
- [CafeF PRC historical-price page](https://cafef.vn/du-lieu/lich-su-giao-dich/hnx/prc-1.chn)
- [VNDIRECT adjusted-price explanation](https://dstock.vndirect.com.vn/lich-su-gia/VND)

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

Migration 027 adds a set-based overload, `core.vndirect_bars_as_of(as_of_date)`, alongside the existing per-symbol function. Both apply `ops.ml_symbol_scope` exclusions and return the full history through the requested session, re-scaled to the adjustment factor effective on that session. The bulk function requires an exact-date anchor and a complete, single-vintage history per symbol; it never fills missing ticker sessions. Its current `price_basis` is `adjusted_as_of_reference`, and it retains VNDIRECT landing and row lineage. Phase 2 uses this single full-coverage price series for all in-scope training dates. VCI and DNSE remain in the database as source-attributed quality cross-checks; their adjusted snapshots are not spliced into the training price series. The historical market dates are still present through VNDIRECT, so the provider adjustment conflicts do not remove ticker/dates from Phase 2.

For a feature window ending on signal date `D`, query the VNDIRECT function as of `D`. For a forward label ending on `T`, query it once as of `T`, then read both the signal-date and target-date prices from that returned series. This keeps both label endpoints on the same adjustment basis. Zero-volume bars retain `is_traded=false`; they are not treated as executed prices or silently filled.

## Raw source fields versus Phase 2 prices

`core.bars_daily_sources.o/h/l/c` and `adj_basis='unadjusted'` correctly describe the immutable raw VNDIRECT landing. Migration 026 stores VNDIRECT's separate adjusted `ad*` snapshot in `adjusted_o/adjusted_h/adjusted_l/adjusted_c` with its fetch vintage. Phase 2 must read `core.vndirect_bars_as_of(symbol_id, as_of_date)` or the market-wide overload; these functions return `price_basis='adjusted_as_of_reference'`. Do not relabel or overwrite the raw fields.

The registered PostgreSQL database was checked on 2026-10-19 against three distinct cases:

| Check | As-of session | Stored raw close | Latest retrospective adjusted close | Function close |
| --- | --- | ---: | ---: | ---: |
| PRC before ex-right | 2023-03-29 | 68.0000 | 10.0100 | 68.0000 |
| PRC prior session, after VND 35,000 dividend became effective | 2023-03-30 | 68.0000 | 10.0100 | 32.9988 |
| FPT prior session, after VND 1,000 dividend became effective | 2024-12-02 | 144.3000 | 109.6580 | 143.3043 |
| FPT ex-right session | 2024-12-02 | 142.2000 | 108.8130 | 142.2000 |
| AGG first trading day | 2020-01-09 | 30.0000 | 13.8960 | 30.0000 |

These checks show the function removes later retrospective adjustments from the history through the requested date. The PRC dividend is documented by [VSDC](https://vsdc.vn/vi/ad/156913); FPT's VND 1,000 dividend and ex-right session are supported by [VSDC](https://vsdc.vn/en/ad/176881) and the [HOSE-hosted disclosure](https://staticfile.hsx.vn/Uploads/UploadDocuments/2374370/20250514%20-%20CFPT2407%20-%20BCB%20chao%20ban%20bo%20sung%20lan%201.pdf). The [State Securities Commission's AGG listing notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/l/chitit?dDocName=APPSSCGOVVN162130344) identifies 2020-01-09 as the first trading day.

The same database check returned 2,844,435 in-scope model rows for 1,518 symbols from 2018-10-01 through 2026-10-16; every row was `adjusted_as_of_reference`. It retained 1,021,077 zero-volume rows with `is_traded=false`. The 248-row difference from the 2,844,683 raw VNDIRECT rows is exactly UTT's explicit, previously approved model-scope exclusion; no row was removed for an unresolved VCI/DNSE price disagreement. Phase 2 feature and label generation is still future work, so this verifies the price input rather than claiming Phase 2 is complete.

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

## VNDIRECT reference gap on 2019-01-02

The first-session reference gap is resolved in migration 030. The source had `basicPrice=0` on 684 in-scope bars for 2019-01-02. The override ledger resolves all 684 without changing source rows: DSN's factor is `59.3/62.9`, supported by [VSDC's dividend notice](https://vsdc.vn/en/ad/125616) and the [ex-right reference calculation](https://cophieu68.vn/quote/event_calc.php?id=dsn); the other 683 factors are 1.0 after cross-checking the [VSDC record-date calendar](https://vsdc.vn/en/lich-giao-dich?date=03%2F01%2F2019&tab=LICH_THQ), current symbol scope, and adjusted-snapshot continuity. The full affected-row counts, including 23 zero-volume UPCoM rows, and per-row evidence are in [`2019-01-02-reference-resolution.md`](2019-01-02-reference-resolution.md).

After migration, the registered market-wide as-of function returned all 2,844,435 in-scope rows for 1,518 symbols through 2026-10-16. The reference view had zero NULL factors; 1,021,077 zero-volume observations remain marked `is_traded=false`. For DSN, the prior 62.9 close becomes 59.3 as of the ex-right session, while the observed 58.5 close is preserved.

## Resolve the remaining 641 VNDIRECT reference candidates

The earlier recommendation to keep unresolved price rows out of Phase 2 was wrong. Resolve the candidate sessions and keep every valid source bar in the price series, including UPCoM/SPC sessions with zero volume. The 641 flagged ticker/sessions now have 42 official corporate-action factors and 599 documented no-action factors of 1.0. UTT remains excluded only under the user's separate, evidence-backed scope decision.

The action set is matched against VSDC's official per-ticker calendar and archived notices; event terms are cross-checked against Cophieu68's calculator. Factors use the official theoretical reference formula with cash dividends, bonus/stock distributions, and rights issues. Listed-market baselines use the preceding valid close. UPCoM uses the last traded weighted-average price; where intervening sessions have no matches, carry the exchange reference across those sessions rather than treating a stale `basicPrice` as a new action. This resolves CH5's 2021-06-07 reference from the last traded VWAP of 15.0, not the stale 13.7 carried through two zero-volume sessions. For CTS, the VSDC terms include all three distributions (21.96% + 3.73% + 3.73%). The formulas are consistent with the [VSDC ex-right guidance](https://vsdc.vn/vi/ad/195688), the [HOSE reference-price rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372202/5.Gia%20tran%20san%2C%20gia%20tham%20chieu%2C%20gia%20dong%20cua.pdf), and [HNX's UPCoM reference-price FAQ](https://cbtd.hnx.vn/vi-vn/hoi-dap.html). The AAM 2019-07-10 cash-dividend action is supported by [VSDC notice 57234](https://vsdc.vn/vi/ad/57234), which records 500 VND/share and a 2019-07-11 record date.

Five 2025-05-13 VNDIRECT OHLC bars (FMC, FTS, GEX, VNM, and VNS) already contain the next session's corporate-action adjustment even in their raw OHLC fields. Their dated CafeF raw OHLC values are applied through a separate, evidence-linked model-bar override, and each correction points to its VSDC notice. The raw VNDIRECT OHLC, volume, `is_traded`, landing, and row lineage stay unchanged. Migration 031 adds this model-price layer and the delist/relist episode handling; migration 032 seeds all 641 factor decisions and five OHLC corrections. Factors are accumulated in log space within each trading episode.

The reproducible resolution ledger is [`reference-factor-resolution-ledger.csv`](reference-factor-resolution-ledger.csv); the five price corrections are in [`vndirect-model-bar-overrides.csv`](vndirect-model-bar-overrides.csv). VSDC, CafeF, and Cophieu68 responses are archived beside these files with hashes. `reconcile_reference_factors.py` regenerates both ledgers and migration 032 from the archived audit inputs. Phase 2 should consume `core.vndirect_bars_as_of(...)`, which now uses the corrected model OHLC and retains the full source row history. Feature and label generation, point-in-time fundamentals, leakage checks, and feature-parity tests still remain before Phase 2 is complete.

## Retain Vietnamese open/range observations

The follow-up audit found 374 VNDIRECT rows where the raw `open` sits outside the reported `high`/`low` range. The user confirmed this relationship can be valid for Vietnamese market data. Do not reject, omit, or replace these rows based on a generic OHLC enclosure check. The exact-date comparison, query evidence, cross-source page hashes, and limitations are documented in [`the open/range audit`](ohlc-discrepancy-audit-20261019/README.md). All 374 rows are already present in the point-in-time adjusted Phase 2 input.

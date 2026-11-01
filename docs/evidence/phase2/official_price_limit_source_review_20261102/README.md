# Official price-limit source review — 2019-01-02

This review checks exchange-published limits against the quarantined BSC
responses for the 31 symbols whose 225 current-hash execution weights remain
null. It is evidence capture only: no raw, core, or feature rows were changed,
and no price-limit fallback was added.

## HNX UPCoM report

The official HNX price-fluctuation report returned one row for each of the 27
UPCoM residual symbols. Its reference, ceiling, and floor values match the
corresponding BSC observations. Its reported close matches BSC and can differ
from the archived VNDIRECT bar close. The report shows a dash for open, high,
and low, and contains no volume field.

The report therefore corroborates the official daily price bands, but does not
validate the VNDIRECT OHLC path or independently establish traded volume.
It cannot close the three positive-volume close conflicts (BSL, DND, and SGP),
and it does not supply the missing executable OHLC for the other UPCoM rows.
The comparison file records exact matches for reference, ceiling, floor, and
close on 27/27 symbols. Its BSC inputs show zero matched volume for 24 symbols
and positive matched volume for the other three; HNX did not report volume.

## HSX quote report

The official HSX Swagger contract and quote report were captured with normal
TLS verification. The historical VNUTI report includes KHP. It reports
reference 10.20, ceiling 10.90, floor 9.49, zero open/high/low/close, and zero
matched volume. This corroborates KHP's limit bands and absence of matched
trading, but provides no executable OHLC. Queries using tradingBy=AFX,
tradingBy=PVP, and tradingBy=TCI returned empty rows. The Swagger contract
does not define tradingBy as a security-symbol parameter, so those empty
queries are not treated as proof that no official record exists for those
securities.

## Decision

Do not import these observations into the execution-weight path. Migration 106
requires complete source-row-linked OHLC and limit evidence; the official HNX
report is limit-only, while the KHP quote reports zero OHLC. A new source
branch would need to preserve the distinction between official price bands,
the VNDIRECT bar, and executable trades. Keep the 225 weights null and
quarantined until evidence satisfies that contract or the execution policy is
revised with tested handling for non-traded/synthetic bars.

## Reproduction

- Capture code: capture_price_limit_sources_20261102.py
- Raw responses and source hashes:
  captures_20261102/capture_manifest.json
- HNX normalized rows:
  captures_20261102/hnx_upcom_price_rows_20190102.csv
- HNX/BSC field comparison:
  captures_20261102/hnx_bsc_comparison_20190102.csv
- The script uses public HNX/HSX endpoints, verifies TLS certificates, and
  makes no vnstock calls or database writes. HNX requests are spaced by 600 ms.

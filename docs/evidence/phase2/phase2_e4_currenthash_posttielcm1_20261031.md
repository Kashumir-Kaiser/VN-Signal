# E4 current-hash reconciliation after TIE and LCM — 2026-10-31

## Result

This report uses V3 feature-set hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b` in the
disposable report clone `vnsignal_phase2_report_20261019`. The census measures
gaps between adjacent feature rows on the effective-session calendar. The
legacy `prior_trade_date` and `next_trade_date` column names do not prove that
either feature endpoint traded.

| Measure | Current result |
| --- | ---: |
| Feature-row gaps / missing effective sessions | 221 / 3,225 |
| Strictly verified transfers / sessions | 218 / 1,532 |
| Intervals without a strict transfer match / sessions | 3 / 1,693 |
| Separately supported CTR and PTM lifecycle cases / sessions | 2 / 1,686 |
| Remaining non-CTR/PTM unresolved intervals / sessions | 1 / 7 |
| Intervals with intervening bars / source rows | 1 / 0 |

The remaining unmatched intervals are CTR (a separate lifecycle case), PTM
(a separate lifecycle case), and GDW (2018-12-06 to 2018-12-18; seven
effective sessions: 2018-12-07, 10, 11, 12, 13, 14, and 17). GDW has zero
intervening bars and zero source rows in the
exact gap. Its 2018-12-06 feature row is marked `is_traded=false`; its last
positive-volume bar on or before that feature row is 2018-12-03. No individual
gap-session trade, suspension, or no-trade status is inferred. The official
HNX evidence establishes the first HNX trade on 2018-12-18, but no captured
authoritative source yet establishes the prior UPCoM endpoint. See the
[GDW source-gap note](phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md).

TIE and LCM now pass the strict verified-transfer view in the disposable
clone as events 290 and 291. TIE's HNX article states HOSE delisting effective
2019-08-01 and first UPCoM trade 2019-08-09; the signed HNX first-trade notice
reports 9,569,900 shares. The stored 2019-07-31 prior endpoint is supported
by a positive-volume VCI bar and the effective-session calendar; the HNX
article does not separately call it the final HOSE trading day. LCM's signed
HOSE Decision 520/QD-SGDHCM states final HOSE trading on 2022-08-26,
delisting effective 2022-08-29, and 24,633,000 shares. The signed HNX notice
states first UPCoM trading on 2022-09-09 and the same share count. VSDC's
2022-08-31 transfer-data date remains a separate milestone. Details, hashes,
and import logs are in the [TIE/LCM source and import packet](phase2_e4_remaining_gap_probe_20261031/tie_lcm_primary_sources_20261031/README.md).

The TIE and LCM import added four immutable source landings and two transfer
events in the disposable clone. The recorded idempotent replay inserted no
duplicate landings or events. No bars, source rows, features, labels, or
per-session statuses were modified.

## Endpoint semantics

The refreshed endpoint audit finds 52 prior and 41 next feature-row endpoints
with `is_traded=false`, and 52 prior feature dates after the last positive
volume bar observed by those dates. It records 218 strict transfer matches;
it does not infer a positive-volume trade or suspension for any absent
session.

## Reproducible evidence

- [Gap-census SQL](phase2_e4_currenthash_gap_pairs_20261031_posttielcm1.sql),
  [CSV](phase2_e4_currenthash_gap_pairs_20261031_posttielcm1.csv), and
  [run log](phase2_e4_currenthash_gap_pairs_20261031_posttielcm1.log)
- [Endpoint-semantics SQL](phase2_e4_feature_endpoint_semantics_20261031_posttielcm1.sql),
  [CSV](phase2_e4_feature_endpoint_semantics_20261031_posttielcm1.csv), and
  [run log](phase2_e4_feature_endpoint_semantics_20261031_posttielcm1.log)
- [TIE/LCM source and import packet](phase2_e4_remaining_gap_probe_20261031/tie_lcm_primary_sources_20261031/README.md)
- [GDW source-gap note](phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md)

E4 remains **PARTIAL**. Phase 2 remains **OPEN**. Suggestions remain disabled.

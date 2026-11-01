# E4 current-hash continuity after GDW source capture — 2026-11-02

This read-only census uses current V3 feature hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b` from
disposable clone `vnsignal_phase2_report_20261019`.

| Measure | Result |
| --- | ---: |
| Feature-row gaps / missing effective sessions | 221 / 3,225 |
| Strict source-verified transfers / sessions | 219 / 1,539 |
| Separately documented CTR/PTM lifecycle cases / sessions | 2 / 1,686 |
| Unresolved non-CTR/PTM intervals / sessions | 0 / 0 |
| Intervals with intervening bars / source rows | 1 / 0 |

The new GDW interval spans seven sessions, 2018-12-07 through 2018-12-17.
HNX Notice 1385/TB-SGDHN establishes the final UPCoM session on 2018-12-06
and cancellation effective 2018-12-07. HNX Notice 1458/TB-SGDHN establishes
the first HNX session on 2018-12-18. Event 292 now matches the feature interval
with zero intervening bar rows and zero source rows. The separate HNX daily
report has zero matched volume on the final-session date. No individual
intervening session is assigned a trading or suspension status.

CTR is separately supported by HNX Notice 89/TB-SGDHN and the SSC first-HOSE
notice; its five stored rows in the interval remain excluded from ML
eligibility. PTM is separately supported by HNX Notice 1315/TB-SGDHN and the
2025 HNX first-return notice. These are lifecycle endpoints, not inferred
transfer events. Their evidence and decision are recorded in
[`docs/DECISIONS.md`](../../../../../DECISIONS.md) and the prior lifecycle
capture packets.

The endpoint audit still records 52 prior and 41 next feature-row endpoints
with `is_traded=false`, and 52 prior feature dates after their last positive
volume bar. These are endpoint-semantics observations; they do not create an
unclassified continuity interval. The full integrity report separately
records zero duplicate-key groups and zero rank-range failures for the
2,844,435-row current-hash V3 set.

Evidence is in the sibling
[`gdw_hnx_deregistration_capture_20261102` source/import packet](README.md):
the successful report-clone import log, full-range gap census, endpoint
semantics audit, CSV outputs, and reproduction SQL. The report clone received
only the two append-only source landings and one verified lifecycle event;
feature, label, bar, and production tables were not modified.

E4 continuity: **PASS**. Phase 2: **OPEN** because 225 execution weights
remain quarantined for source conflicts; do not enable suggestions.

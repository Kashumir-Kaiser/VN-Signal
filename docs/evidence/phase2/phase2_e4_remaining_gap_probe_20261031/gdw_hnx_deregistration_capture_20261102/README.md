# GDW HNX venue endpoints — 2026-11-02

## Primary-source result

HNX Notice **1385/TB-SGDHN**, dated 2018-11-21, names GDW and states:

- Last trading day on HNX/UPCoM: **2018-12-06**.
- UPCoM registration cancellation effective: **2018-12-07**.

HNX Notice **1458/TB-SGDHN**, dated 2018-12-06, states that the first HNX
trading day was **2018-12-18** and lists 9,500,000 shares. Both are scanned,
signed HNX notices. Their full PDFs were visually checked; their text layers
are empty.

The captured HNX daily UPCoM report for 2018-12-06 separately records zero
matched volume. Thus, the December 6 record establishes HNX's final eligible
session designation, not that a trade executed that day. The VSDC transfer of
registration/depository data effective 2018-12-11 remains a separate custody
milestone. The seven sessions after December 6 and before December 18 remain
unclassified individually; this evidence does not infer a trade, no-trade,
suspension, or delisting status for any one of them.

## Captures

The reproducible capture script uses Python's default TLS certificate
validation, asserts the HNX host and PDF content type, and fails if either
source's byte count or SHA-256 changes.

| Notice | Official HNX source | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| 1385/TB-SGDHN, 2018-11-21 | [HNX PDF](https://owa.hnx.vn/ftp/cims/2018/12_W2/000000007986358_1385tb_20181121_1.PDF) | 213,730 | `0755fec1e2e91593f2e2506f6fe65e68d70f672c06b809d685a78f7bd799af00` |
| 1458/TB-SGDHN, 2018-12-06 | [HNX PDF](https://owa.hnx.vn/ftp//PORTALNEW/HEADER_IMAGES/20181206/GDW_Ngay%20giao%20dich%20dau%20tien.pdf) | 634,641 | `aeba54a3203a3baf7fb7c6e7ff7b7cedcd3bece591075e232a44c9769bb642e5` |

See [capture manifest](capture_manifest_gdw_hnx_endpoints_20261102.json),
[capture and staging script](capture_gdw_hnx_endpoints_20261102.py),
[landing stage](landing_stage_gdw_20261102.csv), and
[reviewed event stage](transfer_event_stage_gdw_20261102.csv).

## Disposable-clone import and E4 result

The idempotent import script verified both payload hashes, the notice metadata,
the current-hash feature endpoints, the seven-session gap, and the absence of
intervening bar/source rows. It inserted two immutable source landings and
transfer event 292 into disposable clone
`vnsignal_phase2_report_20261019`. It did not change price bars, features,
labels, or production database `vnsignal`.

The updated full-hash census records 219 strict verified transfers covering
1,539 sessions. The two other intervals, CTR and PTM, remain separate and are
supported by their previously reviewed lifecycle evidence. There are zero
unresolved intervals outside those two documented lifecycle cases. CTR's five
stored transition-period bars remain excluded from model eligibility under
the existing dated lifecycle audit; PTM's long absence is bounded by the
official 2018 delisting and 2025 first-return notices. No daily gap-session
state is imputed.

- [GDW event import SQL](import_gdw_transfer_reportclone_20261102.sql) and its
  [successful import log](import_gdw_transfer_reportclone_20261102.log)
- [Updated E4 report](phase2_e4_currenthash_postgdw_20261102.md)
- [Gap census SQL](phase2_e4_currenthash_gap_pairs_20261102_postgdw.sql),
  [CSV](phase2_e4_currenthash_gap_pairs_20261102_postgdw.csv), and
  [run log](phase2_e4_currenthash_gap_pairs_20261102_postgdw.log)
- [Endpoint semantics SQL](phase2_e4_feature_endpoint_semantics_20261102_postgdw.sql),
  [CSV](phase2_e4_feature_endpoint_semantics_20261102_postgdw.csv), and
  [run log](phase2_e4_feature_endpoint_semantics_20261102_postgdw.log)
- [Prior VSDC and daily-report packet](../gdw_transfer_sources_capture_20261102/README.md)

E4 continuity is **PASS**: every current-hash discontinuity is source-supported
as a verified transfer or one of the two separately reviewed lifecycle cases.
The separate 97-chunk integrity audit remains the source for duplicate-key,
rank-range, and feature-row checks. The later target-readiness census found
that all 225 quarantined execution weights are outside the eligible/investable
cohort; preserve them as NULL and do not impute. The current Phase 2 status
and remaining CI sign-off check are recorded in
[`BUILD_STATUS.md`](../../../../BUILD_STATUS.md) and the
[acceptance checkpoint](../../phase2_acceptance_checkpoint_20261102.md).

# Build status — 2026-11-02

## Current Phase 2 status

**Overall: Phase 2 acceptance evidence is complete; final branch CI is the
remaining sign-off check.** The Master Build Spec's Phase 2 deliverable is
SQL features, labels, and a point-in-time fundamentals archive; its explicit
exit tests (real null-rate report, leakage, and feature parity) pass. Recovery
gates E1–E5 are also recorded as passing at their stated scopes. Current-hash
target readiness is confirmed without imputing missing values: 716,739
tier-ranked targets have ranks and execution weights before the migration-059
250-session cooldown. The 225 null execution weights are all 2018 rows with
zero eligible/investable targets; the 5,776 retained members without a tier
and 152 targets without realized volatility remain unranked and must be
excluded by the tier-ranked head selector. The Phase 3 trainer must follow the
head-specific eligibility contract in `docs/DATA_CONTRACT.md`.

The PIT archive covers the 159 symbols in the latest current-hash investable
L1/L2 cohort (100 L1, 59 L2), across all six statement/frequency groups, with
zero availability or lineage violations. It does not cover the other 1,359
feature-universe symbols. Fundamental mappings and overlay rows remain empty,
so optional model B stays disabled; core price-based Phase 3 can proceed
without it. These data gates do not make the product production-ready:
recommendations stay disabled until their later-phase validation. The exact
code candidate `a4b4497` passed hosted Go, Python, and PostgreSQL 16 CI; the
current evidence-only branch commit must also pass CI before merge.
See the [current E4 report](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_postgdw_20261102.md),
[acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261102.md),
and [hosted CI record](evidence/phase2/phase2_github_actions_a4b4497_20261102.md).

The dated build notes below preserve historical checkpoints. When one differs
from this current-status section, use this section and the latest acceptance
checkpoint as the current decision.

### 2026-11-02 — GDW endpoint evidence and acceptance update

HNX Notice 1385/TB-SGDHN establishes GDW's final UPCoM session as 2018-12-06
and cancellation effective 2018-12-07. HNX Notice 1458/TB-SGDHN establishes
the first HNX session as 2018-12-18. The verified source pair is captured and
imported into disposable clone `vnsignal_phase2_report_20261019` as event 292;
no bars, features, or labels were changed. The refreshed full-hash census
records 219 strict transfers / 1,539 sessions, the separately reviewed CTR
and PTM lifecycle intervals / 1,686 sessions, and zero unresolved
non-CTR/PTM intervals. Do not infer individual gap-session activity. See the
[source packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/README.md)
and [recomputed census](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_postgdw_20261102.md).

The 225 2019-01-02 execution weights remain NULL and quarantined because the
available HNX/HSX records do not provide source-linked executable OHLC for
every affected symbol. The current-hash target census confirms all 225 are
outside the eligible/investable cohort; there are no NULL weights among
eligible/investable tier-ranked targets. See the [target-readiness audit]
(evidence/phase2/phase2_phase3_training_target_readiness_20261102.log). The
PIT archive scope and disabled overlay are described above; these limitations
are explicit Phase 3 scope constraints rather than missing-value imputations.

### 2026-11-02 — official limit-source cross-check

The quarantined execution-weight review now includes source-captured HNX and
HSX reports for 2019-01-02. HNX returned exact-date rows for 27 UPCoM residual
symbols; all 27 reference, ceiling, floor, and close values match BSC, while
the VNDIRECT closes differ. HNX supplies no volume and shows no open/high/low.
HSX's VNUTI report confirms KHP's price bands and zero matched volume, but its
OHLC fields are all zero. These exchange reports do not provide the complete
executable OHLC needed by the current weight rule. No rows were imported and
all 225 affected execution weights remain null and quarantined. See the
[official-source review](evidence/phase2/official_price_limit_source_review_20261102/README.md)
and the updated
[BSC residual report](evidence/phase2/phase2_bsc_price_limit_backfill_20190102_20261101.md).

### 2026-11-01 — latest PIT archive continuation and acceptance status

The current-in-scope VCI statement archive is complete for all 159 symbols
marked `is_investable_member` at the latest current-hash tier date
(2026-10-16). The read-only census records 114,293 archive-managed line-item
versions, 114,349 observations, 955 raw landings, and six statement/frequency
groups with all 159 symbols. Availability and landing-lineage checks report
zero violations. This completes archive coverage for that current investable
cohort; it does not establish archive coverage for the remaining 1,359 symbols
or create model-ready fundamentals. Line-item mappings, industry mappings,
and daily overlay rows remain zero, so the separate fundamental overlay stays
disabled. See the [PIT report](evidence/phase2/phase2_fundamentals_pit_coverage_20261101.md)
and its linked captured census/backfill evidence.

Historical checkpoint before the 2026-11-02 GDW notice capture and target
readiness census. Its Phase 2 blockers are superseded by the current status at
the top of this file and the 2026-11-02 acceptance checkpoint.

### 2026-11-01 — BSC historical price-limit backfill for 2019-01-02

Migration 106 added exact, source-row-linked BSC limit fallback for execution
labels and a resumable symbol-batch weight refresh. The report-clone import
contains 834 exact BSC/VNDIRECT matched rows. Across the 14,866 current-hash
label windows spanning 2019-01-02, recomputation populated weights for the
14,641 windows with an imported BSC observation. The 225 remaining null weights
map to 31 quarantined symbols. For all 31, BSC matching volume equals
VNDIRECT volume and BSC reference price equals the VNDIRECT close, but the
reported closes conflict; KHP's BSC close is zero. BSC reports zero matched
volume for 28 symbols; the other three have positive matched volume and still
conflicting closes. No quarantined rows were imported or used to infer a
weight.

The read-only post-refresh audit asserts zero BSC-backed windows with a null
weight and zero windows without exact BSC evidence receiving a non-null weight.
Batch logs, import, migration assertions, and the ticker-level residual census
are recorded in
[`phase2_bsc_price_limit_backfill_20190102_20261101.md`](evidence/phase2/phase2_bsc_price_limit_backfill_20190102_20261101.md).
All database changes remain in disposable clone
`vnsignal_phase2_report_20261019`; production `vnsignal` was untouched.

The clean two-pass PostgreSQL 18 migration harness passed on disposable test
database `vnsignal_phase2_20261101_post106r2_disposable`, including migration
106, its exact BSC fallback fixture, and the batch-refresh assertions. Go test,
Go race, Go vet, all 45 Python unit tests, Python compile/config checks, Rust
formatting, Clippy, and workspace tests passed. GitHub Actions run 162 passed
the Go, Python, and PostgreSQL 16 jobs on committed SHA
`c65adf6edc2b722999d38aa1dcc23c8832875faa`; its PostgreSQL 16 migration and
integration race steps passed. That run predates the current uncommitted
candidate and does not verify this working tree. See the
[`hosted CI record`](evidence/phase2/phase2_github_actions_run_162_20261101.md)
and local logs linked from the
[`Phase 2 acceptance checkpoint`](evidence/phase2/phase2_acceptance_checkpoint_20261101.md).

Historical checkpoint as of 2026-11-01, before the GDW endpoint source pair,
the all-target readiness census, and current-hash acceptance checkpoint were
completed on 2026-11-02. At that time the 225 rows, partial E4 evidence, and
then-current hosted CI were correctly reported as open. Use the current status
and [2026-11-02 acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261102.md)
for the present decision.

### 2026-11-01 — initial PIT fundamentals archive census (superseded same day)

The initial read-only census covered FPT and TCB only. The later
investable-set backfill and post-backfill census are the current evidence; see
the latest PIT status section above and the detailed report at
[`phase2_fundamentals_pit_coverage_20261101.md`](evidence/phase2/phase2_fundamentals_pit_coverage_20261101.md).

### 2026-11-01 — recovery acceptance checkpoint after BSC refresh

The current recovery checklist records E1 as report-produced, E2 and E3 as
passed on the current feature hash, E4 as partial, and E5 as passed for the
2023 repeatability year. E5 was rerun read-only after the BSC import and retains
the same 12 monthly outputs and canonical year hash. Post-migration-109 Go
tests, race tests, vet, 47 Python tests, Rust format/tests/Clippy, and the clean
two-pass PostgreSQL 18 migration harness pass. Hosted Actions run 162 passed
all three jobs on committed SHA `c65adf6`; the current candidate tree was not
part of that run. The gate-by-gate evidence and scope limits are in
[`phase2_acceptance_checkpoint_20261101.md`](evidence/phase2/phase2_acceptance_checkpoint_20261101.md).

This checkpoint's PIT sample was expanded later the same day to all 159 current
investable L1/L2 members. E4 continuity is not closed, 225 execution weights
remain quarantined, and hosted CI has not been run against the current candidate
tree. The separate overlay remains empty and disabled.

### 2026-11-01 — post-migration-109 full label refresh and validation

The resumable current-hash label build is complete. Its durable monthly ledger
has **97/97 chunks done** for labels dated 2018-10-01 through 2026-10-16:
5,688,870 labels, including 3,161,496 READY rows, linked to feature hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b` and
2,844,435 current-hash features across 1,518 symbols. The full-range snapshot
is in [the integrity audit](evidence/phase2/phase2_postrefresh_label_integrity_20261101.log).
The 88 monthly rebuild chunks from 2019-07 through 2026-10 produced 5,216,840
rows after resuming the earlier 84-month run; the active-build transcript is
[here](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261101-071828-893-c424d413.log).

The READY-label audit found matching targets for every current-hash READY row.
225 execution weights remain NULL only for the 31 quarantined symbols whose
2019-01-02 BSC and VNDIRECT closes conflict; no weights were inferred. The
[post-109 target audit](evidence/phase2/phase2_execution_weight_target_integrity_post109_20261101.log)
and [real-data E2 report](evidence/phase2/phase2_e2_currenthash_post109_20261101.md)
record these results. E2 passed at the 40%, 70%, and 95% cutoffs with zero
pre-cut feature, completed-label, and boundary mismatches on the selected
60-symbol cohort.

The fresh two-pass migration harness passed after migration 109. Go test,
Go race, and Go vet; all 47 Python tests; and Rust formatting, all 21 workspace
tests, and Clippy passed. Logs and the remaining Phase 2 limitations are linked
from the [acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261101.md).
Phase 2 remains **OPEN**: the PIT archive covers the current 159-member
investable cohort but not the complete feature universe, the model overlay is
still disabled, E4 has an unresolved seven-session GDW interval, 225 weights
remain quarantined, and hosted CI has not tested the current candidate tree.
Suggestions remain disabled.

### 2026-11-02 — capture GDW's HNX annual-report attachment

The official HNX listed-market disclosure archive returned GDW article 309502,
“Báo cáo thường niên 2018,” and its PDF attachment. The capture used normal
TLS validation; its manifest records the request, article and attachment
metadata, byte count, and SHA-256. Visual review of the corporate-history
section (PDF page 4, printed page 3/22) confirms the issuer's account of its
2010 UPCoM listing and 2018-12-18 HNX listing. The reviewed section does not
give a final UPCoM trading date or cancellation-effective date. Keep GDW's
seven-session gap unresolved and E4 **PARTIAL**. The secondary 2018-12-07
profile lead is not sufficient to import an endpoint.

See the [capture manifest](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_2019_annual_report_capture_20261101/capture_manifest.json),
[saved PDF](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_2019_annual_report_capture_20261101/GDW_annual_report_2018_attachment_01.pdf),
and [source-gap review](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md).

### 2026-11-02 — rerun current Go and Python checks

The Go suite, Go vet, and all 47 Python unit tests pass on the current code
tree. The worker tests used the repository's Python 3.12 virtual environment
explicitly. Evidence: [Go tests](evidence/phase2/phase2_resume_acceptance_20261102_go_test.log),
[Go vet](evidence/phase2/phase2_resume_acceptance_20261102_go_vet.log), and
[Python tests](evidence/phase2/phase2_resume_acceptance_20261102_python_unittest.log).
Rust and PostgreSQL migration checks from 2026-11-01 remain applicable because
no Rust or SQL code changed after those successful runs. The exact evidence
branch commit still needs its hosted CI result before merge.

### 2026-10-31 — current E4 checkpoint after TIE and LCM events 290–291

TIE and LCM now pass the strict verified-transfer view in the disposable
report clone as events 290 and 291. The official HNX TIE chronology places
HOSE delisting on 2019-08-01 and first UPCoM trading on 2019-08-09; signed HNX
Notice 872/TB-SGDHN confirms the first date and 9,569,900 shares. The stored
2019-07-31 prior endpoint has a positive-volume VCI bar and is the effective
session before the HNX cessation date; the HNX source does not separately say
it was TIE's final HOSE trading day. For LCM, signed HOSE Decision
520/QD-SGDHCM gives final HOSE trading on 2022-08-26, delisting effective
2022-08-29, and 24,633,000 shares. Signed HNX Notice 2754/TB-SGDHN gives the
first UPCoM trade as 2022-09-09 with the same quantity. VSDC Notice 152362's
2022-08-31 registration-data transfer date remains distinct from first trade.
Conflicting recap dates/quantities were rejected in favor of these records.

The guarded import added four immutable source landings and two events only
to `vnsignal_phase2_report_20261019`; replay inserted no duplicates. No bars,
source rows, features, labels, or per-session statuses were changed. The
refreshed current-hash census has 221 feature-row gaps / 3,225 effective
sessions, 218 strict transfer matches / 1,532 sessions, and three unmatched
intervals / 1,693 sessions. CTR and PTM remain separate lifecycle cases
(2 intervals / 1,686 sessions). GDW is the only unresolved non-lifecycle gap
(2018-12-06 to 2018-12-18; 7 sessions); its prior-venue endpoint remains
unproven by captured authoritative evidence. It has no intervening bars or
source rows. No gap-session trade, suspension, or no-trade status is inferred.
One interval has intervening bars (CTR, five rows); none has source rows.

The endpoint-semantics audit finds 52 prior and 41 next feature rows with
`is_traded=false`, and 52 prior dates after the last positive-volume bar.
E4 remains **PARTIAL**, Phase 2 remains **OPEN**, and suggestions remain
disabled. See the [current E4 report](evidence/phase2/phase2_e4_currenthash_posttielcm1_20261031.md),
[current gap census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posttielcm1.csv),
[endpoint-semantics audit](evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_posttielcm1.csv),
[TIE/LCM source and import packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/tie_lcm_primary_sources_20261031/README.md),
and [GDW source-gap note](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md).

Current-code checks after migration 105 passed before these evidence-only
updates: `go -C go test ./...`, `go -C go vet ./...`, all 44 Python tests,
`go -C go test -race ./...`, Rust formatting, Clippy, and Rust tests. The
two-pass disposable PostgreSQL 18 migration harness also passed. Logs are
`phase2_20261031_currenttree_post105_*` in the Phase 2 evidence folder. Hosted
Ubuntu/PostgreSQL 16 CI remains NOT RUN; local checks do not replace it.

### 2026-10-31 — historical E4 checkpoint after ASG event 288

Six signed HOSE-to-UPCoM endpoint pairs for DAG, HTT, ITA, LEC, SJF, and TCD
passed the strict verified-transfer view in the disposable report clone. The
import committed 12 immutable signed endpoint landings and six events (IDs
276–281); replay inserted no duplicates. Source dates, legal cessation dates,
first new-venue dates, and share counts match the signed records. Their exact
feature-row gaps each had zero intervening bars and source rows. No bars,
source rows, features, labels, or per-session statuses were changed.

ASG's HNX-to-HOSE transfer also passes the strict verified-transfer view in the
disposable report clone as event 288. Signed HNX Notice 2884/TB-SGDHN states
the final HNX trading day was 2021-09-21 and reports 75,653,891 shares;
signed HOSE Notice 1675/TB-SGDHCM states the first HOSE trading day was
2021-09-27 and reports the same share count. The gap has three effective
sessions and no intervening bars or source rows. `prior_ceased_from=2021-09-22`
records the first effective session after the signed final-trading date; the
notices do not state a separate legal cancellation-effective date. This is a
calendar-derived event boundary, not a statutory delisting date or inferred
per-session status. The import committed two signed endpoint landings and one
event; replay inserted no duplicates. No bars, source rows, features, labels,
or per-session statuses were changed. See the [ASG source and import packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/asg_second_transfer_capture_20261031/README.md).

The current-hash census has 221 feature-row gaps / 3,225 effective sessions,
216 strictly verified transfers / 1,519 sessions, and five intervals without
a strict transfer match / 1,706 sessions. CTR and PTM remain separate lifecycle cases
(2 intervals / 1,686 sessions); three non-CTR/PTM intervals / 20 sessions
remain unresolved: GDW, TIE, and LCM. TIE remains held
for a source chronology conflict; LCM remains held for a share-count conflict.
One interval contains intervening bars (CTR, five rows); none contains source
rows. The endpoint audit still finds 52 prior and 41 next feature-row endpoints
with `is_traded=false`, and 52 prior feature dates after the last positive bar.
No suspension or individual no-trade status is inferred. E4 remains **PARTIAL**;
Phase 2 remains **OPEN** and suggestions stay disabled. See the [current E4
report](evidence/phase2/phase2_e4_currenthash_postasg1_20261031.md),
[current gap census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_postasg1.csv),
[endpoint-semantics audit](evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_postasg1.csv),
and [batch 12 source and import packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/batch12_signed_source_capture_20261031/README.md).

Current-code checks after migration 105 passed before these evidence-only
updates: `go -C go test ./...`, `go -C go vet ./...`, all 44 Python tests,
`go -C go test -race ./...`, Rust formatting, Clippy, and Rust tests. The
two-pass disposable PostgreSQL 18 migration harness also passed. Logs are
`phase2_20261031_currenttree_post105_*` in the Phase 2 evidence folder. Hosted
Ubuntu/PostgreSQL 16 CI remains NOT RUN; these local checks do not replace it.

### 2026-10-31 — historical E4 checkpoint after TNA

TNA's HOSE-to-UPCoM transition now passes the strict verified-transfer view in
the disposable report clone. Signed HOSE Decision 619/QD-SGDHCM and Notice
1903/TB-SGDHCM distinguish the final HOSE trade (2024-09-13), suspension
effective date (2024-09-16), and delisting effective date (2024-11-19).
Signed HNX Notice 5064/TB-SGDHN records the first UPCoM trade (2024-11-29).
The feature-row gap is 2024-11-18 to 2024-11-29, eight effective sessions;
event 274 uses the legal delisting date as prior cessation. Two signed endpoint
payloads and one event were imported, then replayed idempotently. The rejected
initial transaction rolled back. No bars, source rows, labels, features, or
gap-session statuses were changed.

The current-hash census has 221 feature-row gap intervals / 3,225 effective
sessions, 209 strictly verified transfers / 1,473 sessions, and 12 unmatched
intervals / 1,752 sessions. CTR and PTM remain separate lifecycle cases
(2 intervals / 1,686 sessions); 10 non-CTR/PTM intervals / 66 sessions remain
unresolved. One interval contains intervening bars (CTR, five rows); no
interval contains source-archive rows. The endpoint-semantics audit still finds
52 prior and 41 next feature-row endpoints flagged `is_traded=false`, and 52
prior feature dates after the last positive-volume bar. No suspension or
individual no-trade status is inferred. E4 remains **PARTIAL**; Phase 2 remains
**OPEN** and suggestions stay disabled. See the [current E4 report](evidence/phase2/phase2_e4_currenthash_posttna1_20261031.md),
[post-TNA census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posttna1.csv),
[endpoint-semantics audit](evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_posttna1.csv),
and [TNA capture and import packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/tna_transition_capture_20261031/README.md).

Current-code checks after migration 105 passed before this evidence-only
update: `go -C go test ./...`, `go -C go vet ./...`, all 44 Python tests,
`go -C go test -race ./...`, Rust formatting, Clippy, and Rust tests. The
two-pass disposable PostgreSQL 18 migration harness also passed. Logs are
`phase2_20261031_currenttree_post105_*` in the Phase 2 evidence folder. Hosted
Ubuntu/PostgreSQL 16 CI remains NOT RUN; these local checks do not replace it.

### 2026-10-31 — historical E4 checkpoint after SPC

The SPC UPCoM-to-HNX transfer now passes the strict verified-transfer view in
the disposable report clone. Signed HNX Notice 20/TB-SGDHN states SPC's final
UPCoM trade on 2022-01-18 and cancellation effective 2022-01-19; signed HNX
Notice 125/TB-SGDHN states the first HNX trade on 2022-01-27. Both list
10,530,000 shares. VSDC record 147409 separately records the transfer
registration effective 2022-01-21. The HNX listing-index title for article
411175 contains a 2021 year typo; the dates above come from the signed notice,
corroborated by the second HNX notice and VSDC record. Two hash-pinned signed
endpoint payloads and one event were imported, then replayed idempotently. No
bars, source rows, labels, or gap-session statuses were changed.

The current-hash census has 221 feature-row gap intervals / 3,225 effective
sessions, 208 strictly verified transfers / 1,465 sessions, and 13 unmatched
intervals / 1,760 sessions. CTR and PTM remain separate lifecycle cases
(2 intervals / 1,686 sessions); 11 non-CTR/PTM intervals / 74 sessions remain
unresolved. One interval contains intervening bars (CTR, five rows); no
interval contains source-archive rows. No suspension or individual no-trade
status is inferred. The `prior_trade_date` and `next_trade_date` names in the
census refer to feature-row dates: 52 prior endpoints and 41 next endpoints
have `is_traded=false`. The companion audit makes this limitation explicit.
E4 remains **PARTIAL**; Phase 2 remains **OPEN** and suggestions stay disabled.
See the [current E4 report](evidence/phase2/phase2_e4_currenthash_postspc1_20261031.md),
[post-SPC census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_postspc1.csv),
[endpoint-semantics audit](evidence/phase2/phase2_e4_feature_endpoint_semantics_20261031_postspc1.csv),
and [SPC capture and import packet](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/spc_transition_capture_20261031/).

Current-code checks after migration 105 passed before this evidence-only
update: `go -C go test ./...`, `go -C go vet ./...`, all 44 Python tests,
`go -C go test -race ./...`, Rust formatting, Clippy, and Rust tests. The
two-pass disposable PostgreSQL 18 migration harness also passed. Logs are
`phase2_20261031_currenttree_post105_*` in the Phase 2 evidence folder. Hosted
Ubuntu/PostgreSQL 16 CI remains NOT RUN; these local checks do not replace it.

### 2026-10-31 — historical E4 checkpoint after HOT

After the verified HU3/SII batch and the HOT HOSE-to-UPCoM import, the
current-hash census covers 221 gaps / 3,225 effective sessions: 206 verified
transfers / 1,456 sessions and 15 unclassified intervals / 1,769 sessions.
CTR and PTM remain separate lifecycle cases (2 intervals / 1,686 sessions).
The remaining non-CTR/PTM residual is 13 intervals / 83 sessions, with no
intervening bars or source rows. The full census has one interval with bars
(CTR; five lifecycle-conflicting rows) and none with source rows. No
suspension or no-trade status is inferred.

The HNX index ranker checked those 13 residuals: 11 have an exact first-trade
title/date lead, two have no exact lead (ASG and SHB), and none has paired
endpoints. HOT's signed HOSE/HNX endpoint notices match on 8,000,000 shares,
final HOSE trade 2023-04-26, delisting effective 2023-04-27, and first UPCoM
trade 2023-05-12. Its signed HOSE PDF is hosted on CafeF, so the third-party
host limitation is recorded alongside direct HOSE notice/decision metadata
and the official VSDC transfer notice. The HOT event passes
`ops.phase2_verified_security_transfers` in the disposable report clone; no
bars, source rows, labels, or intervening statuses were added. E4 remains
PARTIAL and suggestions stay disabled. See the [current E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx74_hot_20261031.md),
[posthnx74 census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posthnx74.csv),
and [posthnx75 HNX ranking](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/hnx_disclosure_probe_20261031/candidate_gap_endpoint_pairs_summary_20261031_posthnx75.md).

### 2026-10-31 — historical E4 checkpoint after batch 11

The refreshed current-hash V3 census covers 221 gaps / 3,225 effective
sessions. It contains 203 strictly verified venue-transfer intervals / 1,432
sessions and 18 unclassified intervals / 1,793 sessions. The separately
reviewed CTR gap spans 6 sessions and contains five bars but no source rows;
the separately reviewed PTM gap spans 1,680 sessions and has no bars or source
rows. After keeping those lifecycle cases separate, 16 intervals / 107
sessions remain unexplained. No suspension or no-trade status is inferred.

The latest HNX ranking checked the 16 remaining non-CTR/PTM intervals: 14
first-endpoint-only leads, two without an exact title/date lead, and no paired
endpoints. Ten more UPCoM-to-HOSE transitions were captured and verified in
batch 11. E4 remains PARTIAL and suggestions stay disabled. See the [current
E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx71_20261031.md),
[posthnx70 census](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posthnx70.csv),
and [posthnx71 HNX ranking](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/hnx_disclosure_probe_20261031/candidate_gap_endpoint_pairs_summary_20261031_posthnx71.md).

The POW event passes `ops.phase2_verified_security_transfers` in
disposable report clone `vnsignal_phase2_report_20261019`. Signed HNX Notice
1527/TB-SGDHN establishes final UPCoM trade 2018-12-27 and cancellation
effective 2018-12-28. PV Power's contemporaneous issuer announcement reports
first HOSE trading on 2019-01-14. The old VSD page was excluded: its hostname
failed TLS verification, while the current VSDC route for the legacy ID served
an unrelated record. The three captured source records and event added no
bars, price-source rows, or labels. POW capture, review, clone-only import,
and census evidence is under
`docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/pow_transition_capture_20261031_retry1/`.

HHV evidence remains valid: its five bounded, hash-checked source
records and event pass the same strict view. The 27.9 MB issuer annual report
remains hash-pinned and visually reviewed but excluded from raw landings due
to the bounded payload size. The complete source trail is retained under
`docs/evidence/phase2/phase2_e4_remaining_gap_probe_20261031/`.

After batch 11, `go -C go test ./...`, `go -C go vet ./...`, and all 44 Python
unit tests pass. The first Go invocation used the unavailable Windows Store
`python` alias; rerunning with `VNPIPE_PYTHON` set to the installed interpreter
passed. Latest logs are
`docs/evidence/phase2/phase2_20261031_posthnx71_go_test_pythonpath_retry.log`,
`docs/evidence/phase2/phase2_20261031_posthnx71_go_vet.log`, and
`docs/evidence/phase2/phase2_20261031_posthnx71_python_unittest.log`.
Hosted Ubuntu/PostgreSQL 16 CI remains NOT RUN. Phase 2 remains open pending
E4 closure, adequate PIT fundamentals and overlay coverage, exact price-limit
evidence for 14,866 2018 execution weights, and hosted CI. See the
[recovery gate table](#recovery-gates).

### 2026-10-31 — verify FTM/RIC transfers and refresh current E4 (historical checkpoint)

Visually reviewed HOSE delisting decisions and HNX UPCoM profiles establish
FTM and RIC's final HOSE trade date (2022-05-13), delisting-effective date
(2022-05-16), and first UPCoM trade date (2022-05-26). Four captured source
responses and two events were imported only to disposable clone
`vnsignal_phase2_report_20261019`; both events pass
`ops.phase2_verified_security_transfers`.

The refreshed 221-interval current-hash census now has 104 verified transfers
across 766 sessions. After separately reviewed CTR/PTM lifecycle cases, 115
intervals / 773 sessions remain unexplained, with no intervening bars or
source-archive rows in those residual intervals. No suspension or no-trade
status is inferred. E4 remains partial and suggestions stay disabled. See the
[current E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx11_hose_ftm_ric_20261031.md).

### 2026-10-31 — restore derived targets and verify execution weights

The report-clone label refresh and the subsequent independent 2023 E5 build
left current-hash targets missing from 2024 onward. The cause was the target
builder's downstream invalidation rule: rebuilding an earlier range deletes
all target rows from that point onward, then recreates only the requested
range. The build runner now rejects a backward partial label rebuild when
later targets exist. A guarded 2022 test range was rejected before any chunks
were created.

The forward repair rebuilt 34 calendar-month label chunks from 2024-01-01
through 2026-10-16 on disposable clone
`vnsignal_phase2_report_20261019`; runner exit was 0. The original 97 feature
chunks remain done at 2,844,435 rows, and all 97 label chunks remain done at
5,688,870 rows. A strict current-hash check matched all 3,161,496 READY labels
to derived targets, with zero missing targets.

The exact execution-evidence audit now covers every READY current-hash target.
All 3,101,645 targets from 2019 through 2026 have complete source-row-linked
evidence, non-null weights, and zero stored-value mismatches. In 2018, 14,866
windows lack complete linked price-limit evidence (3,364 at five sessions and
11,502 at twenty); their weights correctly remain NULL. Do not treat those
rows as zero weight or as proof a trade was impossible. Full details are in
the [current-hash execution-weight report](evidence/phase2/phase2_execution_weight_coverage_currenthash_20261031.md).

Go tests, vet and race tests pass, all 44 Python unit tests pass, Rust format,
clippy and tests pass, and the disposable PostgreSQL 18 migration plus tagged
integration suites pass on this working tree. E4 remains PARTIAL with 107
unexplained intervals across 697 sessions after the latest source-backed
HNX/HOSE transfers and the separate CTR/PTM lifecycle cases. PIT fundamentals
coverage remains insufficient to enable the overlay. The E1 null-rate-report
exit criterion is met; its 73 measured
deviations above 1 pp and 13 source-unverified fields remain documented
diagnostics, not extra release gates. Hosted Ubuntu/PostgreSQL 16 CI remains
NOT RUN; the [local fixture-gate report](evidence/phase2/phase2_post_hose_local_ci_20261031/README.md)
records the commands, results, and environment differences. Suggestions stay
disabled. See the updated [recovery gate table](#recovery-gates).

The 2023 E5 result remains valid. Its backward rebuild caused the downstream
target loss described above, which has now been repaired and verified. The
current label builder is guarded against repeating that partial-range pattern.

### 2026-10-31 — continue source-backed E4 transfer reconciliation (prior checkpoint)

HNX batches 2–7 added 58 visually reviewed transfer events; a separate HNM
review resolved a company-name conflict using the signed correction notice.
Three targeted cross-exchange source pairs then verified ADG, HHP, and VCA
transfers to HOSE. Every imported event passed the strict transfer-continuity
check and every import was guarded to disposable clone
`vnsignal_phase2_report_20261019`. The full-range current-hash census has 101
verified transfer intervals across 740 sessions, out of 221 observed gaps /
3,225 sessions. After the separately reviewed CTR/PTM lifecycle cases, 118
intervals across 799 sessions remain unexplained; none contains a bar or
source-archive row. The refreshed HNX index ranking has no remaining exact
two-ended title/date lead. E4 remains PARTIAL; no intervening session is
inferred to be a suspension or no-trade day. See the
[current E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx_batches2_7_hose_20261031.md).

### 2026-10-31 — verify PXS HOSE-to-UPCoM transfer and refresh E4 (historical checkpoint)

The signed HOSE PXS decision explicitly identifies the final HOSE trading day
as 2022-06-23 and delisting effective date as 2022-06-24. A capture-time HNX
profile independently gives the first UPCoM trading day as 2022-07-08. Two
original source captures and one transfer event were imported only to the
disposable report clone; the event passes
`ops.phase2_verified_security_transfers`. The event closes this one 10-session
gap without inferring activity during the interval.

The refreshed current-hash census still covers 221 gaps / 3,225 sessions and
now has 102 strictly verified transfers / 750 sessions. After the separately
reviewed CTR/PTM lifecycle cases, 117 intervals / 789 sessions remain
unexplained. The HNX index ranking on those residuals has zero exact two-ended
title/date matches. E4 remains PARTIAL. See the
[PXS E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx_batches2_7_hose_pxs_20261031.md).

### 2026-10-31 — source-verify two DTC transfers and refresh E4

**Historical checkpoint; the later HNX batch 1 reconciliation below supersedes its gap totals.**

Official HNX notices establish DTC's UPCoM-to-HNX transition in November 2021
and HNX-to-UPCoM transition in April 2025. The HNX cancellation/delisting
notices also state the prior-venue final trading days, so both source pairs
match the exact 12-session and 7-session current-hash gaps. Four byte-preserved
captures and two transfer events were imported only into the disposable report
clone; both events passed `ops.phase2_verified_security_transfers`. The
current-hash census still covers 221 observed gaps / 3,225 sessions. It now has
29 verified transfer intervals / 240 sessions, 192 gaps / 2,985 sessions
without verified transfer matches, and 190 unexplained intervals / 1,299
sessions after the separately reviewed CTR/PTM lifecycle cases. Intervening
sessions are not classified as suspensions or individual no-trade periods.
E4 remains partial and suggestions remain disabled. See the
[post-DTC E4 reconciliation](evidence/phase2/phase2_e4_currenthash_postdtc_20261031.md).

### 2026-10-31 — verify ten HNX transfers and refresh E4 again

The bounded HNX disclosure sweep captured 381 listed/UPCoM index pages for
188 unresolved tickers with no failed pages. Ten two-ended leads were selected
for source review. Visual review of 20 official HNX notices confirms exact
final-trade, cessation and next-venue first-trade dates for ART, BLF, CTX, DPC,
HTP, KTT, L43, L61, L62 and SD4. The clone-only append import added 20 source
landings and ten events; all ten pass the strict transfer-continuity view.
The refreshed 221-gap current-hash census now has 39 verified transfers / 335
sessions, 182 gaps / 2,890 sessions without transfer matches, and 180
unexplained intervals / 1,204 sessions after separate CTR/PTM review. Source
availability remains at capture time. No intervening activity is inferred;
E4 remains partial and suggestions remain disabled. See the
[post-HNX batch 1 E4 reconciliation](evidence/phase2/phase2_e4_currenthash_posthnx_batch1_20261031.md).

### 2026-10-31 — HNX PIT sample and secret-scan warning review

The HNX market-wide search returned 43,285 records on this capture, versus
43,252 in the earlier capture. Sampled adjacent interior pages 2,163 and 2,164
had unique IDs and descending publication times across their boundary. This
does not prove a complete snapshot or historical archive. Article 437725
provides a minute-level listing display and two attachment links; the detail
response itself has no publication timestamp or body text. The 26 PDF pages
have no extractable text layer in the recorded pypdf check and require OCR for
automated value parsing. No values were imported. The PIT gate remains open and
the fundamentals overlay stays disabled. See the updated
[PIT source feasibility report](evidence/phase2/phase2_pit_public_source_feasibility_20261030.md).

The API-key warning associated with
`hose_transfer_sources_20261023/landing_stage.csv` was traced to one key-shaped
match in the old committed Base64 payload for the NSC CafeF notice PDF. That
field is valid Base64 source-file data, not a credential field. The current
hex-encoded row decodes to the same 710,412 bytes and SHA-256, and the current
CSV contains no `AIza` substring. The reachable historical commit still has
the old encoding, so a hosted secret-scanning alert may remain until it is
reviewed as a false positive; no history rewrite or external alert change was
made.

### 2026-10-30 full label refresh after price-limit backfill

**Historical checkpoint; the full refresh later completed. Current status is
summarized above.**

The report-clone label refresh for build `phase2-v3-089-full-20261025` is
reprocessing the full 97-month range from 2018-10-01 through 2026-10-16 after
the exact-row price-limit backfill. The current-hash refresh has **79/97
months committed through 2025-04-30**; 18 months remain. Its first May 2025
retry hit the 30-minute statement timeout while a grouped query populated the
session's per-symbol feature-start cache; that transaction rolled back. The
failure is preserved in
[`May cache timeout evidence`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261030-111126-076-7bb08e30.log).
Migration 099 now fills that cache through indexed per-symbol lookups, which
the PostgreSQL plan confirms uses the V3 hash/symbol/date index. The next
retry passed cache population (2,844,435 rows in 5m04s) but timed out before
`START labels` while computing the exact input hash. The 41-date price-day
hash took 1m28s; the old price-limit join plan scanned an estimated 2.84
million observations and expanded to 7.25 million joined rows. May still has
not advanced, and the second failure is preserved in
[`May input-hash timeout evidence`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261030-125155-807-84beb47c.log).

Migration 100 replaces that global join with per-window index lookups while
preserving the selected rows, `DISTINCT`, raw-landing hash, and final order.
The plan estimates 343,540 candidates and 94,490 distinct observations.
Assertions for migrations 099 and 100 pass on the report clone. Both were
applied and checksum-registered directly because `vnpipe migrate` correctly
stopped at migration 033, whose working-tree bytes differ from its applied
checksum; no earlier checksum was changed. The disposable two-pass migration
harness remains required. See the [first-date plan](evidence/phase2/phase2_label_first_date_index_plan_20261030.md),
[input-hash plan](evidence/phase2/phase2_label_input_limit_lookup_plan_20261030.md),
and the [April checkpoint](evidence/phase2/phase2_label_refresh_checkpoint_20261030_0939.log).
Historical baseline rows in `ops.step_runs`
must not be counted as completion of this refresh. At the prior 51-month
checkpoint, median durable duration was 249,807 ms and mean duration was
329,580 ms. October, November, and December durable steps took 101,464 ms,
578,470 ms, and 125,501 ms; their full monthly cycles took about 10m01s,
12m05s, and 9m59s. January's, February's, and March's full cycles took about
12m05s, 5m25s, and 3m56s by the adjacent monthly start notices; April took
about 10 minutes, May about 8 minutes, June about 4 minutes, July about 5
minutes, August about 7 minutes, September about 4 minutes, October about 8
minutes, November about 4 minutes, December about 4 minutes, January 2024
about 4 minutes, February about 5 minutes, March 2024 about 5 minutes, and
April about 6 minutes, May about 6 minutes, June about 9 minutes, July about
15 minutes, August about 14 minutes, September about 8 minutes, October about
26 minutes, November about 9 minutes, December about 7 minutes, January 2025
about 22 minutes, February 2025 about 27 minutes, and March 2025 about 21
minutes. Runtime remains highly variable.
The runner commits each month and
remains in its own PostgreSQL session on the disposable report clone with live
data disabled; it has not modified the registered `vnsignal` database. See the
[refresh log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261029-213115-949-2e88d7f6.log),
[latest checkpoint](evidence/phase2/phase2_label_refresh_checkpoint_20261030_0910.log),
and [migration 097 catalog check](evidence/phase2/phase2_label_series_start_cache_097_20261030.log).

Migration 096 caches first feature dates for the prior-membership guard;
migration 097 reuses the same cache for the liquidity-series start CTE. May
committed before 097, and June is the first completed chunk after it. The
runtime difference is promising but not yet attributable to the migration.
The exact point-in-time cutoff and target ordering hooks were verified in the
installed function. Migration 098 is now applied to the report clone. It
reuses an identical label input hash only within one monthly transaction,
keyed by date range, feature hash, and execution-weight policy; it preserves
the base feature manifest and exact linked price-limit inputs. It was applied
after September's transaction started. October's durable step was 101,464 ms,
November's 578,470 ms, and December's 125,501 ms; the full cycles were about
10m01s, 12m05s, and 9m59s. The initial hash preflight still takes minutes.
These three observations are variable and do not establish a stable speedup.

The remaining project acceptance work after this refresh includes a current-
hash E1 family-attribution review (the [null-rate report](evidence/phase2/phase2_current_hash_null_rates_full_20261029.md) already exists; it
records 73 deviations from the diagnostic 1-point threshold and 13 source-
unverified fields), refreshed derived-target and execution-weight coverage,
the guarded 12-ticker/24-document E4 import and full reconciliation, E5
repeatability on refreshed labels, and exact-tree tests plus the PostgreSQL
migration harness. E2 leakage and E3 real-data parity have passed on the
current feature hash. The Master Build Spec makes the null-rate report itself
an exit criterion; its 1-point deviation threshold is diagnostic, not an
additional hard gate. The guarded E4 packet contains 12 source-endpoint candidates
covering 163 baseline gap sessions. All 24 staged documents currently have
capture metadata, and the importer converts blank optional dates to NULL.
Defer its report-clone import until the label refresh finishes to keep the
report-clone input snapshot stable throughout the run. The current-hash census remains
unchanged until import and reconciliation pass. Offline stage checks are in
the [E4 staging log](evidence/phase2/phase2_e4_stage_integrity_20261030.log).
Migration 095 is applied to the report clone, and the guarded import passed a
rollback-only database run for all 24 landings and 12 events. No E4 rows were
persisted; the real import and full census remain after the label refresh. See
the [migration apply log](evidence/phase2/phase2_095_reportclone_apply_20261030_retry1.log),
[catalog check](evidence/phase2/phase2_095_reportclone_catalog_check_20261030.log),
and [rollback validation](evidence/phase2/phase2_e4_import_rollback_validation_20261030_retry2.log).
The PIT fundamentals archive is
still incomplete: public-news retrieval is not statement-only and does not
prove version history, full-period coverage, or attachment extraction. See the
[PIT probe evidence](evidence/phase2/phase2_pit_public_source_probe_20261030/)
and [E4 source packet](evidence/phase2/phase2_e4_transfer_sources_20261030/).
Phase 2 is open and suggestions remain disabled.

The earlier possible-Google-key alert in the HOSE-transfer staging CSV was
traced to a key-shaped substring inside the base64 encoding of an NSC PDF.
The decoded document contains no such value. The current stage stores the same
verified PDF bytes as hex and all 14 row sizes/checksums match. See the
[secret-scan audit](evidence/phase2/api_key_scanner_false_positive_20261028.md).

### 2026-10-29 resumed full-range feature and label build

The report clone `vnsignal_phase2_report_20261019` has completed the full
current-hash V3 feature stage for build `phase2-v3-089-full-20261025`: 97
monthly chunks and 2,844,435 rows through 2026-10-16, runner exit 0. See the
[full feature run log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261028-204956-199-0ee9b4e0.log).
Migration 094 passed the clean two-pass PostgreSQL migration harness after a
stale stage-version fixture assertion was updated, and it was applied to the
report clone. See the [migration harness](evidence/phase2/phase2_094_full_harness_retry_20261029.log)
and [report-clone apply log](evidence/phase2/phase2_094_reportclone_20261029.log).

The label stage completed on the same 97-month range using bounded monthly
transactions. Its unchanged cache stability guard passed. Runner exit 0; all
97 label chunks are done, totaling 5,688,870 rows through 2026-10-16. The
ledger reports all 97 feature chunks done (2,844,435 rows) as well. The run
log is [here](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261029-024843-010-20801af4.log).
The registered `vnsignal` database has not been modified; the build is on the
report clone. The current-hash E1 null-rate report is now produced, with 73
measured deviations and 13 source-unverified fields recorded without relaxing
the threshold. Current-hash E2 leakage and E3 parity passed. The full E4 census
passed coverage, key, calendar, and rank checks; attribution still leaves 204
continuity intervals (1,481 sessions) unexplained. Current-hash E5 passed for
the full 2023 calendar year. PIT archive coverage, exact-tree CI, and final
Phase 2 sign-off remain open. Suggestions remain disabled until a valid
champion is established. See the [current-hash E4 report](evidence/phase2/phase2_e4_currenthash_20261029.md).

### 2026-10-29 current-hash E4 integrity census

The report-clone census completed in 97 monthly slices over 2018-10-01 through
2026-10-16. All 2,844,435 V3 rows use the current feature hash and exactly match
V2 symbol-date coverage; key, calendar, and rank checks report zero violations.
The full scan found 221 continuity gaps across 3,225 effective sessions.
Source-backed transfer records explain 15 gaps/58 sessions; reviewed CTR and
PTM lifecycle evidence explains two more; 204 gaps/1,481 sessions remain
unresolved, so E4 is partial. A stale POM/QBS seed-scope assertion was fixed
and the refreshed attribution passed. See the [full E4 report](evidence/phase2/phase2_e4_currenthash_20261029.md)
and [integrity log](evidence/phase2/phase2_e4_integrity_report_currenthash_20261029_retry1.log).
The unresolved set is spread across 2018–2026; all 204 intervals have zero
intervening bars and source rows in the extract, so source/lifecycle
classification remains open rather than inferred.

### 2026-10-29 current-hash E5 repeatability

Two independent full-year 2023 label builds passed the 12-month repeatability
verifier on the current feature hash. Each has 12 durable label chunks/720,718
rows and 12 derived-target chunks/418,245 rows. Monthly input/output hashes,
row counts, policy, and the canonical full-year content hash matched. See the
[E5 report](evidence/phase2/phase2_e5_currenthash_20261029.md), [verifier log](evidence/phase2/phase2_e5_repeatability_currenthash_20261029.log), and build A
and B transcripts linked in that report.

### 2026-10-29 current-hash execution evidence

A read-only aggregate over the report clone found 1,984,894 current-hash
execution-target rows, all with NULL weights; zero had an eligible-investable
membership or liquidity tier. At that baseline query, there were no VNDIRECT
daily price-limit observations in the audited table. Migration 062's exact-row
materializer has since completed 52 monthly transactions from 2022-06 through
2026-09 on the report clone. The successful resume log records 3,838 bounded
calls and 1,583,752 staged rows. Together with the earlier historical slices
and the separate 2026-10-01–16 slice, successful materializer reports sum to
2,837,092 rows; this is a log-derived sum, not an independent full-table
recount. Live routes and the registered `vnsignal` database were not used.
The current derived-target rows have not yet been refreshed against these new
inputs. See the [backfill checkpoint](evidence/phase2/phase2_price_limit_backfill_checkpoint_20261029.md)
and [completed resume log](evidence/phase2/phase2_price_limits_20220601_20260930_resume5.log).
The unadjusted VNDIRECT bar table does have
2,844,683 rows for 1,519 symbols, but bars alone do not establish the required
point-in-time limits or listed-share evidence. Execution weights remain
unvalidated and suggestions remain disabled. See the
[execution-weight report](evidence/phase2/phase2_execution_weight_currenthash_20261029.md)
and [aggregate log](evidence/phase2/phase2_execution_weight_summary_currenthash_20261029.log).

### 2026-10-29 current worktree checks

The current checkout passed `go test ./...`, `go vet ./...`, all 41 Python
unit tests, and the Rust workspace tests (21 tests). Live vnstock routes were
disabled for local checks. Migration 094 passed its disposable two-pass
PostgreSQL harness. These local checks do not constitute hosted CI or close
the remaining Phase 2 data and acceptance gates. Logs: [Go tests](evidence/phase2/phase2_go_test_currenttree_20261029.log),
[Go vet](evidence/phase2/phase2_go_vet_currenttree_20261029.log),
[Python tests](evidence/phase2/phase2_python_tests_currenttree_20261029.log),
[Rust tests](evidence/phase2/phase2_rust_tests_currenttree_20261029.log), and
[migration 094 harness](evidence/phase2/phase2_094_full_harness_retry_20261029.log).

After the price-limit handoff, Go tests passed uncached with the installed
Python 3.11 interpreter configured through `VNPIPE_PYTHON`; Go vet passed and
the 41 Python tests passed with live routes disabled. The first test attempt
used the Windows Store Python alias and failed worker tests with exit 9009;
that environment failure is retained, and the uncached explicit-interpreter
retry passed. Evidence: [uncached Go tests](evidence/phase2/phase2_resume4_go_test_uncached_retry_20261029.log),
[Go vet](evidence/phase2/phase2_resume4_go_vet_20261029.log),
[Python retry](evidence/phase2/phase2_resume4_python_unittest_retry_20261029.log),
and [initial environment failure](evidence/phase2/phase2_resume4_go_test_20261029.log).

### 2026-10-28 latest full-range pause

The latest full-range feature attempt for
`phase2-v3-089-full-20261025` stopped in guarded cache preflight when the
five-block warm-up ended without stabilizing under the unchanged 20% check. It exited
before executing feature chunks. The durable ledger is unchanged at 85 done
(2,488,110 rows), one prior failed slice (2025-09, zero rows), and 11 pending
slices (2025-12 through 2026-10-16). PostgreSQL 18 was cleanly stopped at
04:23:05 +07; there is no listener on port 5432. Resume details and the exact
runner settings are in the [pause handoff](evidence/phase2/phase2_pause_20261028.md).
Diagnose cache warm-up instability before retrying; do not relax the guard.

### 2026-10-28 V2 input-hash checkpoint

Migration 093 replaces the repeated wide year-to-date V2 aggregate in the V3
input manifest with exact per-trade-date SHA-256 digests. Statement triggers
mark old and new V2 dates dirty for inserts, updates, deletes, version/date
moves, and truncation; refresh is serialized with source writes. The manifest
retains the V3 year anchor and the original ordered date/digest contract. A
clean, disposable two-pass PostgreSQL migration harness passed, including the
cache mutation assertions and year-anchor test. That test exposed and now fixes
a fixture declaration mismatch: `core.bars_daily_sources.landing_id` is
`bigint`, not UUID.

Local checks also passed `go -C go test ./...`, `go -C go vet ./...`, and all
41 Python unit tests with market access disabled. Evidence is in the
[migration harness log](evidence/phase2/phase2_migration_harness_093_20261028_landing_id_type.log),
[Go test log](evidence/phase2/phase2_host_verification_20261028_go_test.log),
[vet log](evidence/phase2/phase2_host_verification_20261028_go_vet.log),
[Python log](evidence/phase2/phase2_host_verification_20261028_python_unittest.log),
and [hash-stall profile](evidence/phase2/phase2_input_hash_profile_20261028.md).
Migration 093 is applied to the disposable report clone. The 2019-12 manifest
now completes in 61.24 seconds; its 2019 cache covers 250 dates and 326,456 V2
rows, and three real daily digests match the canonical row serialization in
UTC. A retry after one unstable 90-sample preflight passed the unchanged guard
and rebuilt 2019-12 in its own monthly transaction: 29,171 V3 rows. The
2026-10-28 handoff checkpoint has 85 completed months (2,488,110 rows), one
preserved failed month (2025-09), and 11 pending months (2025-12 through
2026-10). The 2025-10 and 2025-11 chunks committed 34,187 and 29,824 rows.
The 2025-12 chunk was intentionally interrupted by a clean PostgreSQL fast
shutdown and rolled back as one monthly transaction; its ledger row remains
pending and can be retried with the same build ID. The runner's failure
companion records the expected connection loss from that shutdown; the
PostgreSQL log ends with `database system is shut down`. The first preflight
failure is retained as evidence; its 15-symbol cohort varied 22.8%, above the
20% limit, and it wrote no feature rows. See the [2019 hash
probe](evidence/phase2/phase2_v2_hash_probe_2019_20261028.log), [successful
2019 chunk log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261028-032134-936-2d22bf35.log),
[Oct–Nov run log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261028-033156-344-a5f0f1a9.log),
[intentional interruption log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261028-033156-344-a5f0f1a9.log),
the [PostgreSQL handoff record](evidence/phase2/phase2_postgres_clean_shutdown_20261028.log),
and [preflight failure log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261028-030957-289-1f9aba9e.log).
PostgreSQL 18 is left stopped cleanly. To resume this bounded slice, start the
same cluster and rerun the same runner arguments and build ID for
2025-10-01 through 2026-03-31; committed months are revalidated and skipped
when their hashes still match, and pending December is rebuilt. April 2026
onward still requires a later run.
The remaining feature months, labels, PIT coverage, current-candidate E1–E5,
exact-tree CI, and final sign-off remain open.

### 2026-10-26 recovery checkpoint

The migration 089 last-400-session feature candidate is now built in bounded
monthly chunks. After four earlier two-month chunks committed 250,328 rows,
build `phase2-v3-089-last400-20261026-r3` completed all 12 remaining monthly
chunks from 2025-11-11 through 2026-10-16: 347,505 rows, runner exit 0, and no
out-of-memory event. Together, the successful 089 chunks cover the full
last-400-session date window, 2025-03-11–2026-10-16, with 597,833 rows. This is
a full-universe recent-history slice, not a full-history rebuild. The prior
2,844,435-row feature range was built under the pre-089 hash; outside the
rebuilt slice the report-clone candidate is still incomplete and must be
treated as mixed-hash until a full-history rebuild is done.

The r2 attempts at 25 and 30 minutes remain recorded as failed attempts; the
smaller monthly transactions supersede neither their audit records nor their
status. The fixed cache guard was not weakened. The r3 run took approximately
2 h 42 min for the 12-month slice, exceeding the 40-minute full-build plan.
Using the recovery prompt's 8 h limit, 4 h 37 min already elapsed, and 90 min
validation plus 15 min margin, the remaining allowed build time was 98 min;
the slice exceeded that allowance. Stop expanding the candidate in this
recovery window. Do not extrapolate a full-history completion time from this
partial run. Labels, current-candidate E1–E5, and exact-tree CI remain open.
Apply the recovery prompt's bounded-slice fallback as a conditional handoff,
not as evidence that the full Phase 2 exit criteria passed. See the [bounded 089 build report](evidence/phase2/phase2_v3_089_last400_build_20261026.md) and [runner log](evidence/phase2/phase2_build_phase2-v3-089-last400-20261026-r3_20261026-104135-874-dd8d4e0f.log).

### Feature build

The pre-089 full-range build has 2,844,435 rows for 1,518 symbols through
2026-10-16, but it does not satisfy the migration 089 feature hash. The 089
candidate has 16 successful chunks over 2025-03-11–2026-10-16: four earlier
two-month chunks (250,328 rows) and the 12 monthly r3 chunks (347,505 rows).
This disjoint recent slice totals 597,833 rows and covers the last 400 sessions;
it does not replace the remaining pre-089 history. Treat the report-clone V3
table as mixed-hash/partial until every historical chunk is rebuilt under the
same feature definition.

The run used 15-symbol input batches, 5-symbol compute batches, 32 MB work
memory, and one month per transaction. Every r3 monthly chunk committed; the
runner reported 12 chunks and 347,505 rows, with exit 0. The `uncovered` count
in the price-day-hash notices means dates newly added to the session-local hash
cache, not missing market data: each newly uncovered count was matched by the
following hash-aggregate count and then recorded in the temporary coverage
table. This does not certify source completeness. The detailed monthly counts
and interpretation are in the [089 last-400 build report](evidence/phase2/phase2_v3_089_last400_build_20261026.md).

The feature-chunk registry still retains one failed 2023 Q3 parent attempt
(covered by successful monthly chunks) and 12 pending quarterly schedule rows
from 2023 Q4 through 2026 Q3. Preserve those audit states. This recovery run
built features only: labels, PIT fundamentals, current-candidate E1–E5
revalidation, and Phase 2 sign-off remain open. Migration 087 preserves all 90
calibration observations, rejects a greater than 20% within-block timing
inversion, and retains the 1.3 exponent and 40-minute budget gates. Its
two-pass disposable migration harness and focused fixtures passed. The
rollback-only 90-sample calibration passed at 32 MB work memory and a
15-symbol fill batch: worst-block 15/30/60 timings were 1.453/2.588/4.193
seconds, maximum exponent 1.006, and projected full-cache time 2.47 minutes
for 1,518 symbols against the 40-minute cap. See the [migration harness](evidence/phase2/phase2_migration_harness_087_20261025.log),
[focused fixture logs](evidence/phase2/phase2_cache_guard_focused_20261025.log),
and [90-sample calibration log](evidence/phase2/phase2_cache_guarded_90_after_migration087_20261025.log).

### Scaling probes

The fixed 90-sample adjustment-cache calibration is separate from the V3 S1
feature-stage probe and passes. S1 now also passes: three rollback-only 2020
trials per size measured median symbol-local feature-batch times of 10.085,
15.141, and 32.633 seconds for 15, 30, and 60 symbols. The adjacent exponents
are 0.586 and 1.108, both below 1.3. The missing third 60-symbol replicate was
run separately after the original probe script omitted it. This closes the S1
scaling probe only; it does not close the other Phase 2 gates. See the [S1 probe SQL](evidence/phase2/phase2_s1_v3_symbol_scale_current_20261025.sql),
[S1 probe log](evidence/phase2/phase2_s1_v3_symbol_scale_current_20261025.log),
[third 60-symbol replicate](evidence/phase2/phase2_s1_v3_symbol_scale_60_replicate_20261025.log),
and [S2 probe](evidence/phase2/phase2_s2_rank_stage_coveridx_rewarmed_20261025.log),
[index plan](evidence/phase2/phase2_s2_rank_stage_explain_coveridx_20261025.log),
and [migration harness](evidence/phase2/phase2_migration_harness_088_fresh_20261025.log).

The 089 last-400 feature stage succeeded only after using calendar-aligned
monthly transactions. Twelve months from 2025-11-11 through 2026-10-16
committed 347,505 rows in about 2 h 42 min total; each month stayed within its
own transaction and the runner completed with exit 0. This is recent-history
coverage evidence, not a full-history timing estimate or a full Phase 2 pass.
See the [monthly result report](evidence/phase2/phase2_v3_089_last400_build_20261026.md)
and [raw runner log](evidence/phase2/phase2_build_phase2-v3-089-last400-20261026-r3_20261026-104135-874-dd8d4e0f.log).

### E3 chunk-boundary repair

The recorded 2023-04-04 mismatch was caused by the SQL builder selecting its
1,000-session EMA/MACD warmup relative to each requested chunk start. The Rust
parity axis anchors history to the calendar year, so the same session could
produce a different EMA when built in a quarterly chunk than in a yearly
chunk. Migration 089 preserves the full shared-builder body for migration
replay, adds a year-anchored implementation and calendar-splitting wrapper,
routes production/scoped callers through that wrapper, rejects unsafe direct
partial-year shared calls, and advances the V3 feature hash.

A rollback-only transaction on the report clone installed migration 089 and
rebuilt symbol 824 for 2023-04-04 using the candidate wrapper. Its
`ema_100_ratio` was `0.0040100067402384365`, matching the independent Rust
reference `0.00401000674023843651` within the unchanged `1e-9` tolerance. The
transaction rolled back; no report-clone feature row or hash was persisted.
The clean disposable two-pass migration harness passed both migration replays
and the complete SQL assertion suite, including feature, shared-builder, rank,
listing-tenure, and public-execution checks. Full 20-symbol-day E3 parity, the
report-clone full-history V3/label rebuild, and the dependent E1/E2/E5 reruns
remain open. See the [full migration harness log](evidence/phase2/phase2_migration_harness_089_20261025.log).

Evidence: [rollback-only real smoke SQL](evidence/phase2/phase2_e3_year_anchored_smoke_20261025.sql),
[smoke log](evidence/phase2/phase2_e3_year_anchored_smoke_20261025.log),
[year-anchored SQL trace](evidence/phase2/phase2_e3_symbol824_ema100_trace_20261025.sql),
[quarter-start trace](evidence/phase2/phase2_e3_symbol824_ema100_chunkstart_20230401_20261025.sql),
and [Rust reference trace](evidence/phase2/phase2_e3_symbol824_ema100_trace_reference_20261025.rs).

### Recovery gates

| Gate | Current result | Evidence and remaining work |
| --- | --- | --- |
| E1 — null rates | **REPORT PRODUCED for the completed current-hash full-range V3 build.** The report covers 2,844,435 rows, 1,518 symbols, and 101 fields under hash `28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b`. It records 73 measured deviations above 1 pp, 15 within 1 pp, 13 source-unverified, and zero mismatches among six rank/input NULL-alignment checks. Flags are preserved; field-level attribution remains open. | [Current-hash E1 report](evidence/phase2/phase2_current_hash_null_rates_full_20261029.md), [clean CSV](evidence/phase2/phase2_current_hash_null_rates_full_20261029.csv), and [run log](evidence/phase2/phase2_current_hash_null_rates_full_20261029.log). |
| E2 — real-data leakage | **PASS on the current-hash candidate.** A PIT-stratified cohort of 60 symbols passed the 40%, 70%, and 95% cutoff perturbation runs. All pre-cut feature bytes, completed labels, and label boundaries matched; each cutoff had nonzero future equity/index perturbations. Rank comparison used the selected 60-symbol population. | [Current-hash E2 report](evidence/phase2/phase2_e2_currenthash_20261029.md), [full assertion log](evidence/phase2/phase2_e2_currenthash_20261029.log), and [assertion SQL](../../tests/sql/phase2_e2_real_assertions.sql). |
| E3 — feature parity | **PASS on the current-hash candidate.** Twenty real source-attributed symbol-days across three dates passed SQL/Rust parity at 1e-9; selected source payloads and feature hashes verified. The recursive Rust pandas golden suite passed 3/3; the PostgreSQL recursive SQL golden passed in the migration 094 disposable harness, and the current-hash EMA100 real smoke matched its independent reference. | [Current-hash E3 report](evidence/phase2/phase2_e3_currenthash_20261029.md), [real parity log](evidence/phase2/phase2_e3_real_parity_currenthash_20261029.log), and [recursive golden test log](evidence/phase2/phase2_e3_recursive_golden_currenthash_20261029.log). |
| E4 — integrity and scaling | **PASS for integrity and documented continuity.** All 97 monthly slices cover 2,844,435 current-hash rows with exact V2 key coverage, no null/duplicate keys, no non-calendar dates, and zero rank/nonfinite/null-alignment violations. The refreshed census has 221 feature-row gaps / 3,225 sessions: 219 strict transfer matches / 1,539 sessions and two separately supported CTR/PTM lifecycle cases / 1,686 sessions. No other interval remains unresolved. GDW's 7-session gap is backed by HNX Notices 1385/TB-SGDHN and 1458/TB-SGDHN, with zero intervening bars or source rows; no individual gap-session status is inferred. One interval in the full census contains five CTR rows, which remain excluded from model eligibility; none contains source-archive rows. The endpoint-semantic audit shows 52 prior and 41 next feature-row endpoints with `is_traded=false`; those row dates are not proof of trades. Cache, S1, and S2 evidence remains limited to its recorded scope. | [Latest E4 report](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_postgdw_20261102.md), [gap-pair CSV](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_currenthash_gap_pairs_20261102_postgdw.csv), [endpoint-semantics CSV](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_hnx_deregistration_capture_20261102/phase2_e4_feature_endpoint_semantics_20261102_postgdw.csv), and [scaling evidence](evidence/phase2/scaling_probe.md). |
| E5 — repeatability | **PASS for the full 2023 calendar year after the BSC backfill.** The read-only recheck matched the two independent builds across all 12 months; both durable year hashes and the canonical content hash are unchanged. The verifier rolled back. | [Post-BSC repeatability log](evidence/phase2/phase2_e5_repeatability_after_bsc_20261101.log) and [acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261101.md). |
| CI — fixture-only | **PASS for current code candidate `a4b4497`.** Hosted Go race/vet, Python unit/compile/config, PostgreSQL 16 migrations/integration race, and Rust checks all passed. Later local changes are evidence-only and do not alter the tested code. | [Runs 165 and 166 record](evidence/phase2/phase2_github_actions_a4b4497_20261102.md). |
| Derived targets and execution weights | **TARGET COVERAGE PASS; EXACT-EVIDENCE COVERAGE PARTIAL.** All 3,161,496 READY labels have targets. For 2019–2026, 3,101,645 targets have complete exact source evidence, non-null execution weights, and zero mismatches. Of 14,866 windows spanning 2019-01-02, 14,641 now have exact matched BSC evidence; the remaining 225 across 31 symbols stay quarantined because BSC and VNDIRECT closes conflict. Their weights remain NULL. | [Current-hash execution-weight report](evidence/phase2/phase2_execution_weight_coverage_currenthash_20261031.md), [BSC backfill report](evidence/phase2/phase2_bsc_price_limit_backfill_20190102_20261101.md), [annual CSV](evidence/phase2/phase2_execution_weight_setbased_audit_currenthash_20261031.csv), and [strict post-repair target-integrity log](evidence/phase2/phase2_execution_weight_target_integrity_postrepair_20261031.log). |

### Historical Phase 2 checkpoint — superseded on 2026-11-02

The status and open items below describe the earlier 2026-10-26/2026-10-31
checkpoint. They are retained as history, not current blockers. The current
acceptance decision, Phase 3 entry contract, and remaining exact-branch CI
check are recorded at the top of this file and in the
[2026-11-02 acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261102.md).

The PIT fundamentals archive has source-backed VCI rows for FPT (768 line
versions, 824 observations) and TCB (592 versions, 592 observations). A fresh
current-hash per-symbol query finds 1,878/2,008 dates with all three statement
types for each symbol: 3,756 dates total, about 0.13% of 2,844,435. Every
archived version uses the explicitly assumed backfill-lag availability basis;
there are no approved line-item or industry mappings and no materialized
overlay rows. Full source/version coverage remains open. See the [current PIT
scope report](evidence/phase2/phase2_fundamental_v3_scope_currenthash_20261031.md),
[symbol-scope SQL](../../sql/diagnostics/phase2_fundamental_v3_symbol_scope.sql),
and [public-source feasibility report](evidence/phase2/phase2_pit_public_source_feasibility_20261030.md).

Current-hash labels and targets are complete, and execution weights have
complete exact evidence for 2019–2026. Of the 14,866 windows spanning
2019-01-02, 225 remain without exact price-limit evidence and have NULL
weights. E1 produced its report; E2, E3, and the post-BSC E5 recheck passed.
E4 remains partial: the latest census has one unresolved non-lifecycle GDW
interval / seven effective sessions; CTR and PTM remain separately supported
lifecycle cases. PIT fundamentals coverage and the 2018 execution-weight
evidence also remain incomplete. Hosted PostgreSQL 16 CI is green only for the
older committed SHA, not the current candidate. The full-history 089 V3 candidate is built on the report clone; the
bounded last-400 snapshot remains partial evidence. Suggestions remain
disabled without a valid champion.

The checkout is branch phase2-evidence at c65adf6, equal to
origin/phase2-evidence, with uncommitted working-tree changes. GitHub run
40091535600 is green for that committed revision only; it does not validate the
current worktree. The draft [PR 1](https://github.com/Kashumir-Kaiser/VN-Signal/pull/1)
is not merged. No current-tree CI or push to main is claimed. Before delivery,
resolve the correctness and coverage gates, rerun the required Go, Rust,
Python, PostgreSQL migration, race and hosted CI checks on the exact candidate,
then commit and push only after they pass. Live vnstock routes and the registered
vnsignal database have not been used for these checks.

Local verification for this 2026-10-26 checkpoint passed `go -C go test ./...`
with `VNPIPE_PYTHON` set to the installed bundled interpreter, `go -C go vet ./...`,
`python -m unittest discover -s tests -v` (36 tests), and `git diff --check`.
The first Go invocation failed because the Windows Store Python placeholder
was first on PATH; the explicit-interpreter rerun passed. Rust, Go race,
PostgreSQL migration, and hosted CI checks were not run against the current
working tree in that checkpoint. The 2026-10-31 SHB evidence update also passed
`go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover
-s tests -v` (44 tests); evidence logs are recorded in
`docs/evidence/phase2/phase2_20261031_postshb1_*.log`. Rust, Go race,
PostgreSQL migration-harness, and hosted CI checks have not yet been rerun on
the current uncommitted tree. The guarded SHB import and E4 reports ran only on
the disposable report clone; the registered `vnsignal` database and live
vnstock routes were not used.

## 2026-10-25 — Verify POM/QBS transfer intervals in the report clone

After migration 086 passed its disposable two-pass harness, it was applied
forward-only to `vnsignal_phase2_report_20261019`; the migration ledger and
registered `vnsignal` database were not touched. Two source-verified events now
pair the dated HOSE decisions with their exact captured HNX profile bytes.
Event availability is the later source-capture time (POM 2026-10-24 04:21:43Z;
QBS 2026-10-24 04:23:08Z), never the historical profile first-trade date.
Both events match the existing feature gap from May 10 to May 23, 2024: nine
effective sessions each, with zero core bars, bar-source rows, V3 features, or
labels inside either interval. The nearest V3 feature rows are May 9 and May
23. This is transfer context only; it does not prove trading or suspension on
the gap sessions. The full-universe E4 census has not been refreshed.

## 2026-10-25 — Attribute selected E1 nulls to feature input gates

A deterministic 30-symbol, 25,922-row current-hash sample used each feature
row's exact VNDIRECT landing and source-row key, and calculated rolling input
counts using source history before applying the report's date filter. All
10,944 `close_location` NULLs lacked a traded source bar with a nonmissing
close and `high > low`; all 15,567 `close_sma50_ratio` NULLs lacked one of its required
current-trade or 50-traded-close inputs; all 15,883 `realized_vol60` NULLs had
fewer than 60 valid returns; and all 15,883 `beta_vnindex_60` NULLs lacked 60
paired returns or positive index variance. No NULL had its tested inputs
ready, and no non-NULL sample value lacked them. The global-index
`vnindex_realized_vol60` had no NULLs in the sample, including 1,800 rows
within the first 60 equity-symbol rows, confirming its warm-up follows global
index sessions rather than each symbol's row count. This bounded sample does
not resolve all 80 flagged features or 13 source-unverified definitions.
Query and output are linked in the E1 report.

## 2026-10-25 — Pass two-pass migration harness for HNX profile transfer endpoint

Migration 086 and its synthetic SQL assertions passed the full disposable
PostgreSQL migration harness, including two migration passes and the existing
Phase 2 assertion suite. The migration preserves the HNX→HOSE cohort rule from
085 and adds a narrowly scoped HOSE→UPCoM transfer endpoint for the exact POM
and QBS HNX profile captures. It requires a dated HOSE primary source, the
event's HOSE document-date floor, explicit JSON `document_date: null` on the
profile, exact profile URL and capture marker, matching first UPCoM session,
the exact ticker in the original profile bytes, and availability no earlier
than either source capture. This proves source-backed venue continuity context
only. The report-clone application and verification of the 18-session POM/QBS
intervals remain outstanding; no bars, suspensions, or labels are inferred.
## 2026-10-23 — current-hash real E3 and independent recursive goldens

Using only the disposable report clone, the production V3 builder refreshed all
rows for the three deterministic real-data E3 dates under current hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e`. The
builder reported 1,439 rows for 2022-10-10, 1,446 for 2023-04-04 and 1,464 for
2024-09-04. No raw, core or V2 rows were changed.

The real E3 test selected 20 source-attributed symbol-days across those dates,
verified each selected VNDIRECT landing payload hash and bar lineage, confirmed
the current V3 feature hash, and passed the non-recursive SQL↔Rust comparisons
at the unchanged `1e-9` tolerance. Its passing log is
[`phase2_e3_real_parity_065_nonrecursive_20261023.log`](evidence/phase2/phase2_e3_real_parity_065_nonrecursive_20261023.log).

The first broader comparison also compared recursive real features and found
`ema_100_ratio` differed for symbol 824 on 2023-04-04: SQL
`0.004010006674335`, Rust `0.004010006740238`. The failed run is preserved in
[`phase2_e3_real_parity_065_20261023.log`](evidence/phase2/phase2_e3_real_parity_065_20261023.log).
The recovery prompt defines real E3 parity for non-recursive features and
requires recursive EMA/MACD checks against independent goldens. In response,
[`tests/golden/phase2_recursive_ema.csv`](../tests/golden/phase2_recursive_ema.csv)
was generated with pandas 3.0.1 (`adjust=False`, `ignore_na=True`) and checked
by both the Rust reference tests and the SQL feature assertions. The tolerance
was unchanged. This does not establish recursive SQL↔Rust parity on real
history; the observed EMA difference remains a disclosed diagnostic.

The fresh two-pass SQL migration harness passed with the golden assertions in
[`phase2_migration_harness_ema_golden_20261023.log`](evidence/phase2/phase2_migration_harness_ema_golden_20261023.log).
Rust formatting, clippy and workspace tests passed, including the pandas
fixture check ([focused output](evidence/phase2/phase2_rust_recursive_ema_golden_20261023.log)). Go tests/vet and all 29 Python tests passed. The Windows race
run remains unavailable due to ThreadSanitizer shadow-memory allocation error
87. E3's non-recursive real-data slice passed, but recursive golden coverage is
incomplete, so E3 remains open alongside E1, E2, E4, E5 and hosted CI. Phase 2
is not ready for sign-off.

## 2026-10-23 — stabilize V3 rolling market regression

Rust/PostgreSQL parity isolated a small but material numerical mismatch in `idio_vol_vnindex_60`: cumulative-prefix subtraction produced `8.911217534444352e-06`, while a direct rolling sample-variance/covariance reference produced `8.911217502410939e-06`. The relative difference exceeded the existing `1e-9` parity tolerance. Keep the tolerance unchanged. Migration 065 switches the paired 60/250-session regression moments to PostgreSQL's rolling `var_samp`/`covar_samp`, requires the stock and lagged-index return to be present for every moment, adds a stable-moment feature-hash token, and preserves the inherited VNINDEX-return hash token.

The migration patches the shared V3 function body in place so migrations 053/054 can still inspect their rank and repair anchors. A fresh `template0` database passed two complete migration passes plus the full SQL harness. Strict Rust/PostgreSQL parity then passed for 20 deterministic synthetic symbol-days at the existing tolerance. The fixture does not constitute the outstanding real-market E3 comparison.

Current local checks after the migration: Go tests and vet, 29 Python tests, Rust fmt/clippy/workspace tests and the strict database-backed synthetic parity test passed. The Windows race run reached ThreadSanitizer but failed to reserve its shadow memory (error 87), even with UCRT64 GCC configured. Hosted CI is not run. E2 remains blocked on the real 40% branch rebuild; E4 still has 206 unsupported continuity intervals; E5 still lacks a second output hash. Phase 2 remains open.

## 2026-10-23 — corrected window rewrite and E2 retry (latest)

Migration 064 now preserves native averages and standard deviations while
computing exact 250-session extrema with block prefix/suffix windows. The
first replay uncovered stale custom-window aggregate dependencies; cleanup now
drops the full obsolete aggregate/function set. The first real E2 retry also
found that the `n` regular-expression flag prevented the CTE rewrite from
crossing newlines, leaving required spine columns out of `extrema250`. The
rewrite now uses the multiline-safe `s` flag and checks the resulting
projection before replacing the function. On the disposable report clone, the
corrected function projection check and numerical extrema fixture passed.

The repeated synthetic probe completed five alternating runs at 15, 30 and 60
symbols × 2,000 sessions. Direct/integrated medians were 1,122/841 ms,
2,213/1,597 ms and 4,528/3,146 ms, respectively. The integrated method had
zero temporary blocks and a 0.952 row-count scaling exponent (direct: 1.006).
Despite that synthetic win, current-tree E2 remains **NOT PASS**: the latest
corrected real run completed its baseline in 4:00.2, then the 40% branch's V2
rebuild remained CPU-active for 12:45 without a comparison. It was canceled,
and the outer transaction rolled back. No 70% or 95% cut ran. See the
[scaling output](evidence/phase2/phase2_v2_window_scaling_final_20261023.txt),
[rewrite verification](evidence/phase2/phase2_moving_window_rewrite_verification_20261023.log),
and [latest E2 log](evidence/phase2/phase2_e2_real_20261023_103110_365.txt).

After this E2 attempt, the latest current-tree Go tests, race tests, vet, all
29 Python tests, and a fresh two-pass PostgreSQL migration harness passed. The
harness includes migrations 061/063/064 and their SQL assertions; it does not
replace the real-data E2 comparison. The complete harness log is
[here](evidence/phase2/phase2_migration_harness_064regex5_20261023.log).
E3 has not yet been rerun against the migration 064 V2 implementation, so its
earlier 20-symbol-day result is stale for sign-off. Hosted CI remains unrun.

### Earlier recovery recheck (before migration 064)

The production adjustment cache now loads all 2,844,435 rows in 26 bounded
symbol batches, and the E2 current-hash baseline completes. The run then spent
579.592 seconds before entering the 40% perturbed branch; that branch remained
active beyond 16 minutes without a comparison, versus 8:06 in the prior
completed attempt. It was cancelled, the outer transaction rolled back, no
branch schemas or active Phase 2 sessions remained, and current-tree E2 is
NOT PASS. A later indexed-input retry completed branch setup and future
perturbation in about 19 seconds, but its V2 statement remained active for
12:38 without a comparison; it was canceled and rolled back. A plan-only run
captured the estimated V2 tree and was canceled after 63.840 seconds. The plan
has 20 WindowAgg and 9 Sort nodes for an estimated 48,060-row cohort spine;
it contains no actual timing or buffer data. No 70% or 95% branch ran. See the
indexed-input run and plan links above, plus the [plan summary](evidence/phase2/phase2_e2_v2_plan_20261023.md).

The current-hash E5 first build completed 720,718 rows in 367.240 seconds.
An initial repeat was stopped early; a clean forced repeat then reached 753
seconds in the label-build statement, just over twice the first step duration,
without completing. The original chunk is `done`, the repeat chunk is
`pending`, there is no second `step_runs` row or output hash, and follow-up
inspection found zero active Phase 2 sessions. E5 reproducibility is therefore
inconclusive on the current label definition. The run evidence is linked above.

The fresh two-pass PostgreSQL migration harness passed after the fixture was
corrected to build labels for both sides of the 250-session gap-eligibility
boundary. Go tests, vet, race tests, and all 27 Python tests also passed with
the configured bundled Python and MSYS2 UCRT64 GCC. No worker or Rust code was
changed in this recheck. Hosted CI remains unrun.

## 2026-10-22 — corrected E4 attribution and E1 null-model review (historical checkpoint)

The E4 identifier-domain review corrected two false lifecycle mismatches. Bars,
features, lifecycle evidence, and the symbol directory use
`core.symbols.symbol_id`; `core.security_master.security_id` is separate. The
PTM and CTR lifecycle records point to PTM and CTR landings respectively. The
PTM gap is covered by its delisting interval. CTR's six-session gap is the
UPCoM-to-HOSE transition from its last UPCoM session on 2022-02-14 to its first
HOSE session on 2022-02-23. Five VCI rows inside that transition are source
anomalies: they are absent from the audited source archive and both feature
versions. The earlier KTL/TSB attribution and five-TSB-bar conclusions are
withdrawn. Corrected evidence is in
[`the E4 identifier-domain correction`](evidence/phase2/phase2_e4_id_domain_correction_20261022.md).

E4 still has 219 unexplained continuity gaps across 1,539 effective sessions
with no daily bars, source-archive rows, or dated security observations.
Coverage, keys, calendar membership, and rank/input checks pass, but E4 is not
complete.

The E1 report exists and preserves the original denominator and 1pp diagnostic
threshold. Its 73/88 flags compare observed nulls with a lookback-only
expectation. A source audit found that this expectation omits nontraded rows,
complete-window requirements, adjustment-episode resets, and shared
market/index series. These results are not evidence that 73 builders are
broken; feature-by-feature null attribution is still open. The Master Build
Spec calls null-rate shifts a warning and requires a report; it does not set a
1pp Phase 2 exit gate.

At this checkpoint, real-data E2 and E3 did not yet have completed results.
Those gates later passed on 2026-10-23; see the current acceptance entry below.
E5 covers one 2023 label chunk. PIT-fundamentals coverage and source
verification remain incomplete, and hosted CI has not run.

## 2026-10-22 — full rank repair and Phase 2 readiness review

The 97 monthly rank-repair ranges are complete on the disposable report clone
`vnsignal_phase2_report_20261019`: 2,844,435 rows in each of V2 and V3. The
read-only S2 scaling probe passed with exponents 0.359774 and 0.935869. The
current V3 feature-set hash is
`f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.

Phase 2 is **not ready for sign-off**. Refreshed E1 flags 73 of 88
source-measured fields against the lookback-only expectation; this model does
not account for all builder availability conditions, and 13 fields remain
source-unverified. Real-data E2 is incomplete: the first
three-cut attempt was stopped during the first cut's perturbed V3 rebuild
after 28.5 minutes, before any comparisons; see the
[`E2 attempt report`](evidence/phase2/phase2_e2_real_attempt_20261022.md).
E3 has no completed real-data result. E4 has 221 symbol-session continuity
gaps; corrected review explains the PTM and CTR gaps with ticker-matched
lifecycle evidence, while 219 intervals have no daily bars or source-archive
rows and remain unresolved. Five VCI rows inside CTR's venue transition are
source anomalies absent from the audited source archive and V2/V3. See the
[`E4 gap review`](evidence/phase2/phase2_integrity_report_rank_repaired_summary_20261022.md)
and [source-attribution evidence](evidence/phase2/phase2_lifecycle_source_attribution_20261022.csv).

E5 passed for one 2023 label chunk rebuilt twice with identical input and
output hashes. PIT-fundamentals coverage and source verification remain
incomplete, and hosted CI has not run. The registered `vnsignal` database and
live vnstock routes were not used. Local Go tests, Go vet, 27 Python tests,
and the fresh two-pass PostgreSQL migration harness passed after migration
056; logs are linked from the current gate report
[`phase2_gate_status_rank_repaired_20261022.md`](evidence/phase2/phase2_gate_status_rank_repaired_20261022.md).
Suggestions remain disabled because no valid champion exists.

## 2026-10-22 — date-scoped rank update and 88-month checkpoint

The corrected S2 probe was rerun after the repair-function definition changed.
Its read-only rank-stage medians were 0.951241/1.220656/2.335167 seconds for
30/60/120 effective sessions; exponents were 0.359774 and 0.935869, within the
1.3 limit. The certificate is
[`phase2_rank_probe_phase2-rank-repair-055-20261022.json`](evidence/phase2/phase2_rank_probe_phase2-rank-repair-055-20261022.json).

The first March 2025 repair attempt was cancelled after 139.483 seconds while
waiting on table reads. Its durable attempt record is failed and the transaction
rolled back. The separate rank and hash profiles took 2.749 and 2.568 seconds;
the update plan showed a nested loop doing about 31,000 primary-key lookups.
Migration 056 adds the same monthly date bounds to both version updates. The
date-scoped plan uses `features_daily_date_version_idx` and a hash join. The
March retry committed in 36.354 seconds. Plan and profile evidence is in
[`the March update-plan logs`](evidence/phase2/phase2_rank_update_plan_2025-03_date_default_20261022.log)
and [`component profile`](evidence/phase2/phase2_rank_component_profile_2025-03_20261022_retry.log).

The disposable report clone now has 88 successful monthly ranges, covering
2018-10 through 2026-01: 2,582,067 rows per feature version and 5,164,134 rank
updates. February through October 2026 remain. The March 2025 audit row records
two attempts; the completed retry is authoritative. The latest estimated dead
tuple count is 647,221. Phase 2 remains open pending the remaining rank ranges,
forced same-chunk rebuild verification, real E1–E5 evidence and source-dependent
feature coverage. Suggestions remain disabled without a valid champion.

Verification after migration 056: Go tests and vet passed, all 27 Python tests
passed, and the full PostgreSQL migration harness passed on a fresh disposable
test database. Logs are under `docs/evidence/phase2/` with `datefilter_20261022`
in their names. The initial Go test invocation lacked the bundled Python
runtime on PATH; the corrected run passed. The rank runner also now treats an
omitted optional start date as unset, and the passing probe exercises that path.

## 2026-10-22 — S2 probe corrected after rollback-bloat finding

The latest 30/60-session full-repair probe measured 34.303442/151.062488
seconds (exponent 2.138720), then was stopped during the second 120-session
chunk. This is not valid S2 scaling evidence: rolled-back updates still left
393,406 estimated dead tuples in the report-clone feature table. The probe
JSON is marked incomplete, the report copy has zero committed probe audit
rows, and no probe session remains active. The component profile for
2026-08-22..2026-09-21 measured one rank-panel hash at 6.771 seconds and the
read-only rank function at 3.168 seconds; neither alone is a scaling pass.

The runner now measures the read-only shared rank stage over 30/60/120
effective sessions, with a largest-window warm-up and 5-minute statement
timeouts. This matches S2's stage boundary and avoids table writes during the
scaling comparison. The disposable report clone must be vacuumed before that
probe, then real monthly repair remains a separate, checkpointed operation.
No historical repair has started. Phase 2 remains open; real E2/E3, refreshed
E4/E5 and remaining feature-source gates are still outstanding.

## 2026-10-22 — rank probe timeout; market projection fixture passes

Migration 054 is installed on the disposable report database and fixture
database. It shares the production cross-sectional rank calculation with a
bounded repair, records durable chunk attempts and hashes, and rejects changes
to non-rank feature fields. Its fixture assertions pass. Historical repair has
not yet run. The first scaling probe processed 45,513/90,885 V3 rows in
130.478345/167.053286 seconds for its 30/60-session samples, verifying rollback.
The 120-session sample timed out in a later chunk's non-rank hash. No probe
repair rows or audit completions committed. The probe now matches repair's
one-chunk transaction boundary and uses 16 MiB work_mem. Report-clone vacuum
is in progress before a fresh complete 30/60/120-session measurement.
See [the repair log](evidence/phase2/phase2_rank_repair_phase2-rank-repair-053-20261022.log).

The bounded Go test and vet reruns pass, as do eight Rust
unit tests, Rust formatting, and all-target clippy with warnings denied. See
the `phase2_*_rank_recovery_20261022.log` and
`phase2_rust_*_20261022.log` evidence files. A final uninterrupted migration
harness, race run, real E2/E3 and hosted CI are still required. The earlier
27-test Python pass remains recorded, but its latest rerun failed the
five-second health subprocess timeout during vacuum/resource contention
(`phase2_python_market_projection_20261022.log`); a quiet rerun is required.

An additional E2 gap is confirmed: the scoped fixture rebuilds its 60-symbol
cohort, but supplies non-cohort market context from one unchanged persisted
V2 panel. Migration 055 now derives a narrow market-support projection from
the exact canonical production V2 SQL and rejects definition drift. Its fixture
passes binary comparison with fresh V2 output, pre-cut invariance, changed
non-cohort future support, and drift rejection. The revised E2 uses separate
full-universe raw inputs in both branches and routes the canonical VCI view
to branch-specific index bars. The real E2 result remains **NOT RUN**. See
`phase2_market_projection_assertions_20261022.log`. Required source-dependent features and PIT
fundamentals coverage also remain open. Phase 2 is **not ready for Phase 3**.

## 2026-10-22 — rank upgrade and real-evidence harness verification in progress

The clean migration replay through 052 passed, and 052 was installed on the
disposable report clone. Runtime inspection then confirmed that its installed
V2 builder still ranks partial volatility windows, explaining the inherited
E4 mismatch. New migration 053 upgrades that definition, checks rank/input
eligibility, gives Gaussian ranks independent non-null populations, changes the
feature hashes, and rejects stale V2 inputs during V3 builds. All eight Rust
unit tests, the new rank SQL cases, and the complete remaining shared/source/
chunk SQL assertion sequence passed. The clean replay had applied migrations
twice and passed earlier feature/leakage assertions before a cumulative fixture
timeout; an uninterrupted full-harness rerun remains pending. The fixture now
keeps its four passes in one transaction as separate statements with the same
180-second per-statement setting and all original comparisons. Migration 053
was installed on the report clone. Historical output has not been repaired or
certified under these new hashes. All 27 Python tests pass; the Go test attempt
was interrupted for resource contention and must be rerun with bounded build
parallelism.

The original real E3 attempt was canceled while scanning candidate archive
payloads and compared no features. Sampling now precedes mandatory hash and
lineage validation of all 20 selected observations. E2 selection also required
correction: listing snapshots start in October 2026, after its first cut, so the
cohort now uses source-linked historical bar venues. Neither revised real-data
test has a passing result yet. See the [recovery checkpoint](evidence/phase2/phase2_rank_recovery_checkpoint_20261022.md).

Phase 2 remains **IN PROGRESS**. E1, real E2/E3, refreshed E4/E5, PIT coverage,
required source-dependent feature work, current local gates and hosted CI remain
open. Suggestions remain disabled.

## 2026-10-22 — label coverage complete; current E1 fails; Phase 2 remains open

The completed V3 label coverage now spans 2018-10-01 through 2026-10-16. The
current feature set has 2,844,435 rows and `feat.labels_daily` has 5,688,870
rows (two horizons per feature row). 2022 was recovered as H1/H2; the 2023,
2024, 2025 and 2026-to-date chunks are complete in
`phase2-vci-labels-rechunk-20261022`. See the [label recovery checkpoint](evidence/phase2/phase2_label_recovery_20261022.md)
and [durable chunk status and hashes](evidence/phase2/phase2_label_chunk_status_20261022.csv).

The measured 2023 bad-factor scan changed from a 181–189 second per-symbol
nested-loop pattern to a 1.57 second sequential/hash plan. Migration 051 scopes
the planner setting to that query and captures its row count before restoring
the setting. A forced 2023 rebuild reproduced the original output hash
`3c6d2ad64925d19264287c41c6e2ba805826ac3beac653cd2e6bfeac87bcdf2e`, passing
E5 for that chunk. The factor scan and both runner attempts are linked from the
checkpoint above.

The current full-history E1 audit is **FAIL**: 73 of 88 measured features are
outside the literal 1pp null-rate tolerance; 15 are within it and 13 are
source-unverified. A read-only availability breakdown confirms that all
1,021,077 `is_traded=false` rows have null `ret_1` and `close_sma200_ratio`,
but traded-row nulls and other feature deviations remain. This explains some
raw nulls but does not change the E1 result. See the [current E1 report](evidence/phase2/null_rates_full_20261022.md)
and [full CSV](evidence/phase2/null_rates_full_20261022.csv).

The fresh PostgreSQL 18.3 two-pass migration harness v9 **passes**; it is
fixture evidence only, not real-data E2–E4 or hosted CI. Go tests, vet and race,
27 Python tests, Rust fmt/tests/clippy also pass locally; the Rust PostgreSQL
integration test skipped without `DATABASE_URL`. See the [harness
summary](evidence/phase2/phase2-migration-harness-v9-20261022.md) and [current
gate table](evidence/phase2/phase2_gate_status_20261022.md). E2–E4,
PIT-fundamentals coverage, and hosted CI remain open. Completed labels and
passing local fixture checks do not close Phase 2.

## 2026-10-22 — recover 2022 labels as half-year chunks; Phase 2 remains open

This supersedes the preceding “labels remain 0/9” checkpoint. On disposable report clone `vnsignal_phase2_report_20261019`, build `phase2-vci-labels-rechunk-20261022` completed 2022 H1 (342,614 rows, 294,205 ms) and H2 (370,978 rows, 260,659 ms). Both chunks have durable input and output hashes; their combined 713,592 rows match the 2022 annual target count. See the [2022 split checkpoint](evidence/phase2/phase2_labels_2022_split_checkpoint_20261022.md), [chunk status CSV](evidence/phase2/phase2_label_chunk_status_20261022.csv), [captured query plans](evidence/phase2/phase2_labels_2022_autorun_plans_20261022.log), and [H2 runner log](evidence/phase2/phase2_build_phase2-vci-labels-rechunk-20261022_2022H2.log).

`auto_explain` measured the final assembled inserts at 37.7 seconds for H1 and 31.7 seconds for H2, with no conflicts. The earlier annual timeout context names the final insert as the command active at cancellation, but the runner's 30-minute `statement_timeout` was set for the outer `DO` call; that context does not establish that the insert alone consumed 30 minutes. The repeated first-bad-factor scan took about three minutes per half-year and is the measured performance watch item. The old failed annual ledger row remains as historical evidence; the two completed half-year rows cover the 2022 output range.

At this checkpoint labels for 2023–2026 were pending; the newer full-label
checkpoint above records their completion. Corrected E1, real-data E2–E4,
PIT-fundamentals coverage, final local gates, and hosted CI remain open. Phase 2
is **not ready for sign-off**.

## 2026-10-22 — fix the V3 selected-symbol CTE; Phase 2 remains open

Migration 046 fixes a production-path bug: migration 045 renamed the symbol eligibility CTE to `eligible_symbols` but left the downstream selection reading `symbols`. The real 2026 feature attempt failed after 139,501 ms with `relation "symbols" does not exist`; the failed chunk transaction committed no feature rows. An assertion now checks the CTE reference directly, and the fresh PostgreSQL 18.3 two-pass harness v8 passed, including synthetic batch parity and leakage checks ([harness evidence](evidence/phase2/phase2-migration-harness-v8-20261022.md)).

The report-clone migration runner stopped before migration 046 because its existing migration 034 checksum differs from the current source; no migration ledger entry was changed. The additive 046 SQL was applied directly to the disposable report clone, and function introspection confirmed the corrected reference and absence of the stale one. The registered `vnsignal` database and live vnstock quota were not used.

The corrected retry completed the 2026-01-01–2026-10-16 feature chunk: 292,290 rows, `done`, with a 730,650 ms durable step duration and output SHA-256 `5ff467f883e607634c0630ef5458d569d077a8ee6e967b5d7760a0ff1d0c46b2`. All nine feature chunks now total 2,844,435 rows over 2018-10-01–2026-10-16, matching the V2 row count. The full adjustment cache was loaded in 26 fill batches; the measured projection was 22.10 minutes. Runtime detail is in [the corrected 2026 feature recovery evidence](evidence/phase2/phase2_v3_2026_feature_recovery_20261022.md) and [captured runner log](evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021_features_20261022.log). Labels remain 0/9, and availability-aware E1, real E2–E5, PIT fundamentals, final local gates, and hosted CI remain open. Phase 2 is **not ready for sign-off**.

## 2026-10-22 — bounded VCI repair checkpoint; Phase 2 remains open

Migration 044 now installs only bounded backfill support; it no longer rewrites the full V3 table during migration apply. The repair freezes one session-level, one-session-lagged VCI context snapshot and commits 30-calendar-day chunks with durable attempts, row counts, and input/output hashes. Completed chunks are skipped on resume. The PostgreSQL 18.3 two-pass fixture harness v7 passed, including interrupted repair, resume, output-hash verification, and completed-chunk retry assertions ([harness log](evidence/phase2/phase2-migration-harness-v7-20261022.log)).

The DDL is applied to the disposable report clone only. Repair build `phase2-vci-repair-bounded-20261022` is complete: all 98 chunks repaired 2,844,435 V3 rows from 2018-10-01 through 2026-10-16, with 98/98 output hashes and one consistent context hash. The frozen context contains 2,009 rows and has SHA-256 `fca2e344e5cb46a79c021ad5babcb0f23b3f3fba197d3e521cd503a61039d10`. One chunk overlapped autovacuum and took 323.74 seconds; the 63 chunks after cleanup averaged 7.32 seconds (maximum 12.68). After repair, `VACUUM (ANALYZE)` completed in 520.92 seconds, reported zero estimated dead tuples, and the table's normal autovacuum setting was restored. Per-chunk durable state and output hashes are exported to [`VCI repair status`](evidence/phase2/phase2_vci_backfill_status_20261022.csv). The registered `vnsignal` database and live vnstock quota have not been used.

This repairs VCI-derived V3 inherited-index fields; it does not rebuild the stale pre-VCI features and labels. Corrected feature/label builds, eligible-history E1, real E2–E5, PIT fundamentals, final local gates, and hosted CI remain open. Phase 2 is **not ready for sign-off**.

## 2026-10-22 — V3 recovery checkpoint; Phase 2 remains open

Build `phase2-vci-full-rebuild-20261021` committed eight V3 feature chunks for 2018-10-01 through 2025-12-31 (2,552,145 rows). Its 2026-01-01–2026-10-16 feature chunk failed before commit while populating the temporary symbol-batch map; all nine label chunks remain pending for this build. The exact chunk state is [`phase2_feature_chunk_state_20261022.csv`](evidence/phase2/phase2_feature_chunk_state_20261022.csv), and the failed runner output is [`2026 feature chunk log`](evidence/phase2/phase2_build_phase2-vci-full-rebuild-20261021.failed.20261021-235301.log). Earlier full-history V3/label rows predate the VCI correction and are stale for sign-off.

The recovery prompt's fallback—a full-universe last-400-session slice plus a 60-symbol real-data subset—was not run. Migration 044's corrected VCI backfill did not complete within the time box, so neither slice has current-correction evidence; the phase remains open rather than conditionally complete.

The synthetic VCI migration and feature assertions pass in the two-pass PostgreSQL 18.3 harness. Migration 045 now uses one set-based join from selected sessions through the adjustment cache's date-first index; it passed the fresh-install harness and patched the already-installed V3 function on the disposable report clone. Migration 044's real-data backfill was canceled after 10 minutes on that clone while scanning/updating the 3.55 GB feature table; the transaction rolled back, so the clone still lacks the VCI backfill view. No registered `vnsignal` data or live vnstock quota was used. See [`recovery evidence`](evidence/phase2/phase2_recovery_checkpoint_20261022.md), [`migration harness`](evidence/phase2/phase2-migration-harness-v4-20261022.log), and [`044 backfill retry`](evidence/phase2/phase2_apply_044_vci_retry_20261022.log).

The read-only E4 integrity query timed out at five minutes without returning metrics. E1–E5 are not complete on corrected current data: the prior E1 report flagged 79 of 88 measured features outside the one-percentage-point tolerance, but it predates the VCI correction and does not account for every feature's trade/input eligibility. The real E2 perturbation, real E3 parity, corrected E1 report, E4 metrics, and E5 repeat-build hash comparison remain open. The fundamentals overlay also lacks PIT coverage for 2018–2021; its 2022 input-hash chunk was canceled, later chunks remain pending, and no live fundamentals calls were made.

Local Go tests, vet, race tests, 27 Python tests, Rust formatting/tests/clippy, and the two-pass SQL harness passed. Hosted CI was not run. Phase 2 is **not ready for sign-off**; do not promote or enable suggestions.

## 2026-10-21 — full-history feature/label checkpoint and VCI benchmark correction

The disposable report clone completed all 2018-10-01–2026-10-16 V3 feature chunks (2,844,435 rows) and label chunks (5,688,870 rows). These outputs were built before the V3 benchmark-source correction below and must be rebuilt before treating them as current. The full-history E1 diagnostic measured 2,844,435 rows and found 79 of 88 measured features outside the one-percentage-point null-rate tolerance; 13 source-unverified fields are expected NULL. VNINDEX context was 100% NULL because the code selected VNDIRECT while the local history has 1,995 VCI VNINDEX rows and no VNDIRECT VNINDEX rows. Other large null-rate deviations remain unexplained. See [`full-history E1 report`](evidence/phase2/null_rates_full_20261021.md) and [`CSV`](evidence/phase2/null_rates_full_20261021.csv).

V3 feature and label benchmark reads now select the registered VCI VNINDEX history. The two-pass SQL migration harness passed on fresh disposable PostgreSQL 18.3 database `vnsignal_phase2_vci_harness2_20261021_test`, including the one-session lag leakage control against the V3-only `vnindex_realized_vol60` field; the final marker is in [`VCI migration harness log`](evidence/phase2/vci_migration_harness2_20261021.log). The fundamentals overlay remains partial: 2018Q4–2021 chunks completed with zero rows; 2022 was marked failed when the build was canceled at the recovery time limit while computing its input hash; 2023–2026 remain pending. The stable chunk summary is [`full-history checkpoint`](evidence/phase2/full_history_checkpoint_20261021.log), with runner output in `docs/evidence/phase2/phase2_build_phase2-full-20261021.failed.20261021-202421.log`. No live fundamentals calls were made.

Phase 2 is **not ready for sign-off**. Rebuild full-history features/labels after applying migration 043, rerun E1 and explain the remaining null deviations, finish the real-data E1–E5 checks, verify PIT fundamentals coverage, and rerun the current-tree Go/Python/Rust/race gates and hosted CI. Real E3 parity remains unrun; see the existing parity evidence below.

## 2026-10-21 — cache manifest scan fixed; two-pass fixture gates passed

The first real 15-symbol cache probe timed out after five minutes while building its manifest, before reading the adjustment view. The old manifest found symbols by scanning and hashing all 2.84M VNDIRECT source-bar rows. Migration 042 now starts from the one-row-per-security `core.symbols` directory and checks source coverage through its symbol index; it retains delisted historical names and excludes only explicit `ops.ml_symbol_scope` exclusions. The cache records readiness, refuses reuse until every batch is loaded and both lookup indexes are valid, and limits the convenience path to small fixtures. The runner keeps one repeatable-read snapshot across probe and cache batches, with a statement timeout per SQL operation; losing that session still requires rebuilding the temporary cache.

The updated two-pass migration harness passed on disposable PostgreSQL 18.3 database `vnsignal_phase2_cache_retest2_20261021_test`. It replayed migrations twice and passed the 2,282-row exact cache parity, batch retry and cache persistence assertions, existing feature/leakage/chunk assertions, rollback fault injection, and unreachable-connection check. The expected injected `ERROR: division by zero` precedes the final `Phase 2 SQL migration harness passed.` marker. Full output: [`phase2_cache_migration_final_pg18_20261021.log`](evidence/phase2/phase2_cache_migration_final_pg18_20261021.log).

This validates fixture mechanics only. The new manifest has not yet completed real 15/30/60 cache probes, so full-history cache time and the full V3 build remain unmeasured. E1–E5 and hosted CI are incomplete; Phase 2 is **not ready for sign-off**. The previous 5432-clone probe used the old manifest and remains the only real cache timing attempt.

## 2026-10-21 — local fixture migration replay passed after cache batching

The two-pass migration harness completed against a fresh disposable PostgreSQL 18 cluster and database. Migrations replayed twice; the Phase 2 cache assertion verified exact row/column parity against the unchanged `core.vndirect_reference_adjustment_details` view, idempotent batch retry, and cache persistence across committed year chunks. Existing Phase 2 feature, leakage, chunk, rollback, and unreachable-connection assertions reached the harness success marker. The injected rollback fault is expected to print `ERROR: division by zero` before the harness reports `Phase 2 SQL migration harness passed.` See [`phase2_migration_local_pg18_20261021.log`](evidence/phase2/phase2_migration_local_pg18_20261021.log).

This proves the migration and fixture mechanics only. The 2,282 cached fixture rows do not measure full-history performance; the required real 15/30/60 symbol adjustment-cache probe, full V3 build, full-history E1–E5 evidence, Go/Python/Rust current-tree gates, and hosted CI remain incomplete. Phase 2 is **not ready for sign-off**. The local PostgreSQL 18 listener on port 5432 did not provide a usable connection in this turn; only the disposable test cluster was used.

## 2026-10-21 — E3 fresh SQL parity attempt timed out; Phase 2 remains blocked

The real-data parity test compiled, then spent 2,015.05 seconds before PostgreSQL canceled `feat.prepare_phase2_adjustment_rows(true)` at its 30-minute statement timeout while creating the transaction-local adjusted-price cache from `core.vndirect_reference_adjustment_details`. It did not reach the selected-date V2/V3 rebuild or compare any of the 20 symbol-days, so E3 has **no parity result**. The test used the disposable `vnsignal_phase2_e3_20261021_disposable` database and an explicit rollback transaction; the cache timeout occurred before feature builders ran, and a follow-up check found no remaining `phase2_sql_parity` connection. See [`E3 fresh rebuild attempt`](evidence/phase2/parity_fresh_rebuild_20261021.md) and its [run log](evidence/phase2/parity_fresh_rebuild_20261021.log). The SQL parity test compiled and `cargo fmt --check` passed. E1 independently remains unmet: the measured null rates exceed tolerance and the disposable report clone has sparse coverage. Phase 2 is **not ready for sign-off**; the full adjustment-cache path needs a bounded performance fix before real E3 can be completed.

## 2026-10-21 — offline verification after E3 test edit

`cargo fmt --check`, the Rust workspace tests (six unit tests; real PostgreSQL parity skipped in the no-database run), Rust clippy, `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python tests passed. `git diff --check` reported no whitespace errors; it only noted the existing CRLF/LF normalization for the two edited Markdown files.

## 2026-10-21 — E1 null-rate diagnostic completed; acceptance remains unmet

The optimized read-only diagnostic completed against disposable report clone `vnsignal_phase2_report_20261019` with a five-minute statement timeout. It returned 101 feature rows for 408,924 V3 rows, 1,346 symbols, and 320 dates. Coverage is limited to 2018, 2019, and five dates in 2026; no 2020–2025 feature rows are present. Many measured features exceed the expected null-rate tolerance by more than one percentage point, so this is a completed diagnostic but **not a passing E1 acceptance result**. The CSV and coverage interpretation are in [`null_rates_optimized_20261021.csv`](evidence/phase2/null_rates_optimized_20261021.csv) and [`null_rates_optimized_20261021.md`](evidence/phase2/null_rates_optimized_20261021.md). The earlier canceled attempt below is retained as historical evidence. No registered database was used.

## 2026-10-21 — E1 null-rate query checkpoint

The read-only null-rate diagnostic ran against disposable database `vnsignal_phase2_report_20261019` with a five-minute statement timeout, then was canceled at line 327 of `sql/diagnostics/phase2_feature_null_rates.sql`. It produced no rates or CSV rows; the captured output is [`null_rates_attempt_20261021.log`](evidence/phase2/null_rates_attempt_20261021.log), with the attempt details in [`null_rates_attempt_20261021.md`](evidence/phase2/null_rates_attempt_20261021.md). E1 remains **NOT RUN**. No production database was used and the diagnostic made no data writes.

## 2026-10-21 — local verification checkpoint

The full migration harness was started on a fresh disposable database and stopped after migration 023 when the next PostgreSQL connection timed out; it did not reach the Phase 2 fixtures/assertions or its success marker. The test database was dropped after confirming it had no active sessions. The attempt log and check summary are [`phase2_migration_ci_20261021.log`](evidence/phase2/phase2_migration_ci_20261021.log) and [`phase2_local_verification_20261021.md`](evidence/phase2/phase2_local_verification_20261021.md). A current-tree Go test run was also interrupted after more than five minutes without returning package results. Neither attempt is a code-test pass or a code-test failure. Go vet, Python, race, current-tree Rust clippy/tests, and hosted CI remain unverified for this checkout.

## 2026-10-20 — Phase 2 implementation checkpoint

**Phase 2 remains IN PROGRESS.** Migration 037 now computes global market context/ranks once, uses an ordered EMA aggregate and prefix-sum differences for rolling float8 statistics, and assembles V3 rows without a per-row JSONB round-trip. The rollback-only 15/30/60 feature-batch scaling probe passed at exponent 1.025; synthetic feature assertions passed for inherited V2 fields, rolling-stat formulas, and batch-size parity. The resumable runner built 2,239 synthetic V3 rows across two year chunks and skipped both on rerun. On the disposable report clone, real 2018 and 2019 feature chunks remain committed. The 2020 retry hit its 30-minute statement timeout while preparing the full-universe symbol-batch map and committed zero 2020 rows. The full-history run is paused pending an actual plan and bounded timing for that population query; see `docs/evidence/phase2/v3_build_diagnosis.md`. The current full-migration, Go, Rust, Python, race, and CI gates must be rerun after these edits before sign-off.

The required null-rate report has **not** yet been produced from full materialized market history. The disposable report clone contains 2,844,683 VNDIRECT source rows and 2,844,435 V2 feature rows. The 2020 retry used 100-symbol batches and a 30-minute statement timeout, but failed before feature output because its full-universe setup exceeded the timeout; no 2020 V3 rows committed. The offline Rust suite passes, including the EMA golden test. A real-data parity attempt was stopped after 772.65 seconds because the reference loader repeatedly reads point-in-time history per symbol and date; it produced no parity result. Labels and E1–E5 evidence are still pending. Source-dependent fields remain NULL until their evidence and mappings are verified. No live fundamentals calls or quota probes were made; the exact source row-ID/unit mapping and fresh absolute quota reservation are still required before such ingestion. Suggestions remain disabled because Phase 3 has not established a champion.

## 2026-10-19 — correction to VNDIRECT price adjustment status

The earlier Phase 1 completion note was too broad for Phase 2 price use: VNDIRECT rows had only their raw, unadjusted OHLC materialized even though archived responses contained a separate `ad*` OHLC snapshot. Migration 026 now materializes that snapshot with its fetch-time vintage while preserving raw `o/h/l/c`, and adds `core.vndirect_bars_as_of(symbol_id, as_of_date)` to reconstruct a point-in-time series. It is applied to the local PostgreSQL 18.3 database: **2,844,683/2,844,683 rows have complete adjusted OHLC and vintage (100.000%; zero missing)**. FPT's 2024-11-29 raw close remains 144.3; its close reconstructed as of the 2024-12-02 ex-right session is 143.3043, versus HOSE's published adjusted reference of 143.300. The 2024-12-02 close remains 142.2 on its own date basis. Phase 2 must use this function for VNDIRECT feature and label prices. VCI, DNSE, and KBS still need their own adjustment-vintage handling before cross-source price joins.

The 2026-10-19 OHLC audit contains 374 VNDIRECT observations across 214 symbols and 35 sessions where the raw open or close is outside the reported matched-price high/low range; 347 opens and 33 closes are outside, with six observations in both sets. The user confirmed the open/range relationship can be valid in Vietnamese market data, so it is not an exclusion or rewrite rule. Five of the 33 close conflicts already had action-related model-price corrections; migration 033 is applied and corrects the remaining 20 positive-volume HOSE model closes using CafeF's exact same-session open/high/low and matched volume plus official HOSE tick increments. The other eight close conflicts have zero volume and remain in the history as non-traded observations. The registered database now has 25 total evidence-linked model OHLC overrides, 1,328 reference-factor decisions with zero invalid factors, and all 2,844,683 adjusted snapshots complete. Raw VNDIRECT bars and lineage remain intact; all 374 rows stay in the Phase 2 price series. Cophieu68 comparisons remain separate because their price levels use a different basis. Row evidence and source hashes are in the [OHLC conflict audit](probe/phase2-adjustment/ohlc-discrepancy-audit-20261019/README.md).

**State: INCOMPLETE overall; Phases 0 and 1 are COMPLETE, Phase 2 is in progress, Phases 3–5 are not started, and Phase 6 is in progress. No trading recommendations are enabled.** The official HNX calendar and canonical bar dates reconcile for 2018-10-01–2026-10-16: 2,008 expected sessions, 2,008 observed, no missing or unexpected dates. For partial research, the user approved treating residual VCI zero-volume observations with no conflicting positive matched-volume evidence as zero-volume/no-matched-trade observations. This is a working classification, not exchange-certified proof of no trade or lifecycle status; it is not a missing-bar count. Preserve raw rows and `ZERO_VOLUME_UNVERIFIED` audit findings; 24 positive alternate matched-volume dates remain conflicts, 109 negotiated-only dates remain separate activity, and 19 exact HNX zero-matched reports remain exchange-confirmed. Do not synthesize OHLC bars or fill dates without a source row. Zero-volume sessions can occur on UPCoM, HNX (including SPC), and HOSE. Vietstock's tested route failed known HNX positive controls and is not used to certify the residual zeros. The 2026-10-16 DQ run (`3cd86137-dec5-4dc3-9e35-ccee9c886f1b`) PASSED with 30 audited, same-session VCI/VNDIRECT pairs. VNDIRECT supplies a separate source-attributed historical research series; The daily task refreshes VCI canonical bars and VNDIRECT in its separate source series; Phase 2 reads VNDIRECT through its point-in-time adjustment view. CTR's five post-UPCoM/pre-HOSE VCI rows remain intact in canonical history and are excluded from the ML-eligible view through source-row-linked lifecycle events.

Latest Phase 1 update (2026-10-19): official HNX reports returned all 80 selected ticker/session rows for the 16 partial-history tickers across 2026-10-12–2026-10-16. Thirteen tickers traded in that window; CDG, VFC, and VNX had zero matched volume on all five sessions. VNDirect-attributed pages report latest matched dates for those three as CDG 2025-05-13, VFC 2026-07-03, and VNX 2026-07-28; HNX confirms positive volume on each stated date. A targeted KBS probe returned 80 NAS shares on 2020-10-15, matching local VNDIRECT and DNSE volume. A new 16-date exact HNX sample (one unresolved date for each partial-history ticker) returned one row per symbol and zero matched volume/value on all 16. Seven BSC exact-date responses corroborate four HNX matched controls and show the three later VNX totals were negotiated volume with zero matched volume; the parser correction is now committed as an append-only interpretation in the working database. The unresolved zero-volume issue partition remains 14,314 ticker/dates, not 14,314 confirmed missing bars; 22 HNX reports comprise 19 zero-total and three negotiated-only rows.

The wider provider search found HNX's official UPCoM daily InfoFile package with separate matched/put-through volume and value, listed at VND 2,000,000/month with a two-week trial; the public product documents do not confirm whether a trial supplies historical archive files. FiinGroup's per-stock UPCoM schema defines `TotalMatchVolume` as round-lot matching, `TotalDealVolume` as round+odd-lot negotiated, and `TotalVolume` as matched+negotiated round+odd-lot activity. `TotalVolume - TotalDealVolume` is a candidate all-lot matched measure by inference from those field definitions, pending a controlled authorized HNX sample. ICE lists HNX/UPCoM historical and EOD data from February 2020. Current SSI docs make FastConnect a practical no-fee lead: existing SSI brokerage customers can create API keys online, and daily OHLC covers UPCOM from a symbol's first trading date with bulk history. SSI's service overview says there is no manual approval, but its Terms & Environments page still says registration requires approval; verify the live portal flow. No SSI key is configured here, and matched odd-lot semantics, adjustment behavior, and ML retention rights still need a sample and confirmation. These feeds have not been accessed, so the 14,314 activity-date partition and Phase 1 status are unchanged. Exact findings and provider links: [`source search`](probe/phase1-source-search/README.md).

The registered database already has 495 completed full-range KBS raw landings for all 16 partial tickers. Their 23 positive rows on VCI zero-volume issue dates all overlap positive VNDIRECT/DNSE dates. A KBS FPT cash-dividend probe classifies its default OHLC price fields as adjusted; adjustment vintage remains unresolved. A broader CafeF export used its public annual download for the same 16 tickers: 144 hash-recorded workbooks, 31,381 rows, and full symbol/date reconciliation. On the 14,466 VCI zero-volume issue dates, CafeF reports 23 positive matched-volume rows (all overlap existing VNDIRECT/DNSE positives), 106 negotiated-only activity rows, 14,159 zero-volume rows, and 178 absent rows. The 106 negotiated-only dates remain activity evidence, not matched OHLC bars. The original CafeF/HNX partition had 14,333 dates with neither positive matched nor negotiated-volume evidence nor an exact HNX no-match finding; the targeted HNX sample resolved 16, leaving 14,317. Three later VNX dates add negotiated-only activity confirmed by HNX and BSC, leaving 14,314 remaining unresolved dates and 109 distinct negotiated-only dates. The 22 exact HNX reports comprise 19 zero-total and 3 negotiated-only findings. CafeF's corrected MM/DD/YYYY date filter resolved the earlier inconsistent singleton results. See [`CafeF audit`](probe/phase1-cafef-history-audit/README.md), [`KBS audit`](probe/phase1-current-kbs-verify/README.md), [`HNX/public activity checks`](probe/phase1-public-activity-check/README.md), and the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md). No canonical bars, VCI quality-issue rows, or manual lifecycle-event rows changed; exact HNX reports were appended to the exchange evidence ledger.

Verification after the VNDIRECT adjustment and close correction: `go -C go test ./...` (with `VNPIPE_PYTHON=py`), `go -C go vet ./...`, and `py -m unittest discover -s tests -v` passed (27 Python tests). `tests/sql/test_migration.sh` passed against a clean PostgreSQL 18.3 database, including two complete migration passes, the adjusted-price backfill fixture, the 20 close-correction fixture/assertions, and schema checks. The tagged PostgreSQL integration suite passed without `-race` against the disposable `vnsignal_test` database. The local Windows toolchain has CGO disabled and no GCC/Clang compiler, so the race-enabled tagged PostgreSQL suite could not run here; hosted CI remains the place to verify race instrumentation. The registered database has migration 033 applied; all 2,844,683 VNDIRECT rows retain complete adjusted OHLC and fetch-time vintage.

Local PostgreSQL 18.3 confirms 1,519 current listings, 1,754 observed securities, 1,742 company profile observations and 12 profile errors. Each full VCI range has 1,502 COMPLETED, 16 PARTIAL and 1 BLOCKED job; across both ranges this is 32 PARTIAL jobs and two blocked UTT attempts. SHA-verified offline replay audited 989 landings and removed 3,131 stale issue records; `core.bars_daily` has 1,809,966 rows across 2,008 dates. Separate history tables contain 2,844,683 VNDIRECT rows and 2,172,122 DNSE rows. `core.index_bars` now contains a source-keyed 1,995-row VCI VNINDEX history. VCI quality records include two copies of one `high < low` observation and 50 invalid-open issue rows (25 distinct symbol/dates); 25/25 have valid same-session VNDIRECT bars and 14/25 also have DNSE bars. The invalid-open reports concern unusable source open values, not an open outside high/low; auction-price extrema remain allowed. The 158-member Tier A snapshot remains recorded. The two malformed UTT backfill attempts remain BLOCKED as audit evidence, but UTT is excluded from future per-symbol collection and has no verified positive-trade tenure; the Tier A selector requires 250 prior traded sessions, so UTT is outside its candidate set. Source `traded_value` remains NULL; its separately labeled proxy is approved for research.

The 32 VCI partial jobs (16 tickers, two overlapping ranges each) now have a deduplicated date-level source audit. Across those tickers, 13,955 positive VCI bars and 14,338 positive VNDIRECT dates were found; 388 positive VNDIRECT dates have no positive canonical VCI bar (338 have no VCI quality issue and 50 map to a VCI issue date). DNSE has 13,485 positive dates, including 100 without a positive VCI bar. Of 14,466 VCI zero-volume issue dates, 24 have a same-day positive alternate bar; the remaining 14,442 have no positive alternate. Nineteen of those dates are now verified as HNX no-match sessions (three prior SHC reports plus the 16-date sample); 14,423 remain lifecycle-unverified, including 109 separately tracked negotiated-only dates. The narrower activity partition has 14,314 dates with neither positive matched nor negotiated-volume evidence nor an exact HNX no-match report. New targeted HNX lookups confirmed positive exchange volume for all 26 VCI invalid-price/OHLC dates and confirmed the latest positive VNDIRECT date for all 16 audited tickers (15 UPCoM records plus SPC on the HNX-listed route). UTT's 16 CafeF-omitted sessions also have explicit HNX zero-volume rows; HNX was not queried for every UTT session. See [`phase1-partial-audit/README.md`](probe/phase1-partial-audit/README.md), [`HNX latest-positive audit`](probe/phase1-hnx-last-trade-audit/README.md), the [`UTT history audit`](probe/phase1-utt/README.md), the [`EasyStock source audit`](probe/phase1-easystock/README.md), the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md), and the [`corporate-action price-basis check`](probe/phase1-adjustment/README.md).

The BSC follow-up downloaded 31,935 dated rows for these 16 tickers from 2018-10-01 through 2026-10-16, archived across 47 hash-recorded pages. It found no new activity date beyond existing evidence: 24 matched-volume issue rows equal existing VNDIRECT/DNSE values, 106 negotiated-only rows equal CafeF, and three more equal the HNX-confirmed VNX deals. All 23 prior BSC/HNX controls, 12 additional per-symbol negotiated-volume samples, and the last positive BSC activity date for all 16 tickers match the exact HNX reports. The last positive BSC activity observations for CDG and VNX are negotiated-only and later than the previously recorded matched-volume dates. BSC's zero rows remain non-evidence of no trade; its table lacks high/low and reuse terms were not established. One XMC row on 2019-06-27 is flagged for venue attribution because its current UPCoM profile starts on 2019-06-28. No BSC rows were imported. See the [BSC history audit](probe/phase1-bsc-history-audit/README.md).

| Phase | Status | Evidence | Unfinished exit criteria |
| --- | --- | --- | --- |
| 0: probe/schema/config | COMPLETE | Registered-machine vnstock 5.0.3 probes; absolute quota verified; migrations 001–026 applied locally; worker uses the registered Community profile; local Go test/vet, Python, PostgreSQL 18 migration/integration checks pass; clean-HEAD GitHub Actions run 39023562253 passed Go race/vet, Python, and PostgreSQL 16 checks | None; current-tree PostgreSQL 16.15 migration and integration checks passed locally |
| 1: ingestion/backfill | COMPLETE | VCI has 1,502 complete histories; all 16 VCI-partial symbols have completed source-keyed VNDIRECT histories; UTT is explicitly excluded; all 1,518 in-scope symbols therefore have at least one completed history; 30 VCI/VNDIRECT pairs passed the 2026-10-16 DQ gate; zero-volume handling is approved for the residual partial-research observations; VNDIRECT adjusted snapshots are materialized for 2,844,683/2,844,683 rows with raw OHLC preserved | None for Phase 1. Phase 2 must use the VNDIRECT as-of function; VCI, DNSE, and KBS still need separate adjustment-vintage handling before cross-source price joins |
| 2: features/PIT | IN PROGRESS | Migrations 034–046; bounded VCI inherited-index repair is complete for 2,844,435 existing V3 rows on the disposable clone; migration harness v8 passes; the 2026 V3 chunk retry is in progress, labels are 0/9, and E1/real E2–E5 remain open | complete corrected features and labels; complete availability-aware E1, real E2–E5, PIT fundamentals, current-tree Go/Rust/Python/race gates, and hosted CI |
| 3: models/backtest | NOT STARTED | architecture specified | real Rust training, 36+ monthly OOS folds, calibration, backtest |
| 4: serving/portfolio | NOT STARTED | architecture specified | atomic SQLite export, parity, optimisation |
| 5: desktop UI | NOT STARTED | architecture specified | Tauri/Svelte views and performance evidence |
| 6: daemon/operations | IN PROGRESS | local Windows Task Scheduler refresh registered for 06:00 Asia/Ho_Chi_Minh through audited VCI and separate VNDIRECT ingestion | backups, seven unattended trading-day runs, and recovery evidence |

**No mock or fabricated price history, quota report, test performance, expected return, or model confidence is presented as genuine.** CI is deliberately offline and may not consume a user's vnstock account/device quota.

> The dated sections below preserve earlier evidence. The latest 2026-10-19 Phase 0/1 exit audit below supersedes older queue, zero-volume, and test-status snapshots; earlier entries are historical records.

## 2026-10-18 — Phase 1 verification update

- Tier A tenure counts distinct pre-as-of positive-volume VCI bars linked to checksum-valid raw landings. The exact verified listing snapshot still defines the as-of candidate universe. A local check found 1,321/1,505 candidates with at least 250 prior traded dates. The 2026-10-16 build passed tenure, then correctly refused ranking because source `traded_value` is NULL for A32 on 2026-09-18; no Tier A membership was written.
- DQ replay now accepts the observed provider route `market.equity.ohlcv` as well as the internal `equity_ohlcv` alias. The current gate run `e13ea9a1-5837-4a63-a061-95689ee19889` remains STALE with no Tier A members and no selected cross-source pairs. A targeted KBS probe for APF/2018-10-19 returned `AdapterError` and no repair row.
- Added `VNSTOCK_HOME` to the worker's narrow environment allowlist so Go can use the already registered profile state after changing directories. Validation passed: `VNPIPE_DISABLE_LIVE=1 go -C go test -count=1 ./...`; `go -C go vet ./...`; `.venv\Scripts\python.exe -m unittest discover -s tests -v` (26 tests); and `go -C go test -mod=mod -tags "postgres postgres_integration" -p 1 ./... -count=1` against disposable `vnsignal_test`.
- The PostgreSQL-tagged tests deadlocked once when package binaries ran concurrently against their shared disposable database; serial execution passed and CI now uses `-p 1`. Migrations 001–016 and SQL schema assertions ran twice on PostgreSQL 18.3, and the numbered Go migrator verified checksums twice. Direct rollback and unreachable-database assertions passed. The shell wrapper could not finish locally because Git Bash did not resolve `grep`; PostgreSQL 16 hosted CI remains unverified.
- `go -C go test -race ./...` remains unverified locally: with `CGO_ENABLED=1` and installed GCC selected, Go's Windows `cgo.exe` exits with status 2. No race-test pass is claimed.
- A full-range VNDIRECT Finfo query corrected the initial volume-field mistake: `nmVolume` and `ptVolume` are both zero on all 248 HNX sessions for UTT from its first session (2025-10-17) through 2026-10-16. The same endpoint returns 62,800 `nmVolume` for KAI on 2026-10-16 as a positive control. CafeF's 232 returned rows also have zero matched/negotiated volume. Classify UTT as having no recorded executions in the audited period; its repeated 9.2 reference fields are not ML bars. Raw responses and hashes are in [`phase1-utt/README.md`](probe/phase1-utt/README.md).
- A read-only reconciliation of the 32 VCI `PARTIAL` jobs found 16 tickers, each with two overlapping range attempts. The audit deduplicates 14,492 issue ticker/dates: 14,466 zero-volume, 25 invalid-price and one invalid-OHLC. All 26 invalid-price/OHLC dates have a positive same-session VNDIRECT bar; 24 zero-volume dates have a positive same-session bar in at least one alternate source. The remaining 14,442 zero-volume dates stay unverified. VNDIRECT has 14,338 positive dates across these tickers, including 388 without a positive canonical VCI bar; 338 of those have no VCI issue record. DNSE has 13,485 positive dates, 100 without a positive VCI bar. Source rows remain separate and keep raw landing/row/hash lineage. Exact CSV exports, read-only queries, and HNX profile-date lookup links are in [`phase1-partial-audit/README.md`](probe/phase1-partial-audit/README.md); researched venue-profile dates were not inserted as first-ever lifecycle evidence.

## 2026-10-16 P0 hardening evidence

- `go -C go test ./...`, `go -C go test -race ./...`, `go -C go vet ./...`: passed locally.
- `VNPIPE_DISABLE_LIVE=1 python -m unittest discover -s tests -v`: 15 offline tests passed locally, including JSONL main(), oversized input, broken pipe, vendored stdout print, CLI errors and route exceptions.
- `tests/sql/test_migration.sh`: checked into CI, runs migration twice and tests constraints, trigger canonicalization, PIT dates, rollback and connection failure against PostgreSQL 16. **Not run locally (PostgreSQL unavailable). Do not claim green CI until the hosted run completes.**
- `VNPIPE_DISABLE_LIVE=1` is enforced by both the Go quota gateway and Python adapter in CI. The active probe is now a Go-only metered sequence; direct Python `probe(active=True)` fails closed.
- Default config is validated on CLI probes/budget requests; invalid risk cap, timezone, unknown keys and exchange limits are rejected.
- The current CLI has no scheduler, SQLite serving or training. Active OHLCV and company-profile ingestion use `Gateway.CallRecorded`; the remaining `Gateway.Call` in the CLI is the metered probe path. Scheduler, serving and training failure paths cannot be signed off yet.
- Live quota usage API shapes, account entitlements, Postgres outage during migrations, and cross-source real-price data were not exercised. No actual API/device quota was consumed by tests.

## CI repair and next Phase 1 increment (2026-10-16)

- Reproduced hosted Go failure by running `VNPIPE_DISABLE_LIVE=1 go -C go test -race -count=1 ./...`. Four injected gateway tests inherited the hosted CI live-disable flag; added `t.Setenv(..., "0")` only inside those tests. The `TestDisabledInCI` safety test retains the disabling flag and still passes.
- New `ingest.NormalizeBars` validates saved vendor OHLCV frames, refuses unknown/invalid columns, duplicates, non-chronological dates, and numeric invalidity, and never synthesizes missing prices.
- `preview-backfill` generates an offline, budget-capped deterministic plan only from a verified active probe and absolute quota readings. It cannot call the market API.
- `sql/migrations/002_ingest_state.sql` adds backfill jobs and per-attempt reservations for future Postgres integration; CI migration tests now apply both numbered migrations twice, with new invalid-completion and duplicate-reservation assertions.
- Historical note: this section predates the transactional PostgreSQL store added below. Remaining: live source verification, stock-listing import, full historical backfill, models and desktop app. No Phase 0/1 exit claimed.

### Backfill execution boundary (work in progress)

`go/internal/ingest/runner.go` now defines `Runner.RunBarsBackfill`. Offline tests confirm a successful worker response gets validated and committed once, repeated completed jobs consume no additional quota, storage errors fail closed, and hosted CI cannot call the vendor. Every market call goes through `live.Gateway`, never directly through the Python worker.

`LandingStore` was initially an interface; the PostgreSQL implementation and explicitly authorized tagged `backfill` command have now been added, as described below.


## Phase 1 continuation — transactional ingest boundary (2026-10-16)

Implemented and committed on main:

- New database transaction store (`go/internal/ingest/postgres.go`) records a per-attempt reservation before invoking vnstock, records dispatch and result status, and writes raw landing, canonical `core.bars_daily`, and `COMPLETED` marker together. Duplicate/completed job IDs do not request data twice.
- A new singleton `ops.quota_guard` (migration 003) enforces an absolute, durable, cross-process allowance; verifies short-lived vendor readings; retains cross-process pacing after restart; and never returns calls previously counted as spent. A reservation is spent even on a canceled or failed request.
- `live.CallRecorded` refuses absent/failing audit hooks and records failures/cancellation, and the runner quarantines frames that do not match the requested symbol/period/ID. Vendor rate limits remain retryable with a renewed verified quota and expired lease; entitlement errors and invalid frames block the affected job.
- A Windows/Linux native migration command with checksum registry and PostgreSQL dollar-string-aware parser replaces a shell-only runtime process.
- Tagged PostgreSQL integration tests cover real transaction commit/resume, absent-symbol rollback, and durable quota exhaustion across store instances. CI now runs PostgreSQL 16, the native migration command twice, and the tagged driver tests. These **have not been executed locally**, because PostgreSQL and the pinned pgx dependency are not available in this offline build environment.
- A narrowly scoped opt-in `backfill --active` path is wired only for PGX-tagged binaries, current verified absolute quota, a previous successful active probe, and already-known listed symbols. It intentionally does not infer missing symbol metadata or schedule itself.

Historical 2026-10-16 offline evidence recorded a passing Windows race run on an earlier checkout; that result is superseded for current sources. On 2026-10-18, `go -C go test -race ./...` failed before test execution because Windows ThreadSanitizer could not allocate its shadow region (error 87); no current-source race pass is claimed. No live price calls were made. **Phase 1 remains PARTIAL** until full listed-universe coverage, lifecycle and quality exclusions, DQ gates, PostgreSQL 16 CI and runtime operation are verified. No Phase 2–6 exit milestones are claimed.

## Point-in-time equity listings and exact raw bytes (2026-10-16)

- Implemented and pushed strict v5 `equity_list` normalization using documented `symbol`, `exchange`, `icb_code_lv2` fields. Go active probe now saves the complete frame it already requested, alongside its summary, without an extra API call.
- Added `vnpipe import-listings --probe FILE`, requiring a complete active-probe frame with at least 1,000 symbols across HOSE/HNX/UPCOM. PostgreSQL importer preserves original rows and SHA-256, upserts `core.symbols`, appends dated `core.listing_snapshots`, and marks absent names inactive rather than deleting them. Transaction, advisory lock, idempotency, backdate rejection and >5% shrinkage guard enforce safe state changes.
- Migration `004_raw_bytes.sql` records the original vendor JSON bytes as `bytea`, because JSONB canonicalization prevents reliable original-byte SHA comparison; legacy rows remain nullable. Both listing and OHLCV landings write bytes. Added SQL and tagged PostgreSQL tests for exact-byte parity.
- **Verification:** new listing parser and store code passed isolated stdlib Go race/unit tests and vet locally. The full repository Go test suite, PostgreSQL 16 integration, GitHub push workflow result, installed vnstock v5 probe and actual listing import were **not** executed or observed in this environment. All Phase 0/1 exit gates remain open until these are verified on CI and the registered machine.

## Database-derived historical backfill queue (2026-10-16)

- The live `backfill --active` command now selects its candidates directly from the latest verified PostgreSQL `core.listing_snapshots` and `core.symbols`, with no manually maintained `--symbols` file.
- A repeatable-read transaction validates at least 1,000 active symbols across HOSE/HNX/UPCOM, equal listing/active sets, no future or older-than-seven-day snapshot, and SHA-256 parity of the original `raw.landings.payload_bytes` for the corresponding equity listing response. Any mismatch blocks dispatch.
- Completed and blocked jobs are excluded **before** quota-capped planning. Recent RESERVEd/RUNNING job leases are skipped, and leases older than 15 minutes can be retried through the existing durable reservation code. This fixes repeated first-batch starvation.
- The command refreshes passive vendor status/absolute usage, builds its plan using **fresh** quota figures rather than stale quantities embedded in the active probe, and records progress counts. A future date, absent provenance, stale listing, or percentage-only quota fails closed. Repeating exactly the same date range keeps job idempotency.
- Offline coverage: `go test -race -count=1 universe.go universe_test.go universe_driver_test.go` and `go vet` passed in an isolated standard-library test harness. A tagged PostgreSQL 16 test now covers real snapshot import, completed/blocked/leased resume, raw-byte tampering and partial active flags; that tagged test **has not been executed here**.
- **Phase 1 still incomplete:** GitHub-hosted CI result was not returned by the connected tool; installed vnstock probe, PostgreSQL 16 integration, actual ingest/backfill, row throughput, full history coverage and cross-source/data-quality validation remain unverified. Phases 2–6 are still not ready to enter.

## Source-to-universe parity and read-only progress (2026-10-16)

- Hardened `LoadVerifiedBackfillUniverse`: checksum-only integrity was insufficient. It now parses the exact archived vendor listing frame and cross-checks each symbol, exchange and ICB code with the latest PostgreSQL listing state in a consistent transaction. Coordinated relational metadata tampering cannot pass by retaining the same row counts.
- Expanded the offline `database/sql` fake-driver tests to use a **valid** three-exchange, 1,002-symbol listing frame and cover a checksum-valid but membership-tampered database. Added a PostgreSQL integration regression test for coordinated symbol metadata changes.
- Added the read-only `backfill-status --from DATE --to DATE [--source vci]` CLI, returning backfill status counters and at most ten pending symbols without requesting market data or spending quota.
- Verified isolated Go tests with `-race` and `go vet` in a reconstructed standard-library module containing these components. Full repo/PGX CI and the real PostgreSQL 16 integration are not verified in this environment. **Phase 1 is not complete**; no live backfill or recommendation is claimed.

## Quota freshness during long backfills (2026-10-16)

- The five-minute PostgreSQL quota-guard expiry no longer forces every lengthy backfill to stop at the first expiry. `Runner.BeforeCall` now invokes a fail-closed refresh check **only for unfinished jobs, before the local pacer and durable reservation**.
- When less than 90 seconds remain, the runner obtains a new **passive** vnstock status/usage report. It accepts only authenticated Community status (reported internally as `free`) and exact usage limits/counters, deriving remaining daily/monthly calls and using the reported per-minute rate. Missing, Guest, percentage-only, mismatched-worker-ID, or changed-tier readings stop the run before a new market call.
- The refreshed observation is installed through `PostgresStore.InstallQuota`, which retains the lesser of verified remaining allowance and previously unspent budget, preserving all historical reservation records. The new preflight refuses to roll an old Vietnam trading-day quota into a later day; starting the next day's run requires fresh explicit authorization.
- Added Go standard-library unit/race tests for quota guard expiry, database failure, missing observations, tier changes, worker response validation and the no-reservation-on-refresh-failure invariant. Corrected the existing injected storage-failure test to exercise the actual commit path instead of an earlier response-ID mismatch.
- Added a tagged PostgreSQL 16 regression test proving refresh does not replenish three already-consumed reservations. **This tagged test has been committed but has not been executed in this container.** Isolated local Go tests with `-race` and `go vet` passed; the full repository suite and GitHub Actions push checks remain unverified.
- The live historical backfill is still opt-in; there is no automatic unattended overnight/day-boundary daemon. **Phase 1 remains partial.** No real market calls were made here and no model, signals or production serving were enabled.

## CI triage and Phase 1 continuation (2026-10-16)

- GitHub Actions run 66 on `e42516e` exposed two independent regressions: the CI guard test still passed the removed `--symbols` flag, and one raw-byte SQL assertion used an invalid `DO $ ... END $` block. The Go failure also kept the tagged PostgreSQL job from reaching compilation.
- Updated the CI guard test to use supported arguments and added a check that caller-supplied symbols remain rejected. Fixed the PL/pgSQL block to use `$$` delimiters. The tagged integration helper is now named `installVerifiedQuota` to avoid colliding with the `verified` fixture in `planner_test.go`.
- Added `go.sum` and pinned transitive pgx module requirements in `go.mod`; `go mod verify` passes.
- Local checks on Go 1.23.0: `go test -race -count=1 ./...`, `go vet ./...`, and a tagged PostgreSQL build-only run all pass. All 15 Python worker tests pass; Python compilation and TOML parsing pass.
- PostgreSQL 16 service execution is not available in this container because service setup requires privilege transitions the runtime blocks. GitHub Actions run 67 on `a43f0a9` passed the PostgreSQL 16 migration assertions, native migration twice, and tagged database integration tests; it also passed the Go race/vet and Python jobs. The local tagged run compiled the PostgreSQL code but did not execute database tests.
- **Phase 1 remains PARTIAL.** The installed vnstock v5 probe, real listings import, quota-capped historical bars backfill, full coverage, throughput, and end-to-end quality gates still require the user's single registered machine and its local PostgreSQL database. No live market call was made here; no Phase 0/1 exit is claimed.

## 2026-10-16 — authenticated local passive vendor report

- The user registered vnstock 5.0.3 successfully. The CLI status reports `tier=free` (the Community account tier) and `authenticated=true`; the passive probe supplies exact usage limits and counters.
- The fresh report shows 60 requests/minute, 3,600/hour, 10,000/day and 100,000/month, with zero used in each bucket. The report root has `active=false`; no market-data route was called.
- This confirms local authentication and the v5 quota JSON shape only. The active capability probe, listings import, and historical backfill remain unverified. Credentials and device identifiers are intentionally omitted.


## 2026-10-16 — registered-device listing probe

- The user ran the active `equity_list` route from `docs/probe/retry6/2026-10-16.json`. It returned 1,754 rows with columns `symbol`, `exchange`, `organ_name`, `organ_short_name`, and `icb_code_lv2`: HOSE 406, HNX 299, UPCOM 814, and DELISTED 235.
- The initial importer accepted only the three trading exchanges. The live probe proved the provider also returns a `DELISTED` category, with no original exchange. The importer now preserves the complete frame and exact source bytes in `raw.landings`, excludes those 235 rows from `core.symbols`, `core.listing_snapshots`, and backfill candidates, and reports provider/current/excluded counts. It does not infer their prior exchange.
- The Windows Unicode transport fix is in `d04bba5`; Go, Python, and PostgreSQL CI passed. The DELISTED-aware importer is in `1407695`; its Go race/vet, Python, and PostgreSQL 16 migration/integration jobs all passed. No probe JSON containing company rows is committed.
- **Phase 1 remains partial:** the local PostgreSQL migration/import, quota-capped daily-bar backfill, queue resumption, coverage and end-to-end quality gates still need to run on the registered machine.

## 2026-10-17 — Observed historical securities master (Phase 1 still PARTIAL)

- Added migration 008, an offline `vnpipe rebuild-security-master` command, and transactional integration into future verified listing imports. Replays existing `equity_list` raw landing bytes, verifies SHA-256 and full HOSE/HNX/UPCOM membership against dated imported listing snapshots, then preserves the entire provider frame including `DELISTED` category.
- CI run https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/38987359951 passed Go, Python and PostgreSQL integration, including delisted-symbol retention, byte corruption rejection and replay idempotency. **Local registered-device migration/rebuild is not yet reported as executed.**
- The October 16 archived listing should produce 1,754 observed symbols (1,519 currently exchange-listed + 235 provider DELISTED) after local migration/rebuild, with **no additional vnstock request or changed OHLCV job state**.
- Delisted effective dates, first-ever public trading, exchange-transfer history and the pre-2026 investable universe remain **UNKNOWN** until independently evidenced. This is not full historical membership reconstruction. Phase 2–6 are not begun or declared complete.

## 2026-10-17 — Local Phase 1 database audit

- The initial audit verified all 10 recorded migrations. Migrations 011–013 were subsequently applied locally; all 13 recorded SHA-256 checksums matched.
- The verified current listing contains 1,519 active HOSE/HNX/UPCoM symbols; the observed security master contains 1,754 tickers. `ops.company_profile_jobs` reports 1,742 `IMPORTED` and 12 `ERROR`; 1,742 profile observations are archived. Error states remain explicit and are not filled with placeholders.
- The exact existing OHLCV range is 2018-10-01 through 2026-10-16. Read-only `backfill-status` reports 362 `COMPLETED`, 180 `PARTIAL`, 975 pending, 2 deferred prior `InvalidFrame` jobs, 0 blocked and 0 active leases. The expired HMD lease is eligible for normal quota-guarded resume. `core.bars_daily` currently contains 627,164 rows across 538 symbols.
- The quality ledger contains 309,528 `ZERO_VOLUME_UNVERIFIED`, 625 `INVALID_OHLC` and 2 `INVALID_PRICE` observations. These are retained as quality findings; zero-volume rows are not treated as executed trades. Reprocessing already archived OHLCV frames was a no-op (0 inspected), so these counts were unchanged.
- Queue detail audit: all 180 `PARTIAL` jobs have `last_error_type=PartialInvalidTradedBars`, source VCI, one attempt each, and cover 201,383 canonical rows (20–1,994 rows per symbol). Their first bars range from 2018-10-01 to 2022-11-08 and last bars from 2023-12-08 to 2026-10-16. Their retained quality findings are 625 `INVALID_OHLC` across 178 jobs, 2 `INVALID_PRICE` across 2 jobs, and 132,068 `ZERO_VOLUME_UNVERIFIED` across 176 jobs. The two deferred `InvalidFrame` jobs (`A32`, `ABC`) remain pending after one attempt each and have no bars in the requested range.
- A fresh passive probe (`active=false`) through the project `.venv`, reconfirmed on 2026-10-17, reported `tier=guest`, `authenticated=false`, `limit_source=policy_v1` for usage. These policy figures are not valid registered-account quota evidence. No live data route was called during this audit; live ingestion must wait for a fresh authenticated absolute quota report.
- Replayed the PostgreSQL CI migration checks on an isolated PostgreSQL 18.3 `vnsignal_test` database: all 13 migrations applied twice; schema assertions, the injected rollback fault and the connection-failure check passed. Tagged PostgreSQL tests for `internal/ingest` and `internal/dq` passed, including the one-reservation profile audit transitions and persisted DQ blocking result. The disposable database was dropped after verification. This does not replace the hosted PostgreSQL 16 run.
- Offline verification on this revision passed `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...` (with `VNPIPE_PYTHON` set to the project `.venv`), `go -C go vet -p 1 ./...`, and all 23 Python worker tests. The first Go test attempt used the blocked Windows Store Python alias; rerunning with the project interpreter passed. GCC 16.2.0 exists at `C:\msys64\ucrt64\bin\gcc.exe`, but Go starts with `CGO_ENABLED=0`; the explicit cgo race build failed in `runtime/cgo` with exit status 2 before tests ran. The race suite is not verified on this machine; this is not a missing-GCC finding.
- Migration 013 records observed bar dates in `core.calendar`; the local union now has 2,008 observed dates from 2018-10-01 through 2026-10-16. `vnpipe dq-run --date 2026-10-16` persisted a newer `STALE` run (`cc804e57-47c8-4aef-86a3-d5c1d479aa89`). Calendar lookup now finds the expected and preceding observed dates, but Tier A membership and all 30 independent cross-source pairs are absent, so the gate remains blocking. No fabricated samples were added. This proves fail-closed reporting, not full-coverage validation or a passing gate.
- Phase 1 exit is **not met**: 975 jobs remain pending, 180 remain partial, two legacy invalid frames are deferred, the passive vnstock report is Guest/unauthenticated, and Tier A plus independent cross-source evidence is absent. Phases 2–6 remain unstarted.

## 2026-10-17 — Phase 1 calendar and DQ gate increments

- Added migration 014 to make bar-derived calendar evidence reversible. Inserted dates are added; moving a bar removes the old date only after its final bar leaves; deleting the final bar removes only the `observed_bars` source and note while preserving other calendar sources, notes, and session status.
- The disposable `vnsignal_test` database applied migrations 001–014 twice and passed schema assertions, including date move/delete and merged-provenance cases, injected transaction rollback, and unavailable-connection checks. Tagged PostgreSQL integration tests passed for `internal/ingest` and `internal/dq`. The test database was created after confirming it was absent and dropped after verification. The local `vnsignal` migration runner verified prior SHA-256 records and applied migration 014; post-migration checks found 2,008 observed-bar dates for 2,008 distinct bar dates and no stale `observed_bars` calendar rows.
- `RunPostgresGate` now loads previous/current traded bars for exchange-limit action checks, allows a listing-day exemption only with unambiguous archived `FIRST_EVER_PUBLIC_TRADE` evidence, and blocks dated Tier A quality issues (`INVALID_OHLC`, `INVALID_PRICE`, `INVALID_VOLUME`) plus matching `PARTIAL`/`BLOCKED` OHLCV jobs. `ZERO_VOLUME_UNVERIFIED` observations are quarantined and reported as warnings, not treated as executed trades.
- PostgreSQL fault-injection coverage confirmed that an over-limit HOSE move produces the specified warning and quarantine, a Tier A invalid-bar issue plus a partial OHLCV job both block the gate, and 30 selected source-name pairs without landing/row lineage still block. These fixtures ran only in disposable `vnsignal_test`; they are not production market data.
- Latest offline checks passed: `go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, all 23 Python tests, the migration script, and tagged PostgreSQL integration tests. Live routes remained disabled; no vnstock market-data call was made.
- GCC 16.2.0 is installed at `C:\msys64\ucrt64\bin\gcc.exe`, but is not on this shell's default `PATH`; Go therefore defaults to `CGO_ENABLED=0`. With `CGO_ENABLED=1`, explicit `CC`, GCC on `PATH`, and a workspace-local Go cache, the full `go -C go test -race -p 1 -count=1 ./...` run fails while building Go's `runtime/cgo` (`cgo.exe: exit status 2`) before package tests. A direct C syntax-only check using the installed GCC succeeds (exit 0); this does not clear the Go/cgo failure. Visual Studio 2022 Build Tools and `cl.exe` are also installed; a targeted race build using that compiler likewise stalled without output and was interrupted. WSL distro enumeration returns `E_ACCESSDENIED`. Race coverage remains unverified. Do not claim it passed.
- After migration 014, `vnpipe dq-run --date 2026-10-16` persisted STALE run `d309013e-1c37-45f9-8935-4726bf7dccf3`: Tier A membership is unavailable, there are 0 of 30 selected cross-source pairs, and the scoped bar/staleness/session-count checks cannot pass. This is fail-closed evidence, not full-coverage validation.
- Phase 1 remains **PARTIAL**. The registered-device passive report is still Guest/unauthenticated, so no fresh verified absolute quota exists to safely resume the 975 pending jobs or retry the 180 partial and two deferred invalid-frame jobs. There is still no dated Tier A membership or independent second-source OHLCV evidence. No usable production cross-source sample has verified source-landing/row lineage, and no feature-snapshot table exists for a database drift measurement. No Phase 1 exit is claimed.

## 2026-10-17 — source-attributed ingestion and lineaged cross-source DQ

- The worker now preserves an allowlist of vnstock source/provider attribution fields. Live OHLCV ingestion and archived-frame recovery require `attributes.source` to match the explicitly requested source; missing or mismatched attribution is quarantined. The frame remains within the 400-line adapter limit.
- Migration 015 adds nullable primary/secondary landing IDs and zero-based row indexes to DQ samples. Existing rows remain unlineaged and do not count as ready. Readiness counts only selected Tier A pairs with all four lineage fields.
- `RunPostgresGate` now replays exact `payload_bytes`, verifies SHA-256, route, symbol, frame shape/order, selected session, traded OHLCV and provider source/organisation attribution, confirms stored-close parity, and requires distinct provider organisations. Only validated pairs reach the 0.5% close comparison.
- PostgreSQL 18.3 disposable `vnsignal_test` applied migrations 001–015 twice; schema assertions, injected rollback and unavailable-connection checks passed. The app migration runner applied 15 migrations and then verified a zero-change second run. Tagged `internal/dq` and `internal/ingest` integration tests passed: a healthy 30-pair fixture passed, while missing lineage, mismatched provider attribution, same-organisation sources, tampered payload bytes, and a real close mismatch failed as required. All fixture rows and the disposable database were removed.
- The local `vnsignal` database applied migration 015. A new local `dq-run` for 2026-10-16 persisted STALE run `9a5b1467-73df-4a14-b62c-b7e74f95c81d`: Tier A membership is unavailable, 0 of 30 selected lineaged pairs exist, and the scoped bar/staleness/session-count checks cannot pass. No production cross-source values were added.
- Offline checks passed: `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, all 24 Python tests, the migration script, and tagged PostgreSQL integration tests. No live vnstock data route was called. The explicit race build used installed GCC 16.2.0 with `CGO_ENABLED=1` and failed inside Go `runtime/cgo` before package tests (`cgo.exe: exit status 2`); direct GCC C syntax checking passed. Race coverage remains unverified; this is not a missing-GCC finding.
- Phase 1 remains **PARTIAL**. Passive vnstock status is Guest/unauthenticated, so full backfill cannot safely resume; there are still 975 pending jobs, 180 partial histories, and 2 deferred invalid frames. The new schema and validator make cross-source evidence auditable, but no verified Tier A universe or independent second-source OHLCV evidence currently exists. Phases 2–6 remain unstarted.

## 2026-10-18 — Phase 1 remains PARTIAL

- The latest local audit remains anchored at 2026-10-16 market data: 627,164 daily bars across 538 symbols, with bars on 2026-10-16 for 324 symbols. The OHLCV queue has 362 `COMPLETED`, 180 `PARTIAL` (`PartialInvalidTradedBars`), two deferred `PENDING` invalid-frame jobs (`A32`, `ABC`), and one `RUNNING` job (`HMD`); 974 currently listed symbols have no job. Company-profile coverage remains 1,742 archived observations and 12 explicit errors.
- The latest dated PostgreSQL DQ result remains `STALE` (`9a5b1467-73df-4a14-b62c-b7e74f95c81d`): dated Tier A membership is empty, and there are zero selected lineaged cross-source samples. Verified first-public-trade lifecycle evidence is still absent, so the strict Tier A builder correctly fails closed. No production Tier A membership or cross-source values were fabricated.
- Migration 016 adds append-only enforcement to `raw.landings`. PostgreSQL 18.3 disposable migration/schema checks and tagged `internal/ingest` and `internal/dq` integration tests passed through migration 016; the disposable test database was removed. PostgreSQL 16 CI remains unavailable locally because the Docker daemon is not running.
- Offline verification on this checkout passed `VNPIPE_DISABLE_LIVE=1 go -C go test -p 1 -count=1 ./...`, `go -C go vet -p 1 ./...`, and all 24 Python JSONL tests. The full race run again stopped in Go `runtime/cgo` (`cgo.exe: exit status 2`) despite installed GCC at `C:\msys64\ucrt64\bin\gcc.exe`; race coverage is unverified. No live market-data route was called.
- The 2026-10-18 vnstock status command returned `authenticated=false`, `tier=guest`, and an error that it could not retrieve the current client policy from vnstocks.com. This does not establish whether the user's prior registration/key entry succeeded, but it provides no valid authenticated absolute-quota evidence. The saved active probe is dated 2026-10-16 and is stale for the 24-hour index-backfill preflight. Full equity backfill and the VNINDEX/KBS one-call path therefore remain gated. Phase 1 exit criteria are not met; Phases 2–6 remain unstarted.

## 2026-10-18 — Phase 1 latest verification

- The guest status above came from the project-local vnstock state directory. The registered Community account is under the Windows profile `.vnstock`; setting `VNSTOCK_HOME` to that authenticated state directory makes the Go worker's passive preflight report authenticated absolute limits. The latest snapshot at 05:11 +07 shows 6,105 daily and 96,092 monthly calls remaining, with zero pending reports. The profile path, not the API key, is passed to the worker; the key remains in vnstock's encrypted local state.
- VCI history remains 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`; canonical traded value remains NULL in every bar. A SHA-verified source-link count shows 1,321 of 1,505 bar-backed current symbols have at least 250 positive-volume pre-as-of VCI sessions. The Tier A builder accepts that tenure evidence but blocks on the absent source traded-value field; no proxy or synthetic value was introduced.
- The 2026-10-15 FPT KBS compact probe and VCI canonical row both report close 58.0. A KBS APF probe for the invalid VCI date returned `AdapterError` and produced no repair row; no retry was made. Compact reports remain probe-only and do not satisfy durable cross-source lineage.
- The existing active `market_calendar` probe returned 355 rows attributed to `source=builtin`, route `reference.events.market`, organisation `Vnstock Project`, spanning 2000-01-01 through 2026-11-24 with event fields rather than a complete exchange-session list. The report did not retain the raw event frame. This does not satisfy the independent exchange-calendar requirement.
- Latest DQ record is still `e13ea9a1-5837-4a63-a061-95689ee19889`, status STALE, with no Tier A membership or selected lineaged pairs. The source route replay bug is fixed, but Phase 1 still lacks a verified full exchange calendar, source traded value, 30 durable pairs, and resolution of partial/blocked histories.
- Offline Go tests, `go vet`, all 26 Python worker tests, and the serial PostgreSQL integration suite passed. Migration/schema checks passed twice on a disposable PostgreSQL 18.3 database; PostgreSQL 16 hosted CI is pending. The migration shell script's final grep step could not run under local Git Bash. The Windows race test remains unavailable because Go `cgo.exe` exits with status 2 even with GCC enabled.

## 2026-10-18 — authenticated registered probe and backfill outcome

- A passive status report from the default sandbox returned Guest; the same local vnstock 5.0.3 installation returned authenticated Community status (`tier=free`) when run in the registered machine's network context. The active report at `docs/probe/backfill-2026-10-18/2026-10-18.json` records seven route schemas. VCI equity OHLCV returned 1,995 rows from 2018-10-18 through 2026-10-16 (observed maximum history 2,920 days); KBS index OHLCV returned 1,000 rows from 2022-10-12 through 2026-10-16. The raw probe remains local because it includes registered-device metadata and source frames.
- The fresh passive report was authenticated and server-sourced: limits 60/minute, 3,600/hour, 10,000/day, 100,000/month; used 3,888/day and 3,901/month; 20 reports pending. It is evidence of the account at that observation time, not an entitlement guarantee for future routes.
- `backfill --active` ran for the verified VCI depth, 2018-10-18–2026-10-16, with a 10-session monthly budget and a 1,519-call cap. Final read-only queue status: current listing 1,519, source provenance verified, 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`, 0 leased, 0 deferred-invalid and 0 pending. All 1,519 requests have durable quota reservations and corresponding raw landing records. The database has 1,807,778 daily bars through 2026-10-16; 1,505 of 1,519 current symbols have at least one bar. The runner recorded 1,590 invalid traded rows and 851,190 zero-volume-unverified rows; partial states and findings were preserved.
- The blocked equity frame was quarantined as `InvalidFrame: missing/invalid source row count`. No retry was issued. A separate one-call KBS index request was also quarantined: the 2023-05-15 frame has `low` above `close`; it committed zero index bars. Do not retry either frame until a source-specific repair or newly verified route is available.
- Latest persisted DQ result `738362b1-6bf6-49c2-bdd1-4a6ca07f6c27` is `STALE` with five blocker categories: Tier A universe unavailable, no selected cross-source sample (0 of 30), bar checks, staleness, and invalid session counts. There are zero `FIRST_EVER_PUBLIC_TRADE` lifecycle records and zero selected cross-source samples. The calendar contains 2,008 `observed_bars` dates but no independently verified exchange calendar. No Tier A membership or cross-source evidence was fabricated.
- Local PostgreSQL 18.3 has migrations 001–016 applied, including append-only triggers on `raw.landings`. Phase 1 remains **PARTIAL**: the queue is exhausted, but the 494 partial histories, one blocked equity frame, 14 current symbols without bars, invalid KBS index frame, and missing calendar/lifecycle/cross-source evidence prevent exit. Phases 2–6 remain unstarted.
- Verification after the run: `go -C go test ./...` and `go -C go vet ./...` passed with `VNPIPE_PYTHON` set to the project `.venv`; all 24 Python JSONL tests passed; `git diff --check` passed. `go -C go test -race ./...` was attempted with `CGO_ENABLED=1` and installed GCC 16.2.0 (`C:\msys64\ucrt64\bin\gcc.exe`), but Go `runtime/cgo` exited with status 2 before package tests. GCC is installed; race coverage is unverified. PostgreSQL 18.3 migration/integration checks passed through 016 in the disposable test database; PostgreSQL 16 CI cannot run locally because Docker is unavailable. Rust/desktop tests are not available for the unstarted later phases.

## 2026-10-18 — registered key recheck and liquidity-route entitlement

- The local registered vnstock profile was used without copying the key into the repository. A fresh passive report at 05:43 +07 (`docs/probe/phase1-authenticated-probes/passive-recheck/2026-10-18.passive.json`, local-only) returned `authenticated=true`, `tier=free`, and server-sourced absolute limits of 60/minute, 3,600/hour, 10,000/day, and 100,000/month; usage was 3,895/day and 3,908/month, with zero pending reports. This is a current account snapshot, not a market-data entitlement for every route.
- The active `equity_trade_history` capability probe at 05:41 +07 (`docs/probe/phase1-authenticated-probes/2026-10-18.json`, local-only) returned `EntitlementError` for the Community account, with no usable daily traded-value rows. Do not retry this route unless the account entitlement changes; a fresh quota snapshot alone does not grant it.
- The one governed retry of the stale HMD job used a fresh quota snapshot and a new durable reservation, then returned `AdapterError`; it committed no landing. The old-range HMD job is now pending at attempt 2. Do not retry without a source-specific repair. The latest read-only status for the verified VCI range 2018-10-18–2026-10-16 remains 1,024 `COMPLETED`, 494 `PARTIAL`, 1 `BLOCKED`, and zero pending or leased jobs across 1,519 current symbols.
- The authorized Community key resolves authentication. Phase 1 remains **PARTIAL** because `core.bars_daily.traded_value` is NULL, the exact trade-history route is not entitled under the current Community account, DQ has no eligible Tier A universe or 30 selected lineaged pairs, and the observed-bar union is not an independently verified exchange calendar. No turnover proxy was written or treated as exact. Phases 2–6 remain unstarted.

## 2026-10-18 — registered source probes and Phase 1 liquidity evidence

- The existing local registration was verified as Community tier on the network-enabled machine; the sandboxed status command cannot reach the account policy endpoint and falls back to Guest. No new registration was needed. The last complete passive quota report before the targeted probes supplied absolute limits and counters; the five raw-price requests each passed fresh quota preflight and used the metered Go probe path.
- The compact reports in `docs/probe/phase1-authenticated-probes/` record VCI APF raw-price reads and KBS FPT equity reads. APF on 2018-10-22 is a valid one-row observation; on 2018-10-19 the full-precision source row still has `high=9.19157 < close=9.21682`, so it remains quarantined as a provider inconsistency. KBS FPT returned 1,994 rows for 2018-10-18 through 2026-10-15, one row on 2026-10-15, and zero rows on 2026-10-16; all saved KBS equity reports include matching `kbs` source and KB Securities (KBSV) organisation attribution. These probes establish route/provider capability only; they are not canonical backfill rows or the 30 selected, lineaged cross-source pairs required by DQ.
- All 1,807,778 canonical daily bars still have `traded_value IS NULL`. Vnstock's [market-data documentation](https://www.vnstocks.com/docs/vnstock/thi-truong-market) describes equity prices in thousand VND and notes historical adjustment. `close × volume × 1,000` is therefore an adjusted-close-based estimate, not verified executed turnover. It remains exploratory and is not written into the source `traded_value` field or used to claim Tier A eligibility.
- Phase 1 remains PARTIAL. The registered key resolved the auth blocker, but DQ still lacks an independently verified exchange calendar, valid point-in-time tenure evidence for Tier A, liquidity values under an approved basis, and 30 durable independent cross-source pairs. No production data was fabricated and no recommendation is enabled.
- Offline verification on this checkout: `VNPIPE_DISABLE_LIVE=1 go -C go test ./...`, `go -C go vet ./...`, all 26 Python JSONL tests, `go -C go test -tags postgres_integration -run '^$' ./internal/dq` (compile-only), and `git diff --check` passed. The PostgreSQL-tagged integration was not executed against a database. The race suite remains unverified: with CGO enabled and GCC 16.2.0 installed at `C:\msys64\ucrt64\bin\gcc.exe`, Go `runtime/cgo` exits with status 2 before project package tests.

## 2026-10-18 — KBS raw-only path and current Phase 1 gate

- Added `vnpipe ingest-kbs-cross-source` with explicit `--active`, date range, a default one-call cap and a hard maximum of 30. Candidate symbols come from positive-volume VCI bars. The call uses `Gateway.CallRecorded`; the store verifies KBS attribution, exact response bytes, SHA-256, the running job and its successful reservation before writing append-only `raw.landings`. It does not write `core.bars_daily` or select DQ pairs.
- A fresh passive preflight authenticated the registered profile and installed a local quota guard at 06:02 +07. The one-call FPT/KBS request for 2026-10-15 was durably reserved, then the vendor returned `AdapterError`; job 2067 remains `PENDING` at attempt 1 with reservation outcome `FAILED`. No KBS equity landing or canonical-bar change resulted. A separate metered `probe-ohlcv` recheck also returned `AdapterError`; it saved no frame. No further retries were made.
- A read-only database check after the calls found zero KBS equity landings, 1,807,778 VCI canonical bars, and all 1,807,778 `traded_value` fields still NULL. The verified VCI range remains 1,024 `COMPLETED`, 494 `PARTIAL`, and 1 `BLOCKED` jobs.
- The offline `dq-run --date 2026-10-16` produced `682243a2-f6de-4fba-a959-d852dcacf4a5`, status `STALE`, with blockers for unavailable Tier A, 0/30 selected cross-source pairs, no bars in the DQ sample, invalid staleness, and invalid session counts. Publication remains disabled.
- Verification on this machine: `go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover -s tests -v` passed (27 Python tests). The serial PostgreSQL-tagged integration suite passed against disposable local `vnsignal_test` on PostgreSQL 18.3. `go -C go test -race ./...` remains unverified because Go's Windows `runtime/cgo` exits with status 2 even with GCC installed. PostgreSQL 16 hosted CI remains unverified.

## 2026-10-18 — official closure evidence and worker error redaction

- Added [`docs/probe/phase1-calendar-overrides-2019-2026.sql`](probe/phase1-calendar-overrides-2019-2026.sql) and applied 103 explicit `is_session=false` overrides to the local database for HNX-notified holiday closures and make-up Saturdays spanning 2018-12-31 through 2026-09-02. Sources are the official HNX annual notices for 2019–2026 and the 2019/2026 adjustment notices. A pre-insert audit found no canonical bars on these dates; a post-insert audit found 103 rows and zero overlapping canonical bars.
- A gate run for the explicitly closed 2026-01-02 date recorded run `d5a5c694-053e-478f-bdc2-65f11cd2a986` as `STALE` and reported “expected date is not a verified trading session.” It also remained blocked by missing Tier A membership, 30 cross-source pairs, bars for that date, and valid session counts. This verifies that the override controls the gate; it does not complete the exchange calendar.
- The HNX evidence supplies scheduled closures only. Ad hoc exchange suspensions, a complete list of open sessions, and the full 2018 schedule remain unverified. The DQ result remains blocking.
- Fixed the worker JSONL error frame to use a constant safe message instead of including vendor exception text. Python JSONL tests passed (27); Go tests and `go vet` passed when run with a writable workspace cache and the installed project Python interpreter. The Windows race run and PostgreSQL 16 CI migration check remain to be recorded before Phase 1 sign-off.
- A fresh passive report at 06:35 +07 authenticated the registered Community profile (`tier=free` in the library status field) and returned server-sourced absolute limits/counters. The local `quota_guard` was refreshed before the next call. One new KBS `A32` request for 2026-10-15 was reserved through `CallRecorded`, returned `AdapterError`, and committed no frame or landing; the earlier FPT attempt has the same outcome. Both jobs remain pending at attempt 1, KBS equity landings remain zero, and no retry was made.
- Re-ran `dq-run --date 2026-10-16`: run `4f6b9e3b-6523-47c5-baa5-bf796f70bd50` remains `STALE` with blockers for unavailable Tier A, 0/30 selected cross-source pairs, no bars in the DQ sample, invalid staleness, and invalid session counts. The 2026-01-02 closure check is also persisted as `STALE` because it is explicitly not a verified session.
- Local PostgreSQL 18.3 migration checks passed on a new disposable database: all 16 migrations applied twice, schema assertions and the quarantine diagnostic passed, and injected rollback and unreachable-connection checks behaved correctly. The Bash CI wrapper could not start in this Windows sandbox; its checks were run directly with PowerShell/`psql`. Re-running tagged integration tests against a separately named database was refused by their safety guard; the existing `vnsignal_test` database has stale rows and fails the schema assertion, so it was left untouched. PostgreSQL 16 hosted CI remains unavailable.
- The race run was retried with `CGO_ENABLED=1`, `CC=C:\\msys64\\ucrt64\\bin\\gcc.exe`, and workspace-local Go caches; `runtime/cgo` still exits with status 2 before package tests. GCC is installed, but the Windows race suite is not verified. Phase 1 remains partial: the Community entitlement does not expose exact daily executed turnover, VCI still has 494 partial and one blocked history, and there are zero durable KBS landings or selected cross-source pairs.

## 2026-10-18 — approved research proxy and updated Phase 1 evidence

- Tier wording: the user's registered key is **Community**. Vnstock's internal `status()['tier']` value is `free` for that user-facing tier; it is not the user's account name. The account is authenticated, and the documented Community equity OHLCV sources are VCI and KBS.
- The user's approval supersedes the earlier hold on a liquidity proxy. Migration 017 was applied to the working database and verified on a fresh disposable PostgreSQL 18.3 database with all 17 migrations and `tests/sql/schema_assertions.sql`. `core.bars_daily_with_proxy` exposes `traded_value_proxy_vnd = adjusted close × volume × 1,000`; the source `traded_value` field remains untouched. The working database has 1,807,778 canonical bars, including 1,807,695 non-null proxy values; the remaining 83 are null and are not imputed.
- Tier A was built for 2026-10-16 using 20 checksum-linked VCI sessions and the approved research proxy. The result contains 158 symbols from 1,519 verified listed symbols; 824 candidates without a complete, valid 20-session window were excluded. This enables research ranking/features only; it does not establish execution capacity or enable recommendations/order sizing.
- Supported VCI history spans 2018-10-18 through 2026-10-16: 1,024 jobs `COMPLETED`, 494 `PARTIAL`, and 1 `BLOCKED`. The requested 2018-10-01 start is beyond the observed VCI depth. Targeted HMD/HMG requests for the earlier range and the fresh KBS probe returned `AdapterError` and committed no usable frame/landing; no additional retries were made.
- DQ run `83703cc8-5257-404a-892b-ec8796d3d7bb` for 2026-10-16 is `FAILED` only at the cross-source comparison gate: it has 0 of the required 30 durable, independently attributed same-session pairs. A fresh KBS capability probe returned `AdapterError`; KBS raw equity landings remain zero. Phase 1 therefore remains **PARTIAL**, and DQ publication/recommendations remain disabled.
- After the Tier A code changes, `go -C go test ./...`, `go -C go vet ./...`, `python -m unittest discover -s tests -v` (27 tests), and `git diff --check` passed. The fresh-database migration/schema checks passed on PostgreSQL 18.3. PostgreSQL 16 hosted CI and the Windows race suite remain unverified.

## 2026-10-18 — KBS date coverage and refreshed DQ result

- The registered account is Community; `free` remains the library's internal tier identifier. A fresh passive report collected through the Go worker confirmed authenticated status and server-sourced absolute limits.
- Four one-day KBS equity requests were durably reserved through `Gateway.CallRecorded`: AAA returned `AdapterError`, AAS and ABB returned the sanitized cause `NetworkError`, and ACB returned a frame without a valid source row count and was blocked. None produced an equity landing.
- Two multi-day AAA requests succeeded and wrote append-only raw landings with KBSV organisation attribution: the requested intervals 2026-10-01..2026-10-16 and 2026-10-01..2026-10-17 both returned 11 rows ending 2026-10-15. No Oct 16 KBS row was present; no canonical VCI bars were changed.
- Added an optional `--sample-date` to `ingest-kbs-cross-source` so symbol selection can use the dated Tier A set while the KBS request interval extends beyond it. The selector still requires 30 complete, same-session, independently attributed pairs and writes nothing when fewer than 30 qualify.
- `select-dq-cross-source --date 2026-10-16` found 0 of 30 complete candidates and wrote no samples. DQ run `ca9b7bc4-b781-4568-a87f-a8f6856d67e4` is `FAILED` with the sole reported blocker `cross-source sample unavailable: have 0 explicitly selected rows (0 Tier A), require exactly 30 Tier A pairs`.
- After these Go changes, `go -C go test ./...` passed with the project `.venv` interpreter, `go -C go vet ./...` passed, and `python -m unittest discover -s tests -v` passed all 27 tests. The PostgreSQL-tagged selector packages compiled with `-run '^$'`; no tagged integration test was executed against a database.
- Phase 1 remains **PARTIAL**. The Oct 16 gate result does not close the separate history, invalid-row, and complete-calendar exit criteria; recommendations remain disabled.

## 2026-10-18 — authenticated VCI backfill and KBS session-date check

- The registered Community profile was authenticated on the local machine. An active `equity_ohlcv` capability probe succeeded and reported VCI available with 1,995 rows spanning 2018-10-18 through 2026-10-16. The report is saved at [`docs/probe/phase1-continuation/escalated/2026-10-18.json`](probe/phase1-continuation/escalated/2026-10-18.json); `free` in its status object is the library's internal label for Community.
- The quota-guarded VCI backfill ran for 2018-10-01..2026-10-16 against the verified 2026-10-17 listing snapshot (1,519 symbols). All eligible jobs reached a terminal state: 1,023 `COMPLETED`, 495 `PARTIAL`, 1 `BLOCKED`, 0 pending. The start date predates observed VCI history; no rows were fabricated before 2018-10-18. A separate explicit retry of the two deferred legacy `InvalidFrame` jobs produced one `COMPLETED` and one `PARTIAL`; no deferred invalid-frame jobs remain. The blocked UTT frame still has `InvalidFrame: missing/invalid source row count` and was not promoted.
- A separate metered VCI `probe-ohlcv` request for UTT over 2018-10-01..2026-10-16 returned no usable frame (`available=false`, count 0, no 2026-10-16 target row). Its report is at [`docs/probe/phase1-continuation/utt/2026-10-18-UTT-070950.002524400Z.json`](probe/phase1-continuation/utt/2026-10-18-UTT-070950.002524400Z.json); the blocked job was left unchanged.
- Thirty KBS equity requests for 2026-10-15..2026-10-16 were durably reserved and wrote 30 append-only raw landings only. All 30 frames were attributed to KBS but contained October 15 as their latest row; none contained October 16. One fresh KBS request for 2026-10-16..2026-10-17 returned `InvalidFrame: missing/invalid source row count` and wrote no landing. No KBS response changed canonical VCI bars.
- `select-dq-cross-source --date 2026-10-16` found 0 of 30 fully verified same-session pairs and wrote no samples. DQ run `aee82540-e14f-4a34-9e71-44f2a0b55514` is `FAILED` because the required 30 Tier A pairs are unavailable. October 15 KBS rows cannot be substituted: Tier A membership and VCI bars must match the same session.
- Phase 1 remains **PARTIAL**. The VCI queue is drained, but partial/blocked outcomes and the missing same-day KBS pairs keep the quality gate closed; publication and recommendations remain disabled.

## 2026-10-18 — HNX official schedule reconciled to the full backfill calendar

- The HNX Guide to Trading Stocks states that stock trading runs Monday through Friday except public holidays; HNX's annual trading-holiday notices cover 2018–2026, with later adjustments recorded for 2019, 2024, 2025, and 2026. The source-backed import is docs/probe/phase1-hnx-calendar-2018-2026.sql.
- Applied the schedule to the local PostgreSQL vnsignal database. It records 105 HNX-notified closed dates in core.calendar_overrides and the 2,008 expected weekday sessions in core.calendar, each with the applicable HNX notice URL in its notes. The 2024 correction adds April 29 and May 4 as a non-trading makeup Saturday.
- Reconciliation for 2018-10-01 through 2026-10-16 found 2,008 expected sessions and 2,008 observed canonical bar dates, zero expected sessions without bars, zero bars on an effective closed date, and zero conflicts between closures and observed bars. Thus the calendar gap is closed for this historical window; the current event route remains useful for future notices.
- Re-ran dq-run for 2026-10-16; run d91f0e81-079f-479f-871c-0e453e46fc14 is FAILED solely because 0 of 30 explicitly selected same-session Tier A cross-source pairs are available. The calendar, bar-presence, staleness, and session-count checks no longer block that date.
- Phase 1 remains PARTIAL. The latest full-range VCI batch is 1,023 COMPLETED, 495 PARTIAL, and 1 BLOCKED; KBS frames still end on 2026-10-15 and do not satisfy the 2026-10-16 pair gate. No proxy was written into source-reported traded_value, and no recommendations were enabled.

## 2026-10-18 — KBS full-history probe after HNX calendar import

- The audited `ingest-kbs-invalid-history` path fetched 2018-10-01–2026-10-16 for all 494 remaining partial-VCI symbols. Including the earlier A32 request, the database now has 495/495 completed KBS jobs, 495 succeeded durable reservations, 495 checksum-verified append-only raw landings, and 578,108 archived rows. No KBS rows were written to `core.bars_daily`; canonical bars remain VCI-sourced.
- Reconciliation against 1,593 unique VCI invalid symbol/date observations found same-date KBS rows for 1,519, valid traded KBS OHLCV for 937, closes within the DQ 0.5% tolerance for 646, and both valid KBS bars and close agreement for 174. These are candidates for later explicitly sourced ML use; none were silently promoted or used to rewrite VCI history.
- KBS history reaches 2026-10-15 for 247 symbols and has zero 2026-10-16 rows. DQ run `ccf40583-e83f-449c-9d88-a962070d8bed` for 2026-10-16 is `FAILED` only on the latest-session cross-source gate: zero of the required 30 selected Tier A pairs. Calendar, bar-presence, staleness, and session-count checks pass; an Oct 15 KBS row is not substituted for Oct 16.
- Verification: Go tests passed with `VNPIPE_PYTHON` set to the project `.venv`; `go -C go vet -p 1 ./...` and all 27 Python JSONL tests passed. SQL verified all 495 succeeded reservations and matching raw-payload checksums. Phase 1 remains **PARTIAL** with 495 VCI partial jobs, one blocked job, and the Oct 16 pair gate unresolved. Race coverage remains unverified and PostgreSQL 16 hosted CI is unavailable locally.

## 2026-10-18 — official exchange calendar and auction-aware OHLC recovery

- The HNX Guide to Trading Stocks sets the weekday rule (Monday–Friday except public holidays). The annual HNX exchange notices and specific adjustments provide the actual closure dates, including makeup Saturdays when HNX explicitly did not trade. The source-backed import is `docs/probe/phase1-hnx-calendar-2018-2026.sql`; it records 105 closure overrides and 2,008 expected sessions from 2018-10-01 through 2026-10-16. Local reconciliation found 2,008 observed canonical bar dates, zero expected dates without bars, and zero bars on a recorded closure.
- HOSE establishes open/close in separate ATO/ATC call auctions; its quote-field guide defines High/Low as continuous-matching extrema, so a HOSE open can validly sit outside that interval. This is venue-specific: HNX-listed equities use continuous matching plus a closing auction, while UPCoM stocks use continuous matching throughout the session. SSI's official stream schema reports Open/Close separately from highest/lowest matched prices but does not specify whether its extrema include auction prints. Because the generic bar schema lacks reliable session-phase metadata, migration 019 and the validator require positive finite O/H/L/C, `high >= low`, and nonnegative finite volume without requiring H/L to contain O/C. See the HOSE [order-type rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf), HNX [trading FAQ](https://www.hnx.vn/vi-vn/hoi-dap.html), SSI [stream field definitions](https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage), and HOSE quote-field [guide](https://estock.duytan.edu.vn/kien-thuc-dau-tu/kien-thuc-chung-khoan/bai-3-huong-dan-doc-bang-gia-truc-tuyen-tai-hose-70.html).
- Offline replay reclassified 989 checksum-verified VCI landings under validator `vn-equity-auction-extrema-v1`: 495 in the 2018-10-01 range (including six previously partial quarantine frames) and 494 in the 2018-10-18 range. The two replay audit groups record 3,131 removed stale issue entries. Raw bytes and quota reservations were unchanged. The canonical database now has 1,809,966 bars across 2,008 dates. Remaining quality findings are two copies of one genuine high-below-low row and 50 invalid-open rows.
- Both full VCI history ranges now have 1,502 COMPLETED, 16 PARTIAL and 1 BLOCKED jobs. The remaining two blocked job rows are UTT frames with missing/invalid provider row counts and no canonical 2026-10-16 UTT bar. The existing 158-member 2026-10-16 Tier A snapshot remains recorded; a fresh build attempt correctly failed closed on the two blocked UTT jobs.
- Selection for 2026-10-16 again found 0 of 30 complete durable same-session KBS/VCI pairs and wrote no samples. DQ run `29a134d2-ac69-4ac8-bb5e-ea4deae261bd` is FAILED solely at that cross-source gate. KBS archived equity history still ends at 2026-10-15 for observed symbols; no prior-session rows were substituted.
- Verification: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed with the project `.venv` runtime. Targeted PostgreSQL integration tests passed on the disposable local test database, including recovery of a partial quarantine frame. PostgreSQL migration/schema checks passed earlier on local PostgreSQL 18.3; PostgreSQL 16 hosted CI is unavailable locally. The Windows race run with installed GCC stopped because ThreadSanitizer could not allocate its shadow region (error 87).
- Phase 1 remains PARTIAL. The calendar and auction-aware OHLC checks are reconciled, but unresolved VCI partials, the malformed UTT frame and the 0/30 latest-session KBS pair gate prevent Phase 1 exit. Phase 2–6 work and recommendations remain disabled.

## 2026-10-18 — alternate historical sources and VNDIRECT-backed DQ

- The user authorized alternate providers for static history where vnstock/VCI is incomplete, with vnstock/VCI retained as the intended daily refresh route. Historical data stays source-keyed and independently attributed; no DNSE or VNDIRECT values are relabeled as VCI.
- VNDIRECT now has 2,844,683 rows across all 1,519 current symbols for 2018-10-01 through 2026-10-16. Its requested-range jobs are 1,518 `COMPLETED` and one `PARTIAL` (BCF: 27 foreign `VCBF-BCF` rows are issue-recorded and excluded; valid exact-BCF rows remain stored). 1,823,358 rows have positive normal-market volume; 1,021,325 zero-normal-volume observations remain marked nontraded. No VNDIRECT bar falls on an effective closed date.
- DNSE remains a separately useful historical series: 2,172,122 rows across 1,515 symbols for 2018-10-02 through 2026-10-16; 659 jobs are `COMPLETED`, 856 `PARTIAL`, and four `BLOCKED` with no history. Duplicate-date buckets, invalid prices, and zero-volume rows remain issue-recorded rather than synthesized.
- A span-based calendar reconciliation found 3,225 expected symbol/session observations absent from VNDIRECT across 206 symbols between each series' first and last observed dates. These are calendar-derived missing pairs, not proof that every security traded on each session. The largest cluster is 14 symbols missing on 2021-08-30, 2021-08-31 and 2021-09-01; see the lifecycle follow-up below.
- The offline cross-source selector now accepts VCI/VNDIRECT when KBS has no row for the requested session. It replays exact VNDIRECT response bytes and SHA-256, confirms a successful audited request to `api-finfo.vndirect.com.vn` with matching symbol/date filter/status/row count, and records the exact zero-based row. Selection uses the same generic OHLC rule as ingestion (`high >= low`); it does not reject valid auction open/close values outside high/low.
- For 2026-10-16, the selector stored exactly 30 Tier A VCI/VNDIRECT pairs. All 30 close differences were within 0.5%; DQ run `3cd86137-dec5-4dc3-9e35-ccee9c886f1b` is `PASSED` with no blocking findings, warnings, or quarantined rows. The gate now passes for that session; this is not a Phase 1 completion claim.
- Verification after the selector change: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. No worker or migration changed in this increment. PostgreSQL 16 hosted CI and the Windows race suite remain unverified as recorded above.
- Phase 1 remains **PARTIAL**. The latest DQ gate passed, but VCI still has partial and blocked historical jobs, residual provider-quality issues, unresolved source/lifecycle coverage questions, and no verified common adjusted-price basis for mixing VCI, DNSE and VNDIRECT. Phase 2 work has not started.

## 2026-10-18 — alternate-source gap and security-lifecycle audit

- The user reaffirmed that historical data may come from another provider when vnstock cannot supply it; vnstock/VCI remains the intended daily refresh source. Use independently sourced rows from `core.bars_daily_sources` with original landing and call-audit lineage. Do not relabel them as VCI or silently merge differing adjustment bases.
- HNX's official 2021 transfer notice names 13 of the 14 symbols in the 2021-08-30–2021-09-01 missing-data cluster (ABT, BSI, DXS, HAP, KHG, LAF, NSC, PAN, QBS, SSC, TVB, VFG, VND) and sets 2021-08-27 as their last HNX trading date. VNDIRECT and DNSE audited range requests and CafeF's historical endpoint returned no bars for the cluster. These 39 absent pairs align with that transfer interval; do not synthesize zero-volume bars. The 14th symbol, PTM, is a separate lifecycle case. CafeF's exact-range response for BSI is archived at [`BSI-20210830-20210901.json`](probe/phase1-cafef-gap/BSI-20210830-20210901.json); the folder contains the other 13 symbol responses.
- PTM is resolved by the specific 2018 exchange notice, which names the same automobile issuer and ticker, sets 2018-11-27 as its final HNX trading day, and cancels registration from 2018-11-28. The issuer independently says it left the market at the end of 2018, and HNX records its return on 2025-08-22. The 11 positive-volume VCI observations and 12 positive-volume VNDIRECT observations in 2018 all fall inside the verified trading interval. Retain them in their respective source series; do not exclude them as a lifecycle conflict or merge their different/unknown adjustment bases. Exact notice bytes and lifecycle evidence are archived and recorded below.
- HNX records CTR's last UPCoM trading day as 2022-02-14, cancellation on 2022-02-15, and HOSE's official notice records the first HOSE trading day as 2022-02-23. The canonical VCI series nevertheless contains five identical CTR bars on Feb. 16–22; VNDIRECT and DNSE have none, and the archived CafeF response [`CTR-20220216-20220222.json`](probe/phase1-cafef-gap/CTR-20220216-20220222.json) has `TotalCount=0`. Treat those VCI rows as lifecycle-conflicting provider observations; preserve their raw landing and quarantine them from ML pending a durable correction audit.
- The 50 VCI `INVALID_PRICE` issue records represent 25 distinct symbol/session pairs with unusable open values; these do not arise from open/high/low containment. All 25 dates have valid VNDIRECT rows, and 14 also have DNSE rows. Use the source-specific alternatives for historical research with their basis preserved.
- Official lifecycle sources: HNX's [2021 transfer notice](https://www.hnx.vn/vi-vn/chi-tiet-su-kien-60012723-0-hnx.html?_page=1), [PTM final-trading-day notice](https://owa.hnx.vn/ftp/cims/2018/10_W5/000000007933389_1315tb_20181031_1.PDF), [PTM 2025 first-trading notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2022082025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20San%20xuat%20Thuong%20mai%20va%20Dich%20vu%20O%20to%20PTM%20PTM-60021452-1.html), and [issuer history corroboration](https://otoptm.com.vn/ptm-tam-the-moi-cho-hanh-trinh-tro-lai/); HNX's [CTR cancellation notice](https://static2.vietstock.vn/vietstock/2022/1/19/1.CTR_2022.1.19_acb69f8_89tb_20220117_1.PDF) and the SSC's [CTR first-day HOSE notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/m/thngtinthtrng/thngkthtrng/thongtinhose/tintchose?docType=TinBai&mucHienThi=188&selectedPage=20).
- VNDIRECT rows use `unadjusted`; DNSE and VCI remain `unknown` in the database. The 2026-10-16 VCI/VNDIRECT DQ pass verifies a same-session close comparison for that date only; it does not establish that the histories share an adjustment basis. Keep separate source-homogeneous training series until corporate-action adjustment factors are verified.

## 2026-10-18 — alternative historical source policy and UTT lifecycle probe

- The user confirmed that alternate providers may supply historical ML data where vnstock/VCI cannot, while vnstock/VCI remains the preferred daily refresh route. The local history contains 2,844,683 VNDIRECT rows through 2026-10-16 and 2,172,122 DNSE rows. All 16 symbols with partial VCI histories have positive-volume VNDIRECT history; these rows remain in their own source table with `unadjusted` basis and raw response lineage.
- HNX's official UTT first-trading notice records 2025-10-17. Its exact HTML bytes are archived at [`UTT-first-trading-2025-10-17.html`](probe/phase1-lifecycle/UTT-first-trading-2025-10-17.html), SHA-256 `041a8efa044d1fd6d438bceae7b83f21d86029dae1e5c5b0464cf0f47d756b32`; the source landing and append-only `TRADE_ELIGIBLE` evidence are stored in local PostgreSQL as landing 8398 / evidence 1.
- After a fresh authenticated quota check, one metered VCI probe requested UTT from 2025-10-17 through 2026-10-16 with raw prices. It returned a well-formed frame (`time`, `open`, `high`, `low`, `close`, `volume`) with count 0. The local probe report is [`2026-10-18-UTT-110813.105527700Z.json`](probe/phase1-utt/2026-10-18-UTT-110813.105527700Z.json). VNDIRECT and DNSE have no UTT rows. This establishes no UTT history before its official first-trading date and records the empty VCI response after listing; it does not classify every post-listing date as a confirmed non-trading session.
- The initial CafeF/HNX-only audit did not resolve all omitted sessions and therefore left UTT's activity status open at that point. The subsequent full-period VNDIRECT query, with a positive-volume KAI control, reports zero matched and negotiated volume for UTT across all 248 HNX sessions from 2025-10-17 through 2026-10-16. This supersedes the earlier unresolved classification; no execution date is observed in the audited interval and flat reference-price rows remain excluded from OHLCV. Raw pages, omitted-date list, VNDIRECT responses and hashes are recorded in [`phase1-utt/README.md`](probe/phase1-utt/README.md). Sources: [HNX first-trading notice](https://hnx.vn/m-tin-tuc-hnx/Ngay%2017102025%20ngay%20giao%20dich%20dau%20tien%20co%20phieu%20dang%20ky%20giao%20dich%20cua%20CTCP%20Moi%20truong%20Do%20thi%20Thanh%20Tri%20UTT-60021665-1.html), [CafeF history](https://cafef.vn/du-lieu/lich-su-giao-dich-utt-1.chn), [VNDIRECT full-period history API](https://api-finfo.vndirect.com.vn/v4/stock_prices?q=code%3AUTT~date%3Agte%3A2025-10-17~date%3Alte%3A2026-10-16&size=1000&page=1&sort=date%3Aasc&fields=code%2Cdate%2CadOpen%2CadHigh%2CadLow%2CadClose%2CnmVolume%2CnmValue%2CptVolume%2CptValue), and [HNX daily trade report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM).
- Historical training data should read one provider/basis series at a time. VNDIRECT supplies the source-attributed historical research series; VCI can continue daily refresh as its own series. VCI/DNSE/VNDIRECT rows are not stitched together until corporate-action treatment and point-in-time adjustment are validated.
- This source policy makes alternate historical rows available for the 32 partial VCI histories without erasing VCI quality findings. At this stage Phase 1 remained PARTIAL: CTR's lifecycle-conflicting rows had not yet been durably excluded; UTT still had no usable post-listing history from the probed sources; source adjustment basis remained unverified; and Windows race / PostgreSQL 16 hosted CI checks were outstanding. The later CTR correction is recorded below.
- Verification after this increment: `go -C go test -count=1 ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. `go -C go test -tags "postgres postgres_integration" -p 1 ./... -count=1` passed against local PostgreSQL 18.3 with the registered virtual-environment interpreter. `tests/sql/test_migration.sh` passed twice-applied migrations, schema assertions, rollback injection, and unreachable-database check against a fresh disposable PostgreSQL 18.3 database. `go -C go test -race ./...` still fails before test execution because Windows ThreadSanitizer cannot allocate its shadow region (error 87); the hosted PostgreSQL 16 CI job has not run.

## 2026-10-18 — PTM lifecycle corrected from HNX final-trading notice

- HNX notice 1315/TB-SGDHN, dated 2018-10-30, names CTCP Sản xuất, Thương mại và Dịch vụ Ôtô PTM (ticker PTM), gives 2018-11-27 as the final HNX trading day, and 2018-11-28 as the deregistration date. HNX's 2025 notice records the same issuer returning to UPCoM on 2025-08-22; the issuer says it left the market at the end of 2018. This resolves the older generic retrospective that had suggested a 2016 cancellation.
- The archived HNX PDF is [`PTM-delisting-2018-11-27.pdf`](probe/phase1-lifecycle/PTM-delisting-2018-11-27.pdf), SHA-256 `DDF3FFB354A7CEE923085B10FFF59FCC2CD4EDEA3825744FDB39C00C50FFE197`; the 2025 first-trading page is [`PTM-first-trading-2025-08-22.html`](probe/phase1-lifecycle/PTM-first-trading-2025-08-22.html), SHA-256 `2385B5965B458AC71012BE7F4F301B8A430BD9FD5F490F507450D444BF14E163`. PostgreSQL stores both exact source landings (8400, 8401) and three append-only lifecycle intervals (evidence 3–5): eligible through 2018-11-27; delisted 2018-11-28–2025-08-21; eligible from 2025-08-22.
- All 11 positive-volume VCI PTM bars and 12 positive-volume VNDIRECT PTM bars from 2018 occur before the confirmed final trading day. Their existence is supported by the exchange lifecycle and same-issuer notices; preserve their original source lineage and separate adjustment-basis series. Remove PTM from the list of lifecycle-conflicting records.
- At the time of this PTM correction, Phase 1 remained PARTIAL. CTR's five VCI rows from 2022-02-16–2022-02-22 still needed durable exclusion; UTT's post-listing VCI probe was empty and no alternate history had been ingested, so no bars were synthesized. The later CTR correction is recorded below; the 32 VCI partial-job findings, unverified cross-source adjustment basis, Windows race execution, and PostgreSQL 16 hosted CI remain open.

## 2026-10-18 — CTR final UPCoM session verified and ML eligibility corrected

- HNX notice 89/TB-SGDHN states that CTR's final UPCoM trading day was 2022-02-14 and registration was canceled effective 2022-02-15. The SSC's official notice records 2022-02-23 as the first HOSE trading day. The five dates 2022-02-16, 17, 18, 21 and 22 therefore fall between the exchange lifecycle events; this conclusion comes from the notices, not from an assumed trading calendar or a missing-bar pattern.
- The HNX notice PDF is archived at [`CTR-delisting-notice-2022-01-17.pdf`](probe/phase1-lifecycle/CTR-delisting-notice-2022-01-17.pdf), SHA-256 `F5A2B2501997B7393DB6715FCEB1AAEF4D1A614F5A0E110A15C730A7059DAF37`. It is HNX notice 89/TB-SGDHN hosted on Vietstock's static CDN. The first-HOSE-day reference is the [SSC notice](https://ssc.gov.vn/webcenter/portal/ubck/pages_r/m/thngtinthtrng/thngkthtrng/thongtinhose/tintchose?docType=TinBai&mucHienThi=188&selectedPage=20). The HNX source is stored in PostgreSQL as landing 8402 and verified lifecycle evidence 6 (UPCoM delisted 2022-02-15–2022-02-22).
- The five VCI bars map to raw landing 2550, SHA-256 `9631b5e1ea8c48beb69d0dd8915bb81e1926620067b0aa89f51b3e9a8a30d00f`, source rows 829–833 (zero-based), on 2022-02-16, 17, 18, 21 and 22. Migration 022 adds append-only, source-row-linked ML eligibility events, validates each event against its raw response and dated lifecycle evidence, and exposes filtered VCI and alternate-source views. Five `EXCLUDE` events now reference evidence 6; canonical VCI history still contains all five bars, while `core.bars_daily_ml_eligible` returns zero for those dates.
- `import-CTR-lifecycle.sql` and `CTR-lifecycle-landing.csv` preserve the repeatable evidence import. The working database reports five exclusions with their exact raw-row lineage and no canonical row deletion.
- Validation after migration 022: `go -C go test ./...`, `go -C go vet ./...`, and all 27 Python JSONL tests passed. `tests/sql/test_migration.sh` passed twice-applied migrations, schema assertions, injected rollback and unreachable-connection checks on a fresh disposable PostgreSQL 18.3 database. A tagged Go integration invocation did not complete after two minutes and was interrupted without an active database session; no tagged integration pass is claimed. The hosted PostgreSQL 16 job remains unverified, and Windows race execution remains unavailable as recorded above.
- Phase 1 remains PARTIAL. CTR is resolved. Open items are the ticker/date audit of partial VCI histories against separate alternate sources, UTT's empty post-listing history, unverified cross-source adjustment basis, and the PostgreSQL 16 / race checks.

## 2026-10-18 — public-source validation of partial-job findings

- The official HNX UPCoM daily report confirms SNC traded 71 shares on 2026-10-15 in continuous matching, with total traded value VND 1,547,800. This matches VNDIRECT landing 8002; StockBiz and Cophieu68 reported zero volume for that session. The HNX response is archived and hashed in `docs/probe/phase1-partial-audit/hnx-snc-2026-10-15.html`. Current VNX rules define 1–99 shares as an odd lot and allow continuous matching or put-through; odd-lot trades do not determine reference price or index. The exchange report resolves the volume discrepancy.
- VNDIRECT's stored import basis is verified as raw/unadjusted: the parser consumes ordinary OHLC fields and the importer stores them as `unadjusted`; archived payloads separately contain adjusted fields. The response comparison and source links are in `docs/probe/phase1-partial-audit/README.md`. VCI/DNSE adjustment basis and point-in-time corporate-action treatment remain open, so provider series stay separate.
- Sources: [HNX UPCoM daily trading report](https://www.hnx.vn/vi-vn/ModuleReportStockETFs/Report_MD_TradingScale/ListData_UPCoM), [current VNX UPCoM trading rule](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [StockBiz SNC history](https://web.stockbiz.vn/Stocks/SNC/LookupQuote.aspx?Date=16/10/2026), [Cophieu68 SNC history](https://cophieu68.vn/download/historydaily.php?d=2026-10-15), and [VNDIRECT adjustment-basis explanation](https://dstock.vndirect.com.vn/lich-su-gia/VND).

## 2026-10-18 — public historical-source checks and current test status

- Archived EasyStock's public per-symbol JSON feed for all 16 UPCoM tickers in the VCI partial-job audit: 35,684 rows, with 23,893 positive-volume and 11,791 zero-volume rows. It covers 7,447 of 14,492 issue dates and reports zero volume on all 7,447. EasyStock also reports zero for SNC on 2026-10-15, while HNX confirms 71 matched shares. Keep this feed separate; its zero volume is not proof of no execution. The VCI corporate-action sample is adjusted, while the adjustment timestamp is unknown.
- HNX's official public report confirms zero matched volume for SHC on 2026-09-16, 2026-09-18 and 2026-09-21. The report page limits the date picker to one month; an older SNC request returns no rows despite positive VNDIRECT/DNSE records. HNX lists UPCoM EOD and historical data as information services, but public access and fee terms were not verified. Evidence is in `docs/probe/phase1-partial-audit/hnx-recent/`.
- The 2024 VCI 10:3 bonus-share event cross-check shows VNDIRECT raw close 43.80 to 33.40, while VCI/DNSE/CafeF adjusted closes are about 24.24–24.25 to 24.03–24.04. This supports event-level adjustment differences only; VCI/DNSE basis and point-in-time treatment remain unknown. Details and source hashes are in `docs/probe/phase1-adjustment/README.md`.
- Tests on the current dirty checkout this turn: `VNPIPE_DISABLE_LIVE=1 go -C go test -count=1 ./...` passed; `go -C go vet ./...` passed; Python JSONL tests passed (27 tests); `tests/sql/test_migration.sh` passed on disposable PostgreSQL 18.3. GitHub Actions run [39023562253](https://github.com/Kashumir-Kaiser/VN-Signal/actions/runs/39023562253) passed against clean HEAD `e8eeef6`, including PostgreSQL 16 and Go race jobs, but does not cover these uncommitted changes. Local Windows `go test -race` fails after enabling CGO/GCC because ThreadSanitizer cannot allocate its shadow mapping (error 87); no local race pass is claimed.

## 2026-10-18 — Cophieu68 terms and row-level cross-check

- The public Cophieu68 SHC page reports zero volume on 2026-09-16, 2026-09-18, and 2026-09-21, matching the three archived HNX no-match reports. Its SNC page reports zero on 2026-10-15, while HNX records 71 continuous-matching shares; keep the HNX/VNDIRECT execution finding authoritative for that date.
- The Cophieu68 download page advertises adjusted history since 2000 through a legacy AmiBroker script, but the current check/download endpoints returned HTTP 404. Its terms prohibit copying or derivatives without explicit consent except for limited internal page copies. No bulk data was retained or imported; no PostgreSQL rows or quality statuses changed. Notes and source links: [`phase1-cophieu68/README.md`](probe/phase1-cophieu68/README.md).

## 2026-10-18 — historical HNX exact-date validation and source coverage

- The HNX page's visible date picker is limited, but targeted POST filters accepted historical dates in 2018–2020. All 26 distinct VCI invalid-price/OHLC ticker/date pairs have an HNX row with positive total matched volume. A read-only query matched every pair to a positive `vndirect` row in `core.bars_daily_sources_ml_eligible` (`is_traded=true`, `adj_basis=unadjusted`). This validates the separate alternate bars; it does not repair, overwrite, or relabel VCI data.
- For each of the 16 tickers in the partial-history audit, the latest positive VNDIRECT source row through 2026-10-16 was confirmed by an HNX report with the same volume. Fifteen were queried on the UPCoM route; SPC was queried on the HNX-listed route. The raw responses, exact filters, row values and hashes are in [`phase1-hnx-last-trade-audit/`](probe/phase1-hnx-last-trade-audit/). These are latest positive VNDIRECT observations with exchange-confirmed executions; HNX did not independently check every later zero-volume session.
- UTT's 16 sessions omitted from CafeF all return an explicit HNX UTT row with zero total matched volume, including first trading day 2025-10-17. VNDIRECT reports zero through all 248 sessions and CafeF through its 232 returned sessions. HNX has not been queried for every UTT session, so report that no positive trade date is observed through 2026-10-16 rather than claiming an all-session exchange audit. Raw reports and hashes are in [`phase1-utt/hnx-daily-reports/`](probe/phase1-utt/hnx-daily-reports/).
- This corrects the earlier statement that historical HNX requests returned no rows: that finding came from the visible page/date-picker route. Exact historical POST queries work. HNX separately lists historical data and data products in its [UPCoM information service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html) and [2026 service catalog/price schedule](https://owa.hnx.vn/ftp/PORTALNEW/FileContent/HNX_Danh%20muc%20goi%20tin%20va%20bang%20gia%20dich%20vu%20CCTT%2820260105_145538_848%29.pdf); targeted public validation is not treated as bulk-reuse permission.
- No database rows, quality statuses, quota records, or lifecycle classifications were changed by these lookups. Phase 1 remains PARTIAL; VCI/DNSE adjustment basis and point-in-time action handling, zero-volume issue coverage, DQ breadth, PostgreSQL 16 validation on this dirty tree, and local Windows race execution remain open.
- Checks after this evidence update passed: `VNPIPE_DISABLE_LIVE=1` with `VNPIPE_PYTHON=.venv\Scripts\python.exe go -C go test -p 1 ./...`; `go -C go vet -p 1 ./...`; `.venv\Scripts\python.exe -m unittest discover -s tests -v` (27 tests); and `tests/sql/test_migration.sh` with migrations applied twice on a disposable PostgreSQL 18.3 database. No current dirty-tree Windows race pass or PostgreSQL 16 hosted run is claimed; the existing race limitation is recorded above.

## 2026-10-18 — verify adjusted price basis using FPT cash dividend

- Internet research found the official VSDC notice for FPT's VND 1,000/share 2024 cash dividend and an HOSE-hosted notice giving the 2024-12-02 ex-right date. The same local source rows show VNDIRECT raw close 144.3→142.2 thousand VND; its adjusted close is 109.658→108.813. VCI is 109.66→108.81 and DNSE 109.65→108.81. These all match the dividend-adjusted return to rounding; raw close return is materially different. Details, source lineage, payload hashes, and a rerunnable classification SQL file are in [`phase1-adjustment/`](probe/phase1-adjustment/).
- Classified all 1,809,966 VCI canonical bars and 2,172,122 DNSE alternate bars as `adj_basis='adjusted'`; VNDIRECT remains `unadjusted`. The Go ingestion paths now preserve this source-specific classification. Only OHLC price basis is covered; volume semantics are unchanged. KBS remains `unknown` pending its own archived event comparison.
- Historical adjustment vintage is still unresolved. The current VCI/DNSE history is restated and cannot be considered point-in-time safe from this label alone. No prices, volume, trade flags, or ML lifecycle events were changed. Phase 1 remains PARTIAL.
- Verification after the importer edit: `VNPIPE_DISABLE_LIVE=1` with the project `.venv` interpreter and `go -C go test -p 1 ./...` passed; `go -C go vet -p 1 ./...` passed; all 27 Python JSONL tests passed; `git diff --check` passed (CRLF warnings only). Two metered KBS exact-date probes timed out without returning a report; no KBS basis is inferred. PostgreSQL 16 hosted CI and dirty-tree race execution were not rerun in this increment.

## 2026-10-19 — HNX latest-week verification and alternative-source research

- Archived ten official HNX reports covering the 16 partial-history symbols from 2026-10-12 through 2026-10-16: 15 UPCoM symbols through the UPCoM daily report and SPC through the HNX-listed report. The extraction yielded 80 rows, 32 with positive total matched volume. Thirteen tickers had a positive session in the window; CDG, VFC, and VNX did not.
- The HNX results agree with the latest positive rows in the source-specific audit for the 13 recently active names. The three with no trades in the five-session window have older positive VNDIRECT observations that HNX confirmed on their exact dates; this new lookup does not rule out a trade between those dates and October 12.
- SSI's official API documentation offers daily history from the start of trading and historical-file downloads, but requires an SSI trading account and approved FastConnect credentials. TCBS documents long-term OHLCV, but its unauthenticated endpoint returned 401. DNSE documents historical OHLC; its local history remains in its own source series. No credentials were submitted and no database changes were made.
- Phase 1 remains PARTIAL. This targeted lookup does not clear the remaining 14,439 zero-volume issue dates or resolve historical adjustment vintages. Evidence and sources are in [`phase1-hnx-latest-week/README.md`](probe/phase1-hnx-latest-week/README.md).

## 2026-10-19 — interpret HNX special-trading status

- HNX issuer profiles for CDG, VFC, and VNX currently display “Giao dịch đặc biệt.” VNX's current UPCoM regulation (Decision 23/QĐ-HĐTV, effective 2026-03-18) defines status code `SNE` as no round-lot trades for more than 25 consecutive trading sessions. This is consistent with recent inactivity; the separate HNX reports independently show zero total matched volume for these three symbols on Oct 12–16. SNE alone does not rule out odd-lot trades.
- The profiles do not expose when the status began. Do not convert this current aggregate status into exact last-trade dates or use it to classify older zero-volume issue rows. Raw profiles and hashes are recorded in [`phase1-hnx-special-status/README.md`](probe/phase1-hnx-special-status/README.md). No database rows or lifecycle statuses changed.
- Sources: [VNX legal register](https://vnx.vn/vi/van-ban-phap-ly/6), [current VNX UPCoM regulation](https://stream.vnx.vn/VNX//Legal/20260324164637497VNX.-Quy-che-CK-CNY_QD23....pdf), [CDG HNX profile](https://hnx.vn/vi-vn/ModuleIssuer/UC_Issuer/Details/CDG/UC), [VFC HNX profile](https://hnx.vn/cophieu-etfs/chi-tiet-chung-khoan-uc-VFC.html), and [VNX HNX profile](https://hnx.vn/vi-vn/m-tim-kiem-VNX.html).

## 2026-10-19 — targeted KBS check of a VCI zero-volume issue

- A registered-machine KBS OHLCV probe returned two NAS rows for 2020-10-14–2020-10-15. Its 2020-10-15 row has volume 80 and close 26.93. The same issue date has local VNDIRECT volume 80 (raw close 29) and DNSE volume 80 (close 26.9294); VCI has no positive canonical bar and two `ZERO_VOLUME_UNVERIFIED` issue records. This adds a third provider corroboration for positive activity on this row, but does not establish an HNX exchange result or clear the other issue dates.
- A full-range KBS GGG probe returned 380 rows from 2018-10-12 through 2026-10-09; the exact 2026-10-16 request returned no row. Treat KBS as useful supplemental history with a freshness gap in this sample, not a replacement for the VCI daily refresh.
- Current vnstock documentation lists KBS as a selectable Community source for daily equity OHLCV, with no automatic fallback; it also warns source price histories can differ after corporate actions. Keep KBS source rows separate and do not use adjusted prices for point-in-time training until adjustment timing is validated ([source selection](https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources), [market OHLCV](https://www.vnstocks.com/docs/vnstock/thi-truong-market)).
- Exact-date HNX UPCoM report requests for NAS on 2020-10-15 returned the same zero-record response for quoted and unquoted symbol filters. That empty response is unavailable evidence for this date, not evidence of no execution. HNX lists UPCoM historical data as an information product and advertises a two-week trial; use the registered information-service route for any broad exchange audit ([HNX UPCoM data service](https://hnx.vn/vi-vn/dich-vu-cctt/du-lieu-cung-cap-up.html), [service terms and technical requirements](https://www.upboard.hnx.vn/vi-vn/dich-vu-cctt/huong-dan-yeu-cau-ky-thuat-sgtc.html)).
- Probe summaries and HNX response bytes, including hashes and exact request filters, are in `docs/probe/phase1-current-kbs-verify/` and `docs/probe/phase1-hnx-kbs-reconciliation/`. The KBS calls used the Go probe gateway; no market data was imported, and no PostgreSQL rows, quality statuses, or lifecycle evidence changed.
- HNX issuer price-history queries returned 64 dated rows per symbol from 2026-07-16 through 2026-10-16. VNX has one price-bearing row in this window, 2026-07-28, matched to the existing HNX exact-date report (100 shares); CDG and VFC have none. For VFC, eight exact HNX daily matched-volume reports from 2026-07-06 through 2026-07-15 returned zero volume; the HNX-verified 2026-07-03 observation remains the latest positive execution located. These profile rows do not certify the absence of later odd-lot trades. For CDG, the 2025-05-13 positive observation is corroborated by HNX and Investing.com, but the intervening history is not an all-session exchange audit. Details and raw hashes are in [`phase1-hnx-special-status/README.md`](probe/phase1-hnx-special-status/README.md).

## 2026-10-19 — web-check last matched dates and UPCoM volume fields

- Three targeted taichinh.com pages, each displaying VNDirect as its price/volume source, report the latest matched date for CDG as 2025-05-13 (snapshot 2026-09-18), VFC as 2026-07-03 (snapshot 2026-10-09), and VNX as 2026-07-28 (snapshot 2026-10-12). HNX's exact-date reports independently confirm positive exchange volume on all three dates, recorded in [`phase1-hnx-last-trade-audit/hnx-last-trade-reconciliation.csv`](probe/phase1-hnx-last-trade-audit/hnx-last-trade-reconciliation.csv). HNX also reports zero matched volume for these three on 2026-10-12–16. Treat the older dates as latest matched dates in the VNDirect-derived series, supported by targeted HNX confirmation, rather than a complete official no-trade audit of every later session.
- FiinGroup's official UPCoM API schema distinguishes latest round-lot `MatchVolume`, total round-lot matched `TotalMatchVolume`, negotiated `TotalDealVolume`, and total matched-plus-negotiated volume `TotalVolume`, including round and odd lots. This is a promising licensed source to resolve volume-field semantics and historical zero-volume conflicts, but public API documentation does not establish the available backfill period or usage rights. Do not bulk-query the HNX public report or import FiinGroup data until the historical coverage and internal research terms are established.
- taichinh.com terms permit individual research lookups and citation with source attribution, while asking users to contact FTMI before automated, broad or deep collection. This update used only three individual page lookups and imported no data. See [`phase1-public-activity-check/README.md`](probe/phase1-public-activity-check/README.md).
- Phase 1 remains PARTIAL; the 14,439 zero-volume issue dates are still unverified, and the remaining backfill and current-tree CI gates remain open.

## 2026-10-19 — CafeF full-history cross-check for VCI zero-volume issues

- Used CafeF's public export for the 16 partial-history symbols in nine one-year windows per symbol. All 144 XLSX exports passed ZIP validation and SHA-256 verification; they contain 31,381 daily rows from the 2018 partial year through 2026-10-16. The corrected endpoint date format is `MM/DD/YYYY`; an earlier `DD/MM/YYYY` singleton request silently fell back to a recent default range.
- Across 14,466 VCI `ZERO_VOLUME_UNVERIFIED` dates, CafeF reports 23 positive matched-volume dates, all already positive in VNDIRECT or DNSE; 106 additional dates have negotiated volume only; 14,159 rows report zero matched and negotiated volume; and 178 dates have no CafeF row. The three HNX-confirmed SHC no-match dates also show zero volume in CafeF. Thus 14,333 dates have neither positive matched nor negotiated-volume evidence nor an exact HNX no-match report; the 106 negotiated-only rows remain a separate activity signal and do not supply matched OHLC bars.
- `docs/probe/phase1-cafef-history-audit/` contains the raw annual files, hash manifest, complete daily activity extract, per-issue reconciliation, and rerunnable local scripts. CafeF zero/absent rows do not prove that no trade occurred; no CafeF price or volume was imported into PostgreSQL or canonical bars. Phase 1 remains PARTIAL, and the action-adjustment vintages and current-tree CI gates remain open.

## 2026-10-19 — expand the alternative-source search

- Internet research found an exact-fit FireAnt historical feed: its official Excel documentation exposes OHLC, matched `DealVolume`, negotiated `PutthroughVolume`, and total volume by symbol and date range. Its REST API uses OAuth2, the unauthenticated historical-quotes request returned HTTP 401, and FireAnt's current plan page lists the Excel add-in under Premium. FireAnt is a usable next provider only through authorized access.
- HNX confirms two CafeF false negatives outside the 14,466 issue-date population: 100 CDG shares on 2025-05-13 and one VFC share on 2026-07-03, where the CafeF export reports zero matched and negotiated volume. Keep CafeF zero and absent rows as unknown evidence; do not downgrade them to exchange no-trade findings.
- FiinGroup documents a distinct UPCoM schema for round-lot matched volume, negotiated volume, and odd-lot-inclusive total volume. HNX and FiinGroup both have historical products, but their bulk coverage and internal research rights require an authorized trial or license. SSI FastConnect also documents daily history from first trading date but requires an approved brokerage account. EODHD's public demo does not include Vietnam symbols.
- The 14,333 remaining dates still have no matched/negotiated positive evidence or HNX exact-date no-match report; 106 negotiated-only sessions are tracked separately as activity evidence, not OHLC bars. See [`alternative-source search`](probe/phase1-source-search/README.md) and the [`CafeF/HNX cross-check`](probe/phase1-cafef-history-audit/README.md).

## 2026-10-19 — verify another public history source and refresh the registered route

- EasyStock's public page advertises free market-wide OHLCV history from 2007 onward. Archived 16 symbol histories (35,684 rows, 23,893 positive-volume source rows) with SHA-256 manifests. On 14,466 VCI zero-volume issue dates it reports zero volume on 7,434, has no row on 7,032, and reports no positive volume. It adds no evidence to the existing 14,333 unresolved partition. The source misses HNX-confirmed CDG 100-share and VFC one-share executions, as well as the 80-share NAS observation corroborated by four sources. Keep its zero/absent rows out of no-trade certification; matched/deal volume and adjustment vintage are undocumented. See [`EasyStock audit`](probe/phase1-easystock-history-audit/README.md).
- A fresh registered-machine active VCI OHLCV probe succeeded at 2026-10-19 01:38 +07 with one metered call: 1,995 FPT rows from 2018-10-18 through 2026-10-16, columns `time, open, high, low, close, volume`. The official [HOSE 2026 holiday notice](https://www.hsx.vn/vi/tin-tuc/hose-thong-bao-lich-nghi-giao-dich-nam-2026/2437411) lists no October closure; the explicit probe budget was 10 sessions from October 19–30. The authenticated local CLI reports `tier=free`; vnstock's [official account-tier documentation](https://vnstocks.com/docs/vnstock/tham-khao/cap-quyen-va-gioi-han) maps that API-key state to Community. The response verifies a live route today, not full historical coverage or post-call quota. Report: [`2026-10-19 active probe`](probe/phase1-easystock-history-audit/vnstock-probe-20261019/2026-10-19.json).
- No EasyStock or VCI probe rows were written to PostgreSQL. Phase 1 remains PARTIAL.

Verification update on 2026-10-19 supersedes the earlier interrupted attempt above: `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` (CGO enabled with MSYS2 GCC), all 27 Python JSONL tests, all 26 serialized PostgreSQL ingestion integration tests, and `tests/sql/test_migration.sh` passed. The migration check used disposable PostgreSQL 18.3 and applied all migrations twice; migrations 001–025 were then applied to the working `vnsignal` database, and the three VNX interpretation rows were appended and verified. GitHub Actions run 39023562253 still covers clean HEAD `e8eeef6`, not this dirty tree; PostgreSQL 16 hosted CI remains unverified for this checkout.

## 2026-10-19 — three additional HNX-confirmed VNX executions

- A bounded public-history search surfaced VNX issue dates 2026-01-29, 2026-01-30, and 2026-02-12. The exact-symbol HNX UPCoM reports returned one row each, but the first parser read the `Toàn thị trường` totals (15,100, 4,900, and 4,900 shares) as matched volume. Column review showed all matched-session columns were zero and those totals belonged to `Thỏa thuận` (negotiated volume). BSC independently returned zero matched and the same negotiated amounts. See [`VNX HNX verification`](probe/phase1-simplize-history-audit/README.md) and [`BSC exact-date controls`](probe/phase1-source-search/bsc-controls-20261019.json).
- All three dates were in the unresolved activity partition: VCI had zero-volume issue rows, the prior VNDIRECT/DNSE and CafeF audit had no positive volume or CafeF row, and no exact HNX report was previously archived. Positive negotiated evidence moves them out of that partition, reducing it from 14,317 to 14,314; distinct negotiated-only dates rise from 106 to 109.
- Appended all three exact reports to local `raw.landings` and `ops.exchange_daily_bar_evidence`; the initial parse was retained and corrected through an append-only interpretation. No canonical bars, provider rows, or VCI quality issues were changed. The corrected lifecycle status is `VERIFIED_NEGOTIATED_ONLY`; Phase 1 remains PARTIAL.
- The secondary Simplize history output was used only to identify candidate dates; none was imported into PostgreSQL or canonical bars. Its published terms restrict copying or derivative use without written permission. The temporary snapshot is still untracked locally because the shell rejected its cleanup command; do not commit it.

## 2026-10-19 — expanded web research and four KBS issue probes

- Yahoo's official exchange list assigns Vietnam's `.VN` market suffix to Ho Chi Minh City Stock Exchange, so it does not provide the UPCoM history needed for the open gaps. Simplize has public UPCoM history pages and an Excel export control; its UTT page displays blank OHLC and zero volume on recent rows, and explicitly says its prices are adjusted for dividends and splits. Its page does not document matched-versus-negotiated volume or the adjustment vintage, so it remains a targeted secondary check.
- The registered Community KBS source was queried once each for CDG 2025-05-13, VFC 2026-07-03, NAS 2020-10-15, and UTT 2025-10-17 through 2026-10-16. KBS confirms the CDG 100-share session and NAS 80-share session; it misses the HNX-confirmed VFC one-share session (its latest VFC row is 2026-06-17), and returns no UTT rows. The NAS issue was already positive in CafeF/VNDIRECT/DNSE, and CDG/VFC's sampled positive dates are outside the 14,466 VCI zero-volume issue set; the 14,333 unresolved count is unchanged.
- The KBS reports are in [`phase1-kbs-issue-probes-20261019/`](probe/phase1-kbs-issue-probes-20261019/). UTT's zero-row report is also appended to [`phase1-utt/README.md`](probe/phase1-utt/README.md). Four one-call probes used the explicit metered-probe path after fresh exact-quota checks; no probe rows were imported into PostgreSQL. Phase 1 remains PARTIAL because these checks do not complete the remaining backfill, point-in-time price basis, or current-tree CI exits.

## 2026-10-19 — search public datasets and alternate adapters

- The Kaggle Vietnam stock competition documents genuine OHLCV for 30 tickers from 2021-01-04 through 2021-10-29. The short window, limited universe, and competition-rules download gate make it insufficient for the 16 UPCoM partial-history symbols; no competition files were downloaded.
- Mendeley Data publishes daily closes for 627 HOSE/HNX/UPCoM shares from 2014–2024, but the file is close-only and uses anonymized IDs with no public symbol crosswalk. Its CC BY 4.0 license makes it a possible later close-only research input only if identity and adjustment basis are established; it cannot fill OHLCV or volume gaps. No file was downloaded or imported.
- Broader adapter search found OpenStockAPI and `vn-market-data`, but their documented feeds resolve to provider families already represented here (TCBS/KBS/VCI; DNSE/Vietcap/VNDirect/CafeF). Official vnstock v5 docs do not offer TCBS as an equity OHLCV route; Community access permits the KBS/VCI equity routes, while TCBS OpenAPI and SSI FastConnect require separate API credentials/approval. No new credentials or data were used.
- This search added no symbol/date/volume evidence, so the recorded 14,333 unresolved zero-volume issue dates and 106 negotiated-only sessions are unchanged. Phase 1 remains PARTIAL. Source details and links are in [`phase1-source-search/README.md`](probe/phase1-source-search/README.md).

## 2026-10-19 — further public-source checks and current Phase 1 counts

- A newly inspected public Lich Su Gia page reports zero volume for CDG on 2025-05-13, but the archived official HNX report confirms 100 matched shares. Exclude this site from no-trade evidence. FINCO advertises broad adjusted OHLCV, but its public CDG route returned metadata only and its history preview returned `Not authenticated`; approved export access is required and volume semantics/source lineage remain open. FinLens advertises historical OHLCV but requires a separate API key and remains unvalidated. DNSE OpenAPI offers a trade-history route but uses the same DNSE provider family already represented here and requires separate credentials. The Kaggle VN30 candidate remains unverified and does not cover UPCoM.
- The current unresolved zero-volume issue partition is 14,314 ticker/dates, with 109 distinct negotiated-only sessions (106 CafeF plus three VNX HNX reports) and 22 exact HNX reports persisted (19 zero-total and 3 negotiated-only). This is an evidence-classification count, not a missing-bar count. Stockbiz returned the same single-field VNX total-market volumes, but its field does not distinguish matched from negotiated and was not imported. See [`alternative-source search`](probe/phase1-source-search/README.md) and the [`16-date HNX sample`](probe/phase1-hnx-sample-audit/README.md). Phase 1 remains PARTIAL; point-in-time adjustment basis, remaining activity classification, DQ breadth, and required CI checks are still open.
- Further web checks confirmed FireAnt's official historical Excel functions return matched `DealVolume` and negotiated `PutthroughVolume`; its current plan comparison puts the Excel add-in in Premium, with MetaKit base data from Essential upward. A new Kaggle dataset is only a 26-company HOSE real-estate quarterly research sample (2019–2024), not raw daily OHLCV. Neither source was imported or changed the 14,317 unresolved dates. Details: [`alternative-source search`](probe/phase1-source-search/README.md).
- A one-date request to TCBS's legacy public-code OHLCV endpoint for CDG 2025-05-13 returned HTTP 403 with no data. Current TCBS docs require a registered token. This further search did not find an accessible independent OHLCV feed or change the Phase 1 counts.
- Direct exact-date requests to VNDIRECT's public Finfo API returned matched volumes of 1 for VFC (2026-07-03), 80 for NAS (2020-10-15), and 100 for CDG (2025-05-13), with negotiated volume zero on each. All three values match already archived VNDIRECT/HNX evidence; this validates the route but does not reduce the 14,317 unresolved dates. Payloads, URLs and hashes are in [`VNDIRECT API verification`](probe/phase1-vndirect-api-verification-20261019/README.md). No market rows or database statuses changed.
- Broader provider search found DataPro SmartAPI as a potentially useful paid source: it advertises UPCoM EOD history from 2000 and separate matched/negotiated fields, but requires a subscription, charges separately for initial history, and prohibits redistribution. Upstream provenance and this project's ML retention rights remain unverified. TCBS and Fialda also require account/contract access. No authenticated access was available, no data were requested or imported, and Phase 1 remains PARTIAL; next actionable path is an authorized sample plus written scope/rights confirmation.
- The installed vnstock 5.0.3 Community profile was tested with one active `equity_trade_history` route probe through `vnpipe`; it returned `EntitlementError`, and the server usage counters remained unchanged. The route is documented for Extended accounts, so it cannot supply Community matched/deal history. Report: [`trade-history probe`](probe/phase1-trade-history-probe-20261019/2026-10-19.json). No database rows changed.
- Earlier dirty-tree verification before the VNDIRECT adjustment correction: `go -C go test ./...`, `go -C go vet ./...`, and `go -C go test -race ./...` passed; the race run used `CGO_ENABLED=1` and the installed MSYS2 GCC. All 27 Python JSONL tests, all 26 serialized PostgreSQL ingestion integration tests, and `tests/sql/test_migration.sh` also passed against PostgreSQL 18.3. At that point migration 025 was applied to the working database, and the three VNX interpretations were committed and reported `VERIFIED_NEGOTIATED_ONLY`. PostgreSQL 16 hosted CI had not been rerun for that working tree. The activity-date audit retained 14,314 unresolved zero-volume issue ticker/dates.

## 2026-10-19 — continued public-source search and live queue check

- The read-only `backfill-status --from 2018-10-01 --to 2026-10-16` command was run against the recovered local `vnsignal` database. For the 2026-10-17 listing snapshot it reports 1,502 `COMPLETED`, 16 `PARTIAL`, 1 `BLOCKED`, 0 leased, 0 deferred-invalid, and 0 pending jobs. Phase 1 remains partial while partial/blocked outcomes and other exit criteria are open.
- The additional Internet search tested a public VietstockFinance route against exact HNX controls and found false-zero/missing responses; public OpenStockAPI and `vn-market-data` documentation resolved to upstream providers already represented in the repository. No new eligible bars were found. Existing SSI and FiinGroup routes remain separate-credential leads; HNX's historical data service remains the exchange-authorized bulk option.
- Fresh UTT search results support the already archived conclusion: no positive execution was observed through 2026-10-16 across the queried source histories, but this is not a lifetime exchange-wide no-trade claim. UTT remains excluded from trade-bar training.
- The unresolved zero-volume issue ticker/date count remains 14,314 and the negotiated-only count remains 109. The targeted Vietstock web checks were source research only; they created no vnstock quota reservations and no PostgreSQL writes. Detailed source notes and links are in [`continued public-source search`](probe/phase1-source-search/README.md).

## 2026-10-19 — authenticated history options after expanded search

- The current SSI Developer Portal FAQ says Market Data access has no current service fee but requires an SSI securities account and an API key. The documented UPCOM history schemas expose daily OHLC, matched volume, negotiated volume, and total volume including odd lots. No SSI account key is configured here, so no sample could be authenticated or imported.
- FiinQuant's current free plan is capped at 33 tickers and one year of daily history; online registration is temporarily suspended. It cannot cover the project backfill window and is not an available source in this workspace.
- HNX's official per-security UPCoM EOD package is VND 2,000,000/month and HNX advertises a two-week trial. The public catalog does not specify whether the trial includes archive backfill or ML retention rights; the technical guide places connection details after contract signing.
- The expanded search found no anonymous, licensable full-universe feed that passes the project's source and volume-semantics requirements. The live queue remains 1,502 complete, 16 partial, 1 blocked, and 0 pending; the 14,314 unresolved zero-volume issue ticker/date count is unchanged. No market-data calls, imports, or database/quota writes occurred during this research. Phase 1 remains PARTIAL.

## 2026-10-19 — live source coverage after UTT exclusion

- A fresh read-only `backfill-status` run against local PostgreSQL 18.3 reports 1,502 VCI `COMPLETED`, 16 VCI `PARTIAL`, 1 VCI `BLOCKED` (UTT), 0 leased, 0 deferred-invalid, and 0 pending for the 1,519-symbol listing snapshot. UTT is outside the user-approved active scope, leaving 1,518 symbols: 1,502/1,518 (98.95%) complete through VCI and 16/1,518 (1.05%) with a partial VCI result.
- Exchange breakdown of the VCI queue: HNX 298/299 complete, with SPC partial; HOSE 406/406 complete; UPCoM 798/814 complete, with 15 partial and UTT blocked. Removing UTT from the active UPCoM denominator gives 798/813 complete and 15 source-covered partials.
- All 16 VCI-partial symbols have a `COMPLETED` VNDIRECT full-range job. Their source-keyed VNDIRECT history already contains 14,338 positive-volume observations; 388 symbol/dates have no positive canonical VCI bar. These are present as VNDIRECT source rows with unadjusted basis and raw landing lineage, not missing research data. Keep VNDIRECT separate from VCI and do not splice the two bases.
- The approved 14,314 residual zero-volume assumption, 24 positive matched-volume conflicts, 109 negotiated-only dates, and 19 exact HNX zero-matched reports remain separately classified. Zero-volume sessions are plausible on UPCoM, HNX (including SPC), and HOSE; no OHLC bars are synthesized. The 14,314 count is not a missing-bar count.
- The active historical dataset now has at least one completed source history for every in-scope ticker. The VCI queue's 16 `PARTIAL` outcomes and UTT's retained `BLOCKED` outcome are source-specific audit states, not remaining data-coverage blockers. The injected-fault unit and PostgreSQL integration suites pass locally on this tree. The hosted workflow was not rerun; current-tree PostgreSQL 16.15 migration and integration checks passed locally. The PG16 host used an isolated temporary cluster and database and did not modify the registered PostgreSQL 18 dataset.

## 2026-10-19 — Phase 0/1 exit checks passed on the current tree

- Phase 0 exits are evidenced by the registered-machine vnstock 5.0.3 capability report, verified absolute quota fields, migrations 001–025, and a clean current-tree PostgreSQL 16.15 migration/integration run.
- Phase 1 covers 1,518 in-scope symbols after excluding UTT: 1,502 completed VCI histories and 16 completed source-keyed VNDIRECT histories for the VCI-partial tickers. The 16 VCI `PARTIAL` outcomes and UTT `BLOCKED` audit record remain preserved; they do not represent missing in-scope histories. VCI and VNDIRECT series remain separate.
- Zero-volume handling is no longer a Phase 1 blocker. The user-approved residual classification applies to partial research while raw rows and `ZERO_VOLUME_UNVERIFIED` audit findings remain intact; positive matched-volume conflicts and negotiated-only sessions remain separate, and no OHLC bars are synthesized.
- `tests/sql/test_migration.sh` passed against a clean disposable PostgreSQL 16.15 database: two migration passes, schema assertions, injected-failure rollback, and unreachable-connection detection. `go -C go test -tags "postgres postgres_integration" -p 1 ./... -count=1` passed against PostgreSQL 16.15.
- Current-tree checks passed: `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` with CGO enabled and MSYS2 GCC, and all 27 Python JSONL tests. The migration script now places PostgreSQL client options before the database URL so Windows clients execute the same checks correctly.

**Phase 0 and Phase 1 exit criteria are complete. Phase 2 is the next phase; the overall product remains incomplete.**

## 2026-10-19 — point-in-time price basis prepared for Phase 2

- Migration 027 adds a market-wide `core.vndirect_bars_as_of(date)` overload for querying all same-vintage VNDIRECT price histories through one requested session. It seeds the approved UTT exclusion in `ops.ml_symbol_scope`; both the market-wide and per-symbol functions apply that explicit model scope. They return adjusted-as-of OHLC with source-row lineage and fail closed for incomplete/mixed snapshots; missing ticker sessions are not synthesized.
- The local database has 2,844,683 VNDIRECT rows across all 1,519 symbols, every row has all four adjusted OHLC fields, no ticker has mixed vintages, and every symbol has a VNDIRECT row on 2026-10-16. All 2,172,122 DNSE ticker/dates have VNDIRECT counterparts. Of 1,809,966 VCI canonical rows, the only five without VNDIRECT counterparts are the already excluded CTR lifecycle-invalid dates 2022-02-16–2022-02-22. The registered market-wide Phase 2 query returns 1,518 symbols and 2,844,435 rows through 2026-10-16, all on `adjusted_as_of` basis. UTT's 248 raw rows remain preserved and its Phase 2 query result is empty.
- PRC's 2023-03-29 discrepancy is resolved against CafeF's raw 65/70/63/68 OHLC and VSDC's VND 35,000/share dividend notice. VNDIRECT's March 29/30 adjustment-factor ratio matches the 33/68 theoretical ex-right factor; VCI's adjusted close 9.98 agrees, while the DNSE 20.56 value is corrected by that factor to 9.978. Full source response, calculations, and later PRC action cross-checks are in [`Phase 2 adjustment audit`](probe/phase2-adjustment/README.md).
- Phase 2's price input is now the single full-coverage VNDIRECT point-in-time series; no ticker/date is removed because VCI/DNSE adjustment vintages differ. VCI/DNSE remain intact for DQ comparison. The Phase 2 features, labels, point-in-time fundamentals archive, leakage tests, and feature-parity tests remain to be implemented; this evidence completes the price-adjustment prerequisite, not the Phase 2 exit criteria.
- Final verification on 2026-10-19 passed after the explicit-scope SQL assertion was added: `go -C go test ./...` (with `VNPIPE_PYTHON` resolved through `py`), `go -C go vet ./...`, `py -m unittest discover -s tests -v` (27 tests), and `tests/sql/test_migration.sh` against a clean disposable PostgreSQL 18.3 database. The migration check applied all migrations twice, passed schema and PRC-style point-in-time adjustment/scope assertions, and passed rollback and unreachable-connection checks. The registered database also passed the 1,518-symbol/2,844,435-row coverage query and PRC as-of price checks. Hosted CI was not rerun. These results establish the Phase 2 price-input prerequisite; Phase 2 features, labels, fundamentals, leakage tests, and feature-parity tests remain to be implemented.

## 2026-10-19 — revalidate adjusted-as-of input against registered PostgreSQL

- Restarted the local PostgreSQL 18 service and queried the registered `vnsignal` database. The raw VNDIRECT source has 2,844,683 rows across 1,519 symbols, with complete adjusted snapshots and one vintage per symbol. The market-wide Phase 2 function returned 2,844,435 rows across 1,518 in-scope symbols from 2018-10-01 through 2026-10-16; every row has `price_basis='adjusted_as_of'`. It retains 1,021,077 zero-volume rows as `is_traded=false`. The 248-row difference is exactly the explicit UTT scope exclusion; no price-disagreement ticker/date was dropped.
- Verified event-date function output in the live database: PRC 2023-03-29 close is 68.0000 as of that date and 32.9988 as of 2023-03-30; FPT's 2024-11-29 close is 143.3043 as of its 2024-12-02 VND 1,000/share ex-right date; AGG's 2020-01-09 first-day close is 30.0000 as of that day despite a current retrospective snapshot value of 13.8960. This confirms the as-of function removes later adjustment factors while preserving the raw observations. Full column semantics and results are in [`Phase 2 adjustment audit`](probe/phase2-adjustment/README.md).
- Documentation-only evidence update; no SQL, Go, or Python implementation changed in this recheck. The previously recorded current-tree unit, vet, race, JSONL, and migration checks remain the applicable code verification; hosted CI has not been rerun. Phase 2 feature and label generation is still not implemented.

## 2026-10-19 — resolve all VNDIRECT reference factors for the Phase 2 price input

- VNDIRECT's 684 unresolved factors were all on 2019-01-02, where the source returned `basicPrice=0`. Migration 030 applied through the Go migration runner to the registered PostgreSQL 18.3 database; the migration runner verified existing migration checksums and applied one new migration.
- The override ledger contains 684 rows: 169 HNX, 316 HOSE, and 199 UPCoM by the historical bar's `exchange_code`. It records 661 matched-volume rows and 23 zero-volume UPCoM rows. DSN uses the evidence-backed `59.3/62.9` dividend factor; the other 683 are audited no-action factors of 1.0. Raw VNDIRECT rows and zero `basicPrice` values remain unchanged.
- After migration, the in-scope reference view has zero NULL factors. The registered market-wide function returns 2,844,435 rows for all 1,518 in-scope symbols, dated 2018-10-01 through 2026-10-16, with 1,021,077 zero-volume rows retained and no row on a different price basis. DSN's 2018-12-28 close is 59.3 as of 2019-01-02; its 2019-01-02 close remains 58.5.
- `tests/sql/test_migration.sh` passed against a fresh disposable PostgreSQL 18.3 database, applying the full migration sequence twice and checking schema invariants, rollback, connection failure, no-action factor 1.0, DSN dividend factor, and source-row preservation. `go -C go test ./...`, `go -C go vet ./...`, and `py -m unittest discover -s tests -v` also passed (27 Python tests). Hosted CI was not rerun.
- This completes the Phase 2 point-in-time price input prerequisite. Phase 2 feature and label generation, point-in-time fundamentals, leakage checks, and feature parity remain unimplemented; the full product is not complete. The event evidence and per-symbol resolution are in [`2019-01-02 reference resolution`](probe/phase2-adjustment/2019-01-02-reference-resolution.md).

## 2026-10-19 — resolve the remaining VNDIRECT price candidates

- All 641 flagged ticker/sessions now have documented factors: 42 corporate actions and 599 no-action factors of 1.0. Each resolution links to archived public evidence and its response hash. The five VNDIRECT bars that already carried the next session's adjustment use CafeF-backed model OHLC; their VNDIRECT OHLC, volume, trade flag, and lineage remain intact.
- Applied the forward migrations to the registered PostgreSQL 18.3 database through the Go migration runner. It verified existing hashes and applied two new migrations. The already-applied `031_vndirect_adjustment_episodes_and_logspace.sql` ledger row retains its original hash; the new model layer has a distinct migration filename. No migration ledger entries were rewritten.
- The post-migration full-universe as-of query returned 2,844,435 rows for all 1,518 in-scope symbols, from 2018-10-01 through 2026-10-16. It retained 1,021,077 zero-volume rows and returned zero rows on a different price basis. Since the query fails closed for a symbol with an unresolved factor, all in-scope histories are now usable by the Phase 2 price input.
- A clean PostgreSQL 18.3 replay passed with all 32 migrations applied twice, schema and adjustment assertions, injected-failure rollback, and unreachable-connection detection. `go -C go test ./...`, `go -C go vet ./...`, `go -C go test -race ./...` (CGO enabled with MSYS2 GCC), and `py -m unittest discover -s tests -v` (27 tests) passed. Hosted CI was not rerun.
- This resolves the Phase 2 price-adjustment prerequisite. Phase 2 feature and label generation, point-in-time fundamentals, leakage checks, and feature parity remain to be implemented; the overall product is not complete.

## 2026-10-23 — Phase 2 acceptance gates passed (historical checkpoint, superseded)

- Phase 2 now has SQL V2/V3 features, next-open-entry labels, an append-only point-in-time fundamentals archive and overlay, resumable scoped builders, and Rust parity coverage. This supersedes the earlier 2026-10-19 status above, which predates the Phase 2 implementation.
- E1 produced the real null-rate report for 2,844,435 rows across 1,518 symbols through 2026-10-16. The audit found 73/88 fields above the report's lookback-only 1 percentage-point expectation, 13 fields still source-unverified, and explained why those flags are not by themselves confirmed defects. The Master Build Spec treats null-rate shifts as warnings and requires a report; it defines no 1-point exit threshold. Detailed cell-level attribution remains open. See [`E1 null-model audit`](evidence/phase2/phase2_e1_null_model_audit_20261022.md) and its linked report artifacts.
- E2 passed against only the disposable `vnsignal_phase2_report_20261019` database. Across the 40%, 70%, and 95% cut dates (2021-12-14, 2024-05-21, 2026-05-27), the point-in-time-stratified 60-symbol cohort had zero pre-cut feature-row differences, zero completed-label differences, and zero label-boundary mismatches. Each branch produced crossing labels and post-cut feature changes; independently perturbed future equity and index inputs changed the full-market support. The test's outer transaction ended with `ROLLBACK`; the registered `vnsignal` database was not modified. Full counts, the selected cohort, perturbation bounds, and SQL output are in [`E2 real leakage log`](evidence/phase2/phase2_e2_real_leakage_20261023.log).
- E3 passed on 20 deterministic real symbol-days with VNDIRECT source lineage and payload hashes checked against the current V3 feature hash. The three sampled dates were 2023-04-04, 2022-10-10, and 2024-09-04; the transaction-local adjusted-price cache contained 2,844,435 rows. See [`E3 real parity log`](evidence/phase2/phase2_e3_real_parity_20261023_retry12.log).
- Current-tree verification after the Rust changes passed: `go -C go test ./...`, `go -C go vet ./...`, and `python -m unittest discover -s tests -v` (27 tests); the Rust library, integration, and doc-test suites also passed. Hosted CI was not rerun.

At this historical checkpoint, the then-current acceptance gates were reported complete. Later migrations 058, 059, and 064 changed label availability, training eligibility, and the V2 rolling-extrema implementation. The current status at the top of this file supersedes that conclusion: Phase 2 is not ready for sign-off or Phase 3. The later E2, E3, E4, and E5 evidence must be used for the current decision.

### Phase 2 continuation evidence — 2026-10-24
- APP/C92/VIE official HNX source archive: six raw landings committed to report clone; repeat added zero. Exact byte checks and identity checks passed. See `docs/evidence/phase2/hnx_upcom_transfer_sources_20261024/import_retry_20261024.log` and `import_repeat_20261024.log`. This archives evidence only; lifecycle classification remains open.
- Migration 071 fresh two-pass harness passed and was applied to the report clone. Real low-memory feature attempt still stopped before feature generation: measured 15/30/60-symbol probes 827/3495/4544 ms, adjacent exponent 2.079 > 1.3. No guard was weakened and no feature completion is claimed.
- Required 071 Go tests and vet passed. Initial Python run timed out in the five-second health subprocess test; isolated health returned in 1701 ms and an unchanged full 31-test rerun passed (`python_tests_071_isolated_20261024.log`). Initial failure retained.
- Phase 2 remains incomplete; full current feature build, remaining exit evidence, and current candidate CI are outstanding.

### Archived price-band census — 2026-10-24
Read-only census completed successfully on report clone (`docs/evidence/phase2/phase2_price_limit_coverage_20261024.log`). All 2,844,683 VNDIRECT source rows resolve to archived response rows with numeric ceiling/floor pairs; 2,843,396 pairs are positive and ordered, and 1,287 are invalid (1,278 in 2019; nine in 2023). This corrects the earlier implication that raw price-band evidence is absent. It does not establish point-in-time availability, materialized observation coverage, or execution-weight validity. Invalid pairs must remain unusable. No raw/core/feature data was changed by the census.
Migration 072 cache projection accounting: fresh two-pass disposable migration harness exit 0; report-clone apply and rollback-only assertions exit 0. Go tests/vet and Python 31/31 passed with project Python environment. This corrects time estimation only; real scaling guard and E1 remain open.
Isolated full-history build phase2-v3-072-isolated-full-20261024 passed the unchanged preflight: 15/30/60 measured 550/1122/2490 ms, maximum adjacent exponent 1.150 <= 1.3, projected cache 1.06 minutes within 40-minute budget. Full 1518-symbol cache load started. This is preflight evidence only; feature completion remains unproven. Live log: docs/evidence/phase2/phase2_v3_072_isolated_full_20261024.log.
The isolated 072 full-cache attempt was cancelled after exceeding twice its estimate; cancellation arrived during final ANALYZE after all102 batches filled. No feature pass. Migration073 removes unconditional growing-cache DELETE scans on first loads while retaining retry replacement. Targeted scan-counter/uniqueness assertions passed; fresh073 full migration harness and required checks are in progress.
073 verification completed: Go tests/vet and Python31/31 passed; fresh two-pass migration harness exit0; report-clone apply and scan/retry assertions exit0. Corrected full-history feature build phase2-v3-073-isolated-full-20261024 started, with current log docs/evidence/phase2/phase2_v3_073_isolated_full_20261024.log. Previous cancelled072 attempt remains failed.
Corrected073 full build stopped at preflight (552/1718/2115ms, exponent1.638), before cache/feature generation. No repeated-until-green run was attempted. A fixed nine-sample diagnostic retained all measurements: medians619/1239/2911ms (adjacent exponents1.001/1.232), but15-symbol coefficient of variation29.69%, so these medians are not accepted as stable evidence. A fixed90-sample longer diagnostic is now running; it does not change production gates.
Migration074 fixed benchmark: fresh two-pass migration harness exit0, including fixed-sample validation assertions. Final runner readiness change also passed Go tests/vet and Python31/31; report-clone apply/rollback-only assertions succeeded. Full-history build phase2-v3-074-isolated-full-20261024 now running the actual fixed90-sample protocol. No production074 preflight or feature completion is claimed until its results are inspected.
Actual074 benchmark retained all90 samples and correctly rejected unstable block means. Serena processes had restarted automatically and were stopped during that run; local Codex Serena auto-start was then disabled and zero processes verified. Disturbed timing CSV: docs/evidence/phase2/phase2_074_disturbed_samples_20261024.csv. A fresh unchanged-protocol build phase2-v3-074-clean-full-20261024 is running under the corrected local environment; no pass is claimed yet.
Clean074 setup completed: all2844435 cache rows filled in75.336275s and finalized in18.277122s;90-sample aggregate648/1367/2379ms, exponent1.077. Eight quarterly feature chunks committed (2018Q4 through2020Q3), totaling659588 rows. Interactive tool handle/process disappeared afterward; authoritative PostgreSQL inspection found no active build connection and remaining25 chunks pending. Same buildID resumed via hidden background process with persistent status JSON/process start identity and separate resume log; existing done chunks must pass normal hash checks before skipping. See phase2_074_process_loss_audit_20261024.log. No full feature completion claim.
Fundamental analyzer JSON-type checks added to route malformed quoted numeric/order/unit fields through existing quarantine before archival commit. Go tests/vet and Python31/31 passed after formatting; signed32-bit order boundaries and malformed fields covered. Provider capability/row-ID/unit mapping remains open; no live calls or canonical mappings enabled. Evidence: phase2_fundamental_json_types_20261024.md.
Resume1 terminated explicitly with exit1 after90 samples failed block stability; eight committed quarters remain659588rows. The subsequent rollback-only memory diagnostic exited0 and passed sample stability validation, reaching22.3MB backend allocation; it did not invoke the final scaling assertion or build features. Normal function restoration verified. No build is currently running. See phase2_cache_memory_investigation_20261024.md. POM/QBS archived endpoint evidence now supports two further9-session venue-transition explanations (18sessions); manifest hashes/sizes of fivefiles verified and gap_assessment updated. No lifecycle/interval DB classification or bars changed.
075 cache-hash invalidation correction: red regression reproduced stale hashes on074; targeted075 passed; fresh two-pass075 migration harness exit0; Go tests/vet and Python31/31 passed. Report-clone migration and expanded reset/retry/ownership/rollback assertions passed. POM/QBS five source landings committed and repeat addedzero; immutable byte/identity checks passed. Full feature coverage still eightquarters/659588rows; remaining25 feature chunks, label/fundamental/lineage/E4 and CI gates remain open.
After075 and final readiness checks, background resume2 started under the same phase2-v3-074-clean-full-20261024 buildID. Current process9328 start identity verified; log/status use phase2_v3_075_clean_full_resume2_20261024. It must revalidate existing hashes and pass the fixed90-sample guards; no completion claimed. All eight previously committed chunks remain the last proven feature checkpoint.

076 lineage archive: expanded review regression passed (nine source outcomes, strict ISO parsing, append-only including TRUNCATE, scope-sensitive batch fingerprints). Go tests/vet and Python31/31 passed. Fresh two-pass migration harness running; real report-clone lineage and listing-tenure consumption remain unproven. See evidence/phase2/phase2_vci_lineage_archive_076_20261024.md.

076 terminal checkpoint: fresh full two-pass migration harness exit0. Applied report clone; real ABR archive 1426 observations (1424 EXACT, 2 MISSING_LANDING), repeat inserted0. Full-universe lineage remains pending. Fundamental year-zero parser/database mismatch fixed; annual/quarterly boundary regressions and Go tests/vet/Python31 passed. Phase 2 remains incomplete.

Fundamental adapter attribution checkpoint: actual installed5.0.3 quarterly income route returned160rows. Adapter now preserves matching provider/request ticker attribution and rejects conflicts. FPT one-frame durable ingestion committed160managed rows/eightquarters (2024-09-30..2026-06-30), checksum/body and conservative availability verified. Go tests/vet, Python32, explicitCGO UCRT64 Go race, and disposable PostgreSQL fundamental assertions passed. Other statements/yearly capabilities/mappings/coverage remain open. See evidence/phase2/phase2_fundamental_attribution_20261024.md.

12:15 checkpoint:10 quarters through2021-03-31 committed830523rows;23quarters remain (phase2_feature_checkpoint_20261024_1215.log). Migration077 reviewed and targeted/baseline recovery assertions passed; Go/vet/Python32 passed. Its fresh harness/report apply/full lineage are queued behind successful feature completion with process identity and input-hash guards, not yet passed. Current-machine quarterly balance_sheet168rows and cash_flow56rows capability probes also succeeded; source data for those statements is not yet archived. SPI3landings imported, repeat0; no lifecycle classification altered.

12:55 feature checkpoint:12quarters through2021-09-30 committed1007116rows;21quarters remain (phase2_feature_checkpoint_20261024_1255.log). All six FPT statement/frequency archives verified768versions. Observed cash refresh adds56observations, repeat skipped with one reservation (824observations total). Annual capability matching and Vietnam-day observed job keys implemented; Go/vet/Python32 and explicitUCRT64race passed. 078 current-V3 cohort/null-industry corrections passed targeted assertions, including five peers per rank metric. Fresh full harness and report077/078/079/080/081 applications are queued serially in replacement078 process, not passed yet. SPI source-backed gap explanation added to the selected research assessment after three-source archive/repeat verification; this is not a fresh219-interval census.

Migration079 separates parent profit/equity from group totals for P/E and P/B,
persists the operands and versions formula identity. Targeted migration replay
and synthetic overlay assertions pass. The fresh full harness remains queued.
See [valuation evidence](evidence/phase2/phase2_parent_valuation_079_20261024.md).

Migration080 implements explicit legal listing episodes and persisted membership.
Targeted apply/replay, 249/250 boundary, suspension, transfer gap, relisting, PIT
correction and persisted membership assertions pass. Real notice population and
coverage remain open. See [listing tenure evidence](evidence/phase2/phase2_listing_tenure_080_20261024.md).
The latest database checkpoint confirms 14 committed quarters/1,183,092 rows
through 2022-03-31, with 19 quarters pending. PostgreSQL confirms active 2022Q2
computation. See [checkpoint](evidence/phase2/phase2_build_checkpoint_080_completed_quarter_20261024.log).

Migration081 fixes same-day industry availability in the separate fundamental
overlay; targeted apply/replay, overlay and dedicated cutoff/conflict/hash checks
pass, as do Go tests/vet and Python32. See
[industry evidence](evidence/phase2/phase2_industry_availability_081_20261024.md).
The latest checkpoint is 15 committed quarters/1,271,759 rows through 2022-06-30,
with18 quarters pending and active2022Q3 computation. See
[checkpoint](evidence/phase2/phase2_build_checkpoint_081_20261024.log).

The in-progress candidate is committed and pushed on `phase2-evidence` at
`68f44cb60f2f4231df4418365ea8773c6dadc8b5`, with draft
[PR1](https://github.com/Kashumir-Kaiser/VN-Signal/pull/1). Offline CI run
40086998005 was queued for that commit. This records dispatch only, not green CI
or Phase2 completion. Main remains at2caaf4dd31175aa2a6da12f851301ab93a2d3ace.

CI checkpoint: Go race/vet and Python jobs passed on commit68f44cb. The
PostgreSQL job is running its fresh harness; Rust and tagged integration steps
remain pending. See [CI checkpoint](evidence/phase2/phase2_candidate_ci_081_20261024.md).

Branch CI is now fully green: run40086998005 completed successfully on exact
commit68f44cb60f2f4231df4418365ea8773c6dadc8b5. All Go/Python/PostgreSQL/Rust
jobs passed, including tagged database integration and fixture parity. See
[final CI snapshot](evidence/phase2/phase2_candidate_ci_081_green_20261024.json).
This supersedes earlier queued/partial CI observations. Real-data completion and
main merge remain open; no Phase3 readiness is claimed.

Tenure scope review:080's legal-event route is stronger than the originally
accepted conservative250-execution lower bound. Native VNDIRECT source rows
carry dated venue/type fields (including ACB's actual HNX-to-HOSE change), making
an alternative exact execution-proof route worth implementing and validating.
It is not yet implemented; do not claim it passes. See
[scope/source review](evidence/phase2/phase2_tenure_scope_and_execution_evidence_20261024.md).

### Migration 082 local review in progress

The public execution lower-bound route is implemented, with explicit reconstructed event availability and persisted evidence basis. The original consumer fixture omission is fixed; the targeted original suite passed. Added future-notice assertions and the full fresh harness are still running, so 082 is not signed off. SQL source line endings are enforced as LF to fix Windows migration-anchor replay. Go test/vet and Python 32 pass for this worktree. See [082 review](evidence/phase2/phase2_public_execution_082_review_20261024.md).

The latest database checkpoint is 18 committed quarters / 1,542,538 rows through 2023-03-31, with 15 pending. Backend 14332 and scheduler wrapper 13356 were both verified live. See [checkpoint](evidence/phase2/phase2_checkpoint_082_20261024.log). Full feature, label, real-source archive and repeat evidence remain open. Green CI on 68f44cb covers through 081; it does not verify these later changes.

082 local validation update: the complete fresh two-pass migration harness passed, including the new future-notice and persisted-membership tests. Go/vet/Python32 also pass. Real-source qualification and a new CI run remain required.

083 validation: bounded per-security execution-proof hashing replaces the potentially 190 MB flat digest aggregate. The fresh full two-pass harness, targeted migration replay, Go tests/vet and Python 32 pass. The real rollback-only ACB pilot qualified 2,003 exact native executions (545 HNX, 1,458 HOSE), repeat zero. See [083 review](evidence/phase2/phase2_public_execution_083_review_20261024.md). CI run40090371306 is green for 2471be0 (through082); 083 requires a new exact-commit run. Phase2 and main merge remain open.

### 2026-10-25 — Analyze source-bar statistics and recheck the cache guard

The disposable report clone had no planner statistics for `core.bars_daily_sources` despite approximately 5.03 million rows (`last_analyze` and `last_autoanalyze` were NULL; `n_live_tup` was 0). `ANALYZE VERBOSE` sampled 30,000 of 116,680 pages, estimated 5,027,418 live rows, and found no dead rows. The override and symbol-scope tables were analyzed too. Evidence: `docs/evidence/phase2/phase2_analyze_source_bar_stats_20261025.log`. The refreshed 15-symbol source-selection cost plan uses the existing primary-key index-only scan; it does not establish that missing statistics caused the timing instability.

A rollback-only 15-symbol diagnostic returned the same 23,765 rows. The first cold probe took 18.060 seconds; a split run immediately afterward measured initialize/populate/finalize at 1.114/2.499/0.301 seconds. Two additional balanced 15/30/60 warmup cycles measured 2.639/2.195/4.510 seconds and 1.380/1.684/6.132 seconds. Their retained scripts and logs are `phase2_cache_stage_diag15_20261025.*`, `phase2_cache_stage_split15_20261025.*`, and `phase2_cache_warmup_diag_20261025.*` under `docs/evidence/phase2/`.

One fresh fixed 90-sample calibration followed an extra balanced warmup and still failed the unchanged 20% block-stability guard. Block means were 5,219.6/3,909.0/5,702.0 ms (15 symbols, CV 15.3%), 9,101.3/5,998.7/5,783.4 ms (30, CV 21.8%), and 15,118.3/8,792.4/9,567.9 ms (60, CV 25.2%). The run rolled back; it wrote no feature rows. All sample records are retained in `docs/evidence/phase2/phase2_cache_guarded_90_after_warmup_20261025.csv`, with full output in the paired `.log` and `.sql`. PostgreSQL's temporary-file counters did not increase from the preceding diagnostic snapshot, and no other active database query remained afterward. This is not a Phase 2 pass; do not repeat the 90-sample gate until the variable stage latency is better isolated.

### 2026-10-25 — Isolate cache-stage latency and temp-buffer effects

A stage breakdown of the rejected 90-sample set shows variable time in all three stages, with finalization the largest component for 60 symbols: block means were 6.80/4.77/5.15 seconds for finalize, 5.33/3.18/2.80 seconds for populate, and 2.98/0.84/1.62 seconds for initialize and other work. The per-sample breakdown is `docs/evidence/phase2/phase2_cache_guarded_90_stage_breakdown_20261025.csv`.

`auto_explain` on one default-configuration 60-symbol probe recorded 12.055 seconds total, 7,896 local-buffer reads and 4,125 writes, but only three shared-buffer reads. PostgreSQL's global temp-file counters did not grow, so this was temporary-relation I/O rather than a sort/hash temp-file spill. One nested aggregation estimated two rows and returned 26,686; its contribution to timing is not yet established. See `phase2_cache_auto_explain60_20261025.sql`, its client log, and server excerpt.

A single 60-symbol profile with `temp_buffers=64MB` took 122.978 seconds and had 6.94 seconds of local write time. A single `temp_buffers=16MB` profile took 7.055 seconds and reduced local reads, but a repeated two-cycle profile at 16MB varied from 10.330 to 25.434 seconds, with finalization taking 6.90 to 16.57 seconds. Both settings were transaction-local and rolled back. Do not change the builder's 8MB default based on one fast sample; neither alternative produced stable evidence. The 90-sample gate remains failed, and no feature data was written.

### 2026-10-25 — Counterbalanced cache profile and host telemetry

A rollback-only 60-symbol B/A/A/B profile returned 108,331 cache rows in all
four passes and ended with `ROLLBACK`; it wrote no feature rows. The host
monitor retained 132 samples: free memory reached 105 MiB, page-input rate
peaked at 22,176 pages/s, page-output rate at 11,666 pages/s, and disk queue
length at 50. The high paging and low free-memory readings show that this run
was under substantial host pressure, but do not establish which cache stage
caused the time variation. The database's per-function notices also diverge
from some client wall times. `finish_phase2_adjustment_rows` reported both
indexes as already present only in B1 and B2, where the script explicitly
pre-created them; A1 and A2 did not report skipped index creation. The `begin`
function drops and recreates the temporary cache between passes, so the
intended treatments were set up. However, same-session physical cache state
carried across the B/A/A/B order, the paired runs varied sharply, and no
row-image/hash equivalence was recorded. Treat the comparison as illustrative
only; it does not support a strategy change. Preserve the complete logs and
telemetry at `docs/evidence/phase2/phase2_cache_counterbalanced_abba60_20261025.*`;
do not change the cache guard from this profile.

### 2026-10-25 — Google-key-shaped scanner finding in archived-source staging

The current `landing_stage.csv` and every file in its archived evidence packet
have zero matches for the canonical Google API key pattern. One match exists
in the historical base64-encoded staging blob at commit `68f44cb`; that commit
is still contained in `origin/phase2-evidence`. The decoded, manifest-verified
public PDF payloads contain no canonical key, and the current hex-stage replay
passed checksum validation and inserted zero rows. This is a confirmed
encoding false positive, not evidence of an exposed Google credential. The
corrected file and importer are currently local changes; no Phase 2 signoff
or push is claimed.

### 2026-10-25 — Refresh the V3 feature-chunk checkpoint

A read-only query of `ops.feature_chunks` in the report clone confirms 55
completed V3 feature records totaling 2,730,947 rows through 2026-06-30. This
includes 36 successful monthly chunks from 2023-07 through 2026-06, totaling
1,098,842 rows. The older failed 2023 Q3 parent range is covered by its three
successful monthly chunks. The July 2026 monthly chunk remains failed, and the
late-history July–October chunks remain pending; those dates have no completed
feature coverage. The one-symbol July retry did not reach feature writes
because the fixed 90-sample cache guard rejected the unstable calibration.
This supersedes the older 18-quarter checkpoint above; it does not make Phase 2
ready for signoff.

### 2026-10-25 — Current-hash feature null-rate census remains blocked

A bounded read-only E1 report-clone query covered V3 hash
`775b9bd502282ebcf15b69f8654189d5b60cb7e072549570698f723c088a021e` from
2022-10-10 through 2026-06-30. It returned 1,360,112 rows across 1,509 symbols
and 101 feature checks. Eight measured features were within the existing 1
percentage-point tolerance; 80 measured features exceeded it; 13 features are
still marked source-unverified. Several technical-feature discrepancies are
large (for example, `close_sma50_ratio` is 62.2% null against a 5.4% structural
warmup expectation). Six rank features had zero input/null-mismatch rows. This
report does not establish whether the cause is feature generation, valid
source availability, or the structural expectation; investigate that before
accepting E1. Keep the 1pp tolerance unchanged and do not treat this report as
a Phase 2 pass.

The clean CSV is `docs/evidence/phase2/phase2_current_hash_null_rates_ranged_20261025.csv`
(SHA-256 `0bb1d758e5252394aad76fa270af252e9777c7c74ee5ed212af171d62010fb20`).
The original psql stdout, including its seven setup-status lines before the CSV
header, is preserved in the adjacent `.log`; the query is in the adjacent
`.sql`. The earlier unbounded scan timed out and is not used as report evidence.

### 2026-10-27 — V3 input-manifest integrity correction in progress

The migration 089 builder uses a calendar-year anchor and the preceding 1,000
effective sessions, but the saved-chunk input hash still used the monthly chunk
start for its warmup and V2 context ranges. This can miss changes to inputs the
builder consumes, so the previous feature-build checkpoint is not sufficient
to establish resumable-build integrity. The original 089 full-range client was
stopped before more chunks were written; its failure and client logs remain
preserved.

Forward migration 092 aligns the manifest with the builder and changes feature
and label input-manifest domains to v3. The fresh two-pass PostgreSQL harness
passed, including the synthetic prior-month V2 invalidation assertion and the
corrected recursive-builder golden fixture. Migration 092 is applied to
`vnsignal_phase2_report_20261019`; its migration, harness, regression, and
golden logs are retained under `docs/evidence/phase2/`.

The same current-hash build ID resumed on 2026-10-27 at 09:21 Asia/Saigon,
using calendar-month transactions, 15-symbol cache batches, five-symbol V3
compute batches, 32 MB `work_mem`, and the 092 manifest. The deliberate stop at
12:25 Asia/Saigon used Ctrl+C after psql announced the March 2024 feature chunk
and its 1,059 sessions, before that chunk committed. Based on the client
reaching March, monthly feature transactions through 2024-02 had completed;
March 2024 is the first chunk to rerun. Confirm these statuses from
`ops.feature_chunks` after PostgreSQL is available again. The interrupted
chunk's status and data writes were inside its monthly transaction and should
roll back when PostgreSQL recovers the cluster.

The preserved build log is
`phase2_build_phase2-v3-089-full-20261025_20261027-092149-083-1fc49491.log`.
The psql client exited with code 1 after Ctrl+C. The PostgreSQL 18 Windows
service is currently stopped, and the manually running PostgreSQL processes
also exited. Starting `postgresql-x64-18` from this session failed because the
session cannot open the service. An administrator must start that service
before querying or resuming the report clone at
`vnsignal_phase2_report_20261019`.

This run covers only 2023-03-01 through 2026-10-16; it does not cover the
specification's Q4 2018 training start and must not be described as the full
feature history. Once PostgreSQL is running, verify the monthly feature-chunk
statuses and V2 date range, then rerun `phase2-v3-089-full-20261025` with the
same date bounds and batch settings. The runner should skip committed monthly
chunks with unchanged inputs and rebuild March 2024. After completing this
range, resume the same feature build without explicit date overrides so the
runner revalidates 2023+ chunks and fills any earlier months back to the
earliest eligible date (expected in Q4 2018). Only then build labels and refresh
E1–E5, run the point-in-time fundamentals coverage census, and complete
exact-tree CI. The expanded manifest regression still needs a fresh disposable
harness run. Phase 2 is not signed off; the main-branch push remains pending.

For post-build E1, bind the report to the verified full V3 date range and the
exact `feat.phase2_feature_set_hash_v3()` hash; keep source-unverified policy
fields separate from measured structural-null deviations and verify that
policy list against the current builder. For E5, use the current V3 hash and
the full 2023 calendar year as twelve calendar-aligned label chunks; rebuild
the year under a distinct build ID and run the repeatability verifier
immediately after the second build.

The historical 219 continuity-gap count is a frozen 2018–2023 seed, not a
current-hash full-history census. The older attribution query hard-codes that
seed and cannot serve as final E4 evidence. After full coverage is built, use
the V2 `(symbol_id, trade_date)` keys as the expected V3 set, guard that all V3
rows have the current single feature-set hash, check keys against
`core.effective_trading_sessions`, validate rank bounds, and derive adjacency
gaps from the actual session calendar. Review every gap with source and
lifecycle evidence; do not classify absence as a suspension.

### 2026-10-27 — PostgreSQL recovery and controlled V3 resume checkpoint

The 20:19 `pg_ctl start` attempt failed because another process temporarily
held port 5432; PostgreSQL logged IPv6 and IPv4 bind failures and shut down.
At 20:22 the port was clear, the PostgreSQL 18 service was stopped, and the
target data directory had no `postmaster.pid`. This session could not start the
Windows service, so the same cluster was started directly with `pg_ctl` as the
current user. Recovery completed successfully at 20:26:10 after a roughly
three-minute data-directory fsync, WAL redo, and an end-of-recovery checkpoint.
The server accepted connections, with no corruption error. This was a transient
port collision followed by normal crash recovery, not a project-code defect.
The local PostgreSQL logs are `C:\Program Files\PostgreSQL\18\data\log\postgresql-2026-10-27_201923.log`
for the bind failure and `C:\Program Files\PostgreSQL\18\data\log\postgresql-2026-10-27_202249.log`
for recovery and clean shutdown.

The resumable build ID `phase2-v3-089-full-20261025` was rerun against
`vnsignal_phase2_report_20261019` for features from 2023-03-01 through
2026-10-16, with monthly transactions, 15-symbol cache batches, five-symbol
V3 compute batches, 32 MB `work_mem`, and migration 092. Its fixed 90-sample
cache guard passed. The corrected v3 input hashes matched for March 2023 through
February 2024, which the runner skipped. March, April, and May 2024 were rebuilt
and committed with 30,627, 27,721, and 32,023 rows, respectively.

At the one-hour handoff, June 2024 was in feature batch 49. Ctrl+C stopped the
client; the monthly transaction rolled back, and the prior pre-092 row remains
marked `done` with 29,178 rows. That old row is not current-manifest evidence:
the next run must hash-check and rebuild June under migration 092. The client
log is `docs/evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261027-202946-192-96cb3e8d.log`;
it ends during June and has no companion failure log. Earlier `done` rows after
May and before March 2023 also require the documented v3 hash revalidation.
Aggregate status counts therefore must not be reported as current v3 coverage.

After confirming the build client and active database session were gone,
`pg_ctl stop -m fast -w` completed at 21:31:42 and shut the cluster down cleanly.
No PostgreSQL process or
port-5432 listener remains. The Windows service is still stopped because this
session cannot open it; start `postgresql-x64-18` from an elevated session
before the next run, or start this same data directory directly. Resume with
the same build ID and settings, without `-Force`; June 2024 is the next stale
chunk. Phase 2 remains incomplete and is not signed off.

### 2026-10-27 — Port collision diagnosis and June 2024 resume

The 20:19 `pg_ctl start` failure is explained by the PostgreSQL log: the
attempt could not bind either `::` or `0.0.0.0` on port 5432, then shut down.
This is a port collision, not a PostgreSQL data-directory or project-code
failure. Before the controlled resume, `pg_ctl status` showed no server; the
same PostgreSQL 18 data directory was started directly at 21:39. Exactly one
postmaster owned port 5432. Its logger, checkpointer, writer and I/O worker
processes were normal PostgreSQL children, not duplicate servers or Serena
dashboards.

The interrupted June 2024 feature chunk was resumed under the existing build
ID `phase2-v3-089-full-20261025`, bounded to 2024-06-01 through 2024-06-30,
with calendar-month transactions, 15-symbol adjustment-cache batches,
five-symbol V3 compute batches, 32 MB `work_mem`, and 16 MB
`maintenance_work_mem`. The fixed 90-sample cache guard passed. The transaction
committed 29,178 V3 rows for 2024-06-03 through 2024-06-28 with current feature
hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b`.
The stored output hash independently matched the output-hash verifier. The
V2 table has the same 29,178 symbol-session keys for that month. Run evidence:
`docs/evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261027-214535-050-26c8541f.log`.

A standalone input-hash check without the runner's staged temporary cache
stopped at the intentional 60-symbol direct-cache limit; this was a verifier
setup mismatch, not a failed build. The production runner computes the input
hash after it has staged and finalized the full cache in the same session. No
source code or migrations were changed for the port collision.

After verification, the build client had exited and no database sessions were
active. `pg_ctl stop -m fast -w` completed at 22:07:19; PostgreSQL logged a
completed checkpoint and a clean shutdown, `pg_ctl status` reported no server,
and port 5432 had no listener. The service remains stopped. The next resume is
safe with the same build ID and current settings; July 2024 is next for this
bounded range. The wider build remains incomplete: the previous aggregate
still includes stale-hash chunks, 2025-09 remains failed, and 13 later monthly
chunks remain pending. Do not treat the aggregate `done` count as full
current-hash coverage or mark Phase 2 signed off.

### 2026-10-27 — July 2024 V3 chunk checkpoint

Following the June checkpoint, the same build ID completed July 2024 alone with
a calendar-month transaction, 15-symbol adjustment-cache batches, five-symbol
V3 compute batches, 32 MB `work_mem`, and 16 MB `maintenance_work_mem`. The
fixed 90-sample cache guard passed. The runner exited successfully and committed
33,617 V3 rows for 2024-07-01 through 2024-07-31 with feature hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b`. The
stored output hash independently matched. V2 has the same 33,617 symbol-session
keys for July. Input hash `c0d9789999ab44258870ca9750da3ec9f6e12939c92b0795bab30c5654d97585`,
output hash `09597269aca596dfdf12723abc15b68f2c8ae3096791b93f350d10640323b098`.
Run evidence:
`docs/evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261027-221114-989-a8d902e9.log`.

PostgreSQL had no active client sessions when stopped. `pg_ctl stop -m fast -w`
completed at 22:31:47 with a completed checkpoint and clean shutdown; `pg_ctl
status` reported no server and port 5432 had no listener. The PostgreSQL Windows
service remains stopped. The next bounded resume for this range is August 2024;
start the same data directory only after confirming with `pg_ctl status` that no
server already owns port 5432. June and July have current-hash evidence; this
does not certify the other historical `done` chunks. The full V3 range, labels,
current-hash E1–E5, PIT census, exact-tree CI, and main-branch signoff remain
open.

### 2026-10-28 — PostgreSQL collision cleared; full-range build paused safely

The failed 20:19 start log shows both port 5432 addresses were already held.
At this later inspection, PostgreSQL 18 postmaster PID 10568 was running
directly against `C:\Program Files\PostgreSQL\18\data` while the Windows
service `postgresql-x64-18` was stopped, confirming that the cluster can be
running outside the service and collide with a second start. This was an
operational port collision, not a damaged cluster. After confirming the Phase 2
client had exited and canceling only my read-only inspection,
`pg_ctl stop -m fast -w -t 60` completed normally. The postmaster PID file is
gone, port 5432 has no listener, and the Windows service remains stopped. On
resume, start the Windows service or start this data directory directly, but
first confirm no server is already running; do not start both paths.

The full-range build `phase2-v3-089-full-20261025` was running month by month
from the V2 source range `2018-10-01` through `2026-10-16`. Its client was
stopped after the 2019-12 chunk exceeded the 30-minute recovery checkpoint.
The native log is
`docs/evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261027-225651-250-e32bfbce.log`;
the failure summary is
`docs/evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261027-225651-250-e32bfbce.log`.
The log shows October 2018 through November 2019 committed in separate monthly
transactions. December did not reach V3 computation: its input manifest spent
over two hours in the V2-context hash over `feat.features_daily` from
2019-01-01 through 2019-12-31, then the identified build backend was canceled.
That transaction rolled back; the earlier month commits remain durable. The
runner and all diagnostic psql sessions have exited. The report database is
now cleanly shut down and can be resumed with the same build ID and no
`-Force`; first investigate the manifest query plan/performance so the same
unbounded hashing stall is not repeated. Phase 2 remains incomplete.

### 2026-10-28 — Controlled full-range resume checkpoint

The full-range V3 feature runner for `phase2-v3-089-full-20261025` passed cache preflight and proceeded month by month. Its final output marked the March 2023 slice input-unchanged; the April 2023 chunk wrapper was active at the stop request. Ctrl+C exited the client and rolled back its open monthly transaction. Rerun the same build ID and settings so input/output hashes are revalidated and the first remaining mismatch is rebuilt. This is a resumable operational stop, not a Phase 2 pass. PostgreSQL 18 completed a fast, checkpointed shutdown at 11:17:15 +07; `pg_ctl status` reports no server and port 5432 has no listener.

The last ledger snapshot remained 85 done slices / 2,488,110 rows, one earlier failed September slice, and 11 pending slices. Current-hash feature coverage, labels, PIT census, E1-E5, migration harness, exact-tree CI, and main-branch delivery remain open. Migration 094 has not been applied or validated.

### 2026-10-30 — PIT source pagination and label-refresh checkpoint

The HOSE all-news endpoint was captured end to end for calendar 2020 using its
one-based page index: 27,173 rows across 55 pages, 27,172 distinct IDs, and one
duplicate outside the 1,380 title-filter candidates. All candidates have a
non-null `postedDate`, but the keyword filter does not classify financial
statements or establish version history. This closes only the bounded
pagination check; the point-in-time archive and fundamental overlay remain
open/disabled. See
`docs/evidence/phase2/phase2_pit_public_source_feasibility_20261030.md`.

The active report-clone refresh `phase2-v3-089-full-20261025` has passed the
previously slow 2021-12 slice and generated January 2022 label targets
(54,048 rows); the January monthly transaction had not yet emitted its commit
marker at this checkpoint. Thus 39/97 label months remain durably committed
through 2021-12-31; January is still in progress. Continue monitoring the
existing runner. Do not count the generated target rows until its month
commits. After the full label refresh, verify target/weight coverage, rerun
current-hash E1/E4/E5, complete the guarded transfer-event import and PIT
coverage work, then run exact-tree unit/vet/migration checks. No Phase 2 pass
or production-readiness claim is made here.

### 2026-10-30 — February 2022 labels committed; profile repeated checkpoint scan

January and February 2022 label chunks committed, bringing the durable label
ledger to 41/97 months through 2022-02-28. March 2022 is active. Profiling
found that the label checkpoint guard scans and groups the wide V3 feature
table for each month. A 310-MiB index experiment on the report clone did not
change the normal planner choice; a low-memory vacuum was cancelled at 7.8%
to avoid competing with the label run. The index experiment added no source
migration and did not change feature or label rows. The prior 4.74-minute
monthly average implies about 4h25 for the 56 remaining months, but February
took 6m23s while the index/vacuum diagnostics overlapped part of the run, so
the estimate needs a clean follow-up month. Full profiling details are in
[`label refresh I/O profile`](evidence/phase2/phase2_label_refresh_io_profile_20261030.md).

### 2026-10-30 — June refresh active; cached liquidity-series starts

Correction to the earlier 97-month count: `ops.step_runs` contains the old
baseline rows as well as the current-hash refresh attempts. The baseline's 97
unique month keys do not mean this refresh is complete. The current refresh has
44/97 months durably rebuilt through 2022-05-31; the 2022-06-01 through
2022-06-30 chunk is active. May committed 57,194 rows in 834,777 ms with
output hash `eb339b75051635252833ecd8a16cc8e14a956742a610b4f8cae1c82622359b91`.

Migration 097 was applied successfully to the report clone before the June
chunk started. It initializes the session cache before the builder's first
symbol-series CTE and reuses cached first-feature dates there, removing another
per-month group-by on `feat.features_daily`. June is the first chunk exercising
this extension; runtime benefit is not yet measured. Fifty-three refresh
months remain, including June. The live function hooks are verified in the
[097 catalog check](evidence/phase2/phase2_label_series_start_cache_097_20261030.log).

After the refreshed labels commit, still run the guarded 12-ticker/24-document
E4 import and full current-hash E4 reconciliation, current-hash E1 family
attribution, E5 repeatability, and target/execution-weight coverage. E2/E3
remain passes only for their recorded earlier feature hash. The PIT archive
gate remains open, the fundamentals overlay stays disabled, and Phase 2 is not
signed off. Required exact-tree Go/Python tests and PostgreSQL migration checks
remain pending while the low-memory label runner is active.

### 2026-10-30 — April labels committed; May preflight started

April 2022 committed, bringing the durable ledger to 43/97 months through
2022-04-30; May is in preflight. Recorded step-run durations are 6m23s for
February, 14m32s for March, and 10m18s for April. The April chunk completed
with migration 096 active and output hash
`8488503ae3d8593b4a009ab27f966e0681ad4d0fdca8ba215e128b4a0a9a4698`. The
first temp-cache fill ran without an error. Catalog inspection confirms the
session temp relation contains 1,518 symbol rows and survived April's commit;
May is using the same psql session. Three slower-than-usual months are not
enough to set a reliable completion time; measure the next months before
revising the estimate. The PIT archive, E1/E4/E5 current-hash checks,
target/weight coverage, and final exact-tree tests remain open.

The guarded 12-event E4 source import remains pending until labels finish;
then rerun the full current-hash E4 census, E1 family attribution, E5
repeatability and target/weight coverage. E2 and E3 remain passed on their
recorded feature hash. PIT full-history/version semantics and coverage remain
open, so Phase 2 is not signed off and suggestions remain disabled.

### 2026-10-30 — March 2022 committed; apply exact session cache for labels

March 2022 committed, bringing the durable label ledger to 42/97 months
through 2022-03-31; April is active. February took 6m23s and March 14m32s.
The checkpoint guard repeatedly scanned the feature table, and I/O diagnostics
overlapped part of the run. The old 4.74-minute average is no longer a
reliable ETA; 55 months remain.

Migration 096 now caches the exact `(feature_set_hash, symbol_id, first_date)`
mapping in a session-local temporary table that survives monthly commits. It
replaces the repeated full-table group-by with a small cached count while
preserving the same per-symbol first-date rule. It was applied to the report
clone before April began. The first cache fill still performs one full scan;
the next clean chunk duration will show whether later chunks benefit. No
speedup or Phase 2 acceptance is claimed yet. See the
[`label refresh I/O profile`](evidence/phase2/phase2_label_refresh_io_profile_20261030.md).

### 2026-10-30 — June committed after migration 097; July active

June 2022 committed 63,036 rows in 250,397 ms (4m10.397s), with output hash
`40906c64cc4dfb12b670c4f6af99a967e898b566c93959133af48557a1131225`.
The current refresh is now 45/97 months committed through 2022-06-30; July is
active and 52 months remain. June is the first chunk started after migration
097 was applied. Its runtime is lower than May's 13m54.777s, but one chunk is
not enough to establish a stable speedup. The durable database rows and live
checkpoint are in the [refresh record](evidence/phase2/phase2_label_refresh_checkpoint_20261030_0341.log).
The Phase 2 exit gates still open after the refresh are the current-hash
real-data null-rate report, leakage and feature-parity checks (1e-9 parity),
current-hash E1/E2/E3/E4/E5 evidence, target/execution-weight coverage, and
complete PIT fundamentals source/version coverage.

### 2026-10-30 — May retry with staged exact execution weights

The durable current-hash label refresh remains **79/97 months through
2025-04-30**; the prior May attempt reached `START labels` but rolled back
after a 30-minute timeout in the row-wise exact execution-weight refresh. The
cause was about 59k scalar function calls. Migration 101's CTE alternative
matched the scalar reference on one day but had a poor execution profile, so
migration 102 replaces it with analyzed session-local stages. The staged
version matched the scalar reference for all 1,788 ready labels on
2025-04-29 and refreshed them in 9.183 seconds; both validations rolled back.

A report-clone retry launched at 16:12 local ended with a 30-minute statement
timeout in the May 2025 label build. The complete failure and rollback state is
recorded in the later safe-resume checkpoint below. The durable month count did
not advance; no partial May label write persisted. Migrations 099–102 were
applied and checksum-registered directly because migration 033's pre-existing
tree checksum mismatch stops `vnpipe migrate`. The disposable two-pass
migration harness remains required before sign-off. The current-hash full
label refresh, E1 attribution, guarded durable E4 import and reconciliation,
E5 repeatability, target/execution-weight coverage, PIT fundamentals archive
coverage, and final Go/Python/PostgreSQL checks remain open. Phase 2 remains
open and suggestions remain disabled.

### 2026-10-30 — Safe resume checkpoint after May retry rollback

The report-clone retry launched at 16:12 local ended with a 30-minute statement timeout in the May 2025 label build. The adjustment cache finished with 2,844,435 rows; 41 price-day hashes completed in about 7.9 seconds; label target, endpoint, adjustment-prefix, and endpoint-bar stages completed. It then spent about 5m57s on the first-bad-factor stage and timed out while seeding `phase2_label_feature_first_dates` with `GROUP BY symbol_id` over `feat.features_daily`. Failure evidence: [`May first-date cache timeout`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261030-161249-428-55e83d99.log).

The transaction rolled back. Durable refresh remains **79/97 months through 2025-04-30**, with no partial May write and no active runner. Migration 099 contains an indexed first-date lookup and an assertion, but the runtime function still used the old grouped scan. Before another retry, inspect `pg_get_functiondef` through the build runner's exact `DatabaseUrl`, compare it with migration 099, and diagnose a possible target mismatch or later function replacement. Add a guard on that same connection before creating a new migration or relaunching the full refresh. Migrations 099–102 remain applied/checksum-registered on the report clone; migration 033's working-tree checksum mismatch still blocks `vnpipe migrate`, so the clean disposable two-pass migration harness remains open.

Still open: full current-hash label refresh; E1 attribution; guarded durable E4 import and reconciliation; E5 repeatability; target/execution-weight coverage; PIT fundamentals archive coverage; final Go/Python/PostgreSQL checks. Phase 2 remains open and suggestions remain disabled.

### 2026-10-30 — Migration 103 fixes the remaining label first-date scan

A read-only catalog check on `vnsignal_phase2_report_20261019` at port 5432
found two separate first-date cache seeds in the live label builder. The early
seed inserted by migration 097 still used `GROUP BY symbol_id`; the later
liquidity-check seed was already indexed by migration 099. Migration 099's
assertion only established that an indexed lookup existed, so it missed the
remaining early scan. This is the direct cause of the latest May timeout.

Migration 103 replaces the early seed with the indexed per-symbol lookup and
asserts there are exactly two indexed seeds with no old grouped seed. It was
applied to the report clone and registered in `public.vnpipe_migrations` with
SHA-256
`2a2e5c6c45581dc58c83e35eadee3958f6a7f4217fd526d94f599191c80034c8`.
The updated first-date SQL assertion passed on the live function. The label
runner now checks the expected report-clone database and both indexed seed
markers before label work. No full retry has started after this fix; durable
progress remains **79/97 through 2025-04-30**. The clean two-pass migration
harness and current-tree Go/Python/PostgreSQL verification remain pending.

### 2026-10-30 — Reentrant staging fix and verification checkpoint

The clean disposable two-pass SQL migration harness now passes with migrations
103 and 104 and all Phase 2 SQL assertions. Evidence:
[`phase2_104_migration_harness_20261030.log`](evidence/phase2/phase2_104_migration_harness_20261030.log).
The fourth disposable run used a database name accepted by the migration
fixtures; earlier attempts stopped first on a fixture-name mismatch, then
exposed and fixed the listing-tenure fixture contamination and repeated-call
temporary-table bug. Those attempts are not counted as passing harness runs.

Migration 104 makes `feat.refresh_phase2_execution_weights` safe to call
repeatedly in one transaction by dropping its seven session-local staging
tables before each invocation. The updated SQL assertion calls the function
twice in the same transaction and passed on both the report clone and clean
harness. Migrations 103 and 104 were applied and checksum-registered on
`vnsignal_phase2_report_20261019`; report-clone evidence is in
[`phase2_103_104_reportclone_apply_20261030.log`](evidence/phase2/phase2_103_104_reportclone_apply_20261030.log).

On the exact working tree at this checkpoint, `go test ./...`, `go vet ./...`,
and all 42 Python unit tests passed. Logs:
[`Go tests`](evidence/phase2/phase2_20261030_go_test.log),
[`Go vet`](evidence/phase2/phase2_20261030_go_vet.log), and
[`Python tests`](evidence/phase2/phase2_20261030_python_unittest.log).

The current-hash label refresh remains **79/97 months through 2025-04-30**.
The earlier May attempt rolled back before migration 103 corrected the early
first-date seed; no retry has run with both migrations 103 and 104 in place.
Resume the remaining monthly chunks on the report clone using the recorded
matching cache-scaling profile. E1 attribution, durable E4 import and
reconciliation, refreshed-label E5 repeatability, current-hash target and
execution-weight coverage, PIT fundamentals source/version/availability
coverage, and final exact-tree acceptance checks remain open. Phase 2 remains
open and suggestions remain disabled.
### 2026-10-30 — Label refresh resumed after migrations 103 and 104

At 20:01 +07, the guarded label runner resumed build
`phase2-v3-089-full-20261025` on `vnsignal_phase2_report_20261019`, with live
routes disabled and the verified matching cache-scaling profile reused. Its
preflight accepted the report-clone target and both indexed-seed and reentrant
staging guards. May 2025 has committed; June 2025 is active, so the durable
refresh is now **80/97 months through 2025-05-31**. The first-bad-factor stage
took 10.329 seconds in May, down from 5m57s in the rolled-back attempt. Live
runner evidence is
[`phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log).
The `vnsignal` database remains untouched. Final Phase 2 acceptance is still
open pending the remaining labels, refreshed E1/E4/E5 and target/weight checks,
PIT archive coverage, and final verification.
### 2026-10-30 — Label refresh progress: September committed

The resumed report-clone refresh has advanced from 79/97 to **84/97 months
through 2025-09-30**. October 2025 is the active next chunk. May through
September each committed under the same guarded build and current feature hash;
no live vnstock route was used. The complete runner transcript continues in
[`phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log).
### 2026-10-30 — Label refresh progress: October 2025 committed

The report-clone refresh has advanced to **85/97 months through 2025-10-31**;
November 2025 is the active next chunk. May through October are committed under
migrations 103 and 104. The runner remains isolated to the report clone with
live data routes disabled. Evidence remains in
[`phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log).
### 2026-10-30 — Label refresh progress: December 2025 committed

The report-clone refresh has advanced to **87/97 months through 2025-12-31**;
January 2026 is the active next chunk. The May 2025 first-bad-factor scan that
timed out before migration 103 now completes in about 10 seconds, with later
months completing that stage in roughly 2–3 seconds. No timeout has occurred in
the resumed run. See the live runner transcript linked above.
### 2026-10-30 — Label refresh progress: February 2026 committed

The report-clone refresh is now **90/97 months through 2026-02-28**; March
2026 is active. The resumed run has committed every month from May 2025 through
February 2026 without a rollback. Live-data routes remain disabled. The runner
transcript is the durable checkpoint for the active monthly transaction.
### 2026-10-30 — Label refresh progress: March 2026 committed

The report-clone refresh is now **91/97 months through 2026-03-31**; April
2026 is the active next chunk. Six monthly chunks remain through the partial
October 2026 endpoint. No resumed month has rolled back.
### 2026-10-30 — Correction to monthly label count

The progress notes above overcounted the refresh by one after February 2026.
The authoritative starting checkpoint was 79/97 through 2025-04-30. The runner
then committed May–December 2025 (8 months) and January–March 2026 (3 months),
so the correct durable position is **90/97 through 2026-03-31**, with April
through October 2026 still pending/active. The runner transcript's monthly
`START labels` markers and commits are authoritative; no completed month was
lost.
### 2026-10-30 — Label refresh progress: April 2026 committed

The corrected durable count has advanced to **91/97 months through
2026-04-30**; May 2026 is the active next chunk. Six chunks remain, through
2026-10-16. The monthly `START labels` log confirms April committed before May
began.
### 2026-10-30 — Label refresh progress: May 2026 committed

The report-clone refresh has advanced to **92/97 months through 2026-05-31**;
June 2026 is active. Five monthly chunks remain through the partial October
2026 endpoint. The runner has committed each resumed month at its own boundary.
### 2026-10-30 — Label refresh progress: June 2026 committed

The report-clone refresh is now **93/97 months through 2026-06-30**; July
2026 is the active next chunk. June's endpoint-bar stage took longer than the
prior months but completed within the 30-minute statement limit and committed
before the next month started. Four chunks remain through 2026-10-16.
### 2026-10-30 — Label refresh progress: July 2026 committed

The report-clone refresh is now **94/97 months through 2026-07-31**; August
2026 is active. Three chunks remain through the partial October 2026 endpoint.
### 2026-10-30 — Label refresh progress: August 2026 committed

The report-clone refresh is now **95/97 months through 2026-08-31**; September
2026 is the active next chunk. August's longer disk-read stage completed and
committed; two monthly chunks remain through 2026-10-16.
### 2026-10-30 — Label refresh progress: September 2026 committed

The report-clone refresh is now **96/97 months through 2026-09-30**. The final
partial chunk, 2026-10-01 through 2026-10-16, is active; its price-day hash
preflight found zero uncovered dates. One chunk remains.
### 2026-10-30 — Full current-hash label refresh completed

Build `phase2-v3-089-full-20261025` completed the full 97-month label range
on `vnsignal_phase2_report_20261019` (2018-10-01 through 2026-10-16). The
runner reports 97/97 label chunks `done` and 5,688,870 durable label rows;
the existing V3 feature stage remains 97/97 with 2,844,435 rows. The 18
resumed months from May 2025 through October 16, 2026 all committed, and the
runner exited successfully. Full transcript:
[`phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log`](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261030-200159-147-f4d89f1e.log).

This closes the full label-refresh gate only. Current-hash post-build label and
target integrity, E1 current-hash attribution, guarded E4 import and refreshed
reconciliation, E5 repeatability, exact execution-weight coverage, PIT
fundamentals archive evidence, and final exact-tree verification remain open.
Phase 2 remains open pending those checks.

### 2026-10-30 — Post-refresh integrity and E1 attribution

The post-refresh read-only assertion passed for the current feature hash
`28089ed13c1be5a19865bc9cea34c44cb84f3e460ee3f3f2ee837a853d317f6b`:
2,844,435 V3 feature rows and 5,688,870 `close-next-open-v1` label rows across
2018-10-01 through 2026-10-16, with all 97 label chunks done. The clean check
also reports 3,161,496 ready labels. Evidence:
[`phase2_postrefresh_label_integrity_20261030_retry1.log`](evidence/phase2/phase2_postrefresh_label_integrity_20261030_retry1.log).

Current-hash E1 input-gate attribution now covers five selected fields and the
builder-aligned prior-session VNINDEX volatility gate. The five-field query
found small ready-input NULL residuals for the two SMA ratios (9,367 and 5,164
rows) and zero non-NULL values with unavailable checked inputs; the lagged
VNINDEX check found zero ready-input NULLs. This supplements but does not clear
the 73 structural null-rate flags or 13 source-unverified fields in the full
report. Evidence:
[`phase2_e1_full_input_gate_attribution_20261030.md`](evidence/phase2/phase2_e1_full_input_gate_attribution_20261030.md).

### 2026-10-30 — E4 source import and remaining gaps

The guarded report-clone import committed 24 checksum-verified captures and 12
additional distinct transfer events. The post-import full-range reconciliation
now classifies 27 transfer intervals / 221 sessions; the complete population
is 221 intervals / 3,225 sessions. CTR and PTM remain separately supported
lifecycle cases. After excluding those two cases, 192 intervals / 1,318
sessions remain unexplained, so E4 stays **PARTIAL**. No gap was labeled a
suspension or inferred no-trade interval. See
[`phase2_e4_currenthash_postimport_20261030.md`](evidence/phase2/phase2_e4_currenthash_postimport_20261030.md).

### 2026-10-30 — E5 repeatability reverified after target refresh

The pre-refresh 2023 A/B outputs matched each other but no longer matched the
current target table after the archived price-limit inputs were materialized
and refreshed. A fresh 2023 build was compared with the completed full-range
post-backfill build. All 12 monthly label chunks and target chunks now match,
and the canonical full-year content hash is
`320159a4b68e90021bf874a6cfbb750506ecfc4054a89254507abfe06c0028bf`.

The strict check also exposed that a resumed build ID has multiple historical
target attempts. The read-only verifier now associates exactly one current
attempt by durable input hash and current output hash rather than rejecting
any build with retained history or selecting by recency. It passed all 12
months. The earlier failed checks remain preserved. Full report:
[`phase2_e5_repeatability_currenthash_20261030.md`](evidence/phase2/phase2_e5_repeatability_currenthash_20261030.md).

Execution-weight coverage after the backfill refresh and PIT fundamentals
archive coverage remain open. Phase 2 remains open.

### 2026-10-31 — verified four HNX group-source transfers

Migration 105 adds an exact, append-only source-to-security link for a
ticker-specific dated claim inside an intact HNX group article. It preserves
the ordinary same-ticker rule and the existing row-bound HNX-to-HOSE continuity
path. The migration and the synthetic E4 transfer assertions passed on the
disposable report clone.

Four 2021 HOSE-to-HNX transitions (ABT, VFG, BSI, ASG) were imported only to
`vnsignal_phase2_report_20261019`; all pass
`ops.phase2_verified_security_transfers`. The current-hash census now has 135
verified intervals / 1,014 sessions and 86 unclassified intervals / 2,211
sessions. After keeping CTR and PTM separate, 84 intervals / 525 sessions
remain unexplained with no intervening bars or source rows. E4 remains
**PARTIAL**; see
[`phase2_e4_currenthash_posthnx37_group_source_import_20261031.md`](evidence/phase2/phase2_e4_currenthash_posthnx37_group_source_import_20261031.md).

PIT fundamentals archive/overlay coverage, exact 2018 price-limit evidence for
14,866 execution windows, hosted PostgreSQL 16 CI, and final exact-tree checks
remain open. Suggestions remain disabled.

### 2026-10-31 — E4 UPCoM/HOSE endpoint imports resumed

Five additional transfers are now recorded in the disposable report clone:
PXT (HOSE to UPCoM), BSR (UPCoM to HOSE), and HVN, PGV, and BCM (UPCoM to
HOSE). Each event was built from captured official endpoint records and passed
`ops.phase2_verified_security_transfers`; for BCM, the signed HNX notice
establishes the last UPCoM trade on 2020-08-19 and cancellation effective
2020-08-20, while official HOSE record 1194591 establishes first trade on
2020-08-31. The raw captures, stage manifests, guarded import SQL, and BCM
import log are retained under
[`phase2_e4_remaining_gap_probe_20261031`](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/).

The refreshed current-hash census is 221 intervals / 3,225 missing sessions,
with 142 verified transfers covering 1,068 sessions and 79 unclassified
intervals covering 2,157 sessions. One interval contains intervening bar rows;
none contains intervening source-archive rows. The HNX index ranker checked 77
remaining non-CTR/PTM intervals: 34 first-endpoint-only leads, 41
end-endpoint-only leads, two without an exact title/date lead, and no paired
endpoint match. No unclassified interval was labeled a suspension or
no-trade period. Census evidence is
[`phase2_e4_currenthash_gap_pairs_20261031_posthnx48.csv`](evidence/phase2_e4_currenthash_gap_pairs_20261031_posthnx48.csv)
and the matching SQL. E4 remains **PARTIAL**.

PIT fundamentals/archive and overlay coverage, exact price-limit evidence for
the 14,866 unresolved execution weights, hosted PostgreSQL 16 CI, and final
exact-tree verification remain open. Phase 2 remains open and suggestions
remain disabled.

### 2026-10-31 — verified BVB UPCoM-to-HOSE endpoints

The signed HNX attachment for BVB (Notice 2855/TB-SGDHN, page 3) states that
the final UPCoM trade was 2026-07-08 and registration cancellation was
effective 2026-07-09. Official HOSE record 2481120 states that BVB's first
HOSE trading day was 2026-07-21. The four checksum-pinned captures and guarded
import are under
[`bvb_transition_capture_20261031`](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/bvb_transition_capture_20261031/);
one event was imported only to the disposable report clone and passed
`ops.phase2_verified_security_transfers`.

The current-hash census remains 221 intervals / 3,225 missing sessions and now
has 143 verified transfers / 1,076 sessions and 78 unclassified intervals /
2,149 sessions. There is one interval with intervening bars and zero intervals
with source-archive rows. The HNX ranker checked 76 non-CTR/PTM intervals: 34
first-endpoint-only leads, 40 ending-endpoint-only leads, two with no exact
title/date lead, and zero paired endpoints. See
[`phase2_e4_currenthash_gap_pairs_20261031_posthnx50.csv`](evidence/phase2_e4_currenthash_gap_pairs_20261031_posthnx50.csv)
and the matching rank summary `candidate_gap_endpoint_pairs_summary_20261031_posthnx51.md`.
E4 remains **PARTIAL**. PIT fundamentals, price-limit evidence for 14,866
execution weights, hosted PostgreSQL 16 CI, and final exact-tree verification
remain open; suggestions remain disabled.

### 2026-10-31 — E4 batch 11 and current-hash reconciliation

Ten UPCoM-to-HOSE transfers (ABR, AFX, ANT, CCC, MCH, NAB, NHT, ORS, VAB,
VVS) were imported only to the disposable report clone. All ten passed
`ops.phase2_verified_security_transfers`; 20 source landings were stored, and
the verified intervals cover 64 previously missing effective sessions. The
original signed HNX PDFs and their SHA-256 values remain in the evidence
packet. For the 10.5 MB AFX PDF, the raw landing uses its official HNX article
page and pins the linked PDF hash/path because the attachment exceeds the
database's 10 MiB payload bound. The failed initial transaction rolled back;
the successful retry is recorded.

The refreshed census remains 221 intervals / 3,225 missing sessions: 203
verified transfers / 1,432 sessions and 18 unclassified intervals / 1,793
sessions. One interval contains bars (CTR); none contains source-archive rows.
After separately supported CTR/PTM lifecycle cases, 16 intervals / 107 sessions
remain unexplained. HNX ranking found 14 first-endpoint-only leads, two without
an exact title/date lead, and zero paired endpoint leads. TIE remains unresolved
because its HOSE recap conflicts with the cancellation chronology; LCM remains
excluded for a source share-count mismatch. No missing interval is labeled as a
suspension or no-trade period. E4 remains **PARTIAL**. See the
[batch 11 current-hash report](evidence/phase2/phase2_e4_currenthash_posthnx71_20261031.md),
[census SQL](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posthnx70.sql),
[census output](evidence/phase2/phase2_e4_currenthash_gap_pairs_20261031_posthnx70.csv),
and [successful import log](evidence/phase2/phase2_e4_remaining_gap_probe_20261031/import_transition_batch11_reportclone_20261031_retry1.log).

PIT fundamentals/archive and overlay coverage, exact historical price-limit
inputs for 14,866 execution windows, hosted PostgreSQL 16 CI, and final
exact-tree checks remain open. Phase 2 remains open and suggestions remain
disabled.


### 2026-11-01 — Execution-evidence row expansion and quarterly label resume

Migration 108 expands each byte-verified VNDIRECT landing's JSON `data` array once into indexed `(landing_id, source_row)` rows. Execution-weight validation still checks the archived payload digest, byte/JSON parity, source row, and price-limit evidence; it no longer extracts the same TOASTed JSON array separately for every symbol/session. The migration also removes the `labels_daily` dependency trigger installed by 107: raw labels are outputs of this build, and the runner checks their exact chunk output hash, so changing them must not invalidate the cached source-input hash between the raw and derived label steps.

The fresh two-pass PostgreSQL migration harness passed with 108 and the exact execution-weight fixtures: [phase2_20261101_payloadrows_migration_harness_retry.log](evidence/phase2/phase2_20261101_payloadrows_migration_harness_retry.log). Go tests and vet passed with `VNPIPE_PYTHON` set to the project virtual environment; all 47 Python tests passed. Migrations 105–108 are checksum registered on the report clone after checking their installed postconditions.

On the report clone, 2018 Q4 committed at **164,436 rows** and passed the input/output hash check. A full-year 2019 chunk was projected to exceed the 30-minute statement limit, so the uncommitted input-hash attempt was canceled and the runner restarted with three-month chunks. It reused Q4; 2019 Q1 completed at **149,388 rows** and Q2 at **158,206 rows**. The runner is now building 2019 Q3. The active run log is [phase2_build_phase2-v3-089-full-20261025_20261101-052726-986-d55aad46.log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261101-052726-986-d55aad46.log); the canceled annual attempt is preserved separately. Current-hash labels, fundamentals, E1–E5, hosted PostgreSQL 16 CI, and exact-tree verification remain open; Phase 2 stays open and suggestions remain disabled.


### 2026-11-01 — Selective execution-payload staging and monthly resume

The three-month 2019 Q3 statement hit its 30-minute statement timeout while
creating the unique index over all rows expanded from verified VNDIRECT
payloads. The transaction rolled back; its failure log is
[phase2_build_phase2-v3-089-full-20261025.failed.20261101-052726-986-d55aad46.log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025.failed.20261101-052726-986-d55aad46.log).
The same build ID was restarted with calendar-aligned monthly chunks from
2019-07-01. July–September committed under migration 108; October onward uses
migration 109. The first 84 chunks from July 2019 through June 2026 committed
**4,989,864 rows**. The resumed July–October 2026 chunks completed the full
88-month range through 2026-10-16, for **5,216,840 rows**. The durable label
ledger now covers 97/97 month-aligned chunks including the earlier
2018-10–2019-06 range; see the [full integrity snapshot](evidence/phase2/phase2_postrefresh_label_integrity_20261101.log).
The original 84-chunk run log is
[phase2_build_phase2-v3-089-full-20261025_20261101-071828-893-c424d413.log](evidence/phase2/phase2_build_phase2-v3-089-full-20261025_20261101-071828-893-c424d413.log).

| Month | Rows | Runtime |
| --- | ---: | ---: |
| 2019-07 | 60,294 | 15m22s |
| 2019-08 | 57,864 | 8m36s |
| 2019-09 | 52,626 | 12m44s |
| 2019-10 | 60,654 | 3m52s |
| 2019-11 | 55,538 | 2m35s |
| 2019-12 | 58,342 | 3m36s |
| 2020-01 | 45,420 | 3m27s |
| 2020-02 | 53,520 | 3m19s |
| 2020-03 | 58,992 | 3m43s |
| 2020-04 | 53,838 | 3m28s |
| 2020-05 | 53,896 | 4m17s |
| 2020-06 | 59,428 | 3m49s |
| 2020-07 | 62,448 | 3m47s |
| 2020-08 | 57,084 | 4m09s |
| 2020-09 | 57,202 | 4m06s |
| 2020-10 | 60,100 | 4m10s |
| 2020-11 | 57,552 | 3m38s |
| 2020-12 | 63,234 | 4m51s |
| 2021-01 | 55,388 | 4m50s |
| 2021-02 | 41,654 | 3m54s |
| 2021-03 | 63,942 | 5m27s |
| 2021-04 | 55,746 | 5m19s |
| 2021-05 | 55,846 | 4m49s |
| 2021-06 | 61,552 | 5m04s |
| 2021-07 | 61,710 | 5m21s |
| 2021-08 | 61,912 | 5m29s |
| 2021-09 | 56,420 | 6m06s |
| 2021-10 | 59,304 | 6m48s |
| 2021-11 | 62,138 | 6m34s |
| 2021-12 | 65,230 | 6m44s |
| 2022-01 | 54,048 | 6m39s |
| 2022-02 | 45,604 | 5m39s |
| 2022-03 | 65,628 | 6m47s |
| 2022-04 | 57,104 | 6m12s |
| 2022-05 | 57,194 | 5m55s |
| 2022-06 | 63,036 | 6m23s |
| 2022-07 | 60,190 | 5m47s |
| 2022-08 | 66,098 | 6m24s |
| 2022-09 | 57,492 | 6m01s |
| 2022-10 | 60,420 | 6m06s |
| 2022-11 | 63,356 | 6m37s |
| 2022-12 | 63,422 | 5m29s |
| 2023-01 | 46,226 | 5m17s |
| 2023-02 | 57,838 | 5m21s |
| 2023-03 | 66,516 | 5m43s |
| 2023-04 | 57,806 | 5m41s |
| 2023-05 | 57,714 | 5m39s |
| 2023-06 | 63,614 | 6m05s |
| 2023-07 | 60,730 | 7m34s |
| 2023-08 | 66,570 | 6m33s |
| 2023-09 | 55,058 | 6m23s |
| 2023-10 | 63,788 | 5m54s |
| 2023-11 | 63,864 | 5m48s |
| 2023-12 | 60,994 | 6m12s |
| 2024-01 | 64,052 | 5m54s |
| 2024-02 | 46,674 | 5m39s |
| 2024-03 | 61,254 | 6m06s |
| 2024-04 | 55,442 | 5m55s |
| 2024-05 | 64,046 | 10m32s |
| 2024-06 | 58,356 | 10m18s |
| 2024-07 | 67,234 | 8m03s |
| 2024-08 | 64,438 | 8m41s |
| 2024-09 | 55,662 | 8m44s |
| 2024-10 | 67,510 | 8m45s |
| 2024-11 | 61,724 | 7m45s |
| 2024-12 | 64,762 | 7m47s |
| 2025-01 | 50,132 | 7m44s |
| 2025-02 | 59,002 | 7m51s |
| 2025-03 | 61,980 | 8m05s |
| 2025-04 | 59,072 | 8m23s |
| 2025-05 | 59,106 | 7m30s |
| 2025-06 | 62,148 | 9m14s |
| 2025-07 | 68,080 | 9m02s |
| 2025-08 | 62,310 | 8m23s |
| 2025-09 | 59,400 | 8m33s |
| 2025-10 | 68,374 | 7m58s |
| 2025-11 | 59,648 | 7m55s |
| 2025-12 | 68,670 | 8m31s |
| 2026-01 | 59,844 | 10m15s |
| 2026-02 | 45,044 | 9m09s |
| 2026-03 | 66,084 | 7m49s |
| 2026-04 | 60,116 | 5m19s |
| 2026-05 | 60,198 | 5m18s |
| 2026-06 | 66,318 | 22m31s |

Migration 109 narrows the temporary payload-row table to source rows referenced
by eligible bars that have VNDIRECT or BSC price-limit observations. It still
expands each verified landing once and retains the downstream digest,
byte/JSON, exact-row, and limit-evidence checks. Migration 109 and its SHA-256
are registered on the report clone. Its migration assertions and
`phase2_execution_weight_batch_assertions.sql` passed there. The fresh
two-pass migration harness, Go test/race/vet, 47 Python tests, and Rust
format/workspace tests/Clippy also passed; see the
[post-109 acceptance checkpoint](evidence/phase2/phase2_acceptance_checkpoint_20261101.md).
The build is complete, but Phase 2 remains open because its PIT fundamentals,
E4 continuity, quarantined execution weights, and current-tree hosted CI gates
are unresolved. Suggestions remain disabled.

## 2026-11-02 — continue primary-source review for GDW's E4 gap

Historical checkpoint before the later HNX Notice 1385/TB-SGDHN capture.
The result below is superseded by the current status at the top of this file
and the linked GDW endpoint capture packet.

- Capture the official VSDC record for GDW's registration/depository-data
  transfer from UPCoM to HNX effective 2018-12-11, and HNX exact-date UPCoM
  daily reports for December 6, 7, 10, and 11. On December 6, the report
  returns GDW with total-market volume zero; on December 7, 10, and 11, it
  returns no GDW row. The VSDC notice does not state the final UPCoM trading
  date or cancellation-effective date, and an absent HNX row does not establish
  a session status. No event was imported. E4 remains PARTIAL.
- The latest acceptance matrix is
  `evidence/phase2/phase2_acceptance_checkpoint_20261102.md`; raw source
  responses, hashes, and the reproducible capture script are linked from
  `evidence/phase2/phase2_e4_remaining_gap_probe_20261031/gdw_primary_source_gap_20261031/README.md`.
- Phase 2 remains OPEN: E4's prior-venue endpoint, 225 quarantined 2019-01-02
  execution weights, and hosted CI for the exact candidate tree remain
  unresolved. Suggestions remain disabled.

## 2026-11-01 — preflight durable fundamental job states

The VCI fundamental batch preflight now reads each requested job's durable
state before creating the pacer. Completed and partial jobs are skipped;
pending jobs and leases older than the 15-minute reservation window count as
resumable; blocked jobs, active leases, and unknown states reject the batch
before any market-data request. `go -C go test ./...`, `go -C go vet ./...`,
and all 47 Python tests pass. Evidence:
`evidence/phase2/phase2_20261101_fundamental_jobstate_preflight_go_test.log`,
`phase2_20261101_fundamental_error_diagnostics_go_vet.log`, and
`phase2_20261101_fundamental_jobstate_preflight_python_unittest.log`.

This is an offline safety fix only; it does not close Phase 2. The PIT
fundamentals sample, primary-source E4 continuity, 225 quarantined execution
weights, and hosted CI for the candidate tree remain open. Suggestions remain
disabled.

## 2026-11-01 — resume PIT archive batches and fix the one-call pacer

- The first quarterly income batch committed VIC and then reported
  `daily API-call budget exhausted`. The durable PostgreSQL guard still had
  3,547 available calls; the command had hard-coded its in-memory pacer to one
  call. Fix the runner to count unfinished idempotent jobs and compare them
  with the fresh durable guard before creating a batch-sized pacer. If quota
  cannot cover the whole unfinished batch, it now stops before any market-data
  request. Add regression checks for full-batch admission and insufficient
  quota preflight.
- With the installed Python 3.12 environment, `go -C go test ./...`,
  `go -C go vet ./...`, and all 47 Python unit tests pass after the change.
  Evidence: `evidence/phase2/phase2_20261101_fundamental_batchfix_go_test_final2.log`,
  `phase2_20261101_fundamental_error_diagnostics_go_vet.log`, and
  `phase2_20261101_fundamental_batchfix_python_unittest_final.log`.
- Resume the VCI archive through the audited Go `Gateway.CallRecorded` route,
  with fresh absolute-quota verification and durable reservations, targeting
  only disposable clone `vnsignal_phase2_report_20261019`. In total, 78
  additional quarterly/annual statement calls are committed for the 13-symbol
  L1/L2 sample. The post-backfill census has 10,240 archive-managed rows for 15
  symbols, 10,296 observations, and 91 raw landings. Availability-contract and
  observation-lineage audits each report zero violations.
- PIT remains PARTIAL: the sample covers 15 of 1,518 symbols, the approved
  line-item and industry maps are empty, and `feat.fundamental_features_daily`
  remains empty. Do not enable the overlay or infer historical publication
  dates. The refreshed report is
  `evidence/phase2/phase2_fundamentals_pit_coverage_20261101.md`.
- Phase 2 remains OPEN: GDW's seven-session E4 interval has no primary
  endpoint evidence; 225 execution weights remain quarantined for conflicting
  BSC closes; and hosted CI does not include the current candidate tree.
  Suggestions remain disabled. See the updated
  `evidence/phase2/phase2_acceptance_checkpoint_20261102.md`.

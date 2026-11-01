# TIE and LCM transfer source and import packet — 2026-10-31

## Outcome

The source reconciliation and guarded import close the TIE and LCM intervals
in the current V3 feature-set census. Both transfers passed
`ops.phase2_verified_security_transfers` in the disposable report clone
`vnsignal_phase2_report_20261019` as events 290 (TIE) and 291 (LCM). A replay
inserted no duplicate raw landings or events. No price bars, source-archive
rows, features, labels, or missing-session statuses were added or changed.

The date fields deliberately distinguish an observed prior endpoint, the
prior-venue cessation boundary, and the first trading date on the new venue.
They do not classify activity on every missing session.

## TIE — HOSE to UPCoM

- Official HNX article 60005646 says TIE was delisted from HOSE effective
  2019-08-01 and began UPCoM trading on 2019-08-09. Signed HNX Notice
  872/TB-SGDHN and the current official HNX UPCoM profile corroborate the
  first UPCoM date and 9,569,900 shares.
- The event stores 2019-07-31 as `prior_trade_date` because the disposable
  clone has a positive-volume VCI bar on that date and it is the effective
  session immediately before the official 2019-08-01 cessation date. The HNX
  article does not itself state that July 31 was the final HOSE trading day.
- A conflicting HOSE daily recap reverses the delisting and final-trading
  chronology. It was retained as a conflict, not used to override the HNX
  article and signed HNX endpoint notice.

## LCM — HOSE to UPCoM

- Signed HOSE Decision 520/QD-SGDHCM, dated 2022-07-28, states the final HOSE
  trading day was 2022-08-26, delisting was effective 2022-08-29, and the
  delisted quantity was 24,633,000 shares. The signed PDF was captured from a
  Vietstock mirror; its identity and quantity are corroborated by the signed
  HNX Notice 2754/TB-SGDHN and official VSDC Notice 152362.
- Signed HNX Notice 2754/TB-SGDHN and the current official HNX profile state
  the first UPCoM trading day was 2022-09-09 and report 24,633,000 shares.
- VSDC Notice 152362 records the HOSE-to-UPCoM registration-data transfer
  effective 2022-08-31. That administrative transfer date is retained as a
  separate milestone, not substituted for the first trading day.
- The HOSE daily recap that reports 34,633,000 shares conflicts with the
  signed HOSE decision, signed HNX notice, and VSDC notice; it is not used for
  the transfer event.

## Guarded import and replay

`import_tie_lcm_transfers_reportclone_20261031.sql` validates the disposable
database target, source payload hashes and metadata, exact V3 feature-row
endpoints, positive VCI prior bars, the effective-session boundary, absence of
intervening traded bars, and the strict verified-transfer view. The first
execution inserted four immutable endpoint landings and two transfer events.
The retained replay log shows `INSERT 0 0` for both landing and event inserts
and returns events 290 and 291 with their pinned endpoint hashes.

The stage manifest records the capture-manifest hashes and SHA-256 hashes of
all three stage CSVs. Source-review rows include the exact claim, source URL,
local filename, source attribution, page review, and limitations.

## Files

- `capture_manifest_tie_lcm_20261031.json` — HTTP capture times, URLs,
  response metadata, hashes, and failed HOSE annual-report fetches.
- `../capture_tie_lcm_primary_sources_20261031.py` and
  `../capture_lcm_hose_decision_20261031.py` — capture procedures.
- `hnx_tie_transition_article_60005646.html`, `hnx_tie_upcom_profile.html`,
  `hnx_lcm_upcom_profile.html`, and `vsdc_lcm_transfer_notice_152362.html` —
  official HNX/VSDC HTML records.
- `../tie_notice_conflict_capture_20261031/hnx_tie_attachment_01.pdf` — signed
  HNX Notice 872/TB-SGDHN.
- `../hose_upcom_transfer_batch10_capture_20261031_retry1/hnx_lcm_attachment_01.pdf`
  — signed HNX Notice 2754/TB-SGDHN.
- `../lcm_hose_decision_capture_20261031_retry1/hose_decision_520_qd_sgdhcm_lcm.pdf`
  — signed HOSE Decision 520/QD-SGDHCM from the recorded mirror URL.
- `landing_stage_tie_lcm_20261031.csv`,
  `transfer_event_stage_tie_lcm_20261031.csv`, and
  `source_review_tie_lcm_20261031.csv` — sealed stage and review data.
- `stage_manifest_tie_lcm_20261031.json` — stage file hashes and date
  semantics.
- `../import_tie_lcm_transfers_reportclone_20261031.sql` and
  `import_tie_lcm_transfers_reportclone_20261031_replay.log` — guarded import
  and idempotent replay evidence.
- `../../../../../tmp/pdfs/tie_source_review_20261031/hnx_tie_notice_page1.png`,
  `../../../../../tmp/pdfs/lcm_transfer_source_review_20261031/hnx_lcm_notice_page1.png`,
  and `../../../../../tmp/pdfs/lcm_hose_decision_review_20261031/decision_520_page-{1,2}.png`
  — rendered pages visually reviewed during source checking.

See the [refreshed current-hash E4 report](../../phase2_e4_currenthash_posttielcm1_20261031.md)
for the census after these imports. GDW remains the one unresolved non-lifecycle
interval; this packet does not resolve or alter GDW.

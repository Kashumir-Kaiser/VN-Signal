# ASG HNX-to-HOSE transfer evidence — 2026-10-31

## Result

The current V3 feature gap for ASG is 2021-09-21 to 2021-09-27, covering three
effective sessions, with no intervening feature rows, daily bars, or source
rows. The official signed endpoint notices agree on 75,653,891 shares:

- HNX Notice 2884/TB-SGDHN, dated 2021-09-15, states that 2021-09-21 was
  ASG's final HNX trading day and that 75,653,891 shares were transferred back
  to HOSE. The captured PDF is
  [hnx_asg_transfer_notice_401910.pdf](hnx_asg_transfer_notice_401910.pdf).
- HOSE Notice 1675/TB-SGDHCM, dated 2021-09-20, states that ASG's first HOSE
  trading day was 2021-09-27 and lists the same 75,653,891 shares. The captured
  PDF is [hose_asg_first_trade_1483519.pdf](hose_asg_first_trade_1483519.pdf).

The event records `prior_ceased_from=2021-09-22`, the first effective exchange
session after the signed final HNX trading date. Neither notice states a
separate legal cancellation-effective date. This boundary is derived from the
source-stated final trading day and the effective-session calendar; it does
not assert a statutory delisting date or infer a trade, suspension, or other
session-level status during the gap.

Event 288 passed `ops.phase2_verified_security_transfers` in the disposable
report clone. The first import committed two immutable signed-document
landings and one transfer event. The exact replay inserted zero duplicate
landings or events and passed the same strict-view assertion. No bars, source
rows, features, labels, or per-session statuses were written.

## Capture and review

The [packet evidence manifest](evidence_manifest_asg_20261031.json) records
byte counts and SHA-256 hashes for the captured source material, stage files,
import/replay logs, rendered review pages, and post-import census evidence.

The capture scripts preserve official HNX and HOSE article details, attachment
listings, signed PDFs, actual HTTP completion timestamps, byte counts, and
SHA-256 hashes:

- [HNX record and archive discovery manifest](capture_manifest_asg_20261031.json)
- [HOSE first-trade capture manifest](hose_first_trade_capture_manifest_asg_20261031.json)
- [staged source rows](landing_stage_asg_20261031.csv)
- [staged transfer event](transfer_event_stage_asg_20261031.csv)
- [stage manifest](stage_manifest_asg_20261031.json)
- [guarded report-clone importer](import_asg_transfer_reportclone_20261031.sql)
- [first import log](import_asg_transfer_reportclone_20261031.log)
- [idempotent replay log](replay_asg_transfer_reportclone_20261031.log)

Both one-page PDFs were rendered and visually reviewed. The HNX notice has an
HNX seal and signature; the HOSE notice carries its signed approval block.
Rendered review images are in `tmp/pdfs/asg_second_transfer_source_review_20261031/`.

## Current E4 census after ASG

The current-hash census has 221 gaps / 3,225 missing effective sessions, 216
strictly verified transfers / 1,519 sessions, and five intervals / 1,706
sessions without a strict transfer match. CTR and PTM remain separately
supported lifecycle cases (two intervals / 1,686 sessions). Three
non-CTR/PTM intervals / 20 sessions remain unresolved: GDW, TIE, and LCM.
TIE remains held for conflicting source chronology; LCM remains held for a
share-count conflict. No daily source rows occur inside the census gaps.

See the [post-ASG current-hash report](../../phase2_e4_currenthash_postasg1_20261031.md),
[gap census SQL](../../phase2_e4_currenthash_gap_pairs_20261031_postasg1.sql),
[gap census CSV](../../phase2_e4_currenthash_gap_pairs_20261031_postasg1.csv),
[endpoint-semantics audit CSV](../../phase2_e4_feature_endpoint_semantics_20261031_postasg1.csv),
and [run logs](../../phase2_e4_currenthash_gap_pairs_20261031_postasg1.log).
E4 remains **PARTIAL**; Phase 2 remains **OPEN** and suggestions remain
disabled.

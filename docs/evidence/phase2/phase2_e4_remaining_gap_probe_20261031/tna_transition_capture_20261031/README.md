# TNA HOSE-to-UPCoM endpoint packet — 2026-10-31

## Reviewed source facts

The V3 current-hash census identifies a feature-row interval from 2024-11-18
to 2024-11-29, with eight missing effective sessions and no intervening bar or
source rows. The signed sources keep four dates distinct:

| Fact | Date | Primary record |
| --- | --- | --- |
| Final HOSE trading date | 2024-09-13 | HOSE Decision 619/QD-SGDHCM and Notice 1903/TB-SGDHCM |
| Trading suspension effective | 2024-09-16 | HOSE Decision 619/QD-SGDHCM and Notice 1903/TB-SGDHCM |
| HOSE delisting effective | 2024-11-19 | HOSE Decision 619/QD-SGDHCM and Notice 1903/TB-SGDHCM |
| First UPCoM trading session | 2024-11-29 | HNX Notice 5064/TB-SGDHN |

All three signed notices report 49,576,264 shares. The HOSE decision was
published through [official HOSE article 1724218](https://api.hsx.vn/n/api/v1/1/news/1724218)
and its captured attachment metadata. The HNX notice is linked from official
HNX disclosure article 60019952, published on 2024-11-22.

The import represents the prior listing's legal cessation on 2024-11-19. It
does not replace that with the earlier final trade date or suspension date,
and it does not classify any individual session as suspended or no-trade.

## Captures and review

`capture_tna_official_endpoints_20261031.py` captures the official HOSE article
metadata, attachment listings, both signed HOSE PDFs, the HNX article detail
and signed attachment, and the current HNX UPCoM profile. The HNX profile is
supporting evidence only; the transfer's continuity endpoint is the signed
first-trade PDF. Every response has an actual HTTP timestamp, byte count, and
SHA-256 in [capture_manifest_tna_20261031.json](capture_manifest_tna_20261031.json).

All four signed-document pages were rendered and visually reviewed. The exact
facts and roles are recorded in [source_review_tna_20261031.csv](source_review_tna_20261031.csv).

## Stage and disposable-clone import

The stage builder
`../prepare_tna_transition_stage_20261031.py` verifies the source hashes and
the current-hash TNA gap before writing the two-row landing stage and one-row
event stage. The guarded SQL importer
[import_tna_transfer_reportclone_20261031.sql](import_tna_transfer_reportclone_20261031.sql)
refuses any database other than `vnsignal_phase2_report_20261019` and checks
the feature hash, exact gap dates, source hashes, endpoint claims, and session
count.

The initial import transaction inserted two raw landings and one transfer
event; strict verification passed. The replay inserted zero duplicate
landings and zero duplicate events, rechecked the strict view, and committed.
The first capture-stage attempt was rejected by the source-validation trigger
because a signed HNX notice used a metadata key reserved for HNX profile
captures. That transaction was rolled back; the corrected stage uses the
generic `first_trade_date` field and the retry passed. Logs:

- [Initial successful import](import_tna_transfer_reportclone_20261031.log)
- [Rejected and rolled-back attempt](import_tna_transfer_reportclone_attempt1_20261031.log)
- [Successful retry](import_tna_transfer_reportclone_retry1_20261031.log)
- [Idempotent replay](replay_tna_transfer_reportclone_20261031.log)

No bars, daily source rows, feature rows, labels, or per-session statuses were
changed.

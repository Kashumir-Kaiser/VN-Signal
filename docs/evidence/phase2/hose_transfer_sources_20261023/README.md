# Archived HNX-to-HOSE source records (2021)

This packet contains the downloaded source response for the HNX cohort announcement and the HOSE first-trading-day notice PDF for every E4 transfer candidate. `manifest.csv` records document date, ticker, first HOSE date, direct source URL, context page where available, retrieval timestamp (UTC), byte length, MIME type, and SHA-256 of the saved bytes.

## Date findings

The HNX exchange notice establishes 2021-08-27 as the cohort's last HNX trading day. The ticker-specific HOSE notices give these first trading dates:

| Ticker | Last HNX day | First HOSE day | E4 missing effective sessions in the interval |
|---|---|---|---:|
| ABT | 2021-08-27 | 2021-09-06 | 3 |
| BSI | 2021-08-27 | 2021-09-06 | 3 |
| DXS | 2021-08-27 | 2021-09-06 | 3 |
| HAP | 2021-08-27 | 2021-09-06 | 3 |
| KHG | 2021-08-27 | 2021-09-06 | 3 |
| LAF | 2021-08-27 | 2021-09-06 | 3 |
| NSC | 2021-08-27 | 2021-09-06 | 3 |
| PAN | 2021-08-27 | 2021-09-07 | 4 |
| QBS | 2021-08-27 | 2021-09-06 | 3 |
| SSC | 2021-08-27 | 2021-09-06 | 3 |
| TVB | 2021-08-27 | 2021-09-06 | 3 |
| VFG | 2021-08-27 | 2021-09-06 | 3 |
| VND | 2021-08-27 | 2021-09-06 | 3 |

All 13 first-day records are ticker-specific HOSE notices. Most are signed HOSE PDFs served from the CafeF disclosure attachment CDN; the saved bytes are the PDFs themselves, not search-result snippets. DXS is saved from the issuer-hosted HOSE notice. ABT, BSI, VND are HOSE notices in English PDF copies. The PAN date is independently reflected by its notice: it is the only first HOSE day of 2021-09-07, accounting for its additional 2021-09-06 missing session.

Paired exchange dates explain the exact gap windows by transfer lifecycle context. The 12 September 6 first-day notices cover Aug 30, Aug 31, and Sep 1; PAN's September 7 notice additionally covers Sep 6. This establishes the specific event context for these 40 candidate sessions; it does not convert zero-volume observations into suspensions.

## E4 / database disposition

At the initial source-preparation checkpoint, no database writes were made.
The E4 report then showed these 40 sessions in 13 intervals as unresolved;
archiving source bytes alone did not classify them. The later 2026-10-25
transfer-event import and targeted verification are recorded below.

The integrity-gap source files are `../phase2_integrity_gap_attribution_20261022.sql` and `../phase2_integrity_gap_attribution_20261022.csv`. Lifecycle evidence must use intact ticker-matched `security_lifecycle_notice` landings, as enforced by migrations 007 and 057.

## File-backed report-clone import preparation

`landing_stage.csv` is generated from the archived originals and contains their original bytes in hexadecimal alongside the manifest identity fields. Decoding back to the original bytes was rechecked against all 14 manifest SHA-256 values and byte counts. Hex encoding prevents a key-shaped sequence in base64 text from triggering a false positive in secret scanning; archived bytes and hashes are unchanged. `import_hose_transfer_landings_reportclone.sql` is a psql script guarded to `vnsignal_phase2_report_20261019`; it also embeds each expected source URL, local filename, and hash so a changed staging file fails before insertion. It imports raw landing records only and is idempotent for an already present matching source/hash.

### 2026-10-31 secret-scan verification

The warning reported for this file was reproduced in historical commit
`68f44cb60f2f`: exactly one Google-key-shaped match occurred inside the valid
Base64 `body_b64` field for the NSC CafeF notice PDF. The encoded field decodes
to 710,412 bytes with SHA-256
`5641fbcac616bcbdef1623912bc5cee2e24fc79a64e9072981256f98c4d27139`. The
current `body_hex` field decodes to the same byte count and hash, and the
current CSV has no `AIza` substring. This is an encoding false positive, not
an API credential. The historical commit remains reachable, so the hosted
alert may still need to be dismissed as a false positive; this local review
did not change the alert or rewrite repository history.

The HNX cohort document is staged with a null ticker because it describes a group, not a ticker-specific security. The 13 HOSE first-day PDFs retain their exact manifest URL and the identified carrier (`vietstock`, `issuer`, or `cafef`) in landing metadata. No lifecycle intervals are inserted: the current `TRADING_SUSPENDED` type would assert suspension semantics that these transfer notices do not establish. In particular, the cohort document must not be turned into lifecycle evidence for all 13 symbols. No database connection or execution was performed while preparing these files.

## Verified report-clone import — 2026-10-24

The preparation-only statements above describe the initial research checkpoint. The guarded importer has since executed on `vnsignal_phase2_report_20261019`: the first attempt failed its null-ticker validation and rolled back (`../hose_transfer_import_20261024.log`). After correcting the null-safe cohort check, all14 source landings committed (`../hose_transfer_import_20261024_retry.log`); an immediate repeat committed zero additional records (`../hose_transfer_import_20261024_repeat.log`). Original bytes, checksums, sizes, and source identities passed the importer validation. No lifecycle events, bars, or transfer classifications were created. The null-ticker cohort document remains group-level evidence, not independent ticker-specific evidence.

## 2026-10-25 follow-up — exact cohort membership prepared

All 13 ticker-specific PDFs were fetched again through HTTPS. Each response
matched the original manifest's byte count and SHA-256; the check is recorded
in [`https_revalidation_20261025.csv`](https_revalidation_20261025.csv). This
allows a TLS-addressed raw landing for the nine CafeF attachments first
captured through HTTP, while retaining the original landing and bytes.

[`hnx_cohort_membership_stage.csv`](hnx_cohort_membership_stage.csv) preserves
the exact HNX HTML table row for each of the 13 symbols. The row snippets were
verified as exact UTF-8 substrings of the archived HNX file and remain anchored
to its SHA-256. Migration 085 adds an append-only per-symbol membership record
and permits it only as the continuity endpoint of an HNX-to-HOSE transfer.
[`import_hose_transfer_events_reportclone.sql`](import_hose_transfer_events_reportclone.sql)
is guarded to the disposable report clone and uses the verified landing hashes.
Migrations 080 and 085 were applied directly to the report clone because its
Go migration ledger has earlier checksum/name drift; the ledger was left
unchanged. The imports committed nine new HTTPS-addressed HOSE landings, 13
exact HNX row-membership links, and 13 HNX-to-HOSE transfer events. The guarded
importer SHA, size, identity, and endpoint checks passed. A read-only
verification matched all 13 events to V3 feature gaps from 2021-08-27 through
their first HOSE dates, covering 40 effective sessions total, with zero daily
bar or bar-source rows inside those gaps. This records venue context only; it
does not establish suspension, synthesize bars, or create labels. See the
[migration 085 application log](../phase2_migration_085_apply_reportclone_20261025.log),
[import log](hose_transfer_import_20261025.log), and
[targeted verification](../phase2_e4_hose_transfer_verify_20261025_retry.log).
The updated hex-stage importer was then replayed idempotently: all payload
checksums passed and it inserted zero additional landings, memberships, or
transfer events ([replay log](hose_transfer_import_20261025_hex_replay.log)).

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

No DB writes were made, as instructed. The current E4 SQL report still shows these 40 sessions in 13 intervals as unresolved. The prepared SQL archives source bytes only; it does not classify sessions. A lifecycle classification remains blocked until the project defines an audited event type for transfer/no-venue intervals and validates its effect on E4.

The integrity-gap source files are `../phase2_integrity_gap_attribution_20261022.sql` and `../phase2_integrity_gap_attribution_20261022.csv`. Lifecycle evidence must use intact ticker-matched `security_lifecycle_notice` landings, as enforced by migrations 007 and 057.

## File-backed report-clone import preparation

`landing_stage.csv` is generated from the archived originals and contains their original bytes in base64 alongside the manifest identity fields. Its decoded bytes were rechecked against all 14 manifest SHA-256 values and byte counts. `import_hose_transfer_landings_reportclone.sql` is a psql script guarded to `vnsignal_phase2_report_20261019`; it also embeds each expected source URL, local filename, and hash so a changed staging file fails before insertion. It imports raw landing records only and is idempotent for an already present matching source/hash.

The HNX cohort document is staged with a null ticker because it describes a group, not a ticker-specific security. The 13 HOSE first-day PDFs retain their exact manifest URL and the identified carrier (`vietstock`, `issuer`, or `cafef`) in landing metadata. No lifecycle intervals are inserted: the current `TRADING_SUSPENDED` type would assert suspension semantics that these transfer notices do not establish. In particular, the cohort document must not be turned into lifecycle evidence for all 13 symbols. No database connection or execution was performed while preparing these files.

## Verified report-clone import — 2026-10-24

The preparation-only statements above describe the initial research checkpoint. The guarded importer has since executed on `vnsignal_phase2_report_20261019`: the first attempt failed its null-ticker validation and rolled back (`../hose_transfer_import_20261024.log`). After correcting the null-safe cohort check, all14 source landings committed (`../hose_transfer_import_20261024_retry.log`); an immediate repeat committed zero additional records (`../hose_transfer_import_20261024_repeat.log`). Original bytes, checksums, sizes, and source identities passed the importer validation. No lifecycle events, bars, or transfer classifications were created. The null-ticker cohort document remains group-level evidence, not independent ticker-specific evidence.

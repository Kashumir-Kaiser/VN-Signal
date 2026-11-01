# Batch 12 HOSE-to-UPCoM signed endpoint packet — 2026-10-31

## Scope and source review

This packet covers the six exact current-hash feature gaps for DAG, HTT, ITA,
LEC, SJF, and TCD. Each gap had zero intervening bar rows and zero daily source
rows. The source set contains the official HOSE decision and corroborating
notice, plus the official HNX first-trading notice for each symbol. The HNX
index and article detail are retained as discovery and attachment provenance;
the signed HNX notice is the continuity endpoint.

The [capture manifest](capture_manifest_batch12_signed_endpoints_20261031.json)
records 48 HTTP responses with actual UTC timestamps, response sizes, official
URLs, and SHA-256 hashes. It links the source article metadata to each signed
PDF. All 24 pages across the 18 signed PDFs were rendered and visually
reviewed; issuer/ticker, dates, share counts, signatures, and exchange seals
were checked. The review notes and PDF hashes are in
[source_review_batch12_20261031.csv](source_review_batch12_20261031.csv).
The HNX index title for TCD spells the issuer type as “CTPC”; its signed
attachment correctly identifies CTCP Tập đoàn Xây dựng Tracodi, ticker TCD,
the registered share count, and first-trade date. The signed notice, rather
than the index-title spelling, is the continuity source.

| Symbol | HOSE decision / notice | Final trade | Suspension effective | Delisting effective | HNX first trade / notice article | Shares |
| --- | --- | --- | --- | --- | --- | ---: |
| DAG | 2024-10-15 / 2024-10-15 | 2024-08-14 | 2024-08-15 | 2024-10-22 | 2024-11-01 / 60019787 | 60,314,112 |
| HTT | 2020-06-11 / 2020-06-11 | 2020-05-21 | Not stated | 2020-06-18 | 2020-06-26 / 60008745 | 20,000,000 |
| ITA | 2025-01-21 / 2025-01-21 | 2024-09-25 | 2024-09-26 | 2025-02-04 | 2025-02-13 / 60020444 | 938,463,607 |
| LEC | 2025-04-23 / 2025-04-23 | 2024-09-13 | 2024-09-16 | 2025-04-29 | 2025-05-13 / 60021001 | 26,100,000 |
| SJF | 2024-10-25 / 2024-10-25 | 2023-11-10 | 2023-11-13 | 2024-11-01 | 2024-11-13 / 60019853 | 79,200,000 |
| TCD | 2026-07-08 / 2026-07-08 | 2025-10-09 | Not stated | 2026-07-15 | 2026-07-24 / 60023071 | 335,820,641 |

The feature-row intervals and their missing effective-session counts are
DAG 2024-10-21–2024-11-01 (8), HTT 2020-06-17–2020-06-26 (6), ITA
2025-02-03–2025-02-13 (7), LEC 2025-04-28–2025-05-13 (7), SJF
2024-10-31–2024-11-13 (8), and TCD 2026-07-14–2026-07-24 (7). The dates in
each event keep the final positive trade, suspension when explicitly stated,
legal delisting, and first new-venue trade separate. No individual missing
session is classified as suspended or untraded.

## Guarded import and verification

The stage builder
`../prepare_batch12_signed_endpoints_20261031.py` checks every captured PDF
against its response hash and checks each exact gap against the current V3
census before writing the landing/event stages. The stages contain 12 signed
endpoint landings and six transfer events. The importer
[import_batch12_transfer_reportclone_20261031.sql](import_batch12_transfer_reportclone_20261031.sql)
refuses a non-disposable database and rechecks the V3 feature hash, source
hashes and hosts, article IDs, all endpoint dates and share counts, effective
session counts, exact feature-row gaps, and absence of intervening bars/source
rows.

The import committed 12 immutable raw landings and six events. Events 276–281
pass `ops.phase2_verified_security_transfers` for their exact current-hash
intervals. The [idempotent replay](replay_batch12_transfer_reportclone_20261031.log)
inserted zero duplicate landings and zero duplicate events, rechecked all six
strict matches, and committed. The [import log](import_batch12_transfer_reportclone_20261031.log)
contains both transaction results.

No bars, source rows, feature rows, labels, or session statuses were added or
changed. See the [current E4 reconciliation](../../phase2_e4_currenthash_postbatch12_20261031.md),
[current gap census](../../phase2_e4_currenthash_gap_pairs_20261031_postbatch12.csv),
and [stage manifest](stage_manifest_batch12_20261031.json) for reproducible
counts and hashes.

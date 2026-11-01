# FPT VCI fundamental semantics evidence — 2026-10-24

Scope: read-only comparison of archived FPT VCI fundamental landings in `vnsignal_phase2_report_20261019` with official Vnstock documentation and FPT disclosures. No live vnstock routes or database writes were used. The bounded SQL and unedited `psql` output are adjacent as `phase2_fpt_fundamental_semantics_20261024.sql` and `.log`.

## Official-source capture

- FPT's public-disclosure page listed the audited consolidated 2025 financial statements as an official downloadable attachment. The legacy `/.../year-report/2026/march/20260319---fpt---audited-consolidated-financial-statements-for-2025.pdf` URL returned HTTP 404 on this host. The current official media endpoint succeeded: `https://fpt.com/api/media/20260319_FPT_Audited_Consolidated_Financial_Statements_for_2025_dd62a35162.pdf`.
- Captured the official PDF bytes at `2026-10-24T05:32:03.810Z` UTC to `source_fpt_audited_consolidated_financial_statements_2025.pdf`; size 7,827,790 bytes; SHA-256 `bb14bafff1a7849217f34cf4b50e0e3d69d91968f217a66d7c68f07d4c1af284`. Local `pdfinfo` recognizes a 73-page A4 PDF, version 1.6. The contents of this local copy were not text-extracted in this audit; see the indexed-only evidence section below.
- FPT's disclosure page is [Public Disclosure](https://fpt.com/en/ir/information-disclosures). It lists the audited 2025 statements (19 March 2026), 2025 Annual Report (8 April 2026), and interim statements.
- Official Vnstock v5 documentation: [Fundamental data access](https://www.vnstocks.com/docs/vnstock/co-ban-fundamental) states that `value` is according to the `unit` column, monetary values are in đồng, IDs are standardized VAS concepts, and the provider's VCI quarterly statement series returns each quarter separately. Its FPT annual example shows 2025 `IS_REVENUE=70,207,688,944,553`, deductions `-94,863,843,843`, and `IS_NET_REVENUE=70,112,825,100,710`, all `VNĐ`. The same page's FPT 2025 wide example includes gross profit `25,888,529,512,413`. The official [Fundamental output schema](https://vnstocks.com/docs/vnstock/vnstock-data-v3/cau-truc-du-lieu/fundamental) defines the long-row fields and gives absolute VND examples.

## Directly verified against the archived report clone

The SQL query reads only landings 9798, 9802 and 9803 and expands rows only from those three frames. All have SHA-256-valid raw bytes, `source=vci`, `symbol=FPT`, and provider attribution matching each requested statement route. The income frame 9798 and cash-flow frame 9803 both requested `period=quarter`; each contains eight quarters from 2024-Q3 through 2026-Q2. Landing 9802 is the matching balance-sheet frame. Their metadata, source IDs, names, units and the selected 2025 Q1–Q4 values are in the `.log` file.

For FPT 2025, the income rows are in VND and the reported quarterly values sum as follows:

| Provider ID | Observed VCI unit | Q1–Q4 sum, VND |
|---|---:|---:|
| `IS_REVENUE` | `VNĐ` | 70,207,688,944,553 |
| `IS_REVENUE_DEDUCTIONS` | `VNĐ` | -94,863,843,843 |
| `IS_NET_REVENUE` | `VNĐ` | 70,112,825,100,710 |
| `IS_GROSS_PROFIT` | `VNĐ` | 25,888,529,512,413 |
| `IS_OPERATING_PROFIT` | `VNĐ` | 12,951,675,964,776 |
| `IS_NET_PROFIT_AFTER_TAX` | `VNĐ` | 11,232,339,450,733 |
| `IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY` | `VNĐ` | 9,376,127,629,500 |

Landing 9803's `CF_NET_CASH_FLOWS_FROM_OPERATING_ACTIVITIES` Q1–Q4 sum to VND 10,136,043,915,911. Q1+Q2 operating cash flow is VND 1,683,573,278,329. Income `IS_NET_REVENUE` Q1+Q2 sums to VND 32,682,853,982,527; parent-attributable PAT Q1+Q2 sums to VND 4,431,763,974,648. The Q1–Q4 and Q1+Q2 figures are reproduced in the SQL log.

The observed VCI Q1–Q4 values are per-quarter amounts in this FPT frame: their sums reconcile to full-year statement totals, while Q1+Q2 revenue and operating cash flow reconcile to the issuer's six-month totals. This also matches Vnstock's documented quarterly convention. Monetary `value_multiplier=1` is verified for the compared FPT revenue and operating-cash-flow lines; this should not be generalized to other IDs, issuers, units, or versions without equivalent evidence.

## Source values available in official web text, but not locally extracted from the saved PDF

The official FPT PDF is archived and hash-recorded above. The exact 2025 consolidated income and cash-flow amounts below were present in the web search index for that same official FPT PDF, but this audit did not extract those pages from the saved bytes; treat these statement-value comparisons as source-index corroboration, not independent local PDF text verification:

- Form B 02–DN/HN, consolidated income statement, year ended 31 December, columns labelled 2025 VND / 2024 VND: net revenue VND 70,112,825,100,710; gross profit VND 25,888,529,512,413; net operating profit VND 12,951,675,964,776; profit after tax VND 11,232,339,450,734; parent shareholders' attributable profit VND 9,376,127,629,501.
- Form B 03–DN/HN, consolidated cash-flow statement, year ended 31 December: net cash inflows from operating activities VND 10,136,043,915,911.
- The independently captured official Vnstock FPT annual rows directly corroborate the `IS_REVENUE`, deductions, `IS_NET_REVENUE`, gross-profit values and VND unit shown above. The 1-VND differences in the database sums for total/parent PAT relative to indexed annual statement values are consistent with the raw float values' precision; do not claim exact reconciliation for these two fields.
- Search-index evidence for these official statement tables came from the FPT-issued PDF at the captured official media endpoint above. The PDF was not opened successfully through the web PDF renderer, so all content claims from the report other than data independently shown by Vnstock's own documentation remain labelled indexed-only.

## Consolidation-basis caveat

FPT's official 2025 consolidated-report note, as indexed from the same report, says the Group continued to consolidate FPT Telecom through 31 December 2025 and would apply the equity method from financial year 2026. FPT's official 9M2026 release says 2025 comparison figures in that analytical release were restated using the 2026 accounting method. Thus the VCI 2025 annual example and archived 2025 quarter rows represent the as-reported/full-consolidation basis; 2026 comparisons may be on an equity-method basis. Do not splice the two into a growth series without an explicit accounting-basis adjustment and publication-time treatment for any restatement. Because the note and later comparison figures were not extracted from local PDF bytes here, their wording is also indexed-only evidence: [audited report link](https://fpt.com/en/ir/information-disclosures), [FPT 9M2026 release](https://fpt.com/en/news/fpt-s-9-months-2026-revenue-and-pbt-increase-12-4-and-17-0).

## Mapping decision

No mapping is activated by this evidence note. FPT's observed labels and a successful FPT cross-check support these candidates for a separately reviewed VCI/FPT mapping contract: `IS_REVENUE`, `IS_REVENUE_DEDUCTIONS`, `IS_NET_REVENUE`, `IS_GROSS_PROFIT`, `IS_OPERATING_PROFIT`, and a deliberate choice between total `IS_NET_PROFIT_AFTER_TAX` and parent-attributable `IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY`. The overlay's “net profit” accounting basis must be explicitly decided. These FPT-only observations do not establish mappings for banks or other issuers. The report clone has zero active fundamental mappings and zero industry class mappings at audit time; see prior findings and migrations 034/038.

## Parent visual verification of archived bytes
The saved73-page PDF is scanned: pypdf extraction returned zero text on pages1..16 (phase2_fpt_audited_2025_pages1_16_extracted.txt). Parent rendered the original PDF and visually reviewed PDF pages12 and13 (printed pages9 and10), now retained as phase2_fpt_audited_2025_income_page12.png and phase2_fpt_audited_2025_cashflow_page13.png. These directly verify VND columns and the income/cash-flow amounts listed above: gross revenue70207688944553, net revenue70112825100710, gross profit25888529512413, operating profit12951675964776, total PAT11232339450734, parent PAT9376127629501, CFO10136043915911. The two quarter-summed PAT values differ from their audited annual amounts by1VND; preserve that actual discrepancy rather than claiming exact equality. This supersedes the indexed-only limitation for those statement-table amounts. The consolidation-basis note has not yet been visually reviewed and retains its separate indexed-only caveat. No mapping was activated.

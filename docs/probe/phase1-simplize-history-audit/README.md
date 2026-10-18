# HNX verification of three VNX negotiated-only dates

Retrieved 2026-10-19. A bounded public-history search surfaced three VNX
dates that were still unresolved in the archived issue reconciliation. Each
date was checked separately against HNX's official UPCoM daily report. The
HNX report, not the secondary history output, is the retained market evidence.

| Date | HNX matched volume/value | HNX negotiated volume/value | HNX total-market volume/value | Buy orders / shares | Sell orders / shares |
| --- | ---: | ---: | ---: | ---: | ---: |
| 2026-01-29 | 0 / 0 | 15,100 / 175,160,000 | 15,100 / 175,160,000 | 51 / 70,075 | 2 / 15,100 |
| 2026-01-30 | 0 / 0 | 4,900 / 56,840,000 | 4,900 / 56,840,000 | 36 / 75,519 | 1 / 4,900 |
| 2026-02-12 | 0 / 0 | 4,900 / 56,840,000 | 4,900 / 56,840,000 | 18 / 10,719 | 2 / 10,000 |

All requests returned HTTP 200 and exactly one VNX row for the exact date
filter. [`hnx-verification.csv` (local evidence file `hnx-verification.csv`; not published) records each component,
the exact filter, and response hash. The exact HNX HTML responses are in
[`hnx_raw/`](hnx_raw/). The first-pass parser selected total-market columns as
matched volume; that interpretation was corrected after the seven BSC
cross-checks. The original parsed rows remain append-only in the evidence
table, and migration 025 plus [`import_hnx_interpretations.sql`](import_hnx_interpretations.sql)
append the corrected components. The superseded [`build_hnx_import.py`](build_hnx_import.py)
and [`import_hnx_evidence.sql`](import_hnx_evidence.sql) now stop with a warning
so the first-pass interpretation cannot be reimported.

## Database effect

The three reports were appended to the local `vnsignal` database. The HNX
evidence count increased from 19 to 22, and a read-back verified the raw
SHA-256 values. The first-pass records incorrectly stored the total-market
amounts as matched volume. The corrected append-only interpretations show
zero matched volume/value and negotiated volumes of 15,100, 4,900, and 4,900;
the lifecycle view reports `VERIFIED_NEGOTIATED_ONLY`. These dates remain
positive market-activity evidence and are outside the 14,314 remaining
unresolved dates. They do not repair OHLCV bars or change the VCI quality
issues. Phase 1 remains PARTIAL.

## Secondary-source handling

The dates came from a temporary public-history lookup. Simplize's [terms of
use](https://simplize.vn/terms) describe its data as proprietary and restrict
copying or derivative products without written consent. No Simplize values
were imported into PostgreSQL or canonical bars, and none are used for ML.
The temporary local download remains untracked and must not be committed; the
shell rejected the cleanup command. The HNX report files and import manifest
are separate from that temporary output.

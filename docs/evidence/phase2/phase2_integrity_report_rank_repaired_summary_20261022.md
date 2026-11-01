# E4 integrity report after full rank repair — 2026-10-22

Target: disposable report clone `vnsignal_phase2_report_20261019`. The report
ran in 97 non-overlapping monthly, read-only transactions from 2018-10-01
through 2026-10-16. The complete output is
[`phase2_integrity_report_rank_repaired_monthly_20261022.log`](phase2_integrity_report_rank_repaired_monthly_20261022.log),
produced by
[`run_phase2_integrity_report_monthly_rank_repaired_20261022.ps1`](run_phase2_integrity_report_monthly_rank_repaired_20261022.ps1)
using [`the bounded SQL`](../../../sql/diagnostics/phase2_integrity_report_chunked.sql).

## Coverage, keys, calendar, and feature hash

| Check | Result |
| --- | ---: |
| V2 rows | 2,844,435 |
| V3 rows | 2,844,435 |
| V2 keys missing in V3 | 0 |
| V3 keys absent in V2 | 0 |
| V3 null-key rows | 0 |
| V3 duplicate symbol-date groups | 0 |
| V3 rows without an effective session | 0 |
| Adjacent V3 rows more than one effective session apart | 221 |
| Distinct V3 feature-set hashes | 1 |
| V3 rows with current feature-set hash | 2,844,435 |

The current V3 feature-set hash is
`f4d61dd5e75ed4df90d90f28234413b9af73541853b650b5327cc0dd8be2deb1`.
The detailed read-only attribution is in
[`the gap query`](phase2_integrity_gap_attribution_20261022.sql),
[`its CSV output`](phase2_integrity_gap_attribution_20261022.csv), and
[`its run log`](phase2_integrity_gap_attribution_20261022.log). It found 219
intervals with no daily bars and no `core.bars_daily_sources` rows across
1,539 missing effective sessions. No dated security observations cover those
intervals. Their cause cannot be distinguished as suspension or source gap.

The other two intervals are explained by ticker-matched lifecycle evidence.
PTM's 1,680-session gap falls inside its UPCoM delisting interval, ending the
day before trade eligibility resumes on 2025-08-22. CTR's six-session gap is
the documented transition from its final UPCoM session on 2022-02-14 to its
first HOSE session on 2022-02-23. Five VCI rows exist inside the CTR transition
in `core.bars_daily`, but none has a source-archive row or a feature row; their
OHLCV values repeat the final UPCoM bar and are classified as a VCI input
anomaly. Corrected evidence is in
[`the identifier-domain correction`](phase2_e4_id_domain_correction_20261022.md),
[`lifecycle source attribution`](phase2_lifecycle_source_attribution_20261022.csv),
and [`the CTR bar check`](phase2_ctr_lifecycle_bar_check_20261022.csv). The
prior KTL/TSB attribution and bar-check outputs are superseded. E4 remains
incomplete because 219 intervals have no source or lifecycle explanation.

## Rank checks

| Check | Result |
| --- | ---: |
| Uniform ranks outside `[0,1]` or non-finite | 0 |
| Gaussian ranks non-finite | 0 |
| Non-null rank values mapped to null inputs | 0 |
| Null rank values with non-null inputs | 0 |
| Non-null industry ranks without verified inputs | 0 |

Each of the six verified rank/input mappings has zero mismatches across all
monthly slices. The unverified industry rank remains NULL.

## Recorded rank-stage timings

The first monthly slice included all timing rows for build
`phase2-rank-repair-055-20261022` from `ops.step_runs`:

| Attempt status | Count | Duration |
| --- | ---: | ---: |
| Successful monthly ranges | 97 | 2,058,049 ms total; 17,668 ms median |
| Slowest successful range | 1 | 156,456 ms |
| Failed attempt retained in history | 1 | 139,483 ms |

The failed attempt was March 2025, cancelled while waiting on table reads. The
date-scoped retry completed in 36,354 ms and has the same output hash as the
stored completion record. Its failure remains in the audit history. The fresh
S2 read-only probe passed at exponents 0.359774 and 0.935869; see
[`the certificate`](phase2_rank_probe_phase2-rank-repair-055-20261022.json).

E4's coverage, keys, and rank checks pass. Lifecycle review explains two of the
221 session gaps; E4 as a whole remains incomplete until the remaining 219 are
reconciled against suspension or source records.

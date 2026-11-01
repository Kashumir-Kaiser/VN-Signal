# PIT fundamentals archive coverage — 2026-11-01, investable-set backfill

## Report-clone snapshot

The read-only census ran after the 2026-11-01 backfill against disposable
clone `vnsignal_phase2_report_20261019`. As of the latest V3 tier date,
2026-10-16, the current feature hash has 159 investable L1/L2 members (100
L1 and 59 L2). All 159 now have archived data for all six statement and
frequency combinations. The full V3 feature universe remains 1,518 symbols;
the 159 count is the exact current `is_investable_member` scope, not a claim
that the remaining symbols have been archived.

The PIT archive contains 114,293 archive-managed line-item versions,
114,349 append-only observations, and 955 VCI fundamental raw landings.
The 144 previously missing current investable symbols received 864 successful
statement calls across the six combinations. One income-quarter request for
DIG returned a safe `AdapterError`; its durable job was retried with a fresh
reservation and succeeded. Total job attempts are 956 for 955 completed jobs.

| Statement | Frequency | Row versions | Symbols | Symbol-periods | Period-end range |
| --- | --- | ---: | ---: | ---: | --- |
| Income statement | Quarter | 23,776 | 159 | 1,270 | 2024-09-30–2026-09-30 |
| Income statement | Year | 23,356 | 159 | 1,249 | 2018-12-31–2025-12-31 |
| Balance sheet | Quarter | 24,673 | 159 | 1,269 | 2024-09-30–2026-09-30 |
| Balance sheet | Year | 24,211 | 159 | 1,247 | 2018-12-31–2025-12-31 |
| Cash flow | Quarter | 9,219 | 159 | 1,269 | 2024-06-30–2026-09-30 |
| Cash flow | Year | 9,058 | 159 | 1,246 | 2018-12-31–2025-12-31 |

All live market-data requests used the Go runner's `Gateway.CallRecorded`
path, fresh absolute-quota verification, and durable PostgreSQL reservations.
The batch preflight rejects blocked or active jobs before dispatch and sizes
the pacer against the fresh remaining budget. Only the disposable report clone
was the database target; the registered `vnsignal` database was not modified.

## Availability and lineage checks

Every backfilled row uses the documented assumed availability lag: period end
+ 45 days for quarterly statements and +100 days for annual statements, at
midnight in `Asia/Ho_Chi_Minh`. None is marked as a restatement. The complete
read-only census found zero availability-contract violations, zero
same-availability duplicate groups, and zero missing or invalid
observation-to-landing lineage. The assumed lag is not evidence of an original
publication timestamp.

This closes the archive coverage gate for the 159 current investable L1/L2
members. It does not create a fundamental feature overlay. The line-item map,
industry-class map, and `feat.fundamental_features_daily` remain empty because
provider item semantics and accounting scales have not been source-verified.
No line-item or industry mappings were inferred; keep the overlay and model B
disabled until those mappings and model inputs are independently validated.

## Evidence

- Read-only archive, availability, duplicate-version, observation-lineage,
  mapping, and job census:
  [`SQL`](phase2_fundamentals_pit_postbackfill_census_20261101.sql) and
  [`investable-set captured output`](phase2_fundamentals_pit_investable_postbackfill_census_20261101.log).
- Exact current investable symbols and tier rank:
  [`scope SQL`](phase2_fundamental_current_investable_missing_20261101.sql)
  and [`144-symbol scope CSV`](phase2_fundamental_current_investable_missing_20261101.csv).
- Quarterly backfill results:
  [`income batch 1`](phase2_fundamental_backfill_l1l2_income_quarter_batch01_20261101.log),
  [`income batch 1 resume`](phase2_fundamental_backfill_l1l2_income_quarter_batch01_resume_20261101.log),
  [`income batch 2`](phase2_fundamental_backfill_l1l2_income_quarter_batch02_20261101.log),
  [`DIG retry`](phase2_fundamental_retry_DIG_income_quarter_20261101.log),
  [`balance batch 1`](phase2_fundamental_backfill_l1l2_balance_quarter_batch01_20261101.log),
  [`balance batch 2`](phase2_fundamental_backfill_l1l2_balance_quarter_batch02_20261101.log),
  [`cash-flow batch 1`](phase2_fundamental_backfill_l1l2_cashflow_quarter_batch01_20261101.log),
  and [`cash-flow batch 2`](phase2_fundamental_backfill_l1l2_cashflow_quarter_batch02_20261101.log).
- Annual backfill results:
  [`income batch 1`](phase2_fundamental_backfill_l1l2_income_year_batch01_20261101.log),
  [`income batch 2`](phase2_fundamental_backfill_l1l2_income_year_batch02_20261101.log),
  [`balance batch 1`](phase2_fundamental_backfill_l1l2_balance_year_batch01_20261101.log),
  [`balance batch 2`](phase2_fundamental_backfill_l1l2_balance_year_batch02_20261101.log),
  [`cash-flow batch 1`](phase2_fundamental_backfill_l1l2_cashflow_year_batch01_20261101.log),
  and [`cash-flow batch 2`](phase2_fundamental_backfill_l1l2_cashflow_year_batch02_20261101.log).
- Active capability evidence:
  [`quarterly statements`](fundamental_capability_20261101/2026-11-01.json)
  and [`annual statements`](fundamental_capability_year_20261101/2026-11-01.json).
- Backfill safety, response diagnostics, and current-tree tests:
  [`Go tests`](phase2_20261101_fundamental_jobstate_preflight_go_test.log),
  [`Go vet`](phase2_20261101_fundamental_error_diagnostics_go_vet.log),
  and [`Python tests`](phase2_20261101_fundamental_jobstate_preflight_python_unittest.log).
- Shared PIT coverage diagnostic:
  [`phase2_fundamentals_pit_coverage.sql`](../../../sql/diagnostics/phase2_fundamentals_pit_coverage.sql).

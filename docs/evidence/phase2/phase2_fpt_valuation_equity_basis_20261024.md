# FPT valuation equity basis audit — 2026-10-24

## Finding

Migration 038 uses one `net_profit`/`equity` mapping for both consolidated ratios and market-cap valuation. The SQL calculates TTM net profit, then uses it in ROE/ROA/accruals and also P/E; it uses current `equity` for P/B. P/E and P/B use listed shares / parent-company market value. For FPT, consolidated profit includes amounts attributable to non-controlling interests (NCI), while the share market cap represents listed FPT parent shares. The bases therefore do not match unless valuation inputs are parent-attributable.

## Archived row evidence

Read-only query of landing 9802 in `vnsignal_phase2_report_20261019`, limited to 2025-Q4, returned:

- `BS_EQUITY` — label `VỐN CHỦ SỞ HỮU`, VND 43,748,040,747,539.
- `BS_OWNERS_EQUITY` — label `VỐN VÀ CÁC QUỸ`, VND 43,745,290,747,539.
- `BS_TOTAL_LIABILITIES_AND_EQUITY` — label `TỔNG CỘNG NGUỒN VỐN`, VND 88,141,991,634,625.

The observed IDs do not directly provide an explicit parent-attributable book-equity or NCI line. `BS_OWNERS_EQUITY` is not evidence that NCI is excluded: its value is almost the same as `BS_EQUITY` and it is labelled as the broad capital/reserves section. Do not map either row to parent book value on its name alone.

The FPT 2025 audited consolidated statement’s note on movements in owners’ equity separately presents NCI: VND 7,265,096,802,767 at year-end and NCI net profit VND 1,856,211,821,233 for 2025. The income-statement attribution reports profit attributable to parent shareholders separately from total post-tax profit. These amounts establish materiality; they are not a substitute for the missing period-level parent equity row.

## Minimal safe contract

- Keep consolidated `net_profit` and `equity` available for group metrics only when their row semantics are verified. Consolidated total profit / total group equity can support consolidated ROE; total profit / group assets supports ROA; total profit with operating cash flow supports the stated accrual measure.
- Add a distinct parent-attributable profit input and TTM series (using the exact provider row `IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY` when validated). Use that for P/E against FPT parent listed-share market cap. Never substitute total `IS_NET_PROFIT_AFTER_TAX` for missing parent profit.
- Add a distinct parent-attributable equity input only after an explicit provider concept is verified to exclude NCI, or after both total equity and a same-scope, same-period NCI row are available and validated for subtraction. Current archived rows do not meet that contract; P/B must stay NULL. Never treat `BS_OWNERS_EQUITY` as parent equity merely from its English/Vietnamese label.
- If publishing parent ROE, compute it from parent-attributable TTM profit and average parent-attributable equity, separately from consolidated ROE.

## Code references

`sql/migrations/038_phase2_fundamental_features.sql`: mapping feature set lines 18–22; TTM construction lines 289–300; ROE/ROA/accrual inputs lines 377–385; P/E and P/B formulas lines 413–416.

## Sources

- FPT, [Audited Consolidated Financial Statements of 2025](https://fpt.com/api/media/20260319_FPT_Audited_Consolidated_Financial_Statements_for_2025_dd62a35162.pdf), official issuer PDF. Archived bytes: `source_fpt_audited_consolidated_financial_statements_2025.pdf`, SHA-256 `bb14bafff1a7849217f34cf4b50e0e3d69d91968f217a66d7c68f07d4c1af284` (captured 2026-10-24T05:32:03.810Z). NCI values above are from the report’s audited note on movements in owners’ equity.
- FPT, [Public Disclosure](https://fpt.com/en/ir/information-disclosures), lists the 2025 audited consolidated statements (updated 2026-03-19).
- FPT 2025 Annual Report, [audited-note NCI table](https://fpt.com/-/media/project/fpt-corporation/fpt/ir/information-disclosures/year-report/2026/april/20260408---fpt---annual-report-2025_web.pdf), reports NCI net profit and year-end NCI equity.

This is a read-only contract audit; no mapping was activated and no database or raw rows were changed.

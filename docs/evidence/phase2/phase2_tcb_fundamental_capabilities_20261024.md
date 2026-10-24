# TCB free-tier statement archive evidence

Three real quarterly TCB frames committed through the recorded Go gateway. The registered-machine capability reports verify the exact statement/frequency, and each returned frame independently passed ticker/source/route/period/row-type validation before its transactional archive. No raw worker market route or hosted CI was used.

`phase2_fundamental_tcb_quarter_verification_20261024.log` records 96 income rows, 144 balance rows and 56 cash-flow rows: 296 versions across eight quarterly periods, 2024-12-31 through 2026-09-30. Landings9808/9809/9810 pass exact byte checksum and stored JSON equality, their jobs are COMPLETED and their reservations SUCCEEDED. Backfill availability follows the explicit assumed45-day lag; the newest period is not thereby available before its lag date.

Actual bank IDs include IS_NET_INTEREST_INCOME, IS_NET_PROFIT_AFTER_TAX, IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY, BS_TOTAL_ASSETS, BS_TOTAL_LIABILITIES, BS_EQUITY and BS_MINORITY_INTEREST. Gross interest income and expense are not present in these free-tier frames. Their derived ratio cannot be populated from net interest income alone. No such input or financial value is fabricated.

`phase2_tcb_balance_identity_20261024.log` verifies on all eight archived quarterly dates that assets minus liabilities equals BS_EQUITY exactly in the stored numeric values. BS_MINORITY_INTEREST is separately nonzero. This supports the need to distinguish group equity from parent book equity; it does not itself approve a mapping or substitute for verifying the issuer accounting presentation. Current core industry codes are FPT9500 and TCB8300; a current code is not a historical classification record.

All three annual archive commands finished successfully. The database check in
`phase2_tcb_annual_verification_20261024.log` verifies 96 income, 144 balance and
56 cash-flow versions across eight annual periods, 2018-12-31 through 2025-12-31.
All 296 use the explicit assumed100-day availability lag. Their immutable
landings9811/9812/9813 pass byte checksums and decoded JSON equality. This brings
the TCB archive to 592 statement versions. It does not activate bank mappings
or establish historical classification, publication times or training eligibility.

Migration079 implements separate parent valuation operands; its targeted
synthetic checks pass. Real provider mappings and the full harness remain open.

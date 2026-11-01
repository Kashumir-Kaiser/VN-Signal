# VCI source-row lineage audit — 2026-10-23

## Result

The disposable report clone contains enough immutable VCI evidence to reconstruct exact source-row lineage for **1,810,727 of 1,810,729** canonical VCI bars. The two unmatched bars are positive, marked-traded ABR rows dated 2018-10-16 and 2018-10-17. No raw VCI ABR rows for those dates exist in the clone's two archived ABR landings, fetched on 2026-10-18 and 2026-10-19. There are no ambiguous exact matches.

Counting only unique exact matches with positive volume and `is_traded=true` strictly before 2026-10-17 gives **1,321 of 1,505 symbols at or above 250 sessions** and a maximum of 1,995 verified sessions. ABR is the only symbol with unmatched positive VCI sessions; those two sessions are excluded from its count, which still exceeds the 250-session threshold. These are conservative source-backed lower bounds, not inferred listing dates.

## Method and evidence

Ran [`phase2_vci_source_row_lineage_audit_20261023.sql`](phase2_vci_source_row_lineage_audit_20261023.sql) against `vnsignal_phase2_report_20261019`. The audit expands the archived VCI `equity_ohlcv` JSON rows and retains each 1-based array ordinal. It verifies `encode(sha256(payload_bytes), 'hex') = lower(payload_sha256)`, then joins the decoded row to `core.bars_daily` on the same `ingest_id`, ticker, and session date and requires exact equality for open, high, low, close, and volume.

The parse yielded **5,321,301 archived row occurrences across 4,140 nonempty VCI landings**; all 5,321,301 were attached to landings whose payload-byte SHA-256 verified. The canonical-bar match yielded 1,810,727 unique rows, 2 rows with no exact match, and 0 ambiguous rows. The point-in-time count uses `trade_date < DATE '2026-10-17'`.

All audit relations were session-local temporary tables. The transaction was rolled back; no `raw.*`, `core.*`, or persistent feature relation was changed. The full pass took about 99 seconds; no step exceeded 38 seconds.

## Remaining implementation work

This audit proves row-level provenance can be reconstructed for the matched bars, but migration 061 still hardcodes `verified_listed_sessions` to NULL. The production builder has not yet consumed this evidence, and the two ABR rows must remain unverified. Add a durable, reproducible lineage materialization and include the verified per-date session counts in the derived-target input hash before claiming real liquidity-tier eligibility.

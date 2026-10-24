# Verified legal listing tenure — migration 080

The previous label-derived builder hardcoded listing tenure to NULL. Migration
080 adds an append-only reviewed legal-event ledger and connects it to persisted
membership, without inferring admission from prices, incorporation dates or a
current listing snapshot. No real events are inserted by the migration.

## Contract

- Admission starts an explicitly identified episode. A new admission following
  delisting requires a new episode ID; reusing an old identity fails closed.
- Delisting dates mean effective cessation, excluding that date. A known closed
  episode returns zero current tenure and is ineligible.
- An explicit same-identity transfer records both old-venue cessation and new
  admission. Intervening no-venue sessions do not count; signals during that gap
  return zero. A single official notice may prove both facts, or separate notice
  references may support them. Mere proximity of dates is not continuity proof.
- Suspension does not subtract legally listed sessions. Only true calendar
  sessions strictly before the signal date count; 249 fails and 250 can qualify.
- Missing/conflicting evidence returns NULL. Notice availability uses the same
  local 15:00 signal cutoff as other PIT inputs. Date-only document claims are
  conservatively unavailable before the next local calendar date.
- Archive-fetch claims cannot predate either source capture. Verified historical
  publication is an explicit reviewed claim, never inferred from an old event
  date or a current profile. Real evidence must establish publication and legal
  security identity before that mode is used.
- Each notice must have intact SHA-256 bytes and the same security, required
  archive route, and matching URL/document metadata. PDFs/HTML remain original
  bytes; the JSON metadata is a separately reviewed claim. The database does not
  automatically interpret a document's legal meaning. Migration016 preserves
  both bytes and metadata against update/delete/truncate.
- Corrections/withdrawals supersede a single earlier event for the same security,
  cannot become known before it, and leave prior signal knowledge intact.
  Withdrawal removes that claim; it does not automatically restore older claims.

The builder computes an indexed full-calendar session prefix once, then counts
disjoint venue intervals by prefix differences. It computes tenure once per
candidate date. Standalone calls use calendar counting; out-of-range prefix
calls fall back to the calendar. The label dependency hash includes all known
legal-event history, correction links and full prior calendar, beyond the
59-session liquidity warmup. Feature formula identity is unchanged.

## Evidence and limits

Migration apply/replay and targeted assertions passed in the disposable 076
review database. `phase2_listing_tenure_080_corrections_20261024.log` and
`phase2_listing_tenure_080_source_bound_20261024.log` cover boundary counts,
suspension, announced transfer gap, delist/relist, after-close availability,
conflicts/corrections, prefix parity, immutability, and persisted eligible versus
ineligible membership with explicit synthetic liquidity. No live data route was
called. The full fresh two-pass harness is queued after the real feature build.

Initial migration review failed atomically on a newline-sensitive patch anchor;
the anchor now matches a single statement fragment across CRLF/LF files. That
failure and subsequent successful checks are preserved. This is implementation
evidence, not proof that the real historical universe now has listing coverage.
Real ledger population, source review and historical coverage census remain
required before Phase 3 readiness can be claimed.

Final targeted assertions also verify that a calendar correction older than the
liquidity warmup changes the label input hash, and mismatched source URL/security
claims are rejected. See `phase2_listing_tenure_080_final_20261024.log`.
Required Go tests/vet and all 32 Python tests pass in the final080 logs.

Further boundary/cache checks pass in
`phase2_listing_tenure_080_boundary_cache_20261024.log`. Same-date effective
cessation/readmission processes the closure first and resets to the new episode.
The public tenure function always reads the actual calendar; only the builder's
explicit internal helper uses its freshly generated prefix. A stale unrelated
temporary prefix cannot change a standalone result.

An FPT issuer article dated 2015-07-23 states original trading admission on
2006-12-13. Its exact current HTML bytes, checksum, manifest and reviewed excerpts
are archived under `fpt_listing_source_20261024/`. Raw import inserted one landing
and repeat inserted zero. The source establishes a historical admission claim,
not independent original-page vintage or exhaustive subsequent legal continuity.
No real listing ledger event or historical availability was inferred from it.

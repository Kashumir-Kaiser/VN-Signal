# Public execution tenure review — 2026-10-24

Migration 082 restores the previously accepted sufficient lower-bound route for the 250-session membership condition. It requires exact native VNDIRECT bytes, code/date/pointer, raw OHLC, matched `nmVolume`, positive execution, STOCK type and a dated public venue agreeing with the canonical source row. It does not infer an exact listing date or claim an ISIN absent from the source.

The proof records `PUBLIC_EXECUTION_EVENT_RECONSTRUCTION`: a historical public execution is conservatively available at the following local midnight. This is an event-time reconstruction under the existing provider/security price contract. The actual later landing capture and proof observation remain preserved; this is not evidence of a contemporaneously archived vendor vintage. Only strictly earlier true sessions count. Fewer than 250 executions leave tenure unknown. Known lifecycle conflicts fence the route; a consistent reviewed legal episode remains the exact path.

Persisted membership records identify `LEGAL_EPISODE`, `PUBLIC_EXECUTION_LOWER_BOUND` or `UNKNOWN`. An announced future cessation cannot relabel today's lower-bound evidence as a legal episode. A known future admission with no established effective episode fences conflicting older executions.

The initial persisted-consumer fixture failed because it introduced a new security but built only V3, whose shared inputs require the preceding feature stage. Calling the public complete feature builder fixed that failure. The failure logs remain archived. Added tests cover future notices and the explicit event availability contract; the fresh complete harness is still running and is not yet a pass claim.

The first local fresh harness exposed inconsistent SQL line endings in text-based migration anchors. SQL source is now normalized to LF and `.gitattributes` enforces LF on Windows and CI. The subsequent two-pass replay progressed past that migration into assertions. Its final result is still pending.

The serial report follow-up now includes migration 082 and a bounded, independently committed 15-security public execution archive, after the live feature job finishes. No report application or real-data qualification pass is claimed by this note. Phase 2 remains open.

Local result: the fresh two-pass migration harness completed successfully, including all existing assertions and the new public-execution boundary/future-notice cases. See phase2_public_execution_082_lf_harness_20261024.log. Go tests, vet and all 32 Python tests also passed. This does not prove real-source coverage or Phase 2 completion.

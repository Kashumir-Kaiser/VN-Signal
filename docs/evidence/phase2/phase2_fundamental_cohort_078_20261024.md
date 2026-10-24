# Fundamental cohort and industry rank correction (078)

The overlay still selected V2 price rows in both its signal population and event-date lookup. It now requires V3 with the current feature hash in both places; that hash also participates in overlay mapping identity. Seven industry rank formulas previously allowed unknown industries to form a synthetic peer group. Each now requires a non-null industry.

Targeted replay and expanded SQL assertions passed on the disposable schema-verification database. Tests reject stale-hash V3 and V2-only keys, confirm all seven rank inputs have at least five valid peers before testing unknown-industry null ranks, and prove that changing the price feature hash changes overlay identity. Fixture data and temporary function changes roll back. See `phase2_fundamental_cohort_078_review_20261024.log`. Go tests/vet and Python32 passed (`*_078_20261024.log`).

No accounting formula, price source or item mapping was guessed. The same-date nominal/model-corrected close remains appropriate for the stated share-based valuation contract; adjusted_c is a separate source field.

The old077 queue was verified waiting and stopped before database work. Its status records supersession. Replacement078 queue fingerprints the revised migration/test inputs, waits for the identified feature build to succeed, runs a fresh full two-pass harness, then applies077 and078 to the report clone and runs the v2 lineage archive. PID/start and phase are in `phase2_serial_followup_078_20261024.status.json`. At creation it is alive and waiting; the fresh full harness and report applications remain pending, not claimed complete.

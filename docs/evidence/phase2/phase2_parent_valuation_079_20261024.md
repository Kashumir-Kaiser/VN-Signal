# Parent valuation basis — migration 079

P/E now requires four consecutive PIT quarters explicitly mapped as
`parent_net_profit`; P/B requires an explicit `parent_equity` mapping. Group
profit and equity continue to serve consolidated return and leverage formulas.
There is no group-total fallback. No real provider mapping is activated here.

The distinction follows the parent-holder claim: [IAS 33](https://www.ifrs.org/issued-standards/list-of-standards/ias-33-earnings-per-share/)
defines consolidated EPS using profit attributable to ordinary holders of the
parent. This migration uses market capitalization divided by parent profit,
not a weighted-average-share EPS calculation.

Both explicit inputs are persisted alongside the ratios. The mapping identity
includes `valuation=parent-v1`, so unchanged mapping rows cannot retain the old
formula identity. Migration replay passed in the disposable 076 review database.

Synthetic assertions retain group TTM profit of 106 million, introduce parent
TTM profit of 53 million and parent equity of 300 million versus group equity
of 400 million, and verify the distinct P/E and P/B values. Disabling both
parent mappings preserves consolidated returns but makes both valuations NULL.
Existing PIT, missing-share, unknown-industry and V3-cohort assertions pass.
See `phase2_parent_valuation_079_review_retry_20261024.log`.

The first supplemental-fixture attempt failed on a duplicate industry key and
rolled back. Its log is retained; the supplemental fixture was corrected to
reuse that existing synthetic industry. The full fresh two-pass harness remains
queued after the real feature run and is required before signoff.

Required Go test/vet and all 32 Python tests pass with the project virtual
environment on PATH. The first Go run hit the Windows Store Python alias;
its failure log is retained alongside the successful retry. This was an
interpreter environment failure, not a passing test run.

Additional edge assertions pass in
`phase2_parent_valuation_079_edges_retry_20261024.log`: parent revisions fetched
after 15:00 cannot affect the same-day signal, become visible the next eligible
day, and zero/negative/missing parent operands disable valuations. A missing
quarter prevents parent TTM even with three other positive quarters. The first
edge run failed because an earlier hash-identity test left synthetic V3 rows
under its temporary hash; explicitly rebuilding the next test's V3 cohort
restores test independence. That failure log is preserved.

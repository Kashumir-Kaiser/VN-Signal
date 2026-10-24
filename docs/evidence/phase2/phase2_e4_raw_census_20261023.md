# E4 bounded raw-landing census — 2026-10-23

## Result

This read-only census does **not** resolve the 219 unexplained E4 continuity
intervals. It covered the 1,539 effective sessions in the corrected
integrity-gap CSV and checked archived OHLCV/quarantine landings for exact-date
rows. The census found 12 row occurrences on six dates for four symbols
(DBT, HTT, LMH, and MVB), represented by eight VCI `equity_ohlcv` landings.
All 12 rows have structurally valid OHLC values, but all have zero volume;
none is a VNDIRECT row or a positive-volume observation. The matching OHLCV
fingerprints were duplicate observations. No matching canonical or alternate
source bars, or historical listing snapshots, were found for the census dates.

These VCI zero-volume rows cannot fill the VNDIRECT adjusted feature series and
do not establish that a symbol was suspended. The 219 intervals remain
unclassified and E4 remains **NOT PASS** pending ticker-matched source or
lifecycle evidence.

## Scope and reproducibility record

The query ran against the disposable report clone
`vnsignal_phase2_report_20261019`; it did not call vnstock or modify the
registered database. The bounded date set came from
`phase2_integrity_gap_attribution_20261022.csv`, whose SHA-256 is
`C6A97D77D1ECA7D798403E59B44DF4E9C6235CE45F69B8DCADE5F60DEDA770C3`.
The exported per-interval result is
`phase2_e4_raw_census_20261023.csv`, SHA-256
`A709B16A7E4E8676E91DDC700003281123B85FE9AC5D340250B772B7933CB39F`.
The CSV contains 219 intervals and sums to 1,539 missing effective sessions,
12 raw row occurrences, six dates with raw rows, zero VNDIRECT rows, 12 zero-
volume rows, zero positive-volume rows, and 12 valid-OHLC rows.

The census is an exact-date archive lookup for the unresolved interval set; it
does not prove that the archive contains every historical observation or
explain gaps for which no source record exists. No missing bar was synthesized
or substituted from another vendor.

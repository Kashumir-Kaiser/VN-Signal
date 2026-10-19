# VNDIRECT opening/range cross-check — 2026-10-19

## Result

The source extract contains 374 VNDIRECT daily rows (214 symbols, 35 dates) where the raw `open` or `close` is outside the reported `high`/`low` range. `high >= low` for every row. The opening field is outside the range on 347 rows; the close is outside on 33 rows, with six rows in both groups. There are 61 zero-volume rows in the full extract; 153 rows have `open = basic_price`.

The user confirmed an opening field outside matched-price high/low can be valid in Vietnamese market data. Keep those original opens, and do not use a generic OHLC enclosure rule to filter or rewrite them.

The 33 close/range conflicts are fully dispositioned. Five positive-volume bars already have model OHLC corrections for next-session corporate-action adjustments (FMC, FTS, GEX, VNM, VNS). The remaining 20 positive-volume bars are HOSE trades: same-session CafeF raw open/high/low and matched volume exactly equal VNDIRECT, while CafeF's close is inside the shared range and on the HOSE tick schedule; VNDIRECT's close is outside the range and off-tick. Migration 033 applies CafeF close to the model bar only. The official VNDIRECT HSX rules give the tick schedule as 10 VND below 10,000, 50 VND from 10,000 through 49,950, and 100 VND from 50,000; the stored prices are in thousand VND. The raw VNDIRECT OHLCV and lineage remain unchanged.

The other eight close conflicts have zero volume and `is_traded=false`. They remain in the price history as non-traded observations; no executed close exists to substitute, so the audit records them as retained zero-match sessions rather than dropping the dates or inventing trades. The complete row-level partition is in [`vndirect-close-conflict-disposition.csv`](vndirect-close-conflict-disposition.csv), and the 20 corrected bars are in [`vndirect-close-tick-corrections.csv`](vndirect-close-tick-corrections.csv).

Migration 033 is applied to the registered PostgreSQL database. The registered query joined all 374 flagged keys to `core.vndirect_bars_as_of('2026-10-16')`; all 374 return with `price_basis='adjusted_as_of_reference'`. The full adjusted-as-of series contains 2,844,435 rows for 1,518 in-scope symbols, including 1,021,077 zero-volume rows, with zero missing prices or wrong-basis rows. The 20 model close corrections preserve this row count. The database now has 25 total evidence-linked model OHLC overrides and 1,328 reference-factor decisions with zero invalid factors. UTT is the only separately approved model-scope exclusion.

## Public-source comparison

The Cophieu68 historical pages matched all 374 ticker/date pairs and all 374 reported volumes. Its OHLC bars enclose their own open. Its prices are not a raw VNDIRECT replacement: only 52 of 374 Cophieu68 closes exactly match raw VNDIRECT closes, and 65 match the latest VNDIRECT adjusted close. The row-level comparison preserves both values and records the page URL and response hash. No override was inferred from the different price basis.

Official market-data references distinguish ATO opening call auctions from LO continuous trading and label `open`, `high`, and `low` as separate fields: [SSI's data-stream definitions](https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage) and [HOSE's order-type rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf). The [VNDIRECT HSX trading rules](https://support.vndirect.com.vn/hc/vi/articles/360002192174-Quy-%C4%91%E1%BB%8Bnh-giao-d%E1%BB%8Bch-t%E1%BA%A1i-s%C3%A0n-HSX) state the applicable tick increments and opening/closing auction rules. CafeF comparisons are used only for the 20 same-basis, same-OHL, same-volume close conflicts; they are not used to rewrite the valid open/range observations.

## Audit files

- [`vndirect-violations.csv`](vndirect-violations.csv): all 374 raw VNDIRECT rows, source landing IDs, fetch times, and payload hashes.
- [`cophieu68-crosscheck.csv`](cophieu68-crosscheck.csv): all 374 public comparisons with date, volume, prices, source URLs, and page hashes.
- [`cophieu68-fetches.csv`](cophieu68-fetches.csv): page-level fetch status, date range, and response hashes.
- [`fetch_cophieu68_conflicts.py`](fetch_cophieu68_conflicts.py): reproducible public-history collector.
- `cophieu68-pages/`: locally archived public HTML responses; candidate rows identify their exact page file in the cross-check CSV.
- [`cafef-close-range-crosscheck.csv`](cafef-close-range-crosscheck.csv) and [`cafef-close-range-fetches.csv`](cafef-close-range-fetches.csv): exact-session CafeF values and response hashes for all 33 close conflicts.
- [`vndirect-close-conflict-disposition.csv`](vndirect-close-conflict-disposition.csv): retained/corrected disposition for each close conflict.
- [`vndirect-close-tick-corrections.csv`](vndirect-close-tick-corrections.csv): 20 correction rows and their CafeF response hashes.
- [`reconcile_close_range.py`](reconcile_close_range.py): validates the evidence conditions and regenerates the correction ledger and migration 033.
- `cafef-close-range-pages/`: archived CafeF JSON responses used by the 33-row audit; hashes are recorded in the ledgers.
- [`tests/sql/vndirect_close_tick_fixture.sql`](../../../../tests/sql/vndirect_close_tick_fixture.sql) and [`vndirect_close_tick_assertions.sql`](../../../../tests/sql/vndirect_close_tick_assertions.sql): synthetic CI-only fixture and migration assertions; these rows are never loaded into the registered market database or ML history.

All 374 rows stay in the Phase 2 price input. The 20 traded close conflicts now use evidence-backed model closes; zero-volume rows remain as non-traded observations. The separate corporate-action factor audit remains unchanged.

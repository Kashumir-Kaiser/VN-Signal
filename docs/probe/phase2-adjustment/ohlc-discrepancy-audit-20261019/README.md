# VNDIRECT opening/range cross-check — 2026-10-19

## Result

The scan found 374 VNDIRECT daily rows (214 symbols, 35 dates) whose raw `open` is outside the reported `high`/`low` range. In every case, `high >= low` and the close remains inside that range. There are 61 zero-volume rows; 153 rows have `open = basic_price`.

The user confirmed this open/range relationship can be valid in Vietnamese market data. Keep the original VNDIRECT OHLC, volume, trade status, and lineage. Do not filter these rows or invent a replacement open.

The registered PostgreSQL query joined all 374 flagged keys to `core.vndirect_bars_as_of('2026-10-16')`; all 374 returned with `price_basis='adjusted_as_of_reference'`. The full adjusted-as-of series contains 2,844,435 rows for 1,518 in-scope symbols, including 1,021,077 zero-volume rows, with zero missing prices or wrong-basis rows. UTT is the only separately approved model-scope exclusion.

## Public-source comparison

The Cophieu68 historical pages matched all 374 ticker/date pairs and all 374 reported volumes. Its OHLC bars enclose their own open. Its prices are not a raw VNDIRECT replacement: only 52 of 374 Cophieu68 closes exactly match raw VNDIRECT closes, and 65 match the latest VNDIRECT adjusted close. The row-level comparison preserves both values and records the page URL and response hash. No override was inferred from the different price basis.

Official market-data references distinguish ATO opening call auctions from LO continuous trading and label `open`, `high`, and `low` as separate fields: [SSI's data-stream definitions](https://fc-data.ssi.com.vn/Help/NavigateDataStreamPage) and [HOSE's order-type rules](https://staticfile.hsx.vn/Uploads/UploadDocuments/2372213/6.Order%20types.pdf). The public documents do not define VNDIRECT's exact historical aggregation, so this audit does not infer a raw-field rewrite from another provider's adjusted history.

## Audit files

- [`vndirect-violations.csv`](vndirect-violations.csv): all 374 raw VNDIRECT rows, source landing IDs, fetch times, and payload hashes.
- [`cophieu68-crosscheck.csv`](cophieu68-crosscheck.csv): all 374 public comparisons with date, volume, prices, source URLs, and page hashes.
- [`cophieu68-fetches.csv`](cophieu68-fetches.csv): page-level fetch status, date range, and response hashes.
- [`fetch_cophieu68_conflicts.py`](fetch_cophieu68_conflicts.py): reproducible public-history collector.
- `cophieu68-pages/`: locally archived public HTML responses; candidate rows identify their exact page file in the cross-check CSV.

This resolves the apparent range blocker. The rows stay in the Phase 2 price input and the separate corporate-action factor audit remains unchanged.

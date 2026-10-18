# Market-aware OHLCV ingestion (Phase 1)

## Vietnamese session prices and intraday extrema

Updated 2026-10-18 after checking the HOSE trading rules and quote-field
definitions. The previous validator incorrectly required the high/low extrema
to contain the reported open and close.

On HOSE, the opening price is set in the opening call auction (ATO), continuous
matching runs separately, and the closing price is set by the closing call
auction (ATC). HOSE's quote-field guide defines the high and low as the highest
and lowest executions in the continuous-matching session. An ATO or ATC price
can therefore fall outside that intraday range: `low > open`, `low > close`,
`high < open`, and `high < close` can all be legitimate observations. This is
not a price-band or tick-size issue.

The official HOSE rules document the separate ATO, continuous-matching, and
ATC sessions and define the closing price as the final board-lot execution.
The quote-field explanation explicitly assigns high/low to continuous matches:
- https://staticfile.hsx.vn/Uploads/News/437a3bc734a845fc853283b0c627a593/20250429_20250429%20-%20HOSE%20-%20Quy%20dinh%20giao%20dich%20dang%20website%20HOSE.pdf
- https://estock.duytan.edu.vn/kien-thuc-dau-tu/kien-thuc-chung-khoan/bai-3-huong-dan-doc-bang-gia-truc-tuyen-tai-hose-70.html

Do not generalize one provider's field scope to every venue. HNX's guide
distinguishes periodic and continuous matching on its listed-stock market and
continuous matching plus put-through on UPCoM. SSI's streaming contract also
identifies ATO, LO, ATC, and put-through as separate sessions; FiinGroup's
UPCoM contract separately defines opening, highest/lowest, and total-volume
fields. These source contracts describe fields from different matching scopes,
so the robust cross-source ordering check remains `high >= low`. Keep an
open/close containment check disabled unless the exact source contract says
those fields include the same execution phases.
- https://owa.hnx.vn/ftp/PORTALNEW/PUBLICFACTBOOK_FA/20190911/HNX%20Guide%20to%20trading%20stocks.pdf
- https://guide.ssi.com.vn/ssi-products/fastconnect-data/du-lieu-streaming
- https://datafeed.fiingroup.vn/api-giao-dich/co-phieu/co-phieu/upcom-stock-v2

For a traded daily bar, validate each O/H/L/C as positive and finite, require
`high >= low`, and require nonnegative finite volume. Migration 019 applies that
same high/low-only ordering rule at the PostgreSQL boundary. Do not require the open or
close to lie between high and low unless a source explicitly guarantees that
all four fields cover the same session phases. Preserve provider values;
never swap, clip, or synthesize highs/lows.

Vnstock v5 reports adjusted historical equity prices in thousands of VND;
a reported daily bar at 07:00+07:00 is a dated observation, not evidence of
an executed trade if its volume is zero. VCI and KBS can also use different
historical adjustment bases. Verified documentation:
- https://www.vnstocks.com/docs/vnstock/thi-truong-market
- https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources
- https://upcom.hnx.vn/vi-vn/hoi-dap.html
- https://www.vfs.com.vn/en/securities-services-for-individual-customers/regulations-on-trading-floors/instructions-upcom

The 2024 FPT cash-dividend cross-check matches VCI/DNSE OHLC closes to
VNDIRECT's separate adjusted-price fields; VNDIRECT ordinary OHLC remains
unadjusted. The stored `adj_basis` therefore describes price columns only.
Adjustment timing is not stored, so these restated historical prices are not
point-in-time safe by this label alone. See
`docs/probe/phase1-adjustment/README.md` for action notices, source rows, and
payload hashes.

## Durable quality contract

**Every metered successful vendor response is archived verbatim** with
SHA-256. The new \`AnalyzeMarketBars\` accounts for each input row:
- **TRADED:** volume > 0 and valid OHLC: store verbatim in \`core.bars_daily\`.
- **ZERO_VOLUME_UNVERIFIED:** volume = 0: archive and record in \`ops.bar_quality_issues\`;
  do not interpret historical O/H/L/C as matched trades or forward-fill.
- **INVALID_OHLC/INVALID_PRICE/INVALID_VOLUME:** skip only this session
  from canonical traded bars; record exact row index/date/category/reason.
  Raw vendor values are recoverable from the immutable landing.

\`COMPLETED\` means structurally valid source data with no invalid traded
bars (it may contain properly recorded zero-volume sessions).
\`PARTIAL\` means valid trade records were retained but some vendor rows
were invalid; **never treat partial histories as complete training coverage**.
A structurally unusable frame remains \`BLOCKED\` with source bytes quarantined.
Queue selection excludes both complete and partial jobs, avoiding quota-draining
re-fetches. Summary counters and the quality ledger expose gaps.

Migration 005 adds the quality ledger and \`core.bars_daily.is_traded\`.
It marks previously loaded volume-zero bars as \`is_traded=false\` without
deleting historical data. Downstream features, labels and backtests MUST
restrict observed executed-price returns to \`is_traded=true\`; do not
forward-fill across any no-trade gap. Model promotion remains disabled until
Phase 2 point-in-time, suspension and adjusted-price checks pass.

## Offline source-backed recovery

To reclassify already landed VCI frames under a corrected OHLC validator,
including partial quarantine landings, apply migrations 018 and 019 and use each
**original exact date range** and source. The CLI selects PARTIAL frames; malformed
BLOCKED frames remain blocked unless a separate verified recovery path can parse
their archived response:

\`\`\`bash
go -C go run -mod=mod -tags postgres ./cmd/vnpipe migrate --dir ../sql/migrations
export VNPIPE_DISABLE_LIVE=1
go -C go run -mod=mod -tags postgres ./cmd/vnpipe reprocess-archived \
  --from 2018-10-01 --to 2026-10-16 --source vci
go -C go run -mod=mod -tags postgres ./cmd/vnpipe backfill-status \
  --from 2018-10-01 --to 2026-10-16 --source vci
\`\`\`

The recovery checks exact bytes and SHA-256, re-parses every row, writes
valid trades, quality findings and the state transition atomically, and
never invokes vnstock or alters original \`ops.api_reservations\`.
Runs are idempotent: already recovered jobs are not selected.
A32 and ABC were blocked before raw archiving, so they cannot be
source-recovered; do not mark them complete without fetching verified data.

Do not run historical live backfill again merely to validate this change.
The pipeline remains research-only, with no desktop recommendation or
backtest result.

## Audited legacy requeue for A32 and ABC

Old blocked jobs without `landed_id` do not have saved vendor frames, so offline source recovery is impossible. Migration 006 creates `ops.ingest_requeue_audit` for explicitly authorized retries. The command accepts **only** a verified active stock's exact blocked historical job, `InvalidFrame` cause and **no archived landing**. It records the old attempt number and reason, then changes BLOCKED to PENDING. It does not execute vnstock, refund spent quota or bypass the normal live gateway.

From repo root, after migrations and offline recovery, and while the listing snapshot is still within seven days:

```bash
export VNPIPE_DISABLE_LIVE=1
go -C go run -mod=mod -tags postgres ./cmd/vnpipe requeue-unarchived --symbol A32 --from 2018-10-01 --to 2026-10-16 --source vci
go -C go run -mod=mod -tags postgres ./cmd/vnpipe requeue-unarchived --symbol ABC --from 2018-10-01 --to 2026-10-16 --source vci
```

Later, **only with the user's explicit authorization**, the regular `backfill --active` will fetch those entries through the existing durable quota guard and classify returned records under the new market-aware rules. The original failed API calls remain counted and visible in `ops.api_reservations`; no one should edit those records manually.

## Historical eligibility correction (migration 007)

A zero-volume observation does NOT prove a company was publicly listed or eligible to trade. All earlier `NO_TRADE` ledger entries are reclassified as `ZERO_VOLUME_UNVERIFIED` without changing raw bytes, historical data, ingestion jobs, or quotas. `ops.zero_volume_lifecycle_status` remains `LISTING_STATUS_UNVERIFIED` until independently sourced first-ever trading dates and venue-specific eligibility/suspension/delisting intervals are recorded. See [lifecycle evidence](LIFECYCLE_EVIDENCE.md). In particular, the earliest OHLCV date and current exchange listing date must not be substituted for first-ever public trading date.

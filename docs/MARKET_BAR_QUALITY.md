# Market-aware OHLCV ingestion (Phase 1)

## Source evidence, not a one-tick shortcut

2026-10-17 forensic output identified **177** inconsistent VCI candles in six
archived frames: ABI 6, ABR 101, ABT 1, ACE 64, ACG 4, ACL 1. Of these,
**161** had volume zero (ABI 5, ABR 97, ACE 59), and **16** had positive volume.
Most zero-volume contradictions are repeated source rows. Differences up to
1.98 thousand VND / over 1000 bps cannot be waved away as ordinary 2-decimal
rounding.

vnstock v5 reports adjusted historical equity prices in thousands of VND;
a reported daily bar at 07:00+07:00 is a dated observation, not evidence of
an executed trade if its volume is zero. Verified documentation:
- https://www.vnstocks.com/docs/vnstock/thi-truong-market
- https://www.vnstocks.com/docs/vnstock/tham-khao/data-sources
- https://upcom.hnx.vn/vi-vn/hoi-dap.html
- https://www.vfs.com.vn/en/securities-services-for-individual-customers/regulations-on-trading-floors/instructions-upcom

An actual traded candle must satisfy positive finite O/H/L/C,
\`high >= max(open,close)\`, \`low <= min(open,close)\`, and nonnegative volume.
The exchange's 7/10/15% daily bands do not override those inequalities;
reference prices, negotiated trading, price adjustments and no-trade sessions
must be modeled separately. Never 'fix' highs/lows by swapping or clipping.

## Durable quality contract

**Every metered successful vendor response is archived verbatim** with
SHA-256. The new \`AnalyzeMarketBars\` accounts for each input row:
- **TRADED:** volume > 0 and valid OHLC: store verbatim in \`core.bars_daily\`.
- **NO_TRADE:** volume = 0: archive and record in \`ops.bar_quality_issues\`;
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

To reprocess archived blocked VCI frames after migration 005, use the
**original exact date range** and source:

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

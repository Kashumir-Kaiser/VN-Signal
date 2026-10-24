# Data contract — Phase 2

All `raw` landings are append-only, with `ingest_id` (UUID), `fetched_at` (timestamptz), `source`, `route`, `payload` (JSONB) and `payload_bytes` (BYTEA, nullable only for legacy rows); never replace a landing row. Compute `payload_sha256` against exact incoming bytes, not JSONB-serialized text. `core.bars_daily` is the deduplicated daily price table, keyed by `(symbol_id, trade_date)`. `core.index_bars` preserves independent provider histories and is keyed by `(index_symbol, trade_date, source)`. Its `adj_basis` classifies OHLC price fields only; it does not classify volume semantics or encode the timestamp/vintage when historical prices were adjusted. Current VCI and DNSE equity history is classified `adjusted`. VNDIRECT raw `o/h/l/c` remains unadjusted; migration 026 separately materializes the provider's `adOpen/adHigh/adLow/adClose` snapshot in `adjusted_o/adjusted_h/adjusted_l/adjusted_c` and stores its landing time in `adjustment_vintage_at`. Never overwrite raw VNDIRECT fields with adjusted prices. For point-in-time VNDIRECT OHLC, Phase 2 must read `core.vndirect_bars_as_of(symbol_id, as_of_date)` or the market-wide overload `core.vndirect_bars_as_of(as_of_date)`. Both functions apply explicit `ops.ml_symbol_scope` exclusions and rescale one complete, same-vintage snapshot to remove adjustments for actions after `as_of_date`; incomplete or mixed-vintage histories return no rows, and the market-wide overload requires an exact-date anchor without creating missing ticker sessions. UTT is excluded under the user-approved scope decision while its raw rows remain preserved. All other in-scope sessions use this full-coverage VNDIRECT price basis. Phase 2 uses this full-coverage VNDIRECT series as its single price basis, preserving the raw VCI and DNSE histories as source-attributed cross-checks rather than joining snapshots with different adjustment vintages. The audited VNDIRECT history covers every DNSE ticker/date and every VCI ticker/date except five lifecycle-invalid CTR rows already excluded with exchange evidence. For features, use the signal session as `as_of_date`. For a forward label, call the function once with the label-end session and read both signal and label prices from that same returned series so they share one adjustment basis. `traded_value` is reserved for a value reported by the source. Migration 017 creates `core.bars_daily_with_proxy`, which exposes `traded_value_proxy_vnd = c × v × 1,000` for valid traded rows; vnstock documents prices in thousand VND and adjusted historical prices. This is an adjusted-close-based estimate, not exact executed turnover. It is the approved Phase 1 liquidity ranking/ML feature basis, while `adj_basis` remains separately recorded and live order-capacity decisions remain gated.

`core.fundamentals_pit` has `period_end`, `period_type`, `first_seen_at`, `available_at`, `last_seen_at`, `restated`, and `payload`. For backfilled financial periods, availability **cannot be earlier** than conservatively assumed publication lag (quarter: 45 days, year: 100 days); once directly observed on local pulls, availability is the first seen timestamp. Training joins on `available_at <= signal_time`, not `period_end`.

`ops.api_calls` is an append-only audit with route, source, attempted/fetched timestamps, result type, quota bucket metadata and run ID. `ops.pipeline_runs` records an idempotency key, status, step and error. Phase 2 populates `feat` with versioned research features and labels. The `ml` schema has no model, prediction or recommendation relations yet; those belong to later phases. No model performance or trade suggestions are implied by populated feature tables.

Go's DQ gate treats zero and negative prices, high < low, negative volume, duplicate symbol/date rows, invalid ISO session dates, and missing fields as blocking. Exchange price jumps require a separate adjustment/corporate-action review; do not mechanically delete genuine corporate actions.

`core.listing_snapshots` holds complete observations of currently listed HOSE/HNX/UPCOM membership by trade date. If a vendor listing frame includes rows labeled `DELISTED`, keep those rows in the complete raw landing but do not assign an exchange or insert them as active symbols; their former exchange is not established by that field. Previously observed symbols that disappear from the current exchange rows remain in `core.symbols` as inactive. `industry` stores ICB level-two codes from vnstock v5 `icb_code_lv2` (not descriptive sector names). Unknown or partial membership frames must not update the universe.

## Market-aware historical frame classification (migration 005)

See [OHLCV quality contract](MARKET_BAR_QUALITY.md). `ops.bar_quality_issues` accounts for no-trade and source-defective daily observations, while all source bytes remain in `raw.landings`. `ops.ingest_jobs.state=PARTIAL` is not equivalent to historical completeness. Legacy `core.bars_daily.v=0` rows are explicitly marked `is_traded=false`; production features and any trading fills must exclude them. No zero-volume prices are treated as executable trades and no source OHLC values are repaired silently.

Migration 023 adds append-only `ops.exchange_daily_bar_evidence` for exact exchange-report rows. A verified zero matched-volume report can classify that symbol/session as a no-match session without generating an OHLCV bar. Positive alternate bars or positive/inconsistent exchange matched volume remain explicit conflicts with a vendor zero-volume issue. Evidence is accepted only when it matches the archived, checksum-verified raw report.

## Historical listing status is not implied by zero volume

Migration 007 reclassifies zero reported vendor volume as `ZERO_VOLUME_UNVERIFIED`. It adds a provenance-linked lifecycle evidence registry and an eligibility view that defaults to `LISTING_STATUS_UNVERIFIED`. Current symbol membership does not establish past availability; no unverified zero-volume observation may become a liquidity, suspension, or pre-IPO feature. See [lifecycle evidence](LIFECYCLE_EVIDENCE.md).

## Schema inventory and installation scope

The [column catalog](evidence/phase2/phase2_schema_columns_077_20261024.csv) records every column's relation, order, PostgreSQL type, nullability, default and SQL comment after migrations through 077 on the disposable schema-verification database. The [constraint catalog](evidence/phase2/phase2_schema_constraints_077_20261024.csv) records primary/foreign/unique/check constraints, validation state and deferral. These are schema exports, not market data or proof that the report or registered database has the same migration state. See BUILD_STATUS for actual installation and data-validation evidence. Missing column comments are documentation gaps, not permission to infer a financial meaning.

## Price feature matrix and training boundary

Production V3 rows live in `feat.features_daily`, selected by `feature_version='phase2-v3'` and `feature_set_hash=feat.phase2_feature_set_hash_v3()`. The recovery prompt's `features_v3` is this logical selection, not a separate production table. Its primary key is `(symbol_id,trade_date,feature_version)`; the hash is a required selection/reproducibility attribute, not another key dimension. A new hash replaces that version's stored projection only through the validated build pipeline. V2 rows remain a separate version.

`trade_date` identifies the signal session. `built_at` is an operational timestamp, not historical availability. Price-derived predictors use information through that signal close; cross-asset predictors apply their specified one-session lag. Price/volume fields, future labels, source identifiers and operational timestamps must not be included in a model merely because they are numeric columns. The model-input allowlist and feature formulas must be frozen against the current feature hash before training.

Nulls are retained for insufficient lookback, missing/invalid inputs, unavailable source observations, or undefined calculations. They are not zero returns and must not be forward-filled into fabricated trades. The real null-rate report distinguishes lookback expectations from anomalous missingness. Cross-sectional ranks preserve the source metric's null mask and use the population defined by the production builder; investable membership is a separate contract, not implied by receiving a rank.

`feat.phase2_market_features_daily` and `feat.phase2_vci_index_features` hold the separately derived market/index context consumed by the price feature builder. Their exact fields are in the catalog; source basis, date lag and missing-data handling follow the versioned SQL and Master Build Spec.

## Labels and derived targets

`feat.labels_daily` has primary key `(symbol_id,signal_date,horizon_sessions,label_version)`. For `close-next-open-v1`, horizons are 5 and 20 effective trading sessions. Entry is the next session's open and exit is the close at signal session + 1 + horizon. The benchmark uses those same endpoints. Labels store future outcomes, never predictors. Missing entry, exit, intermediate sessions or incompatible adjustment episodes block a READY label; the final incomplete windows stay null.

Phase 3 must obtain training keys from `feat.phase2_training_eligible_v3` (or an independently proven equivalent), joining on symbol, signal date, horizon, approved label version and current feature hash. This view requires READY labels and excludes the 250-effective-session rolling-feature cooldown following a source-session gap. `feat.phase2_training_gaps_v3` records those gaps; it does not call them suspensions. This technical gap filter does not prove legal listing tenure or investable membership. It is not a complete training sample selector: join its keys to the current-hash `feat.phase2_label_targets_v3`, require eligible membership, `is_investable_member`, and valid tier/target ranks for tier-based heads, and retain the configured execution weight as separate sample-weight metadata. Unknown execution evidence cannot silently become weight 1.

`feat.phase2_label_targets_v3` preserves the same label primary key and records raw excess return, date-level 1st/99th percentile bounds, winsorized excess return, volatility-scaled score, liquidity/membership evidence and within-tier target ranks. It does not replace the raw labels. The volatility score divides excess return by `max(sigma60,date_p05_sigma60)*sqrt(horizon)`. Tier target uniform ranks use `(rank-0.5)/count`; a future trainer applies the Gaussian transform. A target's membership gate must be eligible with a valid tier before a tier-based model consumes it.

`feat.phase2_liquidity_tiers_v3` is separate durable liquidity state. Master membership uses median20 turnover-proxy rank, average20 proxy, hysteresis and the verified listed-session gate; recovery tiers use median60 liquidity within eligible members. Tier ranks are not return-target ranks. `membership_tenure_basis` distinguishes a consistent reviewed legal episode (`LEGAL_EPISODE`), a sufficient lower bound of at least 250 exact prior public executions (`PUBLIC_EXECUTION_LOWER_BOUND`), and `UNKNOWN`. The lower-bound route requires intact native VNDIRECT bytes, exact row/code/date/raw OHLC/matched volume, STOCK type and dated public venue agreement; known lifecycle contradictions block it. Fewer than 250 executions remain unknown. This route uses the canonical provider/security identity of the price contract and does not claim an unprovided ISIN or exact admission date. It reconstructs public execution event availability at next local midnight while retaining actual later capture/observation times, rather than claiming an original archived vendor vintage.

Execution weights are target/sample-weight metadata: configured entry-ceiling and repeated-limit-lock rules require exact available price-band evidence. Unknown evidence stays unknown; it cannot receive a fabricated normal execution weight. The effective policy is included in chunk hashes and metadata. Proxy turnover remains research liquidity, not execution capacity.

## Fundamental archive and separate overlay

Managed `core.fundamentals_pit` versions retain statement family, period type/key/end, exact provider row ID/name/order/level/unit/value, source landing/ordinal, ingest ID, fetch/first-seen timestamps, availability basis and restatement state. `core.fundamentals_pit_observations` records every successful immutable landing/row observation, including unchanged repeats. Source ordinals here are zero-based. Whole-frame row equality and byte checks preserve the source, while distinct version/observation records preserve revisions.

Backfill availability is explicitly assumed: period end + 45 days for quarterly statements, +100 days for annual statements, at midnight Asia/Ho_Chi_Minh. Observed ingestion uses the actual fetch/first-seen time. An assumed lag is not proof of an original publication date or of an unrevised historical value. Revised observations must retain their observed availability; later restatements must not silently replace an earlier value as if originally known. Consumers join on `available_at <= signal_time`, not period end or fetch date alone, and retain the assumption flags for research disclosure.

The statement adapter checks any provider ticker against the requested equity and records `symbol`, `requested_symbol`, `requested_period` and `symbol_basis`. A request-only basis is explicit. A fresh capability report must verify the exact statement family and period frequency, with nonempty bounded long-format output. Annual and quarterly permissions are not inferred from each other. Hosted CI uses fixtures and never calls these routes.

`feat.fundamental_line_item_map` binds exact source/family/row ID/unit to a named input, multiplier, scope and mapping version; active entries require source-backed accounting and scale verification. `feat.fundamental_industry_class_map` explicitly selects BANK or OTHER. Unknown mappings/classifications remain unavailable. `feat.fundamental_features_daily` is keyed by `(symbol_id,trade_date,feature_version,mapping_hash)` and retains its PIT snapshot/landing IDs and share/price observation references.

This overlay contains TTM amounts/margins, returns on average balance-sheet assets/equity, growth, leverage, accruals, valuation from PIT shares, bank-specific metrics and industry ranks. Stock-like balance-sheet values are not summed as flows. TTM flows require consecutive independent quarterly amounts; cumulative YTD amounts cannot be summed without validated conversion. Consolidation/accounting-basis changes must be surfaced before growth comparisons. Missing tier-restricted line items stay null. Eight visible quarters cannot supply every longer lag, and they do not automatically satisfy all model-B gates. The overlay stays separate from core price features and is consumed only under the Master Spec's PIT-quarter and independent model-validation gates.

## Source observations, provenance and build evidence

`core.listed_share_observations`, `daily_price_limit_observations`, `calendar_event_observations`, `bars_1m_observations` and the other cataloged source-observation relations retain their explicit source, availability and immutable landing/row lineage. Retrieval in 2026 does not alone prove historical availability. Archived price bands use fetch-time availability; invalid or future-unavailable bands cannot authorize a historical fill. Intraday is forward-collected and optional, not a fabricated historical input.

`ops.phase2_vci_bar_lineage` records versioned exact-row source observations with canonical/input hashes, outcomes and explicitly **one-based** source ordinals. `ops.phase2_vci_lineage_batches` records requested scope, digest, counts and completion time. A stored observation is not automatically current after inputs change. Version 077 recognizes an immutable quarantined route only through its matching, reviewed offline-recovery job/audit chain and row-quality checks; source_evidence preserves that distinction. Neither source equality nor audited recovery establishes legal listing tenure or an original publication timestamp.

`ops.feature_chunks`, `ops.step_runs` and label-target chunk accounting store bounded stage dates, status, row counts, timings, input/output hashes and relevant policy metadata. A committed checkpoint proves that chunk's recorded inputs/output, not the whole Phase 2 acceptance gate. Failed/canceled attempts remain evidence. Phase 3 starts only after the current real-data E1–E5 and CI requirements in BUILD_STATUS are verified.

### Parent valuation basis (migration 079)

`fundamental_line_item_map` accepts distinct income `parent_net_profit` and
balance-sheet `parent_equity` keys. They require verified parent ordinary-holder
semantics. The overlay persists `ttm_parent_net_profit` (four consecutive,
non-null PIT quarters) and `parent_equity`; P/E and P/B divide same-day nominal
market capitalization by those positive operands. Consolidated `ttm_net_profit`
and group equity serve group returns/leverage and never fill missing valuation
inputs. The mapping hash includes `valuation=parent-v1`. No real mappings are
activated by this migration.

### Legal listing tenure (migration 080)

`core.security_listing_events` is an append-only reviewed legal event ledger:
security and episode identity, admission/transfer/delisting/withdrawal, effective
venue dates, original notice references, document date, availability/basis,
reviewed claim and optional single-predecessor correction. Original notice bytes
are checksum-verified; metadata is a separately reviewed legal/publication claim.
`core.verified_listing_tenure(symbol_id,signal_date)` counts true sessions strictly
before the signal within its current episode. Suspensions count; transfer gaps
do not; relisting resets tenure. Known closed/gap states return zero, missing or
conflicting evidence NULL. The label-derived membership consumer persists that
count and requires >=250 plus its complete liquidity inputs. Full prior calendar
and known event/correction history participate in the label input hash. No real
historical events are seeded; source review and coverage remain open.

The public tenure query reads the calendar directly. Its explicit internal
builder helper may use the freshly materialized session prefix; unrelated temp
state cannot change public query results. Same-date cessation then readmission
is supported with a new episode identity.

### Industry observation availability (migration 081)

The fundamental overlay uses timestamped `security_observations`, via
`core.industry_as_of`, rather than date-only listing snapshots. Both observed date
and local15:00 timestamp cutoff apply. Conflicting latest observations or a
latest unknown/delisted category yield NULL. The overlay persists
`industry_observation_ids` and `industry_available_at`, includes industry landings
in `raw_landing_ids`, and versions mapping identity with `industry_observations=v1`.
The fundamentals input manifest hashes these PIT observation dependencies.

# VN-Signal — Master Build Prompt

*A single-user Vietnamese equity research and suggestion system · vnstock free tier · Rust + Go core · PostgreSQL for wrangling, SQLite for serving*

*Prepared 16 October 2026. Statements about vnstock reflect its v5 documentation on that date. The Phase-0 capability probe (§2) overrides any statement here that the installed library contradicts.*

## 0. Operating instructions for the builder

You are a principal engineer building the system below end to end. Follow these rules throughout.

1. Work in the phases of §13. Complete each phase's exit criteria before starting the next, and close each phase with a short status note: what was built, what deviated from this specification, and why.
2. Do not ask clarifying questions. Where this specification is silent, choose the simpler design and log the choice in `docs/DECISIONS.md`.
3. Never invent vnstock functions or limits. The authoritative contract is what the installed package actually does, as recorded by the probe.
4. Priorities, in order: (i) point-in-time correctness and absence of look-ahead leakage, (ii) reproducibility, (iii) latency and footprint, (iv) model sophistication. A simple leakage-free model is a deliverable; a sophisticated leaky model is a defect.
5. Introduce no component outside §3. In particular: no Redis, no message broker, no Airflow or Celery, no Kubernetes, no cloud database, no authentication or multi-user layer.

## 1. Purpose, scope and non-goals

**Purpose.** Each trading day, ingest Vietnamese market data through vnstock, refit a cross-sectional return-forecasting model on the accumulated history, and publish a ranked, risk-annotated, long-only list of suggestions for HOSE, HNX and UPCoM equities, with explicit uncertainty.

**Scope.** One user, one machine, local only. The system only need to run on Windows or Linux; automation may not depend on shell scripts or a Unix-only cron.

**Non-goals.** Order routing or broker integration; shorting, derivatives, warrants, crypto; intraday trading signals; multi-user access, authentication, horizontal scaling or high-traffic design; language models in the decision path.

**Status of outputs.** Research output, not investment advice (vnstock itself disclaims advice). Every screen that shows a suggestion also shows model health and uncertainty.

## 2. Binding constraints of the vnstock free tier

The user operates on the free tier. These constraints are the primary design driver, because each one removes an option that a paid tier would allow.

| Constraint | Documented free-tier fact (Oct 2026) | Design consequence |
| --- | --- | --- |
| Request rate | Read `limits.per_minute` from the exact local usage report; an unauthenticated Guest sample on 2026-10-16 reported 10 req/min. Community rate must be verified from the registered account's report. | Register the Community key (`vnstock register`). Go owns a token bucket set to 85% of the reported rate, capped at 60 req/min. |
| Shared quota | Hourly, daily and monthly buckets, shared across devices and libraries; daily bucket resets 00:00 Vietnam time, monthly on the 1st. JSON usage may expose exact `limits` and `used` counts even when human-readable output shows percentages. | Derive remaining calls only from exact limits minus used; percentage-only reports block. A quota ledger and daily call budget (formula below). Backfills are resumable and may span several days. |
| Device cap | Accounts have a device limit | All calls originate from the user's one machine. Never run ingestion on ephemeral CI runners. |
| Financial statements | Last 4 periods (Guest) or 8 periods (Community); level-1 line items only; no notes; `ratio()` and `note()` are Sponsor-only | Derive every ratio ourselves. Fundamental history must be accumulated forward as point-in-time snapshots, and fundamentals enter through a gated overlay model (§7.3), not the core model. |
| Daily-bar depth | Community edition documented at up to \~8 years of daily bars; verify | Training window of roughly Q4 2018 to present (\~2,000 sessions), covering the 2020 crash, the 2021 retail boom, the 2022 drawdown and the 2023–2026 recovery. |
| 1-minute bars | 180 days of history | Not trainable historically; collect forward only (Phase 2, off by default). |
| Intraday trades | At most 5,000 rows per call | Unused in Phase 1. |
| Errors | `EntitlementError`, `RateLimitedError` (library does not retry; wait about a minute), `InputError` | Typed mapping in the worker; entitlement errors disable a route gracefully instead of failing the run. |
| Sources | Six sources; `source=` selects one; OHLCV defaults to VCI; TCBS does not serve OHLCV | Cross-source reconciliation as a data-quality check (§4.3). |
| Licence | Free for personal, learning and research use; attribution required; non-commercial | Keep data local, never redistribute, show attribution in the app's About page. |

**Call budget.** Daily budget `B = min(0.8 × remaining daily bucket, 0.8 × remaining monthly bucket ÷ remaining trading days in the month)`. The scheduler never plans a run whose estimated calls exceed `B`; it degrades by tier (§4.2) instead.

**Phase-0 probe.** Implement `vnpipe probe`. It issues one minimal call per candidate route, records the tier (`vnstock.status()`), remaining quota (`vnstock usage`), the maximum history each route actually returns, row caps, statement period counts and entitlement errors, and writes `docs/probe/<date>.json`. Backfill horizons, call budgets and feature availability are read from the latest probe report and are never hard-coded.

## 3. Architecture and technology stack

Each language is chosen for the one job it does best. Throughput is not the binding constraint for a single user (the whole dataset is under a few million rows), so the stack is selected for low memory footprint, predictable latency, single-binary deployment and compile-time safety.

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Data adapter | **Python 3.12, one file (≤400 lines)**, managed by `uv`, pinned vnstock | vnstock is a Python library, so this adapter is unavoidable. It is a persistent worker that reads JSON-lines jobs on stdin and writes JSON-lines results on stdout. It contains no business logic. |
| Orchestration and ingestion | **Go 1.23+**, one static binary `vnpipe` | Scheduler daemon with catch-up-on-wake, worker supervision, quota ledger and token bucket, bulk load via `pgx` `CopyFrom`, data-quality gates, migrations, Postgres-to-SQLite snapshot exporter (CGO-free `modernc.org/sqlite`), notifications, CLI. Installable as an OS service. |
| Compute | **Rust (stable), Cargo workspace `vnml`** | Training (LightGBM through its C API; Polars for matrix preparation), walk-forward evaluation, backtester, portfolio optimiser (`clarabel`), in-process inference, and the Tauri backend. If LightGBM will not build on the user's OS, record the decision and fall back to the pure-Rust `forust-ml`. |
| Wrangling | **PostgreSQL 16+**, local, single instance | Raw landing, cleaning, adjustment, point-in-time joins, rolling-window features, label construction, experiment registry. |
| Serving | **SQLite (WAL)** | A self-contained read-only snapshot holding the latest features, predictions, recommendations and champion model, for sub-millisecond reads. |
| Desktop UI | **Tauri 2 + Svelte 5 + TypeScript**, `lightweight-charts` | Native webview, so no bundled Chromium; small installer; low idle memory. |

**Data flow.** vnstock → Python worker → Go (ingest, quota, quality gates) → PostgreSQL `raw → core → feat → ml` → Rust (train, evaluate, backtest, score) → Go exporter → `serving.sqlite` (atomic swap) → Tauri app (inference and UI). User-owned mutable state (holdings, settings, notes) lives in a separate `user.sqlite`, because the snapshot file is replaced wholesale.

**Why no Redis.** There is exactly one reader. SQLite's memory-mapped page cache, with in-process caches in Rust (`moka`, `ArcSwap`), already yields sub-millisecond point reads. A cache tier would add a process, a failure mode and an invalidation problem for no measurable gain.

## 4. Data specification

### 4.1 Data types, depth and cadence

| Dataset | vnstock route (v5; confirm by probe) | Granularity | Depth | Refresh | Use |
| --- | --- | --- | --- | --- | --- |
| Listing and classification | `Reference().equity.list()`, `.industry`, `Reference().company(s).overview()` | Static | Current, plus a daily snapshot diff | Daily | Universe, exchange, ICB industry, listed shares. The daily snapshot builds delisting history from day one. |
| Equity OHLCV | `Market().equity(s).ohlcv(start, end, interval="1D")` | Daily | Maximum available (target ≥ 8 years) | Daily, re-pulling the last 5 sessions to catch restatements | All price/volume features and labels |
| Index OHLCV | Index route per probe: VNINDEX, VN30, VN100, VNMID, VNSML, HNXINDEX, HNX30, UPCOMINDEX, plus ICB sector indices if exposed | Daily | Same as equities | Daily | Benchmark, regime, breadth, relative strength |
| Financial statements | `Fundamental().equity(s).income_statement()`, `.balance_sheet()`, `.cash_flow()`, quarterly and yearly | Per period, level-1 items | Last 8 periods per call, extended by our own accumulation | Weekly for the investable universe | Fundamental overlay (§7.3) |
| Trading calendar | `Reference().events.market()` | Event | Current | Daily | Holidays, system incidents; merged with observed sessions |
| Intraday 1-minute (Phase 2) | Intraday OHLCV route | 1 minute | 180 days, then forward | Daily, top 100 liquid names | Realised variance, VWAP gap, closing-auction share, stored as daily aggregates |
| Cross-asset (optional) | FX, commodities, global indices if entitled | Daily | Per probe | Daily | Exogenous features, lagged one session; silently disabled on `EntitlementError` |

What is deliberately **not** used: Sponsor-only ratio and note endpoints, news and analyst feeds, and any scraped source outside vnstock.

### 4.2 Universe and call tiering

- **Listed universe:** all equities on HOSE, HNX and UPCoM (on the order of 1,500; record the probe count). Daily bars are backfilled once for all of them, because liquidity ranking requires history.
- **Investable universe (default N = 400):** top 400 by median 20-session traded value, with hysteresis (enter at rank ≤ 400, leave at rank > 500), at least 250 sessions listed, and 20-session average traded value of at least 5 billion VND (configurable). Models, recommendations and statements cover this set only.
- **Tier A (daily):** the investable set, one history call per symbol over the last 5 sessions (about 400 calls, roughly 7 minutes at 60 req/min and 20 minutes at 20 req/min), plus about 10 index calls.
- **Tier B (weekly, round-robin):** the remaining listed symbols, used only for breadth statistics and universe re-ranking.
- **Volume estimate:** 400 symbols × \~2,000 sessions ≈ 0.8 million labelled rows (≈ 3.2 million if the full listed universe were used). Everything fits in memory on a laptop; no distributed tooling is permitted.
- **Survivorship caveat:** vnstock lists current symbols, so delisted names are absent from history. Record this as a known bias in the model card, apply the haircut in §9, and shrink it over time as the daily listing snapshots accumulate.

### 4.3 Point-in-time and integrity rules

1. Every stored row carries `source`, `ingest_id` and `fetched_at`. Raw landing tables are append-only.
2. **Fundamental availability.** Table `core.fundamentals_pit` is versioned (`first_seen_at`, `last_seen_at`, `restated`). For back-filled periods, `available_at = period_end + lag` with a conservative default lag of 45 days (quarterly) and 100 days (annual); for periods first observed by our own weekly pulls, `available_at = first_seen_at`. The causal reason: statements were published after the period closed, so using the period-end date would leak future information into every training row.
3. **Adjusted prices.** Determine empirically, per source, whether OHLCV is split- and dividend-adjusted by comparing two sources on tickers with known corporate actions. Store `adj_basis`. Flag any daily return beyond the exchange limit (HOSE ±7%, HNX ±10%, UPCoM ±15%, configurable) that is not a listing-day event as a suspected unadjusted corporate action, and quarantine it.
4. **Suspensions.** A session with zero volume yields a `NaN` return; never forward-fill across suspensions of more than five sessions.
5. **Calendar.** Trading days are the union of observed bars and the events feed; holidays (including Tết) come from the events feed plus a manual override table.
6. **Global series** (US, FX) are lagged by one Vietnamese session so that no value dated after the Vietnamese close is used.

**Data-quality gates.** Blocking: stale latest bar for more than 2% of Tier A symbols; duplicate keys; non-positive prices; high < low; volume negative; cross-source close mismatch above 0.5% on a 30-symbol random sample; row-count drop above 5% versus yesterday. Warning: suspected unadjusted actions, new tickers, universe turnover above 5%, and feature null-rate shifts. A blocking failure keeps yesterday's snapshot live and marks the app `STALE` with the reason.

## 5. Storage design

### 5.1 PostgreSQL (large-scale wrangling)

Schemas: `raw` (append-only landings), `core` (typed, adjusted, deduplicated), `feat` (features and labels), `ml` (runs, models, folds, predictions, recommendations, backtests), `ops` (pipeline runs, step runs, API-call ledger, quality results).

Key tables: `core.symbols`, `core.listing_snapshots`, `core.bars_daily(symbol_id, trade_date, o, h, l, c, v, value, adj_basis)` with primary key `(symbol_id, trade_date)`, `core.index_bars`, `core.fundamentals_pit`, `core.calendar`, `feat.features_daily` (wide, one row per symbol-date, versioned by `feature_set_hash`), `feat.labels_daily`, `ml.runs`, `ml.models`, `ml.predictions`, `ml.recommendations`, `ops.api_calls`.

Operating profile for one user: no replication, no connection pooler, `shared_buffers` ≈ 25% of RAM, generous `work_mem`, `synchronous_commit = off` during bulk loads only, BRIN or B-tree on date columns, no partitioning at this size. Numbered SQL migrations are applied by `vnpipe migrate`. Backups: `pg_dump` weekly, 8 rolling copies. The SQLite snapshot is disposable and always rebuildable.

### 5.2 SQLite serving snapshot (ultra-low-latency inference)

The exporter writes `serving.sqlite.tmp`, runs `PRAGMA integrity_check`, then atomically renames it to `serving.sqlite`; the app detects the swap with a file watcher and reopens read-only. Contents:

- `meta` (as-of date, feature-schema hash, git SHA, run id, health state), `symbols`.
- `bars_daily` for the most recent 756 sessions (about 3 years, for charts), declared `STRICT` and `WITHOUT ROWID` with key `(symbol_id, trade_date)`; `index_bars`.
- `features_latest(symbol_id, as_of, vec BLOB)`: a little-endian `f32` vector ordered by the feature schema, so inference reads one contiguous blob per symbol.
- `models(model_id, kind, blob, sha256, feature_schema_hash, trained_through)`: the champion boosters travel inside the snapshot, so features, model and predictions can never disagree.
- `predictions`, `recommendations`, `shap_top`, `model_health`.

Pragmas on read connections: `journal_mode = WAL`, `query_only = ON`, `mmap_size` ≥ 512 MB, `temp_store = MEMORY`, `cache_size` sized to the file. There is a single writer (the exporter, offline) and a single reader (the app), so there is no lock contention.

**Inference paths.** (a) Default: read the precomputed nightly predictions. (b) Live: load the champion from `models`, score all `features_latest` vectors in-process (used for what-if constraints, universe filters and the parity test). Parity requirement: live and precomputed scores agree within 1e-6.

## 6. Feature engineering

All features at date *t* use data available at the *t* close and nothing later. Target size is about 150 features, defined once in `sql/features/*.sql` through the function `feat.build_features(date_from, date_to)`, which recomputes only the trailing window needed for new dates. The same table feeds training and serving, which removes train/serve skew by construction.

| Family | Examples |
| --- | --- |
| Momentum and reversal | Returns over 1, 2, 3, 5, 10, 20, 60, 120, 250 sessions; 12-1 momentum; residual momentum; distance from 52-week high and low |
| Trend and oscillators | Price/SMA and price/EMA ratios (5 to 200), RSI(14), MACD histogram scaled by price, Bollinger %b and bandwidth, ADX, stochastic |
| Volatility and risk | Realised volatility (5/20/60), downside volatility, ATR%, skewness and kurtosis (60), beta and idiosyncratic volatility versus VNINDEX (60/250), correlation with VN30 |
| Liquidity and flow | Traded-value rank, turnover (volume ÷ listed shares), volume z-scores, Amihud illiquidity, OBV slope, close-location value, gap statistics |
| Vietnam microstructure | Ceiling/floor hits in the last 5 and 20 sessions, consecutive limit streaks, distance to price limit, consecutive up/down days |
| Cross-sectional context | Per-date percent-rank and rank-Gaussian transforms of key features across the universe and within ICB industry |
| Market regime | VNINDEX trend state (price versus 50/200-session averages), realised volatility, drawdown, breadth (share above 50-session average, advance/decline, new highs minus lows), market turnover z-score, cross-sectional dispersion, VN30 versus VNMID/VNSML relative strength, sector relative strength |
| Calendar | Day of week, month, sessions to and from Tết, quarter-end proximity |
| Fundamental overlay (separate matrix) | TTM margins, ROE and ROA, year-on-year and sequential growth, growth acceleration, leverage, accruals, P/E and P/B from listed shares; banks use a bank-specific item map and industry-relative ranks |

Nulls are preserved (LightGBM handles them natively). A Rust/Polars reference implementation recomputes 20 random symbol-days and must match SQL to 1e-9 in CI.

## 7. Modelling and training

### 7.1 Targets

Signal at the close of *t*; entry at the open of *t+1* (assumed fill with slippage); exit at the close of *t+1+h*. Label `y_h` = stock return minus VNINDEX return over that window, with *h* ∈ {5, 20} sessions (default decision horizon 20). Labels are winsorised at the 1st and 99th cross-sectional percentiles. Training targets are rank-Gaussian transformed within each date; the quantile heads use the untransformed excess return so that quantiles remain interpretable in percentage points.

### 7.2 Model family

Gradient-boosted trees (LightGBM) are the primary learner, because daily cross-sectional data with \~0.8 million rows and a low signal-to-noise ratio favours strongly regularised trees over deep networks, and trees train in minutes on a laptop.

- **H1** score at 20 sessions (L2 on rank-Gaussian target), 3 bagging seeds.
- **H2** score at 5 sessions, 3 seeds.
- **H3** quantile heads (0.10, 0.50, 0.90) on the 20-session excess return.
- **H4** log forward realised volatility (20 sessions), used for risk sizing.
- **Challenger (optional):** LambdaRank with per-date query groups on quintile labels.
- **Regularisation defaults:** learning rate 0.03, `num_leaves` ≤ 31, `min_data_in_leaf` ≥ 500, feature and bagging fraction 0.7, L2 penalty, 300 to 800 rounds with early stopping on the last validation fold. Exponential time-decay sample weights with a tunable half-life (0.5 to 3 years), because the market's regime has shifted repeatedly.
- **Composite score:** `s = 0.7·z(H1) + 0.3·z(H2) + w_B·z(B)`, with weights fitted by walk-forward IC under bounds and shrinkage towards the defaults.

### 7.3 Fundamental overlay model B

Because the free tier exposes only 8 periods of abridged statements, the fundamental history in the training window is short, and a model that sees fundamentals as null for older rows could learn "missing ⇒ earlier era", which is a time proxy and not an economic signal. Therefore model B is trained **separately**, only on dates where the fundamental features are available point-in-time, and it enters the composite only when `n_pit_quarters ≥ 6` and its own walk-forward IC is positive; `w_B` is bounded to \[0, 0.5\]. The weight grows automatically as the point-in-time archive deepens.

### 7.4 Validation

Expanding-window purged walk-forward: minimum 3 years of training, monthly test blocks, an embargo of at least 20 sessions between the training end and the test start (labels overlap), and purging of any training row whose label window intersects a test block. Report for each block and in aggregate: daily Spearman rank IC, mean IC, IC information ratio, Newey–West t-statistic (lag ≥ 20), top-quintile minus bottom-quintile spread, top-quintile minus universe, hit rate, and quantile coverage for H3 (should be near 80% for the 10–90 band). Every hyperparameter trial is counted, and Sharpe-type results are reported with a deflation for the number of trials.

### 7.5 Cadence

- **Daily:** refit with frozen hyperparameters (minutes), evaluate, and pass through the promotion gate. Because the 20-session label means each day adds only one newly labelled date, daily refits change the model marginally; the gate therefore decides promotion and prevents churn.
- **Monthly (first Saturday):** random-search or successive-halving tuning over about 40 trials on the walk-forward folds, with a fixed wall-clock budget.
- **Reproducibility:** each run stores the git SHA, data snapshot hash, feature-set hash, seeds, parameters and fold metrics in `ml.runs`. Re-running with identical inputs must yield identical predictions.

### 7.6 Promotion gate

A challenger replaces the champion only if (a) its rank IC over the last 12 monthly test blocks is at least the champion's minus 0.005, (b) the top-quintile maximum drawdown is no worse by more than 2 percentage points, and (c) leakage tests, feature-parity tests and live-versus-precomputed parity all pass. Otherwise the champion is retained and the reason is logged.

### 7.7 Calibration, explanation and health

- **Calibration:** isotonic regression (pool-adjacent-violators, implemented in Rust) on out-of-sample scores gives `P(beats VNINDEX over 20 sessions)`.
- **Explanation:** native TreeSHAP through LightGBM's `pred_contrib`; the top 5 contributions per symbol are written to `shap_top` and rendered in plain language.
- **Health state machine:** `HEALTHY`, `DEGRADED` or `HALTED`, driven by the rolling 60-session IC, quantile-coverage error and feature drift (PSI against the trailing 250 sessions). `DEGRADED` caps gross exposure at 50% and flags every suggestion; `HALTED` suppresses suggestions and shows cash as the default.
- **Honesty clause:** the system must not require a positive backtest to ship. If the out-of-sample IC confidence interval includes zero, the app displays a low-confidence banner and defaults to a defensive allocation. Expected rank IC for daily Vietnamese equity data is modest (single-digit hundredths), and the app reports whatever is measured.

## 8. Recommendation engine

**Portfolio construction.** Long-only. Maximise `αᵀw − λ·wᵀΣw − κ·cost(w, w_prev)` subject to the constraints below, with Σ from Ledoit–Wolf shrinkage on 250 sessions, solved by `clarabel`; if infeasible, fall back to volatility-scaled rank weights.

- Positions 10 to 15 by default; maximum weight 12%; maximum ICB-industry weight 35%.
- Liquidity: order value ≤ 5% of 20-session average traded value; exclude symbols below the liquidity floor.
- Tradability: exclude names at the ceiling on the signal day (a buy cannot fill), listed under 250 sessions, or on the user's manual blacklist (the free tier has no feed for trading-status warnings).
- Rebalance every 5 sessions by default, with a turnover penalty; "no action" is a valid output.
- Exposure overlay: if VNINDEX is below its 200-session average and breadth is under 30%, reduce target gross exposure to 50% (configurable heuristic, documented as such); apply the same cap in `DEGRADED` health.

**Vietnam trading rules (all in `config`, none hard-coded).** Daily price limits by exchange; lot size (100 on HOSE, with odd-lot handling); settlement of T+2 with earliest sale per broker convention; commission default 0.15% per side; sale tax 0.10% of sale value; slippage `5 bps + 25 bps × sqrt(order value ÷ ADV20)`, capped.

**Per-symbol output schema.** Action (`BUY`, `ADD`, `HOLD`, `TRIM`, `SELL`, `AVOID`); conviction 0 to 100 (cross-sectional rank, seed agreement and calibration); expected 20-session excess return as P10, P50 and P90; calibrated probability of beating the index; target weight, VND amount and whole-lot share count given the user's capital; ATR-based review level; top-5 SHAP drivers; risk flags (liquidity, proximity to limit, stale fundamentals, wide uncertainty band, regime cap, health state); estimated round-trip cost.

## 9. Backtesting

An event-driven daily backtester in Rust that reuses the production portfolio code and cost model, with these rules: signal at close *t*, fill at open *t+1* plus slippage; price-limit and lot-size enforcement; T+2 sale restriction; fees and tax; capacity cap against ADV; no use of any value stamped after *t*. Report: annualised return and volatility, Sharpe and Sortino, maximum drawdown, turnover, hit rate, average holding period, and results against VNINDEX and VN30, in total and by calendar year. Apply an explicit survivorship haircut to returns (default 1.0 percentage point per year, configurable and disclosed). Produce an HTML report per promotion and store it in `ml.backtests`.

## 10. Daily pipeline and CI/CD

### 10.1 Daily pipeline (Go orchestrator, idempotent, resumable)

Trigger: 17:30 Asia/Ho\_Chi\_Minh on weekdays, with catch-up if the machine was asleep, and retries until 23:00 while the latest bar date is behind the expected session. Steps recorded in `ops.step_runs`:

1. **Preflight:** disk, Postgres health, `vnstock status` and `usage`, trading-calendar check (skip non-session days), compute call budget `B`.
2. **Ingest** indices, then Tier A bars, then (weekly) Tier B and statements, within `B`; on `RateLimitedError`, wait at least 60 seconds and resume from the checkpoint.
3. **Quality gate 1** on raw data; **merge** into `core`; corporate-action screen.
4. **Build features and labels** for new dates; **quality gate 2** (null rates, PSI).
5. **Train** (daily refit; monthly tuning on schedule), **evaluate**, **promotion gate**.
6. **Score and recommend**; **backtest** report when the champion changes.
7. **Export** the snapshot, integrity-check, atomic swap, notify the app, write the run report.
8. **Housekeeping:** weekly backups, retention of raw landings (90 days).

Failure policy: any blocking failure leaves the previous snapshot live, marks `STALE` with the cause, and sends an OS notification. Nothing partial is ever served. Target duration: under 60 minutes at 60 req/min and under 120 minutes at 20 req/min.

### 10.2 Backfill (one-time, resumable)

Order: listing and indices, then daily bars for all listed symbols, then the liquidity ranking and universe selection, then statements for the investable set (about 3 reports × 2 period types × 400 symbols ≈ 2,400 calls). Checkpoint after every call; pause when the daily bucket is within 20% of exhaustion; resume automatically after the 00:00 reset.

### 10.3 CI/CD

- **CI (GitHub Actions, on push and pull request, no network access to vnstock):** `go vet` and tests; `cargo clippy -D warnings`, `cargo test`, `cargo deny`; UI build; migration test against an ephemeral Postgres service container; leakage tests, feature-parity tests and golden-metric backtest regression on frozen fixtures.
- **Leakage test (mandatory):** perturb every price and volume after date *t* with random noise and assert that all features and predictions for dates ≤ *t* are bit-identical.
- **CD:** tagged releases build the Tauri installer and the `vnpipe` binary as artefacts. Deployment of data and models is the daily pipeline itself (continuous training with the promotion gate), and it runs on the user's machine as an OS service (`vnpipe daemon install`). Hosted CI runners must not run it, because of the device cap and the local database. A self-hosted runner on the same machine is an acceptable alternative trigger.

## 11. Desktop application

Screens: **Today** (ranked suggestions with action, conviction, expected-return band, probability, weight and VND amount, risk flags); **Stock** (price chart with signal history, SHAP drivers, peer ranks, derived fundamentals); **Portfolio** (manual entry or CSV import, P&L, rebalance diff in whole lots); **Market regime** (trend, breadth, volatility, exposure cap); **Model health** (IC over time, calibration plot, PSI, champion and challenger, last retrain); **Backtest explorer**; **Pipeline and quota** (run log, `STALE` reason, remaining quota); **Settings** (capital, risk aversion, constraints, costs, universe filters, blacklist).

Performance budgets (measured on a mid-range laptop, enforced by benchmarks in CI): SQLite point lookup p99 under 2 ms; full-universe ranked query p99 under 25 ms; live rescoring of 400 symbols with the full ensemble p99 under 150 ms; cold start under 2 s; snapshot swap visible within 1 s; idle memory under 300 MB. The only listeners permitted are Postgres on loopback and Tauri IPC.

## 12. Engineering standards

Structured logging (`tracing` in Rust, `slog` in Go) with a run id on every line; typed errors; configuration in `config/default.toml` with a user override file and validation at start-up; secrets (the vnstock API key) in the OS keychain or an untracked `.env`, never in the repository; deterministic builds with pinned dependencies and lock files; `docs/DATA_CONTRACT.md` describing every table and column; a model card regenerated on each promotion, listing training window, known biases (survivorship, short fundamental history), metrics and limits.

Repository layout: `go/` (`cmd/vnpipe`, `internal/{sched,quota,ingest,dq,export,notify}`), `rust/` (`crates/{train,infer,backtest,portfolio,types}`, `app/src-tauri`), `ui/`, `py/vnstock_worker.py`, `sql/{migrations,features}`, `config/`, `docs/`, `.github/workflows/`.

## 13. Delivery phases and exit criteria

| Phase | Deliverable | Exit criteria |
| --- | --- | --- |
| 0 | Probe, schema contracts, config, repository skeleton | Probe report committed; limits read from it; migrations apply cleanly |
| 1 | Worker, ingestion, quota ledger, Postgres `core`, quality gates, resumable backfill | Full backfill completes within quota; gates fail correctly on injected faults |
| 2 | SQL features, labels, point-in-time fundamentals archive | Leakage test and feature-parity test green; null-rate report produced |
| 3 | Trainer, purged walk-forward, calibration, promotion gate, backtester | At least 36 months of out-of-sample blocks reported honestly; reproducible re-run |
| 4 | Snapshot exporter, in-process inference, recommendation engine | Live/precomputed parity within 1e-6; latency budgets met |
| 5 | Tauri application, all screens | Budgets in §11 met; `STALE`, `DEGRADED` and `HALTED` states render correctly |
| 6 | Daily daemon, catch-up, CI/CD, backups, runbook | Seven consecutive unattended daily runs; idempotent re-run yields identical hashes |

## Appendix — default configuration

```toml
[vnstock]
tier_rate_utilisation = 0.85
quota_soft_ceiling = 0.80

[universe]
investable_n = 400
exit_rank = 500
min_sessions_listed = 250
min_adv20_vnd = 5_000_000_000

[labels]
horizons = [5, 20]
entry = "next_open"
benchmark = "VNINDEX"

[validation]
min_train_years = 3
embargo_sessions = 20
test_block = "1M"

[portfolio]
max_positions = 15
max_weight = 0.12
max_industry_weight = 0.35
rebalance_every_sessions = 5
order_to_adv_cap = 0.05
risk_off_gross_cap = 0.50

[costs]
commission_per_side = 0.0015
sale_tax = 0.0010
slippage_base_bps = 5
slippage_impact_bps = 25
survivorship_haircut_per_year = 0.01

[exchange_limits]
HOSE = 0.07
HNX = 0.10
UPCOM = 0.15

[schedule]
timezone = "Asia/Ho_Chi_Minh"
daily_trigger = "17:30"
retry_until = "23:00"
```

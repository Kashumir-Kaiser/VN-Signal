use std::collections::{HashMap, HashSet};
use std::env;
use std::time::Instant;

use postgres::{Client, NoTls};
use vn_signal_phase2_parity::{
    CrossSectionalFeature, MarketFeature, PriceSession, ReferenceFeature,
    compute_cross_sectional_features, compute_market_features_from_reference,
    compute_reference_features,
};

const PARITY_TOLERANCE: f64 = 1e-9;

struct DateParity {
    symbol_ids: Vec<i64>,
    current_features: Vec<ReferenceFeature>,
    cross_sectional: Vec<CrossSectionalFeature>,
    market: Vec<MarketFeature>,
}

struct CachedMarketBar {
    symbol_id: i64,
    trade_date: String,
    episode_start_date: String,
    open: Option<f64>,
    high: Option<f64>,
    low: Option<f64>,
    close: Option<f64>,
    volume: Option<f64>,
    adjustment_ratio: Option<f64>,
}

fn load_cached_market_bars(client: &mut Client, target_date: &str) -> Vec<CachedMarketBar> {
    client
        .query(
            r"WITH market_symbols AS MATERIALIZED (
                SELECT DISTINCT symbol_id
                FROM feat.features_daily
                WHERE feature_version='phase2-v2' AND trade_date<=$1::text::date
            )
            SELECT r.symbol_id,r.trade_date::text,r.episode_start_date::text,
                   r.model_o::double precision,r.model_h::double precision,
                   r.model_l::double precision,r.model_c::double precision,
                   r.v::double precision,r.reference_adjustment_ratio::double precision
            FROM pg_temp.phase2_adjustment_rows r
            JOIN market_symbols m USING(symbol_id)
            WHERE r.source='vndirect' AND r.trade_date<=$1::text::date",
            &[&target_date],
        )
        .expect("read the production point-in-time input cache")
        .into_iter()
        .map(|row| CachedMarketBar {
            symbol_id: row.get(0),
            trade_date: row.get(1),
            episode_start_date: row.get(2),
            open: row.get(3),
            high: row.get(4),
            low: row.get(5),
            close: row.get(6),
            volume: row.get(7),
            adjustment_ratio: row.get(8),
        })
        .collect()
}

fn load_index_closes(client: &mut Client, target_date: &str) -> HashMap<String, Option<f64>> {
    client
        .query(
            r"SELECT trade_date::text,c::double precision
              FROM core.index_bars
              WHERE index_symbol='VNINDEX' AND source='vci'
                AND trade_date<=$1::text::date",
            &[&target_date],
        )
        .expect("load point-in-time VNINDEX closes")
        .into_iter()
        .map(|row| (row.get(0), row.get(1)))
        .collect()
}

fn calendar_axis(client: &mut Client, target_date: &str) -> Vec<(String, i64)> {
    client
        .query(
            r"WITH raw_min AS (
                SELECT min(trade_date) AS d FROM core.bars_daily_sources WHERE source='vndirect'
            ), chunk_start AS (
                SELECT greatest(r.d,date_trunc('year',$1::text::date)::date) AS d
                FROM raw_min r
            ), prior AS (
                SELECT e.trade_date FROM core.effective_trading_sessions e CROSS JOIN raw_min r
                CROSS JOIN chunk_start c
                WHERE e.is_session AND e.trade_date<c.d ORDER BY e.trade_date DESC LIMIT 1000
            ), requested AS (
                SELECT e.trade_date FROM core.effective_trading_sessions e CROSS JOIN chunk_start c
                WHERE e.is_session AND e.trade_date>=c.d AND e.trade_date<=$1::text::date
            ), bounded AS (SELECT trade_date FROM prior UNION SELECT trade_date FROM requested),
            global_sessions AS (
                SELECT e.trade_date,row_number() OVER(ORDER BY e.trade_date)::bigint AS session_ordinal
                FROM core.effective_trading_sessions e
                WHERE e.is_session AND e.trade_date<=$1::text::date
            )
            SELECT b.trade_date::text,g.session_ordinal
            FROM bounded b JOIN global_sessions g USING(trade_date)
            ORDER BY b.trade_date",
            &[&target_date],
        )
        .expect("load the effective calendar used by the SQL session axis")
        .iter()
        .map(|row| (row.get(0), row.get(1)))
        .collect()
}

fn load_market_histories(
    source_rows: &[CachedMarketBar],
    target_date: &str,
    calendar_axis: &[(String, i64)],
    market_symbol_ids: &[i64],
    exchanges: &HashMap<i64, String>,
    index_closes: &HashMap<String, Option<f64>>,
) -> HashMap<i64, Vec<PriceSession>> {
    let market_symbols: HashSet<i64> = market_symbol_ids.iter().copied().collect();
    let mut source_by_symbol: HashMap<i64, Vec<&CachedMarketBar>> = HashMap::new();
    for row in source_rows {
        if market_symbols.contains(&row.symbol_id) && row.trade_date.as_str() <= target_date {
            source_by_symbol.entry(row.symbol_id).or_default().push(row);
        }
    }

    let mut histories = HashMap::with_capacity(market_symbol_ids.len());
    for symbol_id in market_symbol_ids {
        let mut rows = source_by_symbol.remove(symbol_id).unwrap_or_default();
        rows.sort_by(|left, right| {
            (&left.episode_start_date, &left.trade_date)
                .cmp(&(&right.episode_start_date, &right.trade_date))
        });
        let eligible = rows.iter().all(|row| {
            row.adjustment_ratio
                .is_some_and(|ratio| ratio.is_finite() && ratio > 0.0)
        });
        let mut adjusted_by_date: HashMap<&str, (&CachedMarketBar, f64)> = HashMap::new();
        if eligible {
            let mut start = 0;
            while start < rows.len() {
                let episode = &rows[start].episode_start_date;
                let mut end = start + 1;
                while end < rows.len() && rows[end].episode_start_date == *episode {
                    end += 1;
                }
                let episode_rows = &rows[start..end];
                let mut cumulative_log_factor = 0.0;
                for row in episode_rows {
                    cumulative_log_factor += row.adjustment_ratio.expect("eligible factor").ln();
                    // Match SQL's neutral episode basis for OHLC features.
                    // Turnover retains the unnormalized model close separately.
                    let factor = (-cumulative_log_factor).exp();
                    adjusted_by_date.insert(&row.trade_date, (row, factor));
                }
                start = end;
            }
        }

        let exchange = exchanges.get(symbol_id).cloned();
        let history = calendar_axis
            .iter()
            .map(|(trade_date, ordinal)| {
                let adjusted = adjusted_by_date.get(trade_date.as_str());
                let bar = adjusted.map(|(row, factor)| (*row, *factor));
                let volume = bar.and_then(|(row, _)| row.volume);
                PriceSession {
                    session_ordinal: *ordinal,
                    close: bar.and_then(|(row, factor)| row.close.map(|value| value * factor)),
                    model_close: bar.and_then(|(row, _)| row.close),
                    open: bar.and_then(|(row, factor)| row.open.map(|value| value * factor)),
                    high: bar.and_then(|(row, factor)| row.high.map(|value| value * factor)),
                    low: bar.and_then(|(row, factor)| row.low.map(|value| value * factor)),
                    volume,
                    traded: volume.is_some_and(|value| value > 0.0),
                    episode: bar.map(|(row, _)| row.episode_start_date.clone()),
                    exchange: exchange.clone(),
                    trade_date: trade_date.clone(),
                    index_close: index_closes.get(trade_date).copied().flatten(),
                }
            })
            .collect();
        histories.insert(*symbol_id, history);
    }
    histories
}

#[cfg(test)]
mod batched_history_tests {
    use super::{CachedMarketBar, load_market_histories};
    use std::collections::HashMap;

    fn bar(
        trade_date: &str,
        episode_start_date: &str,
        close: f64,
        adjustment_ratio: f64,
    ) -> CachedMarketBar {
        CachedMarketBar {
            symbol_id: 7,
            trade_date: trade_date.to_owned(),
            episode_start_date: episode_start_date.to_owned(),
            open: Some(close),
            high: Some(close + 1.0),
            low: Some(close - 1.0),
            close: Some(close),
            volume: Some(100.0),
            adjustment_ratio: Some(adjustment_ratio),
        }
    }

    #[test]
    fn batched_history_sorts_rows_applies_episode_factors_and_stops_at_target() {
        // Rows intentionally arrive out of order, as a batched SQL result need
        // not be ordered. The third row is beyond the PIT cutoff and must not
        // enter the history or its episode factor.
        let rows = vec![
            bar("2024-01-02", "2024-01-01", 20.0, 0.8),
            bar("2024-01-03", "2024-01-03", 30.0, 0.5),
            bar("2024-01-01", "2024-01-01", 10.0, 0.5),
        ];
        let axis = vec![("2024-01-01".to_owned(), 1), ("2024-01-02".to_owned(), 2)];
        let exchanges = HashMap::from([(7, "HOSE".to_owned())]);
        let index_closes = HashMap::from([
            ("2024-01-01".to_owned(), Some(1_100.0)),
            ("2024-01-02".to_owned(), Some(1_101.0)),
        ]);

        let histories =
            load_market_histories(&rows, "2024-01-02", &axis, &[7], &exchanges, &index_closes);
        let history = &histories[&7];

        assert_eq!(history.len(), 2);
        assert_eq!(history[0].trade_date, "2024-01-01");
        assert_eq!(history[1].trade_date, "2024-01-02");
        assert_eq!(history[0].session_ordinal, 1);
        assert_eq!(history[1].session_ordinal, 2);
        assert_eq!(history[0].episode.as_deref(), Some("2024-01-01"));
        assert_eq!(history[1].episode.as_deref(), Some("2024-01-01"));
        assert_eq!(history[0].close, Some(20.0));
        assert_eq!(history[1].close, Some(50.0));
        assert_eq!(history[0].model_close, Some(10.0));
        assert_eq!(history[1].model_close, Some(20.0));
        assert_eq!(history[0].index_close, Some(1_100.0));
        assert_eq!(history[1].index_close, Some(1_101.0));
    }

    #[test]
    fn retains_prior_market_bars_when_symbol_has_no_target_day_bar() {
        let rows = vec![
            bar("2024-01-01", "2024-01-01", 10.0, 0.5),
            bar("2024-01-03", "2024-01-01", 30.0, 0.5),
        ];
        let axis = vec![("2024-01-01".to_owned(), 1), ("2024-01-02".to_owned(), 2)];
        let exchanges = HashMap::from([(7, "HOSE".to_owned())]);
        let index_closes = HashMap::new();

        let histories =
            load_market_histories(&rows, "2024-01-02", &axis, &[7], &exchanges, &index_closes);
        let history = &histories[&7];

        assert_eq!(history[0].model_close, Some(10.0));
        assert_eq!(history[0].close, Some(20.0));
        assert_eq!(history[1].model_close, None);
        assert_eq!(history[1].close, None);
    }
}

fn load_date_reference(
    client: &mut Client,
    target_date: &str,
    source_rows: &[CachedMarketBar],
    index_closes: &HashMap<String, Option<f64>>,
) -> DateParity {
    let axis = calendar_axis(client, target_date);
    let symbol_ids: Vec<i64> = client
        .query(
            r"SELECT DISTINCT symbol_id FROM feat.features_daily
              WHERE feature_version='phase2-v3' AND trade_date=$1::text::date
              ORDER BY symbol_id",
            &[&target_date],
        )
        .expect("load the v3 cross-sectional universe for the signal date")
        .iter()
        .map(|row| row.get(0))
        .collect();
    assert!(
        !symbol_ids.is_empty(),
        "v3 reference universe is empty at {target_date}"
    );
    let calendar_rows = client
        .query(
            r"SELECT trade_date::text FROM core.effective_trading_sessions
              WHERE is_session AND trade_date<=$1::text::date
              ORDER BY trade_date DESC LIMIT 260",
            &[&target_date],
        )
        .expect("load the 260-session reference axis");
    let first_date: String = calendar_rows
        .last()
        .expect("effective session history exists")
        .get(0);
    let market_symbol_rows = client
        .query(
            r"SELECT DISTINCT f.symbol_id,s.exchange FROM feat.features_daily f
              JOIN core.symbols s USING(symbol_id)
              WHERE f.feature_version='phase2-v2' AND f.trade_date BETWEEN $1::text::date AND $2::text::date
              ORDER BY f.symbol_id,s.exchange",
            &[&first_date, &target_date],
        )
        .expect("load the complete recent SQL market universe");
    let market_symbol_ids: Vec<i64> = market_symbol_rows.iter().map(|row| row.get(0)).collect();
    let exchanges: HashMap<i64, String> = market_symbol_rows
        .iter()
        .map(|row| (row.get(0), row.get(1)))
        .collect();
    let mut histories_by_symbol = load_market_histories(
        source_rows,
        target_date,
        &axis,
        &market_symbol_ids,
        &exchanges,
        index_closes,
    );
    let histories: Vec<Vec<PriceSession>> = market_symbol_ids
        .iter()
        .map(|symbol_id| {
            histories_by_symbol
                .remove(symbol_id)
                .expect("set-based history query returned every v2 market symbol")
        })
        .collect();
    let per_symbol: Vec<Vec<ReferenceFeature>> = histories
        .iter()
        .map(|history| compute_reference_features(history).expect("valid point-in-time bars"))
        .collect();
    let market_index_by_symbol: HashMap<i64, usize> = market_symbol_ids
        .iter()
        .enumerate()
        .map(|(i, symbol)| (*symbol, i))
        .collect();
    let current_features: Vec<ReferenceFeature> = symbol_ids
        .iter()
        .map(|symbol_id| {
            per_symbol[*market_index_by_symbol
                .get(symbol_id)
                .expect("target v3 symbol exists in recent v2 market universe")]
            .last()
            .expect("signal session exists")
            .clone()
        })
        .collect();
    let cross_sectional = compute_cross_sectional_features(&symbol_ids, &current_features);

    let index_closes: Vec<Option<f64>> = histories[0]
        .iter()
        .map(|session| session.index_close)
        .collect();
    let market = compute_market_features_from_reference(&histories, &index_closes, &per_symbol)
        .expect("aligned market and stock session histories");
    DateParity {
        symbol_ids,
        current_features,
        cross_sectional,
        market,
    }
}

fn prepare_adjustment_cache_in_batches(client: &mut Client) {
    let cache_started = Instant::now();
    let batch_size = 60_i32;
    eprintln!("E3 checkpoint: initializing point-in-time cache batches");
    let batch_count: i32 = client
        .query_one(
            "SELECT feat.begin_phase2_adjustment_rows($1)",
            &[&batch_size],
        )
        .expect("initialize the production point-in-time cache in bounded batches")
        .get(0);
    let batches = client
        .query(
            "SELECT DISTINCT batch_no FROM pg_temp.phase2_adjustment_symbol_batches ORDER BY batch_no",
            &[],
        )
        .expect("list the production cache batches");
    assert_eq!(batches.len(), batch_count as usize);
    for row in batches {
        let batch_no: i32 = row.get(0);
        let batch_started = Instant::now();
        let batch_rows: i64 = client
            .query_one(
                "SELECT feat.populate_phase2_adjustment_rows($1)",
                &[&batch_no],
            )
            .expect("populate one bounded point-in-time cache batch")
            .get(0);
        eprintln!(
            "E3 checkpoint: cache batch {batch_no}/{batch_count} rows {batch_rows}, elapsed {:?}",
            batch_started.elapsed()
        );
    }
    let cached_rows: i64 = client
        .query_one("SELECT feat.finish_phase2_adjustment_rows()", &[])
        .expect("validate and index the complete point-in-time cache")
        .get(0);
    eprintln!(
        "E3 checkpoint: point-in-time cache ready, rows {cached_rows}, elapsed {:?}",
        cache_started.elapsed()
    );
}

#[test]
fn postgres_features_match_polars_reference_for_twenty_symbol_days() {
    let Ok(database_url) = env::var("DATABASE_URL") else {
        if env::var("VNPIPE_REQUIRE_PARITY").as_deref() == Ok("1") {
            panic!("DATABASE_URL is required when VNPIPE_REQUIRE_PARITY=1");
        }
        eprintln!(
            "skipping PostgreSQL parity test: DATABASE_URL is not set and VNPIPE_REQUIRE_PARITY is not 1"
        );
        return;
    };
    let require_real_parity = env::var("VNPIPE_REQUIRE_REAL_PARITY").as_deref() == Ok("1");
    let mut client = Client::connect(&database_url, NoTls)
        .expect("connect to the disposable PostgreSQL acceptance database");
    let transaction_read_only = if require_real_parity { "off" } else { "on" };
    client
        .batch_execute(
            &format!("SET default_transaction_read_only={transaction_read_only}; SET statement_timeout='30min'; SET temp_file_limit='90GB'; SET work_mem='128MB'; SET jit=off; SET synchronous_commit=off; SET application_name='phase2_sql_parity'; BEGIN"),
        )
        .expect("bound SQL parity to an explicit transaction with a thirty-minute statement timeout");

    let persisted: i64 = client
        .query_one(
            "SELECT count(*) FROM feat.features_daily WHERE feature_version='phase2-v3'",
            &[],
        )
        .expect("check the persisted synthetic v3 feature fixture")
        .get(0);
    assert!(
        persisted > 0,
        "the persisted v3 fixture has no feature rows"
    );

    let sample_date_limit = env::var("VNPIPE_PARITY_SAMPLE_DATE_LIMIT")
        .ok()
        .map(|value| {
            value
                .parse::<i64>()
                .expect("valid parity sample date limit")
        });
    if let Some(limit) = sample_date_limit {
        assert!(limit > 0, "parity sample date limit must be positive");
    }
    let sample_date_ceiling = env::var("VNPIPE_PARITY_DATE_CEILING").ok();
    let diagnostic_date = env::var("VNPIPE_PARITY_DIAGNOSTIC_DATE").ok();
    if require_real_parity {
        assert_eq!(
            sample_date_limit,
            Some(3),
            "real-data parity must be bounded to three dates"
        );
        if let Some(date) = &diagnostic_date {
            let bytes = date.as_bytes();
            assert!(
                bytes.len() == 10
                    && bytes[4] == b'-'
                    && bytes[7] == b'-'
                    && bytes
                        .iter()
                        .enumerate()
                        .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit()),
                "diagnostic sample date must be an ISO date"
            );
            eprintln!(
                "E3 diagnostic-only sample restricted to {date}; this run cannot satisfy the full parity gate"
            );
        }
    }

    let sample_started = Instant::now();
    let samples = client
        .query(
            r"WITH real_sample_dates AS MATERIALIZED (
                SELECT e.trade_date AS sample_date
                FROM core.effective_trading_sessions e
                WHERE $2::boolean AND e.is_session
                  AND e.trade_date<DATE '2098-01-01'
                  AND ($3::text IS NULL OR e.trade_date<$3::text::date)
                  AND ($4::text IS NULL OR e.trade_date=$4::text::date)
                  AND EXISTS (
                      SELECT 1
                      FROM feat.features_daily f
                      JOIN core.symbols s ON s.symbol_id=f.symbol_id
                      WHERE f.trade_date=e.trade_date
                        AND f.feature_version='phase2-v3'
                        AND f.ret_1 IS NOT NULL AND f.ret_5 IS NOT NULL
                        AND f.sma_5_ratio IS NOT NULL AND f.vol_5 IS NOT NULL
                        AND f.source='vndirect' AND f.bar_landing_id IS NOT NULL
                        AND f.bar_source_row IS NOT NULL
                        AND s.symbol NOT IN
                            ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE','P2STOCH')
                  )
                ORDER BY md5(e.trade_date::text)
                LIMIT COALESCE($1::bigint,2147483647)
            ), fixture_sample_dates AS MATERIALIZED (
                SELECT f.trade_date AS sample_date
                FROM feat.features_daily f
                WHERE NOT $2::boolean AND f.feature_version='phase2-v3'
                  AND f.ret_1 IS NOT NULL AND f.ret_5 IS NOT NULL
                  AND f.sma_5_ratio IS NOT NULL AND f.vol_5 IS NOT NULL
                GROUP BY f.trade_date
                ORDER BY md5(f.trade_date::text)
                LIMIT COALESCE($1::bigint,2147483647)
            ), sample_dates AS MATERIALIZED (
                SELECT sample_date FROM real_sample_dates
                UNION ALL
                SELECT sample_date FROM fixture_sample_dates
            ), sample_pairs AS MATERIALIZED (
                SELECT f.symbol_id,f.trade_date,
                       row_number() OVER (PARTITION BY f.trade_date
                                          ORDER BY md5(f.symbol_id::text||f.trade_date::text)) AS pair_order,
                       md5(f.trade_date::text) AS date_order
                FROM sample_dates d
                JOIN feat.features_daily f
                  ON f.trade_date=d.sample_date AND f.feature_version='phase2-v3'
                LEFT JOIN core.symbols s ON $2::boolean AND s.symbol_id=f.symbol_id
                WHERE f.ret_1 IS NOT NULL AND f.ret_5 IS NOT NULL
                  AND f.sma_5_ratio IS NOT NULL AND f.vol_5 IS NOT NULL
                  AND (NOT $2::boolean OR (
                      f.trade_date<DATE '2098-01-01'
                      AND ($3::text IS NULL OR f.trade_date<$3::text::date)
                      AND f.source='vndirect' AND f.bar_landing_id IS NOT NULL
                      AND f.bar_source_row IS NOT NULL
                      AND s.symbol NOT IN
                          ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE','P2STOCH')
                  ))
            )
            SELECT f.symbol_id, f.trade_date::text, f.ret_1, f.ret_5, f.sma_5_ratio, f.vol_5,
                    return_20s,return_60s,close_sma20_ratio,close_sma50_ratio,close_sma60_ratio,
                    realized_vol20,realized_vol60,turnover_proxy_vnd,log_turnover_proxy_vnd,
                    turnover_sma20_vnd,volume_sma20,gap_open_1d,intraday_return,intraday_range_pct,
                    close_location,return_2s,return_3s,return_10s,return_120s,return_250s,
                    close_sma100_ratio,close_sma200_ratio,distance_52w_high,distance_52w_low,
                    rsi_14,bollinger_pct_b_20,bollinger_bandwidth_20,downside_vol20,atr_pct_14,
                    volume_zscore_20,obv_slope_20,large_move_approx,session_ordinal,day_of_week,month_of_year,
                    rank_momentum_20s,rank_turnover_proxy,rank_realized_vol20,
                    rank_gaussian_return20,rank_gaussian_turnover_proxy,rank_gaussian_realized_vol20,
                    rank_gaussian_momentum20_industry,vnindex_return_20s,vnindex_return_60s,
                    vnindex_realized_vol20,market_breadth_above_sma50,market_advance_minus_decline,
                    market_new_high_minus_low,market_turnover_z20,market_return_dispersion,
                    vnindex_sma50_ratio,vnindex_sma200_ratio,vnindex_drawdown252,vnindex_realized_vol60,
                    quarter_end_proximity_days,
                    (correlation_vn30_60 IS NULL AND turnover_listed_shares IS NULL AND
                     limit_up_hit IS NULL AND limit_down_hit IS NULL AND limit_up_streak IS NULL AND
                     limit_down_streak IS NULL AND distance_to_price_limit IS NULL AND
                     sessions_to_tet IS NULL AND sessions_from_tet IS NULL AND
                     intraday_realized_variance IS NULL AND intraday_vwap_gap IS NULL AND
                     intraday_closing_auction_share IS NULL AND
                    rank_gaussian_momentum20_industry IS NULL) AS source_dependent_null,
                    momentum_12_1s,residual_momentum_12_1s,ema_5_ratio,ema_10_ratio,ema_20_ratio,
                    ema_50_ratio,ema_100_ratio,ema_200_ratio,macd_histogram_pct,adx_14_sma,
                    stochastic_k_14,stochastic_d_3,downside_vol5,downside_vol60,return_skew_pop60,
                    return_excess_kurtosis_pop60,beta_vnindex_60,beta_vnindex_250,
                    idio_vol_vnindex_60,idio_vol_vnindex_250,amihud_proxy_20,gap_mean20,gap_std20
              FROM feat.features_daily f
              JOIN sample_pairs p USING(symbol_id,trade_date)
              WHERE f.feature_version='phase2-v3' AND f.ret_1 IS NOT NULL
                AND f.ret_5 IS NOT NULL AND f.sma_5_ratio IS NOT NULL AND f.vol_5 IS NOT NULL
              ORDER BY (NOT $2::boolean AND f.symbol_id=(SELECT symbol_id FROM core.symbols WHERE symbol='P2STOCH')
                       AND trade_date IN (
                           SELECT trade_date FROM (
                               SELECT trade_date,row_number() OVER(ORDER BY trade_date)-1 AS offset_no
                               FROM core.calendar WHERE source='phase2_test_fixture'
                           ) fixture_dates WHERE offset_no IN (15,16,18)
                       )) DESC,
                      CASE WHEN $2::boolean THEN p.pair_order END,
                      CASE WHEN $2::boolean THEN p.date_order END,
                      md5(f.symbol_id::text || f.trade_date::text) LIMIT 20",
            &[
                &sample_date_limit,
                &require_real_parity,
                &sample_date_ceiling,
                &diagnostic_date,
            ],
        )
        .expect("select the deterministic random sample of SQL feature rows");
    eprintln!(
        "E3 checkpoint: selected {} deterministic feature rows, elapsed {:?}",
        samples.len(),
        sample_started.elapsed()
    );
    assert_eq!(
        samples.len(),
        20,
        "the selected SQL population must produce exactly 20 eligible symbol-days"
    );
    if require_real_parity {
        let sample_dates: HashSet<String> = samples.iter().map(|row| row.get(1)).collect();
        assert_eq!(
            sample_dates.len(),
            if diagnostic_date.is_some() { 1 } else { 3 },
            "real-data parity must cover all three required dates unless diagnostic-only date is set"
        );

        let database_name: String = client
            .query_one("SELECT current_database()", &[])
            .expect("identify the disposable database before rebuilding features")
            .get(0);
        assert!(
            database_name == "vnsignal_phase2_report_20261019"
                || (database_name.starts_with("vnsignal_phase2_")
                    && database_name.ends_with("_disposable")),
            "real-data parity rebuild is restricted to disposable Phase 2 databases; got {database_name}"
        );
        let symbol_ids: Vec<i64> = samples.iter().map(|row| row.get(0)).collect();
        let trade_dates: Vec<String> = samples.iter().map(|row| row.get(1)).collect();
        // Select before hashing: hashing every candidate landing repeatedly
        // reads the full archive just to choose twenty observations. Validate
        // every selected row instead, so a corrupt selected payload fails the
        // test rather than silently disappearing from the sampling universe.
        let provenance_started = Instant::now();
        let provenance = client
            .query_one(
                r"WITH selected_pairs AS (
                    SELECT * FROM unnest($1::bigint[],$2::text[]) AS p(symbol_id,trade_date)
                ), selected_inputs AS MATERIALIZED (
                    SELECT f.symbol_id,f.trade_date,b.landing_id,b.ingest_id
                    FROM selected_pairs p
                    JOIN feat.features_daily f
                      ON f.symbol_id=p.symbol_id AND f.trade_date=p.trade_date::date
                     AND f.feature_version='phase2-v3'
                    LEFT JOIN core.bars_daily_sources b
                      ON b.symbol_id=f.symbol_id AND b.trade_date=f.trade_date
                     AND b.source='vndirect' AND b.landing_id=f.bar_landing_id
                     AND b.source_row=f.bar_source_row
                ), selected_landings AS MATERIALIZED (
                    SELECT DISTINCT landing_id,ingest_id FROM selected_inputs
                ), verified_landings AS MATERIALIZED (
                    SELECT l.landing_id,l.ingest_id,
                           l.source='vndirect' AND l.route='equity_ohlcv'
                           AND l.payload_sha256=encode(sha256(l.payload_bytes),'hex') AS valid
                    FROM selected_landings k
                    JOIN raw.landings l USING(landing_id,ingest_id)
                )
                SELECT count(*)::bigint,
                       count(*) FILTER(WHERE l.valid)::bigint
                FROM selected_inputs i
                LEFT JOIN verified_landings l USING(landing_id,ingest_id)",
                &[&symbol_ids, &trade_dates],
            )
            .expect("verify archived payload hashes and source-row lineage for all selected real observations");
        eprintln!(
            "E3 checkpoint: selected source lineage verified, elapsed {:?}",
            provenance_started.elapsed()
        );
        assert_eq!(
            provenance.get::<_, i64>(0),
            20,
            "all selected real observations must retain their source inputs"
        );
        assert_eq!(
            provenance.get::<_, i64>(1),
            20,
            "every selected real observation must have an intact archived VNDIRECT payload"
        );
        let current_feature_hash: String = client
            .query_one("SELECT feat.phase2_feature_set_hash_v3()", &[])
            .expect("read the current production V3 feature definition hash")
            .get(0);
        let selected_hashes = client
            .query_one(
                r"WITH selected_pairs AS (
                    SELECT * FROM unnest($1::bigint[],$2::text[]) AS p(symbol_id,trade_date)
                )
                SELECT count(*)::bigint,
                       count(*) FILTER(WHERE f.feature_set_hash=$3)::bigint
                FROM selected_pairs p
                JOIN feat.features_daily f
                  ON f.symbol_id=p.symbol_id AND f.trade_date=p.trade_date::date
                 AND f.feature_version='phase2-v3'",
                &[&symbol_ids, &trade_dates, &current_feature_hash],
            )
            .expect("verify sampled SQL features were built with the current production hash");
        assert_eq!(
            selected_hashes.get::<_, i64>(0),
            20,
            "all sampled real feature rows must still exist in the persisted SQL table"
        );
        assert_eq!(
            selected_hashes.get::<_, i64>(1),
            20,
            "all sampled real feature rows must use the current production V3 feature hash"
        );
        prepare_adjustment_cache_in_batches(&mut client);
    }

    let latest_sample_date = samples
        .iter()
        .map(|row| row.get::<_, String>(1))
        .max()
        .expect("selected SQL parity rows");
    if !require_real_parity {
        client
            .batch_execute("SELECT feat.prepare_phase2_adjustment_rows(true)")
            .expect("materialize the production transaction-local point-in-time price cache once");
    }
    let history_load_started = Instant::now();
    let cached_market_bars = load_cached_market_bars(&mut client, &latest_sample_date);
    let index_closes = load_index_closes(&mut client, &latest_sample_date);
    eprintln!(
        "E3 checkpoint: loaded {} market rows and index context through {latest_sample_date}, elapsed {:?}",
        cached_market_bars.len(),
        history_load_started.elapsed()
    );

    let mut references: HashMap<String, DateParity> = HashMap::new();
    for sample in &samples {
        let signal_date: String = sample.get(1);
        if !references.contains_key(&signal_date) {
            let reference_started = Instant::now();
            eprintln!("E3 checkpoint: starting Polars reference for {signal_date}");
            references.insert(
                signal_date.clone(),
                load_date_reference(
                    &mut client,
                    &signal_date,
                    &cached_market_bars,
                    &index_closes,
                ),
            );
            eprintln!(
                "E3 checkpoint: Polars reference for {signal_date} completed, elapsed {:?}",
                reference_started.elapsed()
            );
        }
    }

    for sample in samples {
        let symbol_id: i64 = sample.get(0);
        let signal_date: String = sample.get(1);
        let expected: Vec<Option<f64>> = (2..37).map(|i| sample.get(i)).collect();
        let expected_large_move: Option<bool> = sample.get(37);
        let date_reference = references
            .get(&signal_date)
            .expect("reference computed for sampled date");
        let symbol_index = date_reference
            .symbol_ids
            .iter()
            .position(|id| *id == symbol_id)
            .expect("sample symbol exists in the SQL cross-sectional universe");
        let actual = &date_reference.current_features[symbol_index];
        let cross = &date_reference.cross_sectional[symbol_index];
        let context = &date_reference.market[date_reference.market.len().saturating_sub(2)];
        let observed: Vec<Option<f64>> = vec![
            actual.ret_1,
            actual.ret_5,
            actual.sma_5_ratio,
            actual.vol_5,
            actual.return_20s,
            actual.return_60s,
            actual.close_sma20_ratio,
            actual.close_sma50_ratio,
            actual.close_sma60_ratio,
            actual.realized_vol20,
            actual.realized_vol60,
            actual.turnover_proxy_vnd,
            actual.log_turnover_proxy_vnd,
            actual.turnover_sma20_vnd,
            actual.volume_sma20,
            actual.gap_open_1d,
            actual.intraday_return,
            actual.intraday_range_pct,
            actual.close_location,
            actual.return_2s,
            actual.return_3s,
            actual.return_10s,
            actual.return_120s,
            actual.return_250s,
            actual.close_sma100_ratio,
            actual.close_sma200_ratio,
            actual.distance_52w_high,
            actual.distance_52w_low,
            actual.rsi_14,
            actual.bollinger_pct_b_20,
            actual.bollinger_bandwidth_20,
            actual.downside_vol20,
            actual.atr_pct_14,
            actual.volume_zscore_20,
            actual.obv_slope_20,
        ];
        let names = [
            "ret_1",
            "ret_5",
            "sma_5_ratio",
            "vol_5",
            "return_20s",
            "return_60s",
            "close_sma20_ratio",
            "close_sma50_ratio",
            "close_sma60_ratio",
            "realized_vol20",
            "realized_vol60",
            "turnover_proxy_vnd",
            "log_turnover_proxy_vnd",
            "turnover_sma20_vnd",
            "volume_sma20",
            "gap_open_1d",
            "intraday_return",
            "intraday_range_pct",
            "close_location",
            "return_2s",
            "return_3s",
            "return_10s",
            "return_120s",
            "return_250s",
            "close_sma100_ratio",
            "close_sma200_ratio",
            "distance_52w_high",
            "distance_52w_low",
            "rsi_14",
            "bollinger_pct_b_20",
            "bollinger_bandwidth_20",
            "downside_vol20",
            "atr_pct_14",
            "volume_zscore_20",
            "obv_slope_20",
        ];
        for (i, feature) in names.iter().enumerate() {
            match (expected[i], observed[i]) {
                (None, None) => {}
                (Some(sql), Some(reference)) => assert!(
                    within_relative_tolerance(sql, reference),
                    "{feature} differs by more than relative tolerance {PARITY_TOLERANCE} for {symbol_id} at {signal_date}: SQL={sql:.15}, Polars={reference:.15}"
                ),
                pair => panic!(
                    "{feature} nullability mismatch for {symbol_id} at {signal_date}: SQL/reference={pair:?}"
                ),
            }
        }
        assert_eq!(
            expected_large_move, actual.large_move_approx,
            "large_move_approx differs for {symbol_id} at {signal_date}"
        );

        for (name, sql, reference) in [
            (
                "rank_momentum_20s",
                sample.get::<_, Option<f64>>(41),
                cross.rank_momentum_20s,
            ),
            (
                "rank_turnover_proxy",
                sample.get::<_, Option<f64>>(42),
                cross.rank_turnover_proxy,
            ),
            (
                "rank_realized_vol20",
                sample.get::<_, Option<f64>>(43),
                cross.rank_realized_vol20,
            ),
            (
                "rank_gaussian_return20",
                sample.get::<_, Option<f64>>(44),
                cross.rank_gaussian_return20,
            ),
            (
                "rank_gaussian_turnover_proxy",
                sample.get::<_, Option<f64>>(45),
                cross.rank_gaussian_turnover_proxy,
            ),
            (
                "rank_gaussian_realized_vol20",
                sample.get::<_, Option<f64>>(46),
                cross.rank_gaussian_realized_vol20,
            ),
            (
                "vnindex_return_20s",
                sample.get::<_, Option<f64>>(48),
                context.vnindex_return_20s,
            ),
            (
                "vnindex_return_60s",
                sample.get::<_, Option<f64>>(49),
                context.vnindex_return_60s,
            ),
            (
                "vnindex_realized_vol20",
                sample.get::<_, Option<f64>>(50),
                context.vnindex_realized_vol20,
            ),
            (
                "market_breadth_above_sma50",
                sample.get::<_, Option<f64>>(51),
                context.market_breadth_above_sma50,
            ),
            (
                "market_turnover_z20",
                sample.get::<_, Option<f64>>(54),
                context.market_turnover_z20,
            ),
            (
                "market_return_dispersion",
                sample.get::<_, Option<f64>>(55),
                context.market_return_dispersion,
            ),
            (
                "vnindex_sma50_ratio",
                sample.get::<_, Option<f64>>(56),
                context.vnindex_sma50_ratio,
            ),
            (
                "vnindex_sma200_ratio",
                sample.get::<_, Option<f64>>(57),
                context.vnindex_sma200_ratio,
            ),
            (
                "vnindex_drawdown252",
                sample.get::<_, Option<f64>>(58),
                context.vnindex_drawdown252,
            ),
            (
                "vnindex_realized_vol60",
                sample.get::<_, Option<f64>>(59),
                context.vnindex_realized_vol60,
            ),
        ] {
            compare_optional(name, sql, reference, symbol_id, &signal_date);
        }
        assert_eq!(
            sample.get::<_, Option<i64>>(52),
            context.market_advance_minus_decline,
            "market_advance_minus_decline differs for {symbol_id} at {signal_date}"
        );
        assert_eq!(
            sample.get::<_, Option<i64>>(53),
            context.market_new_high_minus_low,
            "market_new_high_minus_low differs for {symbol_id} at {signal_date}"
        );
        assert_eq!(
            sample.get::<_, i64>(38),
            actual.session_ordinal,
            "session_ordinal differs for {symbol_id} at {signal_date}"
        );
        assert_eq!(
            sample.get::<_, Option<i16>>(39),
            actual.day_of_week,
            "day_of_week differs for {symbol_id} at {signal_date}"
        );
        assert_eq!(
            sample.get::<_, Option<i16>>(40),
            actual.month_of_year,
            "month_of_year differs for {symbol_id} at {signal_date}"
        );
        assert_eq!(
            sample.get::<_, Option<i16>>(60),
            actual.quarter_end_proximity_days,
            "quarter_end_proximity_days differs for {symbol_id} at {signal_date}"
        );
        assert!(
            sample.get::<_, bool>(61),
            "source-dependent columns must remain NULL without audited evidence for {symbol_id} at {signal_date}"
        );
        // The recovery gate compares non-recursive features on real data.
        // EMA and MACD recursion are checked against the independent pandas
        // golden fixture by both the Rust suite and PostgreSQL assertions.
        let extra = [
            (
                "momentum_12_1s",
                sample.get::<_, Option<f64>>(62),
                actual.momentum_12_1s,
            ),
            (
                "residual_momentum_12_1s",
                sample.get::<_, Option<f64>>(63),
                actual.residual_momentum_12_1s,
            ),
            (
                "adx_14_sma",
                sample.get::<_, Option<f64>>(71),
                actual.adx_14_sma,
            ),
            (
                "stochastic_k_14",
                sample.get::<_, Option<f64>>(72),
                actual.stochastic_k_14,
            ),
            (
                "stochastic_d_3",
                sample.get::<_, Option<f64>>(73),
                actual.stochastic_d_3,
            ),
            (
                "downside_vol5",
                sample.get::<_, Option<f64>>(74),
                actual.downside_vol5,
            ),
            (
                "downside_vol60",
                sample.get::<_, Option<f64>>(75),
                actual.downside_vol60,
            ),
            (
                "return_skew_pop60",
                sample.get::<_, Option<f64>>(76),
                actual.return_skew_pop60,
            ),
            (
                "return_excess_kurtosis_pop60",
                sample.get::<_, Option<f64>>(77),
                actual.return_excess_kurtosis_pop60,
            ),
            (
                "beta_vnindex_60",
                sample.get::<_, Option<f64>>(78),
                actual.beta_vnindex_60,
            ),
            (
                "beta_vnindex_250",
                sample.get::<_, Option<f64>>(79),
                actual.beta_vnindex_250,
            ),
            (
                "idio_vol_vnindex_60",
                sample.get::<_, Option<f64>>(80),
                actual.idio_vol_vnindex_60,
            ),
            (
                "idio_vol_vnindex_250",
                sample.get::<_, Option<f64>>(81),
                actual.idio_vol_vnindex_250,
            ),
            (
                "amihud_proxy_20",
                sample.get::<_, Option<f64>>(82),
                actual.amihud_proxy_20,
            ),
            (
                "gap_mean20",
                sample.get::<_, Option<f64>>(83),
                actual.gap_mean20,
            ),
            (
                "gap_std20",
                sample.get::<_, Option<f64>>(84),
                actual.gap_std20,
            ),
        ];
        for (name, sql, reference) in extra {
            compare_optional(name, sql, reference, symbol_id, &signal_date);
        }
        assert!(
            sample.get::<_, Option<f64>>(47).is_none(),
            "industry Gaussian rank must remain NULL until dated ICB evidence exists"
        );
    }
    client
        .batch_execute("ROLLBACK")
        .expect("discard the session-local cache without changing database data");
}

fn compare_optional(name: &str, sql: Option<f64>, reference: Option<f64>, symbol: i64, date: &str) {
    match (sql, reference) {
        (None, None) => {}
        (Some(sql), Some(reference)) => assert!(
            within_relative_tolerance(sql, reference),
            "{name} differs by more than relative tolerance {PARITY_TOLERANCE} for {symbol} at {date}: SQL={sql:.15}, Polars={reference:.15}"
        ),
        pair => {
            panic!("{name} nullability mismatch for {symbol} at {date}: SQL/reference={pair:?}")
        }
    }
}

fn within_relative_tolerance(left: f64, right: f64) -> bool {
    if left == right {
        return true;
    }
    if !left.is_finite() || !right.is_finite() {
        return false;
    }
    let scale = left.abs().max(right.abs());
    scale > 0.0 && (left - right).abs() / scale <= PARITY_TOLERANCE
}

#[cfg(test)]
mod tolerance_tests {
    use super::{PARITY_TOLERANCE, within_relative_tolerance};

    #[test]
    fn uses_relative_error_at_large_and_small_scales() {
        assert!(within_relative_tolerance(1_000_000_000.0, 1_000_000_000.5));
        assert!(within_relative_tolerance(
            1e-9,
            1e-9 * (1.0 + PARITY_TOLERANCE * 0.5)
        ));
        assert!(!within_relative_tolerance(
            1e-9,
            1e-9 * (1.0 + PARITY_TOLERANCE * 2.0)
        ));
    }

    #[test]
    fn zero_requires_exact_equality() {
        assert!(within_relative_tolerance(0.0, 0.0));
        assert!(!within_relative_tolerance(0.0, f64::MIN_POSITIVE));
    }

    #[test]
    fn rejects_non_finite_values_unless_exactly_equal() {
        assert!(!within_relative_tolerance(f64::NAN, f64::NAN));
        assert!(within_relative_tolerance(f64::INFINITY, f64::INFINITY));
    }
}

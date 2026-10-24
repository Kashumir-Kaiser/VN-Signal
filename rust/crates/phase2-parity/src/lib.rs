use polars_core::prelude::{Column, DataFrame};

#[derive(Clone, Debug, PartialEq)]
pub struct PriceSession {
    /// The signal-session position in the effective Vietnam trading calendar.
    pub session_ordinal: i64,
    /// SQL-neutralized close for this session. `None` means no source bar exists.
    pub close: Option<f64>,
    /// Model close before episode normalization, used by the SQL turnover proxy.
    pub model_close: Option<f64>,
    pub open: Option<f64>,
    pub high: Option<f64>,
    pub low: Option<f64>,
    pub volume: Option<f64>,
    /// True only when the source reports positive matched volume.
    pub traded: bool,
    /// Exchange-documented security episode start. Missing rows inherit the
    /// most recent prior episode, matching the SQL builder's session spine.
    pub episode: Option<String>,
    pub exchange: Option<String>,
    /// ISO date for calendar-derived features.
    pub trade_date: String,
    pub index_close: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ReferenceFeature {
    pub ret_1: Option<f64>,
    pub ret_5: Option<f64>,
    pub sma_5_ratio: Option<f64>,
    pub vol_5: Option<f64>,
    pub return_20s: Option<f64>,
    pub return_60s: Option<f64>,
    pub return_2s: Option<f64>,
    pub return_3s: Option<f64>,
    pub return_10s: Option<f64>,
    pub return_120s: Option<f64>,
    pub return_250s: Option<f64>,
    pub close_sma20_ratio: Option<f64>,
    pub close_sma50_ratio: Option<f64>,
    pub close_sma60_ratio: Option<f64>,
    pub close_sma100_ratio: Option<f64>,
    pub close_sma200_ratio: Option<f64>,
    pub distance_52w_high: Option<f64>,
    pub distance_52w_low: Option<f64>,
    pub realized_vol20: Option<f64>,
    pub realized_vol60: Option<f64>,
    pub rsi_14: Option<f64>,
    pub bollinger_pct_b_20: Option<f64>,
    pub bollinger_bandwidth_20: Option<f64>,
    pub downside_vol20: Option<f64>,
    pub atr_pct_14: Option<f64>,
    pub volume_zscore_20: Option<f64>,
    pub obv_slope_20: Option<f64>,
    pub turnover_proxy_vnd: Option<f64>,
    pub log_turnover_proxy_vnd: Option<f64>,
    pub turnover_sma20_vnd: Option<f64>,
    pub volume_sma20: Option<f64>,
    pub gap_open_1d: Option<f64>,
    pub intraday_return: Option<f64>,
    pub intraday_range_pct: Option<f64>,
    pub close_location: Option<f64>,
    pub large_move_approx: Option<bool>,
    pub session_ordinal: i64,
    pub day_of_week: Option<i16>,
    pub month_of_year: Option<i16>,
    pub quarter_end_proximity_days: Option<i16>,
    /// SQL market breadth uses the partial-frame SMA50 before the full-window
    /// stock SMA ratio is available.
    pub sma50_level_partial: Option<f64>,
    pub momentum_12_1s: Option<f64>,
    pub residual_momentum_12_1s: Option<f64>,
    pub ema_ratios: [Option<f64>; 6],
    pub macd_histogram_pct: Option<f64>,
    pub adx_14_sma: Option<f64>,
    pub stochastic_k_14: Option<f64>,
    pub stochastic_d_3: Option<f64>,
    pub downside_vol5: Option<f64>,
    pub downside_vol60: Option<f64>,
    pub return_skew_pop60: Option<f64>,
    pub return_excess_kurtosis_pop60: Option<f64>,
    pub beta_vnindex_60: Option<f64>,
    pub beta_vnindex_250: Option<f64>,
    pub idio_vol_vnindex_60: Option<f64>,
    pub idio_vol_vnindex_250: Option<f64>,
    pub amihud_proxy_20: Option<f64>,
    pub gap_mean20: Option<f64>,
    pub gap_std20: Option<f64>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct CrossSectionalFeature {
    pub rank_momentum_20s: Option<f64>,
    pub rank_turnover_proxy: Option<f64>,
    pub rank_realized_vol20: Option<f64>,
    pub rank_gaussian_return20: Option<f64>,
    pub rank_gaussian_turnover_proxy: Option<f64>,
    pub rank_gaussian_realized_vol20: Option<f64>,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct MarketFeature {
    pub vnindex_return_20s: Option<f64>,
    pub vnindex_return_60s: Option<f64>,
    pub vnindex_realized_vol20: Option<f64>,
    pub market_breadth_above_sma50: Option<f64>,
    pub market_advance_minus_decline: Option<i64>,
    pub market_new_high_minus_low: Option<i64>,
    pub market_turnover_z20: Option<f64>,
    pub market_return_dispersion: Option<f64>,
    pub vnindex_sma50_ratio: Option<f64>,
    pub vnindex_sma200_ratio: Option<f64>,
    pub vnindex_drawdown252: Option<f64>,
    pub vnindex_realized_vol60: Option<f64>,
}

#[derive(Debug)]
pub enum FeatureError {
    InvalidOrdinal,
    InvalidPrice,
    Polars(polars_core::error::PolarsError),
}

impl From<polars_core::error::PolarsError> for FeatureError {
    fn from(value: polars_core::error::PolarsError) -> Self {
        Self::Polars(value)
    }
}

/// Recomputes the parity subset used by the PostgreSQL acceptance test.
/// Windows count effective exchange sessions, never compressed observations.
pub fn compute_reference_features(
    sessions: &[PriceSession],
) -> Result<Vec<ReferenceFeature>, FeatureError> {
    let mut prior_ordinal = None;
    let mut inherited_episode: Option<String> = None;
    let mut closes = Vec::with_capacity(sessions.len());
    let model_closes: Vec<Option<f64>> = sessions.iter().map(|row| row.model_close).collect();
    let mut opens = Vec::with_capacity(sessions.len());
    let mut highs = Vec::with_capacity(sessions.len());
    let mut lows = Vec::with_capacity(sessions.len());
    let mut volumes = Vec::with_capacity(sessions.len());
    let mut traded = Vec::with_capacity(sessions.len());
    let mut episodes = Vec::with_capacity(sessions.len());

    for row in sessions {
        if prior_ordinal.is_some_and(|prior| row.session_ordinal <= prior) {
            return Err(FeatureError::InvalidOrdinal);
        }
        prior_ordinal = Some(row.session_ordinal);
        if let Some(price) = row.close
            && (!price.is_finite() || price <= 0.0)
        {
            return Err(FeatureError::InvalidPrice);
        }
        if let Some(episode) = &row.episode {
            inherited_episode = Some(episode.clone());
        }
        closes.push(row.close);
        opens.push(row.open);
        highs.push(row.high);
        lows.push(row.low);
        volumes.push(row.volume);
        traded.push(row.traded);
        episodes.push(inherited_episode.clone());
    }

    // Use Polars columns as the reference's typed, null-preserving data model.
    // The SQL contract's rolling windows are then implemented explicitly so
    // their session offsets, endpoint masks and sample-variance denominator
    // remain visible and auditable.
    let frame = DataFrame::new(
        sessions.len(),
        vec![
            Column::new("close".into(), closes.clone()),
            Column::new("open".into(), opens.clone()),
            Column::new("high".into(), highs.clone()),
            Column::new("low".into(), lows.clone()),
            Column::new("volume".into(), volumes.clone()),
            Column::new("traded".into(), traded.clone()),
        ],
    )?;
    let close_values: Vec<Option<f64>> = frame.column("close")?.f64()?.iter().collect();
    let traded_values: Vec<bool> = frame.column("traded")?.bool()?.no_null_iter().collect();
    let open_values: Vec<Option<f64>> = frame.column("open")?.f64()?.iter().collect();
    let high_values: Vec<Option<f64>> = frame.column("high")?.f64()?.iter().collect();
    let low_values: Vec<Option<f64>> = frame.column("low")?.f64()?.iter().collect();
    let volume_values: Vec<Option<f64>> = frame.column("volume")?.f64()?.iter().collect();

    let mut obv_values = vec![None; sessions.len()];
    let mut obv_total = 0.0;
    let mut obv_any = false;
    for i in 1..sessions.len() {
        if episodes[i].as_deref() != episodes[i - 1].as_deref() {
            obv_total = 0.0;
            obv_any = false;
        }
        if episodes[i].is_some()
            && traded_values[i]
            && let Some(volume) = volume_values[i]
        {
            if episodes[i].as_deref() == episodes[i - 1].as_deref()
                && let (Some(close), Some(previous)) = (close_values[i], close_values[i - 1])
            {
                obv_total += volume
                    * if close > previous {
                        1.0
                    } else if close < previous {
                        -1.0
                    } else {
                        0.0
                    };
            }
            obv_any = true;
        }
        if episodes[i].is_some() && obv_any {
            obv_values[i] = Some(obv_total);
        }
    }

    let mut result = Vec::with_capacity(sessions.len());
    for index in 0..sessions.len() {
        let current = close_values[index];
        let current_episode = episodes[index].as_deref();

        let same_episode = |other: usize| {
            current_episode.is_some() && current_episode == episodes[other].as_deref()
        };
        let return_at = |other: usize| -> Option<f64> {
            let now = current?;
            let prior = close_values[other]?;
            (traded_values[index]
                && traded_values[other]
                && same_episode(other)
                && now > 0.0
                && prior > 0.0)
                .then_some(now / prior - 1.0)
        };

        let ret_1 = index.checked_sub(1).and_then(return_at);
        let ret_5 = index.checked_sub(5).and_then(return_at);
        let return_20s = index.checked_sub(20).and_then(return_at);
        let return_60s = index.checked_sub(60).and_then(return_at);
        let return_2s = index.checked_sub(2).and_then(return_at);
        let return_3s = index.checked_sub(3).and_then(return_at);
        let return_10s = index.checked_sub(10).and_then(return_at);
        let return_120s = index.checked_sub(120).and_then(return_at);
        let return_250s = index.checked_sub(250).and_then(return_at);

        let sma_5_ratio = if index >= 4
            && traded_values[index]
            && (index - 4..=index).all(|i| {
                traded_values[i]
                    && close_values[i].is_some()
                    && episodes[i].as_deref() == current_episode
            }) {
            let mean = close_values[index - 4..=index]
                .iter()
                .map(|value| value.expect("validated five traded closes"))
                .sum::<f64>()
                / 5.0;
            current.map(|price| price / mean - 1.0)
        } else {
            None
        };

        let vol_5 = if index >= 4 {
            let returns: Vec<f64> = (index - 4..=index)
                .filter_map(|i| {
                    if i == 0 || episodes[i].as_deref() != current_episode {
                        return None;
                    }
                    let previous = i - 1;
                    if episodes[previous].as_deref() != current_episode {
                        return None;
                    }
                    let now = close_values[i]?;
                    let before = close_values[previous]?;
                    (traded_values[i] && traded_values[previous] && before > 0.0)
                        .then_some(now / before - 1.0)
                })
                .collect();
            if returns.len() == 5 {
                sample_stddev(&returns)
            } else {
                None
            }
        } else {
            None
        };

        let mean_close = |window: usize| -> Option<f64> {
            let start = index.checked_sub(window - 1)?;
            let values = (start..=index)
                .map(|i| {
                    (traded_values[i] && episodes[i].as_deref() == current_episode)
                        .then_some(close_values[i]?)
                })
                .collect::<Option<Vec<_>>>()?;
            Some(values.iter().sum::<f64>() / window as f64)
        };
        let close_sma20_ratio = mean_close(20).and_then(|mean| current.map(|c| c / mean - 1.0));
        let close_sma50_ratio = mean_close(50).and_then(|mean| current.map(|c| c / mean - 1.0));
        let close_sma60_ratio = mean_close(60).and_then(|mean| current.map(|c| c / mean - 1.0));
        let close_sma100_ratio = mean_close(100).and_then(|mean| current.map(|c| c / mean - 1.0));
        let close_sma200_ratio = mean_close(200).and_then(|mean| current.map(|c| c / mean - 1.0));
        let sma50_start = index.saturating_sub(49);
        let sma50_values: Vec<f64> = (sma50_start..=index)
            .filter(|&i| traded_values[i] && episodes[i].as_deref() == current_episode)
            .filter_map(|i| close_values[i])
            .collect();
        let sma50_level_partial = (!sma50_values.is_empty())
            .then(|| sma50_values.iter().sum::<f64>() / sma50_values.len() as f64);
        let rolling_vol = |window: usize| -> Option<f64> {
            let start = index.checked_sub(window - 1)?;
            let returns = (start..=index)
                .map(|i| {
                    if !traded_values[i] || episodes[i].as_deref() != current_episode || i == 0 {
                        return None;
                    }
                    let prev = i - 1;
                    if !traded_values[prev] || episodes[prev].as_deref() != current_episode {
                        return None;
                    }
                    let now = close_values[i]?;
                    let before = close_values[prev]?;
                    (before > 0.0).then_some(now / before - 1.0)
                })
                .collect::<Option<Vec<_>>>()?;
            sample_stddev(&returns)
        };
        let returns_for_window = |window: usize| -> Option<Vec<f64>> {
            let start = index.checked_sub(window - 1)?;
            (start..=index)
                .map(|i| {
                    if !traded_values[i] || episodes[i].as_deref() != current_episode || i == 0 {
                        return None;
                    }
                    let prev = i - 1;
                    if !traded_values[prev] || episodes[prev].as_deref() != current_episode {
                        return None;
                    }
                    let (now, before) = (close_values[i]?, close_values[prev]?);
                    (before > 0.0).then_some(now / before - 1.0)
                })
                .collect()
        };
        let rsi_14 = returns_for_window(14)
            .map(|rs| {
                let gain = rs.iter().map(|r| r.max(0.0)).sum::<f64>() / 14.0;
                let loss = rs.iter().map(|r| (-r).max(0.0)).sum::<f64>() / 14.0;
                if loss == 0.0 {
                    100.0
                } else {
                    100.0 - 100.0 / (1.0 + gain / loss)
                }
            })
            .filter(|_| traded_values[index]);
        let downside_vol20 = returns_for_window(20)
            .map(|rs| (rs.iter().map(|r| r.min(0.0).powi(2)).sum::<f64>() / 20.0).sqrt());
        let atr_pct_14 = if traded_values[index] {
            let start = index.checked_sub(13);
            start.and_then(|start| {
                let mut values = Vec::with_capacity(14);
                for i in start..=index {
                    let p = i.checked_sub(1)?;
                    if !traded_values[i]
                        || !traded_values[p]
                        || episodes[i].as_deref() != current_episode
                        || episodes[p].as_deref() != current_episode
                    {
                        return None;
                    }
                    let (h, l, prev, c) = (
                        high_values[i]?,
                        low_values[i]?,
                        close_values[p]?,
                        close_values[i]?,
                    );
                    if c <= 0.0 {
                        return None;
                    }
                    values.push((h - l).max((h - prev).abs()).max((l - prev).abs()) / c);
                }
                Some(values.iter().sum::<f64>() / 14.0)
            })
        } else {
            None
        };
        let bollinger = if traded_values[index] && mean_close(20).is_some() {
            let start = index.checked_sub(19).unwrap_or(index);
            let values: Vec<f64> = (start..=index)
                .filter_map(|i| {
                    (traded_values[i] && episodes[i].as_deref() == current_episode)
                        .then_some(close_values[i])
                        .flatten()
                })
                .collect();
            (values.len() == 20).then(|| {
                let mean = values.iter().sum::<f64>() / 20.0;
                let sd = sample_stddev(&values).unwrap_or(0.0);
                (sd, mean)
            })
        } else {
            None
        };
        let bollinger_pct_b_20 = bollinger
            .filter(|(sd, _)| *sd > 0.0)
            .and_then(|(sd, mean)| current.map(|c| (c - (mean - 2.0 * sd)) / (4.0 * sd)));
        let bollinger_bandwidth_20 =
            bollinger.and_then(|(sd, mean)| (mean > 0.0).then_some(4.0 * sd / mean));
        let distance_52w_high = if traded_values[index] {
            index.checked_sub(249).and_then(|start| {
                let hs: Option<Vec<f64>> = (start..=index)
                    .map(|i| {
                        (traded_values[i] && episodes[i].as_deref() == current_episode)
                            .then_some(high_values[i]?)
                    })
                    .collect();
                let top = hs?.into_iter().reduce(f64::max)?;
                (top > 0.0)
                    .then_some(top)
                    .and_then(|top| current.map(|c| c / top - 1.0))
            })
        } else {
            None
        };
        let distance_52w_low = if traded_values[index] {
            index.checked_sub(249).and_then(|start| {
                let ls: Option<Vec<f64>> = (start..=index)
                    .map(|i| {
                        (traded_values[i] && episodes[i].as_deref() == current_episode)
                            .then_some(low_values[i]?)
                    })
                    .collect();
                let bottom = ls?.into_iter().reduce(f64::min)?;
                (bottom > 0.0)
                    .then_some(bottom)
                    .and_then(|bottom| current.map(|c| c / bottom - 1.0))
            })
        } else {
            None
        };
        let volume_window: Vec<f64> = index
            .checked_sub(19)
            .map(|start| {
                (start..=index)
                    .filter(|&i| traded_values[i] && episodes[i].as_deref() == current_episode)
                    .filter_map(|i| volume_values[i])
                    .collect()
            })
            .unwrap_or_default();
        let volume_zscore_20 = if traded_values[index] && volume_window.len() > 1 {
            let mean = volume_window.iter().sum::<f64>() / volume_window.len() as f64;
            sample_stddev(&volume_window)
                .filter(|sd| *sd > 0.0)
                .and_then(|sd| volume_values[index].map(|v| (v - mean) / sd))
        } else {
            None
        };
        let obv_start = index.saturating_sub(19);
        let obv_points: Vec<(f64, f64)> = (obv_start..=index)
            .filter(|&i| current_episode.is_some() && episodes[i].as_deref() == current_episode)
            .filter_map(|i| obv_values[i].map(|y| (sessions[i].session_ordinal as f64, y)))
            .collect();
        let obv_slope_20 = regression_slope(&obv_points);
        let turnover = if traded_values[index] {
            model_closes[index]
                .zip(volume_values[index])
                .map(|(close, volume)| close * volume * 1000.0)
        } else {
            None
        };
        let window_mean = |values: &[Option<f64>], window: usize| -> Option<f64> {
            // SQL avg over a ROWS frame is defined for a partial frame at the
            // beginning of a symbol episode; only the return/SMA feature
            // families below require a full window.
            let start = index.saturating_sub(window - 1);
            let selected: Vec<f64> = (start..=index)
                .filter(|&i| traded_values[i] && episodes[i].as_deref() == current_episode)
                .filter_map(|i| values[i])
                .collect();
            (!selected.is_empty()).then(|| selected.iter().sum::<f64>() / selected.len() as f64)
        };
        let turnover_series: Vec<Option<f64>> = (0..=index)
            .map(|i| {
                if traded_values[i] {
                    model_closes[i].zip(volumes[i]).map(|(c, v)| c * v * 1000.0)
                } else {
                    None
                }
            })
            .collect();
        let turnover_sma20_vnd = window_mean(&turnover_series, 20);
        let volume_sma20 = window_mean(&volumes, 20);
        let previous = index
            .checked_sub(1)
            .filter(|&i| traded_values[index] && traded_values[i] && same_episode(i));
        let gap_open_1d = previous.and_then(|i| {
            open_values[index]
                .zip(close_values[i])
                .map(|(o, c)| o / c - 1.0)
        });
        let intraday_return = if traded_values[index] {
            open_values[index].zip(current).map(|(o, c)| c / o - 1.0)
        } else {
            None
        };
        let intraday_range_pct = if traded_values[index] {
            high_values[index]
                .zip(low_values[index])
                .zip(current)
                .map(|((h, l), c)| (h - l) / c)
        } else {
            None
        };
        let close_location = if traded_values[index] {
            high_values[index]
                .zip(low_values[index])
                .zip(current)
                .and_then(|((h, l), c)| (h > l).then_some((c - l) / (h - l)))
        } else {
            None
        };
        let large_move_approx = if traded_values[index] {
            close_values
                .get(index.wrapping_sub(1))
                .copied()
                .flatten()
                .filter(|p| *p > 0.0)
                .and_then(|prior| {
                    current.map(|c| {
                        let limit = match sessions[index].exchange.as_deref() {
                            Some("HOSE") => 0.069,
                            Some("HNX") => 0.099,
                            _ => 0.149,
                        };
                        (c / prior - 1.0).abs() >= limit
                    })
                })
        } else {
            None
        };

        result.push(ReferenceFeature {
            ret_1,
            ret_5,
            sma_5_ratio,
            vol_5,
            return_20s,
            return_60s,
            return_2s,
            return_3s,
            return_10s,
            return_120s,
            return_250s,
            close_sma20_ratio,
            close_sma50_ratio,
            close_sma60_ratio,
            close_sma100_ratio,
            close_sma200_ratio,
            distance_52w_high,
            distance_52w_low,
            realized_vol20: rolling_vol(20),
            realized_vol60: rolling_vol(60),
            rsi_14,
            bollinger_pct_b_20,
            bollinger_bandwidth_20,
            downside_vol20,
            atr_pct_14,
            volume_zscore_20,
            obv_slope_20,
            turnover_proxy_vnd: turnover,
            log_turnover_proxy_vnd: turnover.map(|v| (1.0 + v).ln()),
            turnover_sma20_vnd,
            volume_sma20,
            gap_open_1d,
            intraday_return,
            intraday_range_pct,
            close_location,
            large_move_approx,
            session_ordinal: sessions[index].session_ordinal,
            day_of_week: iso_weekday(&sessions[index].trade_date),
            month_of_year: month_number(&sessions[index].trade_date),
            quarter_end_proximity_days: quarter_end_proximity(&sessions[index].trade_date),
            sma50_level_partial,
            momentum_12_1s: None,
            residual_momentum_12_1s: None,
            ema_ratios: [None; 6],
            macd_histogram_pct: None,
            adx_14_sma: None,
            stochastic_k_14: None,
            stochastic_d_3: None,
            downside_vol5: None,
            downside_vol60: None,
            return_skew_pop60: None,
            return_excess_kurtosis_pop60: None,
            beta_vnindex_60: None,
            beta_vnindex_250: None,
            idio_vol_vnindex_60: None,
            idio_vol_vnindex_250: None,
            amihud_proxy_20: None,
            gap_mean20: None,
            gap_std20: None,
        });
    }
    populate_v3_price_features(
        sessions,
        &close_values,
        &model_closes,
        &open_values,
        &high_values,
        &low_values,
        &volume_values,
        &traded_values,
        &episodes,
        &mut result,
    );
    Ok(result)
}

#[allow(clippy::too_many_arguments, clippy::collapsible_if)]
fn populate_v3_price_features(
    sessions: &[PriceSession],
    closes: &[Option<f64>],
    model_closes: &[Option<f64>],
    opens: &[Option<f64>],
    highs: &[Option<f64>],
    lows: &[Option<f64>],
    volumes: &[Option<f64>],
    traded: &[bool],
    episodes: &[Option<String>],
    out: &mut [ReferenceFeature],
) {
    let n = sessions.len();
    let mut emas = vec![[None; 8]; n];
    let mut counts = vec![0usize; n];
    let mut macd_sig = vec![None; n];
    let mut macd_n = vec![0usize; n];
    let periods = [5usize, 10, 20, 50, 100, 200, 12, 26];
    for i in 0..n {
        let prev = i.checked_sub(1);
        let reset = prev.is_none_or(|p| episodes[p] != episodes[i]);
        if let Some(c) = closes[i] {
            if reset {
                emas[i] = [Some(c); 8];
                counts[i] = usize::from(traded[i]);
            } else {
                let p = prev.unwrap();
                emas[i] = emas[p];
                counts[i] = counts[p] + usize::from(traded[i] && closes[i].is_some());
                if traded[i] {
                    for (k, period) in periods.iter().enumerate() {
                        emas[i][k] = Some(
                            (2.0 / (*period as f64 + 1.0)) * c
                                + (1.0 - 2.0 / (*period as f64 + 1.0)) * emas[p][k].unwrap_or(c),
                        );
                    }
                }
            }
            let line = emas[i][6].zip(emas[i][7]).map(|(a, b)| a - b);
            let prior_sig = prev.and_then(|p| macd_sig[p]);
            if counts[i] >= 26 {
                macd_sig[i] = Some(match (reset, traded[i], prior_sig) {
                    (true, _, _) => line.unwrap_or(0.0),
                    (false, true, None) => line.unwrap_or(0.0),
                    (false, true, Some(s)) => 0.2 * line.unwrap_or(0.0) + 0.8 * s,
                    (false, false, s) => s.unwrap_or_else(|| line.unwrap_or(0.0)),
                });
                macd_n[i] = if reset {
                    1
                } else {
                    prev.map(|p| macd_n[p]).unwrap_or(0) + usize::from(traded[i])
                };
            }
        } else if let Some(p) = prev {
            emas[i] = emas[p];
            counts[i] = counts[p];
            macd_sig[i] = macd_sig[p];
            macd_n[i] = macd_n[p];
        }
        if traded[i] {
            if let Some(c) = closes[i] {
                for k in 0..6 {
                    out[i].ema_ratios[k] = emas[i][k]
                        .filter(|v| counts[i] >= periods[k] && *v > 0.0)
                        .map(|v| c / v - 1.0);
                }
                out[i].macd_histogram_pct = if counts[i] >= 26 && macd_n[i] >= 9 && c > 0.0 {
                    emas[i][6]
                        .zip(emas[i][7])
                        .zip(macd_sig[i])
                        .map(|((a, b), s)| (a - b - s) / c)
                } else {
                    None
                };
            }
        }
    }
    let mut returns = vec![None; n];
    let mut gaps = vec![None; n];
    let mut idxret = vec![None; n];
    for i in 1..n {
        if traded[i] && traded[i - 1] && episodes[i] == episodes[i - 1] {
            returns[i] = closes[i]
                .zip(closes[i - 1])
                .filter(|(_, p)| *p > 0.0)
                .map(|(c, p)| c / p - 1.0);
            gaps[i] = opens[i]
                .zip(closes[i - 1])
                .filter(|(_, p)| *p > 0.0)
                .map(|(o, p)| o / p - 1.0);
        }
    }
    let mut dx = vec![None; n];
    for i in 0..n {
        if let Some(start) = i.checked_sub(13) {
            let mut tr = Vec::new();
            let mut pdm = Vec::new();
            let mut mdm = Vec::new();
            for j in start..=i {
                let Some(p) = j.checked_sub(1) else { break };
                if !traded[j] || !traded[p] || episodes[j] != episodes[p] {
                    break;
                }
                let (Some(h), Some(l), Some(ph), Some(pl), Some(pc)) =
                    (highs[j], lows[j], highs[p], lows[p], closes[p])
                else {
                    break;
                };
                tr.push((h - l).max((h - pc).abs()).max((l - pc).abs()));
                pdm.push((h - ph).max(0.0));
                mdm.push((pl - l).max(0.0));
            }
            if tr.len() == 14 {
                let p = pdm.iter().sum::<f64>() / 14.0;
                let m = mdm.iter().sum::<f64>() / 14.0;
                if tr.iter().sum::<f64>() > 0.0 && p + m > 0.0 {
                    dx[i] = Some(100.0 * (p - m).abs() / (p + m));
                }
            }
        }
        if traded[i] {
            if let Some(start) = i.checked_sub(13) {
                let ids = start..=i;
                if ids.clone().all(|j| {
                    traded[j]
                        && episodes[j] == episodes[i]
                        && highs[j].is_some()
                        && lows[j].is_some()
                }) {
                    let hi = ids
                        .clone()
                        .filter_map(|j| highs[j])
                        .reduce(f64::max)
                        .unwrap();
                    let lo = ids.filter_map(|j| lows[j]).reduce(f64::min).unwrap();
                    if hi > lo {
                        out[i].stochastic_k_14 = closes[i].map(|c| 100.0 * (c - lo) / (hi - lo));
                    }
                }
            }
            if let Some(start) = i.checked_sub(2) {
                out[i].stochastic_d_3 = (start..=i)
                    .map(|j| out[j].stochastic_k_14)
                    .collect::<Option<Vec<_>>>()
                    .map(|v| v.iter().sum::<f64>() / 3.0);
            }
        }
        if let Some(start) = i.checked_sub(13) {
            out[i].adx_14_sma = (start..=i)
                .map(|j| dx[j])
                .collect::<Option<Vec<_>>>()
                .map(|v| v.iter().sum::<f64>() / 14.0);
        }
    }
    for i in 1..n {
        if let (Some(a), Some(b)) = (sessions[i].index_close, sessions[i - 1].index_close) {
            if a > 0.0 && b > 0.0 {
                idxret[i] = Some(a / b - 1.0)
            }
        }
    }
    let lag_idx: Vec<Option<f64>> = (0..n)
        .map(|i| i.checked_sub(1).and_then(|p| idxret[p]))
        .collect();
    let roll = |vals: &[Option<f64>], i: usize, w: usize| -> Option<Vec<f64>> {
        let s = i.checked_sub(w - 1)?;
        (s..=i).map(|j| vals[j]).collect()
    };
    let regression = |x: &[f64], y: &[f64]| -> Option<(f64, f64, f64, f64)> {
        let mx = x.iter().sum::<f64>() / x.len() as f64;
        let my = y.iter().sum::<f64>() / y.len() as f64;
        let vx = x.iter().map(|v| (v - mx).powi(2)).sum::<f64>() / (x.len() - 1) as f64;
        let vy = y.iter().map(|v| (v - my).powi(2)).sum::<f64>() / (y.len() - 1) as f64;
        let cov = x
            .iter()
            .zip(y)
            .map(|(a, b)| (a - mx) * (b - my))
            .sum::<f64>()
            / (x.len() - 1) as f64;
        (vx > 0.0).then_some((cov / vx, vy, vx, cov))
    };
    let mut beta60 = vec![None; n];
    for i in 0..n {
        for (w, which) in [(60, 0usize), (250, 1usize)] {
            if let (Some(sr), Some(mr)) = (roll(&returns, i, w), roll(&lag_idx, i, w)) {
                if let Some((b, sv, mv, cov)) = regression(&mr, &sr) {
                    if which == 0 {
                        beta60[i] = Some(b);
                        out[i].beta_vnindex_60 = Some(b);
                        out[i].idio_vol_vnindex_60 = Some((sv - cov * cov / mv).max(0.0).sqrt());
                    } else {
                        out[i].beta_vnindex_250 = Some(b);
                        out[i].idio_vol_vnindex_250 = Some((sv - cov * cov / mv).max(0.0).sqrt());
                    }
                }
            }
        }
        if let Some(v) = roll(&returns, i, 5) {
            out[i].downside_vol5 =
                Some((v.iter().map(|x| x.min(0.0).powi(2)).sum::<f64>() / 5.0).sqrt());
        }
        if let Some(v) = roll(&returns, i, 60) {
            out[i].downside_vol60 =
                Some((v.iter().map(|x| x.min(0.0).powi(2)).sum::<f64>() / 60.0).sqrt());
            if let Some((skew, excess_kurtosis)) = population_skew_kurtosis(&v) {
                out[i].return_skew_pop60 = Some(skew);
                out[i].return_excess_kurtosis_pop60 = Some(excess_kurtosis);
            }
        }
        if let Some(v) = roll(&gaps, i, 20) {
            out[i].gap_mean20 = Some(v.iter().sum::<f64>() / 20.0);
            out[i].gap_std20 = sample_stddev(&v);
        }
        if let Some(v) = roll(&returns, i, 20) {
            let am = v
                .iter()
                .enumerate()
                .filter_map(|(k, r)| {
                    let j = i + 1 - 20 + k;
                    let t = model_closes[j]
                        .zip(volumes[j])
                        .map(|(c, vol)| c * vol * 1000.0)?;
                    Some(r.abs() / t)
                })
                .collect::<Vec<_>>();
            if am.len() == 20 {
                out[i].amihud_proxy_20 = Some(am.iter().sum::<f64>() / 20.0);
            }
        }
        if i >= 251 {
            let window = (i - 251..=i - 21).collect::<Vec<_>>();
            if window.iter().all(|j| returns[*j].is_some()) {
                out[i].momentum_12_1s = Some(
                    window
                        .iter()
                        .map(|j| (1.0 + returns[*j].unwrap()).ln())
                        .sum::<f64>()
                        .exp()
                        - 1.0,
                );
                let beta = beta60.get(i.saturating_sub(21)).copied().flatten();
                if let (Some(b), true) = (beta, window.iter().all(|j| lag_idx[*j].is_some())) {
                    let mr = window
                        .iter()
                        .map(|j| lag_idx[*j].unwrap())
                        .map(|r| (1.0 + r).ln())
                        .sum::<f64>()
                        .exp()
                        - 1.0;
                    out[i].residual_momentum_12_1s = Some(out[i].momentum_12_1s.unwrap() - b * mr);
                }
            }
        }
    }
    let _ = (highs, lows);
}

/// Computes the Phase 2 v2 percentile ranks and v3 Gaussian ranks for one
/// signal date. Missing inputs are omitted from each ranking population.
pub fn compute_cross_sectional_features(
    symbol_ids: &[i64],
    features: &[ReferenceFeature],
) -> Vec<CrossSectionalFeature> {
    assert_eq!(symbol_ids.len(), features.len());
    let momentum: Vec<Option<f64>> = features.iter().map(|f| f.return_20s).collect();
    let turnover: Vec<Option<f64>> = features.iter().map(|f| f.turnover_proxy_vnd).collect();
    let volatility: Vec<Option<f64>> = features.iter().map(|f| f.realized_vol20).collect();
    let rank_momentum = percent_ranks(symbol_ids, &momentum);
    let rank_turnover = percent_ranks(symbol_ids, &turnover);
    let rank_volatility = percent_ranks(symbol_ids, &volatility);
    let gauss_momentum = gaussian_ranks(symbol_ids, &momentum);
    let gauss_turnover = gaussian_ranks(symbol_ids, &turnover);
    let gauss_volatility = gaussian_ranks(symbol_ids, &volatility);
    (0..features.len())
        .map(|i| CrossSectionalFeature {
            rank_momentum_20s: rank_momentum[i],
            rank_turnover_proxy: rank_turnover[i],
            rank_realized_vol20: rank_volatility[i],
            rank_gaussian_return20: gauss_momentum[i],
            rank_gaussian_turnover_proxy: gauss_turnover[i],
            rank_gaussian_realized_vol20: gauss_volatility[i],
        })
        .collect()
}

fn percent_ranks(symbol_ids: &[i64], values: &[Option<f64>]) -> Vec<Option<f64>> {
    let mut ordered: Vec<(usize, i64, f64)> = values
        .iter()
        .enumerate()
        .filter_map(|(i, value)| value.map(|v| (i, symbol_ids[i], v)))
        .collect();
    ordered.sort_by(|a, b| a.2.total_cmp(&b.2).then_with(|| a.1.cmp(&b.1)));
    let n = ordered.len();
    let mut output = vec![None; values.len()];
    let mut start = 0;
    while start < n {
        let mut end = start + 1;
        while end < n && ordered[end].2 == ordered[start].2 {
            end += 1;
        }
        let rank = if n <= 1 {
            0.0
        } else {
            start as f64 / (n - 1) as f64
        };
        for (i, _, _) in &ordered[start..end] {
            output[*i] = Some(rank);
        }
        start = end;
    }
    output
}

fn gaussian_ranks(symbol_ids: &[i64], values: &[Option<f64>]) -> Vec<Option<f64>> {
    let mut ordered: Vec<(usize, i64, f64)> = values
        .iter()
        .enumerate()
        .filter_map(|(i, value)| value.map(|v| (i, symbol_ids[i], v)))
        .collect();
    ordered.sort_by(|a, b| a.2.total_cmp(&b.2).then_with(|| a.1.cmp(&b.1)));
    let n = ordered.len();
    let mut output = vec![None; values.len()];
    let mut start = 0;
    while start < n {
        let mut end = start + 1;
        while end < n && ordered[end].2 == ordered[start].2 {
            end += 1;
        }
        let p = (start + end) as f64 / (2.0 * n as f64);
        let quantile = normal_quantile(p);
        for (i, _, _) in &ordered[start..end] {
            output[*i] = quantile;
        }
        start = end;
    }
    output
}

/// Computes market, index, and breadth features over aligned effective-session
/// histories. The caller applies the required one-session lag by selecting the
/// result immediately before the stock signal session.
pub fn compute_market_features(
    symbol_histories: &[Vec<PriceSession>],
    index_closes: &[Option<f64>],
) -> Result<Vec<MarketFeature>, FeatureError> {
    if symbol_histories
        .iter()
        .any(|h| h.len() != index_closes.len())
    {
        return Err(FeatureError::InvalidOrdinal);
    }
    let per_symbol = symbol_histories
        .iter()
        .map(|history| compute_reference_features(history))
        .collect::<Result<Vec<_>, _>>()?;
    compute_market_features_from_reference(symbol_histories, index_closes, &per_symbol)
}

/// Computes market context from reference features already calculated for the
/// same aligned histories, avoiding a duplicate per-symbol feature pass.
pub fn compute_market_features_from_reference(
    symbol_histories: &[Vec<PriceSession>],
    index_closes: &[Option<f64>],
    per_symbol: &[Vec<ReferenceFeature>],
) -> Result<Vec<MarketFeature>, FeatureError> {
    if symbol_histories.len() != per_symbol.len()
        || symbol_histories
            .iter()
            .any(|history| history.len() != index_closes.len())
        || per_symbol
            .iter()
            .any(|features| features.len() != index_closes.len())
    {
        return Err(FeatureError::InvalidOrdinal);
    }
    let n = index_closes.len();
    let mut index_returns = vec![None; n];
    for i in 1..n {
        if let (Some(now), Some(before)) = (index_closes[i], index_closes[i - 1])
            && now > 0.0
            && before > 0.0
        {
            index_returns[i] = Some(now / before - 1.0);
        }
    }

    let mut daily_turnover = vec![None; n];
    let mut daily_dispersion = vec![None; n];
    let mut advances_minus_declines = vec![None; n];
    let mut new_high_minus_low = vec![None; n];
    let mut breadth = vec![None; n];
    for day in 0..n {
        let mut turn = 0.0;
        let mut turn_count = 0;
        let mut returns = Vec::new();
        let mut advances = 0_i64;
        let mut declines = 0_i64;
        let mut highs = 0_i64;
        let mut lows = 0_i64;
        let mut eligible = 0_i64;
        let mut above50 = 0_i64;
        for (history, computed) in symbol_histories.iter().zip(per_symbol) {
            let bar = &history[day];
            let feature = &computed[day];
            if let Some(value) = feature.turnover_proxy_vnd {
                turn += value;
                turn_count += 1;
            }
            if let Some(value) = feature.ret_1 {
                returns.push(value);
                if value > 0.0 {
                    advances += 1;
                }
                if value < 0.0 {
                    declines += 1;
                }
            }
            if feature.distance_52w_high.is_some_and(|v| v >= -1e-12) {
                highs += 1;
            }
            if feature.distance_52w_low.is_some_and(|v| v <= 1e-12) {
                lows += 1;
            }
            if bar.traded && feature.sma50_level_partial.is_some_and(|sma| sma > 0.0) {
                eligible += 1;
                if bar
                    .close
                    .is_some_and(|close| feature.sma50_level_partial.is_some_and(|sma| close > sma))
                {
                    above50 += 1;
                }
            }
        }
        if turn_count > 0 {
            daily_turnover[day] = Some(turn);
        }
        daily_dispersion[day] = sample_stddev(&returns);
        let has_market_rows = symbol_histories.iter().any(|h| h[day].close.is_some());
        if has_market_rows {
            advances_minus_declines[day] = Some(advances - declines);
            new_high_minus_low[day] = Some(highs - lows);
        }
        if eligible > 0 {
            breadth[day] = Some(above50 as f64 / eligible as f64);
        }
    }

    let mut result = Vec::with_capacity(n);
    for day in 0..n {
        let idx_return = |lag: usize| -> Option<f64> {
            let now = index_closes.get(day).copied().flatten()?;
            let before = index_closes.get(day.checked_sub(lag)?).copied().flatten()?;
            (now > 0.0 && before > 0.0).then_some(now / before - 1.0)
        };
        let vol = |window: usize| -> Option<f64> {
            let start = day.checked_sub(window - 1)?;
            let values: Option<Vec<f64>> = (start..=day).map(|i| index_returns[i]).collect();
            sample_stddev(&values?)
        };
        let index_sma_ratio = |window: usize| -> Option<f64> {
            let start = day.checked_sub(window - 1)?;
            let closes: Option<Vec<f64>> = (start..=day)
                .map(|i| index_closes[i].filter(|v| *v > 0.0))
                .collect();
            let closes = closes?;
            let last = *closes.last()?;
            let mean = closes.iter().sum::<f64>() / window as f64;
            (mean > 0.0).then_some(last / mean - 1.0)
        };
        let index_drawdown252 = day.checked_sub(251).and_then(|start| {
            let closes: Option<Vec<f64>> = (start..=day)
                .map(|i| index_closes[i].filter(|v| *v > 0.0))
                .collect();
            let closes = closes?;
            let high = closes.iter().copied().reduce(f64::max)?;
            (high > 0.0).then_some(index_closes[day]? / high - 1.0)
        });
        let market_turnover_z20 = day.checked_sub(19).and_then(|start| {
            let values: Option<Vec<f64>> = (start..=day).map(|i| daily_turnover[i]).collect();
            let values = values?;
            let mean = values.iter().sum::<f64>() / values.len() as f64;
            sample_stddev(&values)
                .filter(|sd| *sd > 0.0)
                .and_then(|sd| daily_turnover[day].map(|current| (current - mean) / sd))
        });
        result.push(MarketFeature {
            vnindex_return_20s: idx_return(20),
            vnindex_return_60s: idx_return(60),
            vnindex_realized_vol20: vol(20),
            market_breadth_above_sma50: breadth[day],
            market_advance_minus_decline: advances_minus_declines[day],
            market_new_high_minus_low: new_high_minus_low[day],
            market_turnover_z20,
            market_return_dispersion: daily_dispersion[day],
            vnindex_sma50_ratio: index_sma_ratio(50),
            vnindex_sma200_ratio: index_sma_ratio(200),
            vnindex_drawdown252: index_drawdown252,
            vnindex_realized_vol60: vol(60),
        });
    }
    Ok(result)
}

fn parse_date(date: &str) -> Option<(i64, i64, i64)> {
    let mut parts = date.split('-');
    Some((
        parts.next()?.parse().ok()?,
        parts.next()?.parse().ok()?,
        parts.next()?.parse().ok()?,
    ))
}

fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = year - i64::from(month <= 2);
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = month + if month > 2 { -3 } else { 9 };
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

fn iso_weekday(date: &str) -> Option<i16> {
    let (year, month, day) = parse_date(date)?;
    Some((days_from_civil(year, month, day) + 3).rem_euclid(7) as i16 + 1)
}

fn month_number(date: &str) -> Option<i16> {
    parse_date(date).map(|(_, month, _)| month as i16)
}

fn quarter_end_proximity(date: &str) -> Option<i16> {
    let (year, month, day) = parse_date(date)?;
    let end_month = ((month - 1) / 3 + 1) * 3;
    let end_day = match end_month {
        3 | 12 => 31,
        6 => 30,
        9 => 30,
        _ => return None,
    };
    Some((days_from_civil(year, end_month, end_day) - days_from_civil(year, month, day)) as i16)
}

fn normal_quantile(p: f64) -> Option<f64> {
    if !(0.0 < p && p < 1.0) {
        return None;
    }
    let (a, b, c, d): ([f64; 6], [f64; 5], [f64; 6], [f64; 4]) = (
        [
            -39.6968302866538,
            220.946098424521,
            -275.928510446969,
            138.357751867269,
            -30.6647980661472,
            2.50662827745924,
        ],
        [
            -54.4760987982241,
            161.585836858041,
            -155.698979859887,
            66.8013118877197,
            -13.2806815528857,
        ],
        [
            -0.00778489400243029,
            -0.322396458041136,
            -2.40075827716184,
            -2.54973253934373,
            4.37466414146497,
            2.93816398269878,
        ],
        [
            0.00778469570904146,
            0.32246712907004,
            2.445134137143,
            3.75440866190742,
        ],
    );
    let horner = |coeff: &[f64], x: f64| coeff.iter().fold(0.0, |v, c| v * x + c);
    if !(0.02425..=0.97575).contains(&p) {
        let lower = p < 0.02425;
        let tail = if lower { p } else { 1.0 - p };
        let q = (-2.0 * tail.ln()).sqrt();
        let x = horner(&c, q) / (horner(&d, q) * q + 1.0);
        Some(if lower { x } else { -x })
    } else {
        let q = p - 0.5;
        let r = q * q;
        Some(horner(&a, r) * q / (horner(&b, r) * r + 1.0))
    }
}

fn sample_stddev(values: &[f64]) -> Option<f64> {
    if values.len() < 2 {
        return None;
    }
    let mean = values.iter().sum::<f64>() / values.len() as f64;
    let variance = values
        .iter()
        .map(|value| {
            let delta = value - mean;
            delta * delta
        })
        .sum::<f64>()
        / (values.len() - 1) as f64;
    Some(variance.sqrt())
}

fn population_skew_kurtosis(values: &[f64]) -> Option<(f64, f64)> {
    if values.is_empty() {
        return None;
    }
    let mean = values.iter().sum::<f64>() / values.len() as f64;
    let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64;
    if variance <= 0.0 {
        return None;
    }
    let sd = variance.sqrt();
    let third = values.iter().map(|v| (v - mean).powi(3)).sum::<f64>() / values.len() as f64;
    let fourth = values.iter().map(|v| (v - mean).powi(4)).sum::<f64>() / values.len() as f64;
    Some((third / sd.powi(3), fourth / sd.powi(4) - 3.0))
}

fn regression_slope(points: &[(f64, f64)]) -> Option<f64> {
    if points.len() < 2 {
        return None;
    }
    let x_mean = points.iter().map(|p| p.0).sum::<f64>() / points.len() as f64;
    let y_mean = points.iter().map(|p| p.1).sum::<f64>() / points.len() as f64;
    let denom = points.iter().map(|p| (p.0 - x_mean).powi(2)).sum::<f64>();
    (denom > 0.0).then(|| {
        points
            .iter()
            .map(|p| (p.0 - x_mean) * (p.1 - y_mean))
            .sum::<f64>()
            / denom
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn market_features_reuse_precomputed_reference_rows() {
        let histories = vec![
            sessions(&[100.0, 101.0, 103.0, 102.0, 104.0, 105.0]),
            sessions(&[90.0, 92.0, 91.0, 94.0, 93.0, 96.0]),
        ];
        let index_closes = vec![
            Some(1_000.0),
            Some(1_002.0),
            Some(1_005.0),
            Some(1_004.0),
            Some(1_010.0),
            Some(1_012.0),
        ];
        let reference_rows = histories
            .iter()
            .map(|history| compute_reference_features(history).unwrap())
            .collect::<Vec<_>>();

        let direct = compute_market_features(&histories, &index_closes).unwrap();
        let reused =
            compute_market_features_from_reference(&histories, &index_closes, &reference_rows)
                .unwrap();

        assert_eq!(reused, direct);
    }

    #[test]
    fn gaussian_ranks_use_independent_nullable_populations_and_average_ties() {
        let seed = compute_reference_features(&sessions(&[100.0])).unwrap()[0].clone();
        let mut features = vec![seed; 4];
        for (i, feature) in features.iter_mut().enumerate() {
            feature.return_20s = [Some(0.1), Some(0.2), None, Some(0.1)][i];
            feature.turnover_proxy_vnd = [None, Some(100.0), Some(200.0), Some(100.0)][i];
            feature.realized_vol20 = [Some(0.2), None, Some(0.4), Some(0.2)][i];
        }
        let actual = compute_cross_sectional_features(&[4, 3, 2, 1], &features);
        // Three eligible observations per metric: the tied pair has midpoint
        // probability 1/3, and the largest observation has probability 5/6.
        let low = normal_quantile(1.0 / 3.0);
        let high = normal_quantile(5.0 / 6.0);
        let expected = [
            (low, None, low),
            (high, low, None),
            (None, high, high),
            (low, low, low),
        ];
        for (row, (momentum, turnover, volatility)) in actual.iter().zip(expected) {
            assert_eq!(row.rank_gaussian_return20, momentum);
            assert_eq!(row.rank_gaussian_turnover_proxy, turnover);
            assert_eq!(row.rank_gaussian_realized_vol20, volatility);
        }
    }

    #[test]
    fn gaussian_ranks_handle_singleton_and_empty_populations() {
        let seed = compute_reference_features(&sessions(&[100.0])).unwrap()[0].clone();
        let mut features = vec![seed; 2];
        for feature in &mut features {
            feature.return_20s = None;
            feature.turnover_proxy_vnd = None;
            feature.realized_vol20 = None;
        }
        features[0].turnover_proxy_vnd = Some(100.0);
        let actual = compute_cross_sectional_features(&[1, 2], &features);
        assert_eq!(actual[0].rank_gaussian_turnover_proxy, Some(0.0));
        assert_eq!(actual[1].rank_gaussian_turnover_proxy, None);
        for row in actual {
            assert_eq!(row.rank_gaussian_return20, None);
            assert_eq!(row.rank_gaussian_realized_vol20, None);
        }
    }

    fn sessions(closes: &[f64]) -> Vec<PriceSession> {
        closes
            .iter()
            .enumerate()
            .map(|(index, close)| PriceSession {
                session_ordinal: index as i64 + 1,
                close: Some(*close),
                model_close: Some(*close),
                open: Some(*close),
                high: Some(*close),
                low: Some(*close),
                volume: Some(1000.0),
                traded: true,
                episode: Some("2024-01-01".to_owned()),
                exchange: Some("HOSE".to_owned()),
                trade_date: format!("2024-01-{:02}", index + 1),
                index_close: Some(100.0 + index as f64),
            })
            .collect()
    }

    #[test]
    fn returns_and_rolling_features_use_session_offsets() {
        let data = sessions(&[100.0, 101.0, 102.0, 103.0, 104.0, 105.0]);
        let actual = compute_reference_features(&data).expect("valid data");
        assert_eq!(actual[4].sma_5_ratio, Some(104.0 / 102.0 - 1.0));
        assert_eq!(actual[5].ret_1, Some(105.0 / 104.0 - 1.0));
        assert_eq!(actual[5].ret_5, Some(105.0 / 100.0 - 1.0));
        assert!(actual[5].vol_5.is_some());
    }

    #[test]
    fn no_trade_sessions_are_not_compressed_into_windows() {
        let mut data = sessions(&[100.0, 101.0, 102.0, 103.0, 104.0, 105.0]);
        data[2].traded = false;
        let actual = compute_reference_features(&data).expect("valid data");
        assert_eq!(actual[3].ret_1, None);
        assert_eq!(actual[5].ret_5, Some(105.0 / 100.0 - 1.0));
        assert_eq!(actual[5].vol_5, None);
    }

    #[test]
    fn recursive_ema_matches_independent_seeded_golden_values() {
        let data = sessions(&[10.0, 12.0, 14.0, 16.0, 18.0, 20.0, 22.0, 24.0, 26.0, 28.0]);
        let actual = compute_reference_features(&data).expect("valid golden history");

        assert_eq!(actual[3].ema_ratios[0], None);
        assert!((actual[4].ema_ratios[0].unwrap() - 0.21702838063439064).abs() < 1e-12);
        assert!((actual[9].ema_ratios[0].unwrap() - 0.16163055391619574).abs() < 1e-12);
        assert!((actual[9].ema_ratios[1].unwrap() - 0.3672718222007252).abs() < 1e-12);
    }

    #[test]
    fn recursive_ema_all_period_seeds_and_episode_masks_match_closed_form_golden() {
        // For closes C_t = 10 + 2t and an EMA seeded with C_0, the independent
        // closed form is EMA_t = C_t - 2*(1-alpha)/alpha * (1 - (1-alpha)^t).
        // The constants below are C_(p-1)/EMA_(p-1)-1 for each specified period.
        let periods = [5usize, 10, 20, 50, 100, 200];
        let golden = [
            0.21702838063439064,
            0.3672718222007252,
            0.5076654871377144,
            0.6388403042529927,
            0.695634402120612,
            0.7273355269526713,
        ];
        let closes: Vec<f64> = (0..410)
            .map(|i| {
                let offset = if i < 205 { i } else { i - 205 };
                10.0 + 2.0 * offset as f64
            })
            .collect();
        let mut data = sessions(&closes);
        for row in &mut data[205..] {
            row.episode = Some("second-adjustment-episode".to_owned());
        }
        let actual = compute_reference_features(&data).expect("valid two-episode history");

        for (slot, period) in periods.into_iter().enumerate() {
            assert!(actual[period - 2].ema_ratios[slot].is_none());
            let first_seeded = actual[period - 1].ema_ratios[slot]
                .expect("first episode emits at its full-period mask");
            assert!((first_seeded - golden[slot]).abs() < 1e-12);

            let reset_mask_index = 205 + period - 2;
            assert!(actual[reset_mask_index].ema_ratios[slot].is_none());
            let second_seeded = actual[205 + period - 1].ema_ratios[slot]
                .expect("episode reset must restart the full-period mask");
            assert!((second_seeded - golden[slot]).abs() < 1e-12);
        }
    }

    #[test]
    fn recursive_features_match_pandas_golden_fixture() {
        // Generated with pandas 3.0.1 Series.ewm(adjust=False, ignore_na=True).
        // The same frozen inputs and outputs are consumed by the PostgreSQL
        // migration assertions so SQL and Rust are checked independently of
        // this reference implementation.
        let golden = include_str!("../../../../tests/golden/phase2_recursive_ema.csv");
        let mut data = Vec::new();
        let mut expected = Vec::new();
        for line in golden.lines().skip(1) {
            let fields: Vec<_> = line.split(',').collect();
            assert_eq!(
                fields.len(),
                12,
                "unexpected recursive EMA golden row: {line}"
            );
            let close = fields[3].parse::<f64>().expect("golden close");
            let traded = fields[4].parse::<bool>().expect("golden traded flag");
            data.push(PriceSession {
                session_ordinal: data.len() as i64 + 1,
                close: Some(close),
                model_close: Some(close),
                open: Some(close),
                high: Some(close),
                low: Some(close),
                volume: Some(if traded { 1000.0 } else { 0.0 }),
                traded,
                episode: Some(fields[0].to_owned()),
                exchange: Some("HOSE".to_owned()),
                trade_date: fields[2].to_owned(),
                index_close: Some(1100.0),
            });
            expected.push(
                fields[5..12]
                    .iter()
                    .map(|value| {
                        if value.is_empty() {
                            None
                        } else {
                            Some(value.parse::<f64>().expect("golden recursive feature"))
                        }
                    })
                    .collect::<Vec<_>>(),
            );
        }
        assert_eq!(data.len(), 430, "golden fixture row count changed");

        let actual = compute_reference_features(&data).expect("valid recursive golden history");
        for (index, (observed, expected)) in actual.iter().zip(expected).enumerate() {
            let observed = [
                observed.ema_ratios[0],
                observed.ema_ratios[1],
                observed.ema_ratios[2],
                observed.ema_ratios[3],
                observed.ema_ratios[4],
                observed.ema_ratios[5],
                observed.macd_histogram_pct,
            ];
            for (feature, (actual, expected)) in observed.iter().zip(expected).enumerate() {
                match (actual, expected) {
                    (None, None) => {}
                    (Some(actual), Some(expected)) => assert!(
                        (actual - expected).abs() <= 1e-12,
                        "recursive golden feature {feature} differs at fixture row {index}: Rust={actual:.17}, pandas={expected:.17}"
                    ),
                    _ => panic!(
                        "recursive golden feature {feature} mask differs at fixture row {index}: Rust={actual:?}, pandas={expected:?}"
                    ),
                }
            }
        }
    }

    #[test]
    fn amihud_uses_the_model_close_turnover_basis() {
        let closes: Vec<f64> = (0..24)
            .map(|index| 100.0 + index as f64 * 0.7 + (index % 3) as f64)
            .collect();
        let mut data = sessions(&closes);
        for session in &mut data {
            session.model_close = session.close.map(|close| close * 2.0);
        }

        let actual = compute_reference_features(&data).expect("valid turnover history");
        let expected = (1..=20)
            .map(|index| {
                actual[index].ret_1.unwrap().abs()
                    / (data[index].model_close.unwrap() * data[index].volume.unwrap() * 1000.0)
            })
            .sum::<f64>()
            / 20.0;

        assert!((actual[20].amihud_proxy_20.unwrap() - expected).abs() < 1e-24);
    }

    #[test]
    fn episode_boundaries_reset_price_windows() {
        let mut data = sessions(&[100.0, 101.0, 102.0, 103.0, 104.0, 105.0]);
        data[5].episode = Some("2025-01-01".to_owned());
        let actual = compute_reference_features(&data).expect("valid data");
        assert_eq!(actual[5].ret_1, None);
        assert_eq!(actual[5].ret_5, None);
        assert_eq!(actual[5].sma_5_ratio, None);
        assert_eq!(actual[5].vol_5, None);
    }

    #[test]
    fn v3_source_independent_families_have_full_window_values() {
        let data: Vec<PriceSession> = (0..320)
            .map(|i| {
                let close = 100.0 + i as f64 * 0.1 + (i % 7) as f64 * 2.0;
                let mut row = sessions(&[close]).remove(0);
                row.session_ordinal = i as i64 + 1;
                row.trade_date = format!("2024-{:03}", i + 1);
                row.close = Some(close);
                row.open = Some(close * (0.995 + (i % 5) as f64 * 0.001));
                row.high = Some(close + 2.0);
                row.low = Some(close - 2.0);
                row.index_close = Some(1000.0 + i as f64 * 0.2 + (i % 9) as f64 * 4.0);
                row
            })
            .collect();
        let features = compute_reference_features(&data).expect("valid synthetic session history");
        let last = features.last().expect("features emitted");
        assert!(last.momentum_12_1s.is_some());
        assert!(last.residual_momentum_12_1s.is_some());
        assert!(last.ema_ratios.iter().all(Option::is_some));
        assert!(last.macd_histogram_pct.is_some());
        assert!(last.adx_14_sma.is_some());
        assert!(last.stochastic_k_14.is_some());
        assert!(last.stochastic_d_3.is_some());
        assert!(last.downside_vol5.is_some());
        assert!(last.downside_vol60.is_some());
        assert!(last.return_skew_pop60.is_some());
        assert!(last.return_excess_kurtosis_pop60.is_some());
        assert!(last.beta_vnindex_60.is_some());
        assert!(last.beta_vnindex_250.is_some());
        assert!(last.idio_vol_vnindex_60.is_some());
        assert!(last.idio_vol_vnindex_250.is_some());
        assert!(last.amihud_proxy_20.is_some());
        assert!(last.gap_mean20.is_some());
        assert!(last.gap_std20.is_some());
    }

    #[test]
    fn population_skew_and_excess_kurtosis_use_one_window_mean() {
        let (skew, kurtosis) = population_skew_kurtosis(&[-1.0, -1.0, 1.0, 1.0]).unwrap();
        assert!(skew.abs() < 1e-12);
        assert!((kurtosis + 2.0).abs() < 1e-12);
    }
}

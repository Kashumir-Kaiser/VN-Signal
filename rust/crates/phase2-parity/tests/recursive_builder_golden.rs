use vn_signal_phase2_parity::{PriceSession, compute_reference_features};

const GOLDEN: &str = include_str!("../../../../tests/golden/phase2_recursive_builder_golden.csv");
const FEATURES: [&str; 10] = [
    "ema_5_ratio",
    "ema_10_ratio",
    "ema_20_ratio",
    "ema_50_ratio",
    "ema_100_ratio",
    "ema_200_ratio",
    "macd_histogram_pct",
    "rsi_14",
    "atr_pct_14",
    "adx_14_sma",
];

#[test]
fn recursive_builder_series_matches_pandas_golden() {
    let mut sessions = Vec::new();
    let mut expected = Vec::new();

    for line in GOLDEN.lines().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        assert_eq!(fields.len(), 17, "malformed recursive golden row: {line}");
        let step = fields[0].parse::<i64>().expect("golden step");
        let open = fields[1].parse::<f64>().expect("golden open");
        let high = fields[2].parse::<f64>().expect("golden high");
        let low = fields[3].parse::<f64>().expect("golden low");
        let close = fields[4].parse::<f64>().expect("golden close");
        let traded = fields[5].parse::<bool>().expect("golden traded flag");

        sessions.push(PriceSession {
            session_ordinal: step,
            close: Some(close),
            model_close: Some(close),
            open: Some(open),
            high: Some(high),
            low: Some(low),
            volume: Some(if traded { 1000.0 } else { 0.0 }),
            traded,
            episode: Some("p2ready".to_owned()),
            exchange: Some("HOSE".to_owned()),
            trade_date: fields[16].to_owned(),
            index_close: Some(1100.0),
        });

        expected.push(
            fields[6..16]
                .iter()
                .map(|value| {
                    if value.is_empty() {
                        None
                    } else {
                        Some(value.parse::<f64>().expect("golden recursive value"))
                    }
                })
                .collect::<Vec<_>>(),
        );
    }

    assert_eq!(sessions.len(), 320, "golden fixture row count changed");
    let actual = compute_reference_features(&sessions).expect("valid non-linear golden history");
    for (row, (observed, expected)) in actual.iter().zip(expected).enumerate() {
        let observed = [
            observed.ema_ratios[0],
            observed.ema_ratios[1],
            observed.ema_ratios[2],
            observed.ema_ratios[3],
            observed.ema_ratios[4],
            observed.ema_ratios[5],
            observed.macd_histogram_pct,
            observed.rsi_14,
            observed.atr_pct_14,
            observed.adx_14_sma,
        ];
        for (feature, (actual, expected)) in observed.iter().zip(expected).enumerate() {
            match (actual, expected) {
                (None, None) => {}
                (Some(actual), Some(expected)) => assert!(
                    (actual - expected).abs() <= 1e-12,
                    "{} differs at fixture row {}: Rust={actual:.17}, pandas={expected:.17}",
                    FEATURES[feature],
                    row + 1
                ),
                _ => panic!(
                    "{} NULL mask differs at fixture row {}: Rust={actual:?}, pandas={expected:?}",
                    FEATURES[feature],
                    row + 1
                ),
            }
        }
    }

    // The fixture's dates are the exact weekdays in the SQL fixture.
    // Recomputing the 2099 segment from January 1 plus all prior fixture
    // sessions (fewer than 1,000) must reproduce its full-history values.
    let year_start = sessions
        .iter()
        .position(|session| session.trade_date.as_str() >= "2099-01-01")
        .expect("fixture crosses into the next calendar year");
    let warmup_start = year_start.saturating_sub(1000);
    let year_reference = compute_reference_features(&sessions[warmup_start..])
        .expect("valid calendar-year warm-up history");
    let year_output_offset = year_start - warmup_start;
    for (full, year) in actual[year_start..]
        .iter()
        .zip(&year_reference[year_output_offset..])
    {
        assert_eq!(
            full, year,
            "year-anchored recursive features changed at a year boundary"
        );
    }
}

#[test]
fn recursive_ema_carries_untraded_and_missing_rows_and_resets_episodes() {
    let mut sessions = Vec::new();
    for i in 0..35_i64 {
        let second_episode = i >= 18;
        let close = if i == 7 || i == 24 {
            None // no source bar on this effective session
        } else if i == 5 || i == 21 {
            Some(if second_episode { 202.0 } else { 104.0 }) // prior close carried by a zero-volume source row
        } else {
            Some(if second_episode {
                200.0 + (i - 18) as f64
            } else {
                100.0 + i as f64
            })
        };
        let traded = close.is_some() && i != 5 && i != 21;
        sessions.push(PriceSession {
            session_ordinal: i + 1,
            close,
            model_close: close,
            open: close,
            high: close,
            low: close,
            volume: Some(if traded { 1000.0 } else { 0.0 }),
            traded,
            episode: (i == 0)
                .then(|| "ep1".to_owned())
                .or_else(|| (i == 18).then(|| "ep2".to_owned())),
            exchange: Some("HOSE".to_owned()),
            trade_date: format!("2098-01-{:02}", (i % 28) + 1),
            index_close: Some(1100.0),
        });
    }

    let actual = compute_reference_features(&sessions).expect("valid sparse series");
    let mut state = [None; 6];
    let mut episode_count = 0usize;
    let mut current_episode = None;
    for (i, session) in sessions.iter().enumerate() {
        let episode = if i >= 18 { "ep2" } else { "ep1" };
        if current_episode != Some(episode) {
            state = [None; 6];
            episode_count = 0;
            current_episode = Some(episode);
        }
        if let Some(close) = session.close {
            if state[0].is_none() {
                state = [Some(close); 6];
            }
            if session.traded {
                episode_count += 1;
                for (slot, period) in [5.0, 10.0, 20.0, 50.0, 100.0, 200.0].iter().enumerate() {
                    state[slot] = Some(
                        (2.0 / (period + 1.0)) * close
                            + (1.0 - 2.0 / (period + 1.0)) * state[slot].unwrap(),
                    );
                }
            }
        }
        for slot in 0..6 {
            let expected = if session.traded && episode_count >= [5, 10, 20, 50, 100, 200][slot] {
                session
                    .close
                    .zip(state[slot])
                    .map(|(close, ema)| close / ema - 1.0)
            } else {
                None
            };
            assert_eq!(
                actual[i].ema_ratios[slot],
                expected,
                "EMA slot {slot} at row {}",
                i + 1
            );
        }
    }
    assert!(
        actual[7].ema_ratios.iter().all(Option::is_none),
        "missing bar must not emit EMA values"
    );
    assert!(
        actual[5].ema_ratios.iter().all(Option::is_none),
        "zero-volume row must not emit EMA values"
    );
    assert!(
        actual[21].ema_ratios.iter().all(Option::is_none),
        "untraded carry row must not emit EMA values"
    );
    assert!(
        actual[22].ema_ratios[0].is_none(),
        "episode reset must restart the 5-traded-session warmup"
    );

    for invalid in [0.0, -1.0, f64::NAN, f64::INFINITY] {
        let mut invalid_sessions = sessions.clone();
        invalid_sessions[0].close = Some(invalid);
        assert!(
            compute_reference_features(&invalid_sessions).is_err(),
            "invalid close {invalid:?} must be rejected"
        );
    }
}

#[test]
fn recursive_features_use_exactly_the_prior_1000_sessions_at_year_anchor() {
    let mut sessions = Vec::with_capacity(1500);
    let (mut year, mut month, mut day, mut weekday) = (2098, 1, 6, 0); // Monday, first SQL fixture session
    for i in 0..1500_i64 {
        let close = 100.0 + i as f64 * 0.01 + (i % 37) as f64 * 0.7 + (i % 9) as f64 * 0.13;
        sessions.push(PriceSession {
            session_ordinal: i + 1,
            close: Some(close),
            model_close: Some(close),
            open: Some(close - 0.2),
            high: Some(close + 0.4),
            low: Some(close - 0.5),
            volume: Some(1000.0),
            traded: true,
            episode: Some("continuous".to_owned()),
            exchange: Some("HOSE".to_owned()),
            trade_date: format!("{year:04}-{month:02}-{day:02}"),
            index_close: Some(1100.0),
        });

        loop {
            day += 1;
            weekday = (weekday + 1) % 7;
            let days_in_month = match month {
                2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
                2 => 28,
                4 | 6 | 9 | 11 => 30,
                _ => 31,
            };
            if day > days_in_month {
                day = 1;
                month += 1;
                if month > 12 {
                    month = 1;
                    year += 1;
                }
            }
            if weekday < 5 {
                break;
            }
        }
    }
    // Choose a later year so the calendar anchor has more than 1,000 prior
    // effective sessions available. The session calendar skips weekends.
    let year_start = sessions
        .iter()
        .position(|s| s.trade_date.starts_with("2102-"))
        .expect("long axis includes calendar year 2102");
    let warmup_start = year_start.saturating_sub(1000);
    assert_eq!(
        year_start - warmup_start,
        1000,
        "fixture must have more than 1,000 prior sessions"
    );
    // This observation is just outside the allowed 1,000-session warmup.
    // Its long EMA tail makes the exact cutoff distinguishable numerically.
    let outlier = &mut sessions[warmup_start - 1];
    outlier.close = Some(100_000.0);
    outlier.model_close = Some(100_000.0);
    outlier.open = Some(99_999.8);
    outlier.high = Some(100_000.4);
    outlier.low = Some(99_999.5);
    let full = compute_reference_features(&sessions).expect("valid long history");
    let anchored = compute_reference_features(&sessions[warmup_start..]).expect("anchored history");
    let offset = year_start - warmup_start;
    let extra_history = compute_reference_features(&sessions[warmup_start - 1..])
        .expect("history with one extra prior session");
    let manual_ema_ratio = |history: &[PriceSession], target: usize, period: f64| {
        let mut ema = history[0].close.expect("seed close");
        for row in history.iter().take(target + 1).skip(1) {
            if row.traded {
                let close = row.close.expect("traded close");
                ema = (2.0 / (period + 1.0)) * close + (1.0 - 2.0 / (period + 1.0)) * ema;
            }
        }
        history[target].close.expect("target close") / ema - 1.0
    };
    assert_eq!(
        anchored[offset].ema_ratios[5],
        Some(manual_ema_ratio(&sessions[warmup_start..], offset, 200.0))
    );
    assert_eq!(
        extra_history[offset + 1].ema_ratios[5],
        Some(manual_ema_ratio(
            &sessions[warmup_start - 1..],
            offset + 1,
            200.0
        ))
    );
    assert_ne!(
        full[year_start].ema_ratios[5], anchored[offset].ema_ratios[5],
        "fixture must distinguish year-anchored state from unbounded full-history state"
    );
    assert_ne!(
        anchored[offset].ema_ratios[5],
        extra_history[offset + 1].ema_ratios[5],
        "fixture must distinguish an exact 1,000-session warmup from 1,001 sessions"
    );
}

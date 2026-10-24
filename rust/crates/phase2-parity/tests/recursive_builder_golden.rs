use vn_signal_phase2_parity::{PriceSession, compute_reference_features};

const GOLDEN: &str = include_str!("../../../../tests/golden/phase2_recursive_builder_golden.csv");
const FEATURES: [&str; 7] = [
    "ema_5_ratio",
    "ema_10_ratio",
    "ema_20_ratio",
    "ema_50_ratio",
    "ema_100_ratio",
    "ema_200_ratio",
    "macd_histogram_pct",
];

#[test]
fn recursive_builder_series_matches_pandas_golden() {
    let mut sessions = Vec::new();
    let mut expected = Vec::new();

    for line in GOLDEN.lines().skip(1) {
        let fields: Vec<_> = line.split(',').collect();
        assert_eq!(fields.len(), 10, "malformed recursive golden row: {line}");
        let step = fields[0].parse::<i64>().expect("golden step");
        let close = fields[1].parse::<f64>().expect("golden close");
        let traded = fields[2].parse::<bool>().expect("golden traded flag");

        sessions.push(PriceSession {
            session_ordinal: step,
            close: Some(close),
            model_close: Some(close),
            open: Some(close),
            high: Some(close),
            low: Some(close),
            volume: Some(if traded { 1000.0 } else { 0.0 }),
            traded,
            episode: Some("p2ready".to_owned()),
            exchange: Some("HOSE".to_owned()),
            trade_date: format!("2098-{:02}-{:02}", (step - 1) / 28 + 1, (step - 1) % 28 + 1),
            index_close: Some(1100.0),
        });

        expected.push(
            fields[3..10]
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
    let actual = compute_reference_features(&sessions).expect("valid linear golden history");
    for (row, (observed, expected)) in actual.iter().zip(expected).enumerate() {
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
}

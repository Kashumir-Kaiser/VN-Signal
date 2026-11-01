-- Read-only coverage and evidence audit for weights on READY forward labels.
-- Denominator is every READY feat.labels_daily row matched to the current V3
-- target hash. Labels without a matching target are reported separately.
-- A valid weight requires complete per-session VNDIRECT unadjusted OHLC + exact
-- source-row-linked limit observations and raw OHLC equality, as in migration
-- 063. This report preserves NULLs and categorizes missing evidence; it does
-- not infer price bands, outcomes, market fills, or execution capacity.
-- Run only on the disposable report clone named below.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5min';
DO $$ BEGIN
  IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
    RAISE EXCEPTION 'diagnostic is restricted to vnsignal_phase2_report_20261019';
  END IF;
END $$;

WITH ready AS MATERIALIZED (
  SELECT l.symbol_id,l.signal_date,l.horizon_sessions,l.label_version,
         l.feature_set_hash,l.entry_date,l.exit_date,t.execution_weight,
         t.membership_gate_status,t.is_investable_member,t.liquidity_tier
    FROM feat.labels_daily l
    LEFT JOIN feat.phase2_label_targets_v3 t
      ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
     AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
     AND t.feature_set_hash=l.feature_set_hash
     AND t.feature_set_hash=feat.phase2_feature_set_hash_v3()
   WHERE l.label_status='READY'
     AND l.feature_set_hash=feat.phase2_feature_set_hash_v3()
), target_rows AS (
  SELECT * FROM ready WHERE membership_gate_status IS NOT NULL
), weight_evidence AS MATERIALIZED (
  SELECT r.*,
         (SELECT count(*) FROM core.effective_trading_sessions c
           WHERE c.is_session AND c.trade_date BETWEEN r.entry_date AND r.exit_date) AS expected_sessions,
         (SELECT count(*)
            FROM core.effective_trading_sessions c
            JOIN core.bars_daily_sources_ml_eligible b
              ON b.symbol_id=r.symbol_id AND b.trade_date=c.trade_date
             AND b.source='vndirect' AND b.adj_basis='unadjusted'
            JOIN core.daily_price_limit_observations p
              ON p.symbol_id=b.symbol_id AND p.trade_date=b.trade_date
             AND p.source='vndirect' AND p.raw_landing_id=b.landing_id
             AND p.source_row=b.source_row
            JOIN raw.landings rl ON rl.landing_id=b.landing_id
             AND rl.source='vndirect' AND rl.route='equity_ohlcv'
             AND rl.payload_sha256 ~ '^[0-9a-f]{64}$'
           WHERE c.is_session AND c.trade_date BETWEEN r.entry_date AND r.exit_date
             AND p.available_at=p.fetched_at AND p.fetched_at=rl.fetched_at
             AND jsonb_typeof(p.row_payload)='object'
             AND jsonb_typeof(p.row_payload->'open')='number'
             AND jsonb_typeof(p.row_payload->'high')='number'
             AND jsonb_typeof(p.row_payload->'low')='number'
             AND jsonb_typeof(p.row_payload->'close')='number'
             AND p.limit_up>0 AND p.limit_down>0 AND p.limit_up>=p.limit_down
             AND b.o=(p.row_payload->>'open')::double precision
             AND b.h=(p.row_payload->>'high')::double precision
             AND b.l=(p.row_payload->>'low')::double precision
             AND b.c=(p.row_payload->>'close')::double precision
         ) AS valid_evidence_sessions,
         (SELECT count(*) FROM core.effective_trading_sessions c
           JOIN core.bars_daily_sources_ml_eligible b
             ON b.symbol_id=r.symbol_id AND b.trade_date=c.trade_date
            AND b.source='vndirect' AND b.adj_basis='unadjusted'
          WHERE c.is_session AND c.trade_date BETWEEN r.entry_date AND r.exit_date) AS unadjusted_bar_sessions,
         (SELECT count(*) FROM core.effective_trading_sessions c
           JOIN core.bars_daily_sources_ml_eligible b
             ON b.symbol_id=r.symbol_id AND b.trade_date=c.trade_date
            AND b.source='vndirect' AND b.adj_basis='unadjusted'
           JOIN core.daily_price_limit_observations p
             ON p.symbol_id=b.symbol_id AND p.trade_date=b.trade_date
            AND p.source='vndirect' AND p.raw_landing_id=b.landing_id
            AND p.source_row=b.source_row
          WHERE c.is_session AND c.trade_date BETWEEN r.entry_date AND r.exit_date) AS linked_limit_rows
    FROM target_rows r
)
SELECT date_trunc('year',signal_date)::date AS calendar_year,
       horizon_sessions,
       count(*) AS ready_current_hash_targets_denominator,
       count(*) FILTER (WHERE execution_weight=0) AS weight_zero,
       count(*) FILTER (WHERE execution_weight=0.5) AS weight_half,
       count(*) FILTER (WHERE execution_weight=1) AS weight_one,
       count(*) FILTER (WHERE execution_weight IS NULL) AS weight_null,
       count(*) FILTER (WHERE expected_sessions IS NULL OR expected_sessions=0) AS invalid_or_empty_window,
       count(*) FILTER (WHERE expected_sessions>0 AND valid_evidence_sessions=expected_sessions) AS complete_exact_evidence,
       count(*) FILTER (WHERE expected_sessions>valid_evidence_sessions) AS incomplete_exact_evidence,
       count(*) FILTER (WHERE expected_sessions>unadjusted_bar_sessions) AS windows_missing_unadjusted_bars,
       count(*) FILTER (WHERE expected_sessions>linked_limit_rows) AS windows_missing_linked_limit_rows,
       count(*) FILTER (WHERE expected_sessions IS DISTINCT FROM valid_evidence_sessions OR
           execution_weight IS DISTINCT FROM feat.phase2_exact_execution_weight(symbol_id,entry_date,exit_date)) AS stored_weight_or_evidence_mismatch,
       count(*) FILTER (WHERE membership_gate_status='ELIGIBLE' AND is_investable_member) AS eligible_investable_targets,
       count(*) FILTER (WHERE liquidity_tier IS NOT NULL) AS targets_with_liquidity_tier
  FROM weight_evidence
 GROUP BY 1,2
 ORDER BY 1,2;

-- Preserve the total READY-label denominator and targets missing entirely.
-- A missing target is distinct from a target whose execution_weight is NULL.
SELECT date_trunc('year',l.signal_date)::date AS calendar_year,
       l.horizon_sessions,
       count(*) AS ready_current_hash_labels,
       count(t.symbol_id) AS matched_current_hash_targets,
       count(*) FILTER (WHERE t.symbol_id IS NULL) AS labels_without_current_target,
       count(*) FILTER (WHERE t.symbol_id IS NOT NULL AND t.execution_weight IS NULL) AS matched_targets_with_null_weight
  FROM feat.labels_daily l
  LEFT JOIN feat.phase2_label_targets_v3 t
    ON t.symbol_id=l.symbol_id AND t.signal_date=l.signal_date
   AND t.horizon_sessions=l.horizon_sessions AND t.label_version=l.label_version
   AND t.feature_set_hash=l.feature_set_hash
   AND t.feature_set_hash=feat.phase2_feature_set_hash_v3()
 WHERE l.label_status='READY'
   AND l.feature_set_hash=feat.phase2_feature_set_hash_v3()
 GROUP BY 1,2 ORDER BY 1,2;

-- The schema has no single canonical exchange/venue column on the target or
-- label rows. Venue splits are intentionally omitted rather than inferred from
-- a current listing snapshot. `valid_evidence_sessions` repeats the migration
-- 063 source, raw-row, freshness, limit-pair and exact-OHLC conditions; counts
-- do not certify that raw landing bytes were rehashed here. The migration's
-- policy function determines whether complete evidence maps to 0/0.5/1.
-- Missing target rows are excluded from the weight-evidence denominator and
-- explicitly counted by the following READY-label summary.

COMMIT;

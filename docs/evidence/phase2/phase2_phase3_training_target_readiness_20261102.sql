-- Read-only Phase 3 target readiness census on the already-built current-hash
-- target table. The report clone is missing migration 059's rolling-gap views,
-- so this audit verifies the documented target-side selector directly.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5min';

DO $phase2_phase3_target_readiness_guard$
DECLARE
    v_rank_rows_missing_weight bigint;
    v_tier_rows_missing_weight bigint;
    v_unranked_rows_with_score bigint;
    v_missing_tier_in_rank_window bigint;
BEGIN
    IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
        RAISE EXCEPTION 'diagnostic is restricted to vnsignal_phase2_report_20261019';
    END IF;

    WITH stats AS MATERIALIZED (
        SELECT count(*) FILTER (
                   WHERE t.membership_gate_status='ELIGIBLE'
                     AND t.is_investable_member
                     AND t.liquidity_tier IS NOT NULL
                     AND t.target_uniform_rank IS NOT NULL
                     AND t.execution_weight IS NULL
               ) AS rank_rows_missing_weight,
               count(*) FILTER (
                   WHERE t.membership_gate_status='ELIGIBLE'
                     AND t.is_investable_member
                     AND t.liquidity_tier IS NOT NULL
                     AND t.execution_weight IS NULL
               ) AS tier_rows_missing_weight,
               count(*) FILTER (
                   WHERE t.membership_gate_status='ELIGIBLE'
                     AND t.is_investable_member
                     AND t.liquidity_tier IS NOT NULL
                     AND t.volatility_scaled_score IS NOT NULL
                     AND t.target_uniform_rank IS NULL
               ) AS unranked_rows_with_score,
               count(*) FILTER (
                   WHERE t.membership_gate_status='ELIGIBLE'
                     AND t.is_investable_member
                     AND t.liquidity_tier IS NULL
                     AND t.tier_liquidity_rank60 BETWEEN 1 AND 400
               ) AS missing_tier_in_rank_window
          FROM feat.phase2_label_targets_v3 t
         WHERE t.feature_set_hash=feat.phase2_feature_set_hash_v3()
    )
    SELECT rank_rows_missing_weight,tier_rows_missing_weight,
           unranked_rows_with_score,missing_tier_in_rank_window
      INTO v_rank_rows_missing_weight,v_tier_rows_missing_weight,
           v_unranked_rows_with_score,v_missing_tier_in_rank_window
      FROM stats;

    IF v_rank_rows_missing_weight <> 0 OR v_tier_rows_missing_weight <> 0 THEN
        RAISE EXCEPTION 'eligible tiered investable targets have % rank-ready and % total NULL weights',
            v_rank_rows_missing_weight,v_tier_rows_missing_weight;
    END IF;
    IF v_unranked_rows_with_score <> 0 THEN
        RAISE EXCEPTION 'eligible tiered investable targets have % scores without target ranks',
            v_unranked_rows_with_score;
    END IF;
    IF v_missing_tier_in_rank_window <> 0 THEN
        RAISE EXCEPTION 'eligible investable targets have % tier ranks in 1-400 but no liquidity tier',
            v_missing_tier_in_rank_window;
    END IF;
END
$phase2_phase3_target_readiness_guard$;

SELECT date_trunc('year',t.signal_date)::date AS calendar_year,
       t.horizon_sessions,
       count(*) AS current_hash_targets,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member) AS eligible_investable_targets,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NOT NULL
                          AND t.target_uniform_rank IS NOT NULL
                          AND t.execution_weight IS NOT NULL) AS phase3_tier_rank_ready_rows,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NULL) AS retained_members_without_tier,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NOT NULL
                          AND t.target_uniform_rank IS NULL
                          AND t.volatility_scaled_score IS NULL
                          AND t.realized_vol60 IS NULL) AS rank_rows_without_volatility,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NOT NULL
                          AND t.execution_weight IS NULL) AS tiered_investable_null_weights,
       count(*) FILTER (WHERE t.execution_weight IS NULL) AS all_null_weights
  FROM feat.phase2_label_targets_v3 t
 WHERE t.feature_set_hash=feat.phase2_feature_set_hash_v3()
 GROUP BY 1,2
 ORDER BY 1,2;

SELECT count(*) AS current_hash_targets,
       count(*) FILTER (WHERE t.execution_weight IS NULL) AS all_null_weights,
       count(*) FILTER (WHERE t.execution_weight IS NULL
                          AND t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member) AS null_weights_on_eligible_investable,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NOT NULL
                          AND t.target_uniform_rank IS NOT NULL
                          AND t.execution_weight IS NOT NULL) AS phase3_tier_rank_ready_rows,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NULL) AS eligible_investable_missing_tier,
       count(*) FILTER (WHERE t.membership_gate_status='ELIGIBLE'
                          AND t.is_investable_member
                          AND t.liquidity_tier IS NOT NULL
                          AND t.target_uniform_rank IS NULL
                          AND t.realized_vol60 IS NULL) AS tiered_rank_rows_missing_volatility
  FROM feat.phase2_label_targets_v3 t
 WHERE t.feature_set_hash=feat.phase2_feature_set_hash_v3();

COMMIT;

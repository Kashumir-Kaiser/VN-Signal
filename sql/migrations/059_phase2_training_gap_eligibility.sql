BEGIN;

-- A feature row after a missing source session can contain rolling values
-- whose lookback overlaps that unclassified interval. Keep those rows out of
-- Phase 3 until 250 effective sessions have elapsed after the first observed
-- row following each gap. Forward labels are independently filtered by the
-- MISSING_SESSION guard installed in migration 058.
CREATE OR REPLACE VIEW feat.phase2_training_gaps_v3 AS
WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), feature_sequence AS MATERIALIZED (
    SELECT f.symbol_id,
           s.session_no,
           lag(s.session_no) OVER (PARTITION BY f.symbol_id ORDER BY s.session_no)
               AS prior_session_no
    FROM feat.features_daily f
    JOIN sessions s USING (trade_date)
    WHERE f.feature_version = 'phase2-v3'
      AND f.feature_set_hash = feat.phase2_feature_set_hash_v3()
)
SELECT symbol_id,
       prior_session_no AS last_observed_session_no,
       session_no AS first_observed_session_no,
       session_no - prior_session_no - 1 AS missing_sessions
FROM feature_sequence
WHERE prior_session_no IS NOT NULL
  AND session_no - prior_session_no > 1;

CREATE OR REPLACE VIEW feat.phase2_training_eligible_v3 AS
WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
)
SELECT f.symbol_id,
       f.trade_date AS signal_date,
       l.horizon_sessions,
       l.label_version,
       f.feature_set_hash,
       l.excess_return
FROM feat.features_daily f
JOIN feat.labels_daily l
  ON l.symbol_id = f.symbol_id
 AND l.signal_date = f.trade_date
 AND l.feature_set_hash = f.feature_set_hash
JOIN sessions signal_session ON signal_session.trade_date = f.trade_date
WHERE f.feature_version = 'phase2-v3'
  AND f.feature_set_hash = feat.phase2_feature_set_hash_v3()
  AND l.label_version = 'close-next-open-v1'
  AND l.label_status = 'READY'
  AND NOT EXISTS (
      SELECT 1
      FROM feat.phase2_training_gaps_v3 g
      WHERE g.symbol_id = f.symbol_id
        AND signal_session.session_no >= g.first_observed_session_no
        AND signal_session.session_no < g.first_observed_session_no + 250
  );

COMMENT ON VIEW feat.phase2_training_gaps_v3 IS
    'Current-hash V3 symbol histories with at least one missing effective source session between observed feature rows. Missing sessions are not inferred to be suspensions.';
COMMENT ON VIEW feat.phase2_training_eligible_v3 IS
    'READY current-hash V3 label keys excluding the 250 effective-session rolling-feature cooldown after unexplained source-session gaps. Phase 3 training must read this view or document an equivalent policy.';

COMMIT;

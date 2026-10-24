BEGIN;

-- A label's entry/exit dates come from the exchange session spine. If the
-- source price series omits an effective session inside that holding window,
-- the adjustment-factor row count is smaller than the horizon. Preserve the
-- output row for audit, but never expose an incomplete return as READY.
DO $phase2_label_missing_session_guard$
DECLARE
    v_definition text := pg_get_functiondef(
        'feat.build_labels_set_based_shared(date,date,bigint[])'::regprocedure
    );
    v_anchor constant text :=
        'WHEN t.entry_episode IS DISTINCT FROM t.exit_episode THEN ''EPISODE_CHANGED''';
BEGIN
    IF position('sp.factor_rows' IN v_definition) = 0
       OR length(v_definition) - length(replace(v_definition, v_anchor, '')) <> length(v_anchor)
       OR position('WHEN t.exit_bar_date IS NULL' IN v_definition) = 0 THEN
        RAISE EXCEPTION 'unexpected Phase 2 shared label builder; refusing missing-session patch';
    END IF;

    v_definition := replace(
        v_definition,
        v_anchor,
        v_anchor || E'\n                   WHEN sp.factor_rows IS DISTINCT FROM t.horizon_sessions::bigint'
        || E' THEN ''MISSING_SESSION'''
    );
    IF position('WHEN sp.factor_rows IS DISTINCT FROM t.horizon_sessions::bigint'
                IN v_definition) = 0 THEN
        RAISE EXCEPTION 'missing-session guard was not installed in the shared label builder';
    END IF;
    EXECUTE v_definition;
END;
$phase2_label_missing_session_guard$;

-- Reclassify already materialized current-version labels whose exact
-- calendar window crosses a missing feature session. The interval list is
-- derived from the current hashed V3 feature rows; no missing price is filled.
WITH sessions AS MATERIALIZED (
    SELECT trade_date,
           row_number() OVER (ORDER BY trade_date)::bigint AS session_no
    FROM core.effective_trading_sessions
    WHERE is_session
), feature_sequence AS MATERIALIZED (
    SELECT f.symbol_id,
           f.trade_date,
           s.session_no,
           lag(s.session_no) OVER (PARTITION BY f.symbol_id ORDER BY f.trade_date)
               AS prior_session_no
    FROM feat.features_daily f
    JOIN sessions s USING (trade_date)
    WHERE f.feature_version = 'phase2-v3'
      AND f.feature_set_hash = feat.phase2_feature_set_hash_v3()
), missing_sessions AS MATERIALIZED (
    SELECT sequence.symbol_id, s.trade_date AS missing_trade_date
    FROM feature_sequence sequence
    JOIN sessions s
      ON s.session_no > sequence.prior_session_no
     AND s.session_no < sequence.session_no
    WHERE sequence.prior_session_no IS NOT NULL
      AND sequence.session_no - sequence.prior_session_no > 1
), affected AS MATERIALIZED (
    SELECT DISTINCT l.symbol_id, l.signal_date, l.horizon_sessions, l.label_version
    FROM feat.labels_daily l
    JOIN missing_sessions gap
      ON gap.symbol_id = l.symbol_id
     AND gap.missing_trade_date BETWEEN l.entry_date AND l.exit_date
    WHERE l.label_version = 'close-next-open-v1'
      AND l.feature_set_hash = feat.phase2_feature_set_hash_v3()
      AND l.label_status = 'READY'
)
UPDATE feat.labels_daily l
   SET label_status = 'MISSING_SESSION',
       stock_return = NULL,
       vnindex_return = NULL,
       excess_return = NULL,
       computed_at = now()
  FROM affected a
 WHERE l.symbol_id = a.symbol_id
   AND l.signal_date = a.signal_date
   AND l.horizon_sessions = a.horizon_sessions
   AND l.label_version = a.label_version;

COMMENT ON FUNCTION feat.build_labels_set_based_shared(date,date,bigint[])
IS 'Builds PIT 5/20-session excess-return labels on the effective exchange session spine. It records MISSING_SESSION when source factor rows do not cover every expected session inside the holding window.';

COMMIT;

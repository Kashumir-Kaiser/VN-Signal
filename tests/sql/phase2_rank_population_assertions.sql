\set ON_ERROR_STOP on
-- Exercise the actual V3 builder with disjoint nullable rank inputs, ties,
-- singleton/empty populations, and a stale V2 input. Synthetic fixtures only.
BEGIN;
DO $rank_populations$
DECLARE
    d date;
    ids bigint[];
    i integer;
    batch_no integer;
    actual feat.features_daily%ROWTYPE;
    low_score double precision:=feat.normal_quantile(1.0/3);
    high_score double precision:=feat.normal_quantile(5.0/6);
    expected_return double precision[];
    expected_turnover double precision[];
    expected_vol double precision[];
    mismatch_count bigint;
    rejected boolean:=false;
    previous_path text;
BEGIN
    IF EXISTS (
        SELECT 1 FROM feat.features_daily
         WHERE feature_version='phase2-v2'
           AND ((rank_momentum_20s IS NULL)<>(momentum_20s IS NULL)
             OR (rank_turnover_proxy IS NULL)<>(turnover_proxy_vnd IS NULL)
             OR (rank_realized_vol20 IS NULL)<>(realized_vol20 IS NULL))
    ) THEN RAISE EXCEPTION 'fresh V2 output has mismatched source/rank eligibility'; END IF;
    IF EXISTS (
        SELECT 1 FROM feat.features_daily
         WHERE feature_version='phase2-v3'
           AND ((rank_gaussian_return20 IS NULL)<>(return_20s IS NULL)
             OR (rank_gaussian_turnover_proxy IS NULL)<>(turnover_proxy_vnd IS NULL)
             OR (rank_gaussian_realized_vol20 IS NULL)<>(realized_vol20 IS NULL))
    ) THEN RAISE EXCEPTION 'fresh V3 output has mismatched source/Gaussian-rank eligibility'; END IF;
    -- Keep this test scoped to one deterministic 60-symbol cache sample so it
    -- also runs safely against the disposable report clone's full universe.
    PERFORM feat.begin_phase2_adjustment_rows(60,60);
    FOR batch_no IN
        SELECT DISTINCT b.batch_no FROM pg_temp.phase2_adjustment_symbol_batches b ORDER BY b.batch_no
    LOOP
        PERFORM feat.populate_phase2_adjustment_rows(batch_no);
    END LOOP;
    PERFORM feat.finish_phase2_adjustment_rows();
    previous_path:=feat.phase2_builder_set_context('core','feat','ops');
    SELECT trade_date INTO STRICT d FROM feat.features_daily
     WHERE feature_version='phase2-v2'
       AND symbol_id IN (SELECT symbol_id FROM pg_temp.phase2_adjustment_symbol_batches)
     GROUP BY trade_date
    HAVING count(*)>=4 ORDER BY trade_date DESC LIMIT 1;
    SELECT array_agg(symbol_id ORDER BY symbol_id) INTO ids FROM (
        SELECT symbol_id FROM feat.features_daily
         WHERE feature_version='phase2-v2' AND trade_date=d
           AND symbol_id IN (SELECT symbol_id FROM pg_temp.phase2_adjustment_symbol_batches)
         ORDER BY symbol_id LIMIT 4
    ) chosen;

    -- The V2 long-form rank stream must retain the exact three independently
    -- eligible percent_rank populations, including ties and singleton rules.
    WITH expected AS (
        SELECT base.symbol_id,rr.rank_r20,rt.rank_turnover,rv.rank_vol
          FROM feat.features_daily base
          LEFT JOIN (
              SELECT symbol_id,percent_rank() OVER(PARTITION BY trade_date ORDER BY return_20s) AS rank_r20
                FROM feat.features_daily
               WHERE feature_version='phase2-v2' AND trade_date=d AND return_20s IS NOT NULL
          ) rr USING(symbol_id)
          LEFT JOIN (
              SELECT symbol_id,percent_rank() OVER(PARTITION BY trade_date ORDER BY turnover_proxy_vnd) AS rank_turnover
                FROM feat.features_daily
               WHERE feature_version='phase2-v2' AND trade_date=d AND turnover_proxy_vnd IS NOT NULL
          ) rt USING(symbol_id)
          LEFT JOIN (
              SELECT symbol_id,percent_rank() OVER(PARTITION BY trade_date ORDER BY realized_vol20) AS rank_vol
                FROM feat.features_daily
               WHERE feature_version='phase2-v2' AND trade_date=d AND realized_vol20 IS NOT NULL
          ) rv USING(symbol_id)
         WHERE base.feature_version='phase2-v2' AND base.trade_date=d
    )
    SELECT count(*) INTO mismatch_count
      FROM feat.features_daily f
      JOIN expected e USING(symbol_id)
     WHERE f.feature_version='phase2-v2' AND f.trade_date=d
       AND ((f.rank_momentum_20s IS DISTINCT FROM e.rank_r20)
         OR (f.rank_turnover_proxy IS DISTINCT FROM e.rank_turnover)
         OR (f.rank_realized_vol20 IS DISTINCT FROM e.rank_vol));
    IF mismatch_count<>0 THEN
        RAISE EXCEPTION 'V2 rank-stream values differ from independent percent_rank populations on % rows',mismatch_count;
    END IF;

    UPDATE feat.features_daily SET
        return_20s=NULL,momentum_20s=NULL,turnover_proxy_vnd=NULL,realized_vol20=NULL,
        rank_momentum_20s=NULL,rank_turnover_proxy=NULL,rank_realized_vol20=NULL
     WHERE feature_version='phase2-v2' AND trade_date=d AND symbol_id=ANY(ids);
    FOR i IN 1..4 LOOP
        UPDATE feat.features_daily SET
            return_20s=CASE i WHEN 1 THEN 0.1 WHEN 2 THEN 0.2 WHEN 4 THEN 0.1 END,
            momentum_20s=CASE i WHEN 1 THEN 0.1 WHEN 2 THEN 0.2 WHEN 4 THEN 0.1 END,
            turnover_proxy_vnd=CASE i WHEN 2 THEN 100 WHEN 3 THEN 200 WHEN 4 THEN 100 END,
            realized_vol20=CASE i WHEN 1 THEN 0.2 WHEN 3 THEN 0.4 WHEN 4 THEN 0.2 END,
            rank_momentum_20s=CASE i WHEN 1 THEN 0 WHEN 2 THEN 1 WHEN 4 THEN 0 END,
            rank_turnover_proxy=CASE i WHEN 2 THEN 0 WHEN 3 THEN 1 WHEN 4 THEN 0 END,
            rank_realized_vol20=CASE i WHEN 1 THEN 0 WHEN 3 THEN 1 WHEN 4 THEN 0 END
         WHERE feature_version='phase2-v2' AND trade_date=d AND symbol_id=ids[i];
    END LOOP;
    PERFORM feat.build_price_features_v3_shared(d,d,ids);
    expected_return:=ARRAY[low_score,high_score,NULL,low_score];
    expected_turnover:=ARRAY[NULL,low_score,high_score,low_score];
    expected_vol:=ARRAY[low_score,NULL,high_score,low_score];
    FOR i IN 1..4 LOOP
        SELECT * INTO STRICT actual FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND trade_date=d AND symbol_id=ids[i];
        IF actual.rank_gaussian_return20 IS DISTINCT FROM expected_return[i]
           OR actual.rank_gaussian_turnover_proxy IS DISTINCT FROM expected_turnover[i]
           OR actual.rank_gaussian_realized_vol20 IS DISTINCT FROM expected_vol[i] THEN
            RAISE EXCEPTION 'independent rank population/tie regression for symbol %: %, %, %',
                ids[i],actual.rank_gaussian_return20,
                actual.rank_gaussian_turnover_proxy,actual.rank_gaussian_realized_vol20;
        END IF;
    END LOOP;

    -- Exercise the E1 row-level rank/input alignment counter with an injected
    -- mismatch; equal aggregate NULL rates must not mask a bad row.
    UPDATE feat.features_daily SET rank_gaussian_return20=NULL
     WHERE feature_version='phase2-v3' AND trade_date=d AND symbol_id=ids[1]
       AND return_20s IS NOT NULL;
    SELECT count(*) FILTER (
               WHERE (rank_gaussian_return20 IS NULL)<>(return_20s IS NULL)
           ) INTO mismatch_count
      FROM feat.features_daily
     WHERE feature_version='phase2-v3' AND trade_date=d AND symbol_id=ANY(ids);
    IF mismatch_count<>1 THEN
        RAISE EXCEPTION 'rank/input NULL alignment diagnostic missed injected mismatch';
    END IF;

    UPDATE feat.features_daily SET return_20s=NULL,momentum_20s=NULL,
        turnover_proxy_vnd=CASE WHEN symbol_id=ids[1] THEN 1 END,realized_vol20=NULL,
        rank_momentum_20s=NULL,rank_realized_vol20=NULL,
        rank_turnover_proxy=CASE WHEN symbol_id=ids[1] THEN 0 END
     WHERE feature_version='phase2-v2' AND trade_date=d AND symbol_id=ANY(ids);
    PERFORM feat.build_price_features_v3_shared(d,d,ids);
    IF EXISTS (
        SELECT 1 FROM feat.features_daily
         WHERE feature_version='phase2-v3' AND trade_date=d AND symbol_id=ANY(ids)
           AND (rank_gaussian_return20 IS NOT NULL OR rank_gaussian_realized_vol20 IS NOT NULL
             OR rank_gaussian_turnover_proxy IS DISTINCT FROM
                 CASE WHEN symbol_id=ids[1] THEN 0::double precision END)
    ) THEN RAISE EXCEPTION 'singleton/empty Gaussian rank population regression'; END IF;

    UPDATE feat.features_daily SET feature_set_hash=repeat('0',64)
     WHERE feature_version='phase2-v2' AND trade_date=d AND symbol_id=ids[1];
    BEGIN
        PERFORM feat.build_price_features_v3_shared(d,d,ids);
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'Phase 2 V3 requires current, rank-consistent V2 inputs%' THEN
            rejected:=true;
        ELSE RAISE;
        END IF;
    END;
    IF NOT rejected THEN RAISE EXCEPTION 'V3 accepted a stale V2 feature hash'; END IF;
    PERFORM feat.phase2_builder_restore_context(previous_path);
END;
$rank_populations$;
ROLLBACK;

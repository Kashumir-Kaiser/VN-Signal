-- Upgrade installed builders as well as fresh installations. Earlier V2
-- builds ranked partial volatility windows; V3 also used the intersection of
-- three unrelated non-null populations for every Gaussian rank.
BEGIN;

DO $rank_integrity$
DECLARE
    definition text;
    anchor text;
    start_pos integer;
    end_pos integer;
BEGIN
    definition:=pg_get_functiondef('feat.build_features_v2_shared(date,date,bigint[])'::regprocedure);
    anchor:='FROM picked WHERE vol20 IS NOT NULL) rv';
    IF strpos(definition,anchor)>0 THEN
        definition:=replace(definition,anchor,
            'FROM picked WHERE vol20 IS NOT NULL AND return_n20=20) rv');
    END IF;
    IF strpos(definition,'WHERE vol20 IS NOT NULL AND return_n20=20')=0 THEN
        RAISE EXCEPTION 'unexpected V2 volatility rank population';
    END IF;
    IF strpos(definition,'phase2_v2_rank_integrity')=0 THEN
        anchor:='    RETURN affected;';
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V2 rank-integrity assertion anchor';
        END IF;
        definition:=replace(definition,anchor,$assertion$
    -- phase2_v2_rank_integrity: ranks and values must share eligibility.
    IF EXISTS (
        SELECT 1 FROM features_daily f
         WHERE f.feature_version=v_version
           AND f.trade_date BETWEEN p_date_from AND p_date_to
           AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids))
           AND ((f.rank_realized_vol20 IS NULL)<>(f.realized_vol20 IS NULL)
             OR (f.rank_momentum_20s IS NULL)<>(f.momentum_20s IS NULL)
             OR (f.rank_turnover_proxy IS NULL)<>(f.turnover_proxy_vnd IS NULL))
    ) THEN
        RAISE EXCEPTION 'Phase 2 V2 rank/input eligibility mismatch';
    END IF;
    RETURN affected;$assertion$);
    END IF;
    EXECUTE definition;

    definition:=pg_get_functiondef('feat.build_price_features_v3_shared(date,date,bigint[])'::regprocedure);
    IF strpos(definition,'independent_nonnull_rank_populations_v1')=0 THEN
        start_pos:=strpos(definition,'    INSERT INTO pg_temp.phase2_v3_ranks');
        end_pos:=strpos(definition,'    CREATE UNIQUE INDEX IF NOT EXISTS phase2_v3_ranks_key_idx');
        IF start_pos=0 OR end_pos<=start_pos THEN
            RAISE EXCEPTION 'unexpected V3 Gaussian rank stage anchors';
        END IF;
        definition:=overlay(definition PLACING $ranks$
    INSERT INTO pg_temp.phase2_v3_ranks
    -- independent_nonnull_rank_populations_v1: each metric has its own
    -- eligible population. Ties receive their average ordinal before the
    -- Gaussian transform; a singleton maps to normal_quantile(0.5)=0.
    WITH inputs AS MATERIALIZED (
        SELECT f.symbol_id,f.trade_date,x.metric,x.value
          FROM features_daily f
          CROSS JOIN LATERAL (VALUES
              ('return20',f.return_20s),
              ('turnover',f.turnover_proxy_vnd),
              ('vol20',f.realized_vol20)
          ) x(metric,value)
         WHERE f.feature_version='phase2-v2'
           AND f.trade_date BETWEEN p_date_from AND p_date_to
           AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids))
           AND x.value IS NOT NULL
    ), ranks AS (
        SELECT symbol_id,trade_date,metric,
               feat.normal_quantile(
                   (rank() OVER(PARTITION BY trade_date,metric ORDER BY value)
                    +(count(*) OVER(PARTITION BY trade_date,metric,value)-1)/2.0-0.5)
                   /count(*) OVER(PARTITION BY trade_date,metric)
               ) AS score
          FROM inputs
    )
    SELECT symbol_id,trade_date,
           max(score) FILTER(WHERE metric='return20'),
           max(score) FILTER(WHERE metric='turnover'),
           max(score) FILTER(WHERE metric='vol20')
      FROM ranks GROUP BY symbol_id,trade_date;
$ranks$ FROM start_pos FOR end_pos-start_pos);
    END IF;
    IF strpos(definition,'phase2_v3_current_base_integrity')=0 THEN
        anchor:='    DELETE FROM features_daily';
        IF length(definition)-length(replace(definition,anchor,''))<>length(anchor) THEN
            RAISE EXCEPTION 'unexpected V3 base-integrity assertion anchor';
        END IF;
        definition:=replace(definition,anchor,$base_assertion$
    -- phase2_v3_current_base_integrity: rebuilding V3 cannot certify stale V2.
    IF EXISTS (
        SELECT 1 FROM features_daily f
         WHERE f.feature_version='phase2-v2'
           AND f.trade_date BETWEEN p_date_from AND p_date_to
           AND (p_symbol_ids IS NULL OR f.symbol_id=ANY(p_symbol_ids))
           AND (f.feature_set_hash IS DISTINCT FROM feat.phase2_feature_set_hash()
             OR (f.rank_realized_vol20 IS NULL)<>(f.realized_vol20 IS NULL)
             OR (f.rank_momentum_20s IS NULL)<>(f.momentum_20s IS NULL)
             OR (f.rank_turnover_proxy IS NULL)<>(f.turnover_proxy_vnd IS NULL))
    ) THEN
        RAISE EXCEPTION 'Phase 2 V3 requires current, rank-consistent V2 inputs; rebuild V2 first';
    END IF;
    DELETE FROM features_daily$base_assertion$);
    END IF;
    EXECUTE definition;
END;
$rank_integrity$;

-- A change to rank eligibility changes feature meaning and must invalidate
-- existing output hashes. These transformations also handle older installed
-- hash functions without rewriting an applied migration's history.
DO $rank_hashes$
DECLARE definition text;
BEGIN
    definition:=pg_get_functiondef('feat.phase2_feature_set_hash()'::regprocedure);
    IF strpos(definition,'strict_full_window_cross_sectional_vol_rank')=0 THEN
        IF strpos(definition,'|obv_slope20_same_episode')=0 THEN
            RAISE EXCEPTION 'unexpected V2 hash definition';
        END IF;
        definition:=replace(definition,'|obv_slope20_same_episode',
            '|obv_slope20_same_episode|strict_full_window_cross_sectional_vol_rank');
        EXECUTE definition;
    END IF;
    definition:=pg_get_functiondef('feat.phase2_feature_set_hash_v3()'::regprocedure);
    IF strpos(definition,'independent_nonnull_rank_populations_v1')=0 THEN
        IF strpos(definition,'|source_dependent_features_null_without_evidence')=0 THEN
            RAISE EXCEPTION 'unexpected V3 hash definition';
        END IF;
        definition:=replace(definition,'|source_dependent_features_null_without_evidence',
            '|independent_nonnull_rank_populations_v1|source_dependent_features_null_without_evidence');
        EXECUTE definition;
    END IF;
END;
$rank_hashes$;

COMMIT;

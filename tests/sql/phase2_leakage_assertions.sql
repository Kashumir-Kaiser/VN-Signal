\set ON_ERROR_STOP on
BEGIN;
SET LOCAL vnpipe.phase2_symbol_batch_size='2';
CREATE TEMP TABLE phase2_feature_snapshot (
    symbol_id bigint NOT NULL,
    trade_date date NOT NULL,
    feature_version text NOT NULL,
    row_image jsonb NOT NULL,
    PRIMARY KEY(symbol_id,trade_date,feature_version)
) ON COMMIT DROP;
CREATE TEMP TABLE phase2_label_snapshot (
    symbol_id bigint NOT NULL,
    signal_date date NOT NULL,
    horizon_sessions integer NOT NULL,
    stock_return double precision,
    label_status text NOT NULL,
    PRIMARY KEY(symbol_id,signal_date,horizon_sessions)
) ON COMMIT DROP;
CREATE TEMP TABLE phase2_post_cut_feature_snapshot (
    symbol_id bigint NOT NULL,
    trade_date date NOT NULL,
    feature_version text NOT NULL,
    row_image jsonb NOT NULL,
    PRIMARY KEY(symbol_id,trade_date,feature_version)
) ON COMMIT DROP;

DO $$
DECLARE
    d0 date;
    cutoff date;
    lag_date date;
    lag_next_date date;
    d24 date;
    changed_stock_rows bigint;
    changed_index_rows bigint;
    changed_symbol bigint;
    changed_date date;
    changed_fields text;
    label_symbol bigint;
    label_return_before double precision;
    label_status_before text;
    post_cut_key_mismatches bigint;
    post_cut_value_changes bigint;
    index_value_same_session_before double precision;
    index_value_same_session_after double precision;
    index_value_next_session_before double precision;
    index_value_next_session_after double precision;
BEGIN
    SELECT trade_date INTO d0 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 0 LIMIT 1;
    SELECT trade_date INTO cutoff FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 12 LIMIT 1;
    SELECT trade_date INTO lag_date FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 70 LIMIT 1;
    SELECT trade_date INTO lag_next_date FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 71 LIMIT 1;
    SELECT trade_date INTO d24 FROM core.calendar
     WHERE source='phase2_test_fixture' ORDER BY trade_date OFFSET 72 LIMIT 1;
    IF d0 IS NULL OR cutoff IS NULL OR lag_date IS NULL OR lag_next_date IS NULL OR d24 IS NULL THEN
        RAISE EXCEPTION 'synthetic Phase 2 leakage calendar fixture is incomplete';
    END IF;

    PERFORM feat.build_features(d0,d24);
    INSERT INTO phase2_feature_snapshot(symbol_id,trade_date,feature_version,row_image)
    SELECT f.symbol_id,f.trade_date,f.feature_version,to_jsonb(f)-'built_at'
    FROM feat.features_daily f
    WHERE f.feature_version='phase2-v3' AND f.trade_date BETWEEN d0 AND cutoff;
    IF NOT EXISTS (SELECT 1 FROM phase2_feature_snapshot) THEN
        RAISE EXCEPTION 'no pre-perturbation feature rows to compare';
    END IF;
    INSERT INTO phase2_post_cut_feature_snapshot(symbol_id,trade_date,feature_version,row_image)
    SELECT f.symbol_id,f.trade_date,f.feature_version,to_jsonb(f)-'built_at'
    FROM feat.features_daily f
    WHERE f.feature_version='phase2-v3' AND f.trade_date>cutoff AND f.trade_date<=d24;
    IF NOT EXISTS (SELECT 1 FROM phase2_post_cut_feature_snapshot) THEN
        RAISE EXCEPTION 'no post-cut feature rows to compare';
    END IF;

    -- Same-session index observations must not enter a stock feature row.
    -- Their effect is expected on the next effective session, which is the
    -- positive control for the required one-session cross-asset lag.
    SELECT f.vnindex_realized_vol60 INTO index_value_same_session_before
      FROM feat.features_daily f JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.trade_date=lag_date AND f.feature_version='phase2-v3';
    SELECT f.vnindex_realized_vol60 INTO index_value_next_session_before
      FROM feat.features_daily f JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.trade_date=lag_next_date AND f.feature_version='phase2-v3';
    IF index_value_same_session_before IS NULL OR index_value_next_session_before IS NULL THEN
        RAISE EXCEPTION 'one-session lag fixture lacks non-null VNINDEX volatility controls';
    END IF;
    UPDATE core.index_bars
       SET o=o*1.013,h=h*1.013,l=l*1.013,c=c*1.013
     WHERE index_symbol='VNINDEX' AND source='vci' AND trade_date=lag_date;
    IF NOT FOUND THEN RAISE EXCEPTION 'could not perturb VNINDEX same-session bar'; END IF;
    PERFORM feat.build_features(d0,d24);
    SELECT f.vnindex_realized_vol60 INTO index_value_same_session_after
      FROM feat.features_daily f JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.trade_date=lag_date AND f.feature_version='phase2-v3';
    SELECT f.vnindex_realized_vol60 INTO index_value_next_session_after
      FROM feat.features_daily f JOIN core.symbols s USING(symbol_id)
     WHERE s.symbol='P2READY' AND f.trade_date=lag_next_date AND f.feature_version='phase2-v3';
    IF index_value_same_session_after IS DISTINCT FROM index_value_same_session_before THEN
        RAISE EXCEPTION 'same-session VNINDEX data changed stock features at %',lag_date;
    END IF;
    IF index_value_next_session_after IS NOT DISTINCT FROM index_value_next_session_before THEN
        RAISE EXCEPTION 'one-session lag positive control did not change next-session VNINDEX context at %',lag_next_date;
    END IF;

    -- Capture a READY future label before perturbation. Its entry and exit are
    -- both strictly after cutoff, so its stock return is the positive control.
    SELECT symbol_id INTO label_symbol FROM core.symbols WHERE symbol='P2READY';
    PERFORM feat.build_labels(cutoff,cutoff);
    INSERT INTO phase2_label_snapshot
        (symbol_id,signal_date,horizon_sessions,stock_return,label_status)
    SELECT symbol_id,signal_date,horizon_sessions,stock_return,label_status
    FROM feat.labels_daily
    WHERE symbol_id=label_symbol AND signal_date=cutoff AND horizon_sessions=5;
    SELECT stock_return,label_status
      INTO label_return_before,label_status_before
      FROM phase2_label_snapshot
     WHERE symbol_id=label_symbol AND signal_date=cutoff AND horizon_sessions=5;
    IF label_status_before IS DISTINCT FROM 'READY' OR label_return_before IS NULL THEN
        RAISE EXCEPTION 'future-label positive control is not READY before perturbation';
    END IF;

    -- Perturb every future price and volume with deterministic independent
    -- per-row noise in [−20%, +20%]. Hashes make this repeatable while ensuring
    -- the input values actually change; all mutations roll back below.
    WITH hashed AS MATERIALIZED (
        SELECT b.symbol_id,b.trade_date,
               sha256(convert_to(s.symbol||':'||b.trade_date::text||':price','UTF8')) AS price_hash,
               sha256(convert_to(s.symbol||':'||b.trade_date::text||':volume','UTF8')) AS volume_hash
        FROM core.bars_daily_sources b
        JOIN core.symbols s USING(symbol_id)
        WHERE b.source='vndirect' AND b.trade_date>cutoff
    ), noise AS MATERIALIZED (
        SELECT symbol_id,trade_date,
               0.8+(
                   get_byte(price_hash,0)::double precision*16777216.0+
                   get_byte(price_hash,1)::double precision*65536.0+
                   get_byte(price_hash,2)::double precision*256.0+
                   get_byte(price_hash,3)::double precision
               )/4294967295.0*0.4 AS price_factor,
               0.8+(
                   get_byte(volume_hash,0)::double precision*16777216.0+
                   get_byte(volume_hash,1)::double precision*65536.0+
                   get_byte(volume_hash,2)::double precision*256.0+
                   get_byte(volume_hash,3)::double precision
               )/4294967295.0*0.4 AS volume_factor
        FROM hashed
    )
    UPDATE core.bars_daily_sources b
       SET o=b.o*n.price_factor,h=b.h*n.price_factor,l=b.l*n.price_factor,
           c=b.c*n.price_factor,adjusted_o=b.adjusted_o*n.price_factor,
           adjusted_h=b.adjusted_h*n.price_factor,adjusted_l=b.adjusted_l*n.price_factor,
           adjusted_c=b.adjusted_c*n.price_factor,basic_price=b.basic_price*n.price_factor,
           average_price=b.average_price*n.price_factor,v=b.v*n.volume_factor
      FROM noise n
     WHERE b.symbol_id=n.symbol_id AND b.trade_date=n.trade_date
       AND b.source='vndirect';
    GET DIAGNOSTICS changed_stock_rows=ROW_COUNT;
    WITH hashed AS MATERIALIZED (
        SELECT i.index_symbol,i.trade_date,
               sha256(convert_to(i.index_symbol||':'||i.trade_date::text||':price','UTF8')) AS price_hash,
               sha256(convert_to(i.index_symbol||':'||i.trade_date::text||':volume','UTF8')) AS volume_hash
        FROM core.index_bars i
        WHERE i.source='vci' AND i.trade_date>cutoff
    ), noise AS MATERIALIZED (
        SELECT index_symbol,trade_date,
               0.8+(
                   get_byte(price_hash,0)::double precision*16777216.0+
                   get_byte(price_hash,1)::double precision*65536.0+
                   get_byte(price_hash,2)::double precision*256.0+
                   get_byte(price_hash,3)::double precision
               )/4294967295.0*0.4 AS price_factor,
               0.8+(
                   get_byte(volume_hash,0)::double precision*16777216.0+
                   get_byte(volume_hash,1)::double precision*65536.0+
                   get_byte(volume_hash,2)::double precision*256.0+
                   get_byte(volume_hash,3)::double precision
               )/4294967295.0*0.4 AS volume_factor
        FROM hashed
    )
    UPDATE core.index_bars i
       SET o=i.o*n.price_factor,h=i.h*n.price_factor,l=i.l*n.price_factor,
           c=i.c*n.price_factor,v=i.v*n.volume_factor
      FROM noise n
     WHERE i.index_symbol=n.index_symbol AND i.trade_date=n.trade_date
       AND i.source='vci';
    GET DIAGNOSTICS changed_index_rows=ROW_COUNT;
    IF changed_stock_rows=0 OR changed_index_rows=0 THEN
        RAISE EXCEPTION 'future stock or VNINDEX fixture values were not perturbed';
    END IF;

    -- The function normally reuses its session-local PIT cache across chunks.
    -- Refresh it after changing source inputs so this test actually exercises
    -- the perturbed stock-price path rather than a stale cached snapshot.
    PERFORM feat.prepare_phase2_adjustment_rows(true);
    PERFORM feat.build_features(d0,d24);
    IF EXISTS (
        SELECT 1
        FROM phase2_feature_snapshot old
        FULL JOIN (
            SELECT * FROM feat.features_daily
            WHERE feature_version='phase2-v3' AND trade_date BETWEEN d0 AND cutoff
        ) current
          ON current.symbol_id=old.symbol_id AND current.trade_date=old.trade_date
         AND current.feature_version=old.feature_version
        WHERE old.symbol_id IS NULL OR current.symbol_id IS NULL
           OR old.row_image IS DISTINCT FROM (to_jsonb(current)-'built_at')
    ) THEN
        SELECT coalesce(old.symbol_id,current.symbol_id),
               coalesce(old.trade_date,current.trade_date),
               CASE WHEN old.symbol_id IS NULL THEN 'unexpected row added'
                    WHEN current.symbol_id IS NULL THEN 'row missing after rebuild'
                    ELSE 'changed feature values' END
          INTO changed_symbol,changed_date,changed_fields
          FROM phase2_feature_snapshot old
          FULL JOIN (
              SELECT * FROM feat.features_daily
              WHERE feature_version='phase2-v3' AND trade_date BETWEEN d0 AND cutoff
          ) current
            ON current.symbol_id=old.symbol_id AND current.trade_date=old.trade_date
           AND current.feature_version=old.feature_version
         WHERE old.symbol_id IS NULL OR current.symbol_id IS NULL
            OR old.row_image IS DISTINCT FROM (to_jsonb(current)-'built_at')
         ORDER BY coalesce(old.trade_date,current.trade_date),coalesce(old.symbol_id,current.symbol_id)
         LIMIT 1;
        IF changed_fields='changed feature values' THEN
            SELECT string_agg(fields.key,',' ORDER BY fields.key)
              INTO changed_fields
              FROM phase2_feature_snapshot old
              JOIN feat.features_daily current
                ON current.symbol_id=old.symbol_id AND current.trade_date=old.trade_date
               AND current.feature_version=old.feature_version
              CROSS JOIN LATERAL jsonb_each(old.row_image) fields
             WHERE old.symbol_id=changed_symbol AND old.trade_date=changed_date
               AND fields.value IS DISTINCT FROM (to_jsonb(current)-'built_at')->fields.key;
        END IF;
        RAISE EXCEPTION 'future prices or volume changed features for symbol % at %: %',
            changed_symbol,changed_date,changed_fields;
    END IF;

    SELECT count(*) INTO post_cut_key_mismatches
    FROM (
        (SELECT symbol_id,trade_date,feature_version
           FROM phase2_post_cut_feature_snapshot
         EXCEPT
         SELECT symbol_id,trade_date,feature_version
           FROM feat.features_daily
          WHERE feature_version='phase2-v3' AND trade_date>cutoff AND trade_date<=d24)
        UNION ALL
        (SELECT symbol_id,trade_date,feature_version
           FROM feat.features_daily
          WHERE feature_version='phase2-v3' AND trade_date>cutoff AND trade_date<=d24
         EXCEPT
         SELECT symbol_id,trade_date,feature_version
           FROM phase2_post_cut_feature_snapshot)
    ) key_diff;
    IF post_cut_key_mismatches<>0 THEN
        RAISE EXCEPTION 'post-cut feature key coverage changed after perturbation (% mismatches)',
            post_cut_key_mismatches;
    END IF;
    SELECT count(*) INTO post_cut_value_changes
      FROM phase2_post_cut_feature_snapshot old
      JOIN feat.features_daily current
        USING(symbol_id,trade_date,feature_version)
     WHERE current.feature_version='phase2-v3'
       AND current.trade_date>cutoff AND current.trade_date<=d24
       AND old.row_image IS DISTINCT FROM (to_jsonb(current)-'built_at');
    IF post_cut_value_changes=0 THEN
        RAISE EXCEPTION 'post-cut feature perturbation changed no same-key feature values';
    END IF;

    PERFORM feat.build_labels(cutoff,cutoff);
    IF NOT EXISTS (
        SELECT 1
        FROM phase2_label_snapshot old
        JOIN feat.labels_daily current
          USING(symbol_id,signal_date,horizon_sessions)
        WHERE old.stock_return IS DISTINCT FROM current.stock_return
          AND old.label_status='READY' AND current.label_status='READY'
    ) THEN
        RAISE EXCEPTION 'future-price perturbation failed to change the READY positive-control label';
    END IF;
END $$;
ROLLBACK;

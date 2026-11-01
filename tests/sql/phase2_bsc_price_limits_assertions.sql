-- Synthetic CI-only fixture: no live or historical market data is seeded.
-- This proves BSC source lineage, exact close/volume admission, label-only
-- fallback, input-hash invalidation, and scalar/batched weight equivalence.
BEGIN;
SET LOCAL statement_timeout='10min';

-- Replace the expensive, unrelated base feature hash only inside this
-- rollback-only fixture so the production label input-hash function's exact
-- price-limit dependency can be tested without rebuilding the feature cache.
CREATE OR REPLACE FUNCTION ops.phase2_label_target_chunk_base_input_hash(
    p_date_from date,
    p_date_to date
)
RETURNS text LANGUAGE sql STABLE AS $phase2_bsc_fixture_base_hash$
    SELECT ops.phase2_hash_text(
        coalesce(p_date_from::text,'null')||'|'||coalesce(p_date_to::text,'null')
    )
$phase2_bsc_fixture_base_hash$;

DO $phase2_bsc_price_limits_fixture$
DECLARE
    v_symbol_id bigint;
    v_vndirect_landing_id bigint;
    v_bsc_landing_id bigint;
    v_bad_close_landing_id bigint;
    v_fetched timestamptz:=TIMESTAMPTZ '2100-03-30 10:00:00+07';
    v_ingest uuid:='30000000-0000-4000-8000-000000000310';
    v_bar_rows jsonb;
    v_vndirect_payload jsonb;
    v_vndirect_bytes bytea;
    v_vndirect_hash text;
    v_bsc_html text;
    v_bsc_cells jsonb;
    v_bsc_row jsonb;
    v_bsc_response jsonb;
    v_bsc_payload jsonb;
    v_bsc_bytes bytea;
    v_bsc_hash text;
    v_bad_html text;
    v_bad_cells jsonb;
    v_bad_row jsonb;
    v_bad_response jsonb;
    v_bad_payload jsonb;
    v_bad_bytes bytea;
    v_bad_hash text;
    v_materialized bigint;
    v_batch_rows bigint;
    v_hash_before text;
    v_hash_after text;
    v_weight double precision;
    v_error text;
    v_failed boolean;
BEGIN
    INSERT INTO core.symbols(symbol,exchange,first_seen_at,last_seen_at)
    VALUES('P2BSCFIX','HOSE',v_fetched,v_fetched)
    RETURNING symbol_id INTO v_symbol_id;

    INSERT INTO core.calendar(trade_date,is_session,source,notes) VALUES
        (DATE '2100-03-10',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-11',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-12',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-15',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-16',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-17',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-18',true,'synthetic_test','CI fixture only'),
        (DATE '2100-03-19',true,'synthetic_test','CI fixture only')
    -- Make repeat runs safe if another SQL fixture already seeded a session.
    ON CONFLICT (trade_date) DO NOTHING;

    v_bar_rows:=jsonb_build_array(
        jsonb_build_object('code','P2BSCFIX','date','2100-03-10','open',100,'high',105,'low',99,'close',105,'nmVolume',1000,'ptVolume',0,'ceilingPrice',0,'floorPrice',0),
        jsonb_build_object('code','P2BSCFIX','date','2100-03-11','open',106,'high',108,'low',105,'close',107,'nmVolume',1100,'ptVolume',0,'ceilingPrice',110,'floorPrice',90),
        jsonb_build_object('code','P2BSCFIX','date','2100-03-12','open',107,'high',109,'low',106,'close',108,'nmVolume',1200,'ptVolume',0,'ceilingPrice',111,'floorPrice',91),
        jsonb_build_object('code','P2BSCFIX','date','2100-03-15','open',108,'high',110,'low',107,'close',109,'nmVolume',1300,'ptVolume',0,'ceilingPrice',112,'floorPrice',92),
        jsonb_build_object('code','P2BSCFIX','date','2100-03-16','open',109,'high',111,'low',108,'close',110,'nmVolume',1400,'ptVolume',0,'ceilingPrice',113,'floorPrice',93)
    );
    v_vndirect_payload:=jsonb_build_object('data',v_bar_rows);
    v_vndirect_bytes:=convert_to(v_vndirect_payload::text,'UTF8');
    v_vndirect_hash:=encode(sha256(v_vndirect_bytes),'hex');
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        v_ingest,'vndirect','equity_ohlcv',v_fetched,'P2BSCFIX',
        v_vndirect_payload,v_vndirect_hash,v_vndirect_bytes
    ) RETURNING landing_id INTO v_vndirect_landing_id;

    INSERT INTO core.bars_daily_sources(
        symbol_id,trade_date,source,o,h,l,c,v,adj_basis,is_traded,
        landing_id,source_row,ingest_id,fetched_at
    )
    SELECT v_symbol_id,(r.row_payload->>'date')::date,'vndirect',
           (r.row_payload->>'open')::double precision,
           (r.row_payload->>'high')::double precision,
           (r.row_payload->>'low')::double precision,
           (r.row_payload->>'close')::double precision,
           (r.row_payload->>'nmVolume')::double precision,
           'unadjusted',(r.row_payload->>'nmVolume')::numeric>0,
           v_vndirect_landing_id,(r.ordinality-1)::integer,v_ingest,v_fetched
      FROM jsonb_array_elements(v_bar_rows) WITH ORDINALITY r(row_payload,ordinality);

    IF core.materialize_vndirect_daily_price_limits(
        DATE '2100-03-11',DATE '2100-03-16',ARRAY[v_symbol_id]
    )<>4 THEN
        RAISE EXCEPTION 'expected four exact VNDIRECT control limits';
    END IF;

    INSERT INTO feat.labels_daily(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,
        entry_date,exit_date,label_status,stock_return,vnindex_return,excess_return,price_basis
    ) VALUES(
        v_symbol_id,DATE '2100-03-09',5,'bsc-fixture-v1',repeat('a',64),
        DATE '2100-03-10',DATE '2100-03-16','READY',0,0,0,'adjusted_as_of_exit'
    );
    INSERT INTO feat.phase2_label_targets_v3(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,
        raw_excess_return,winsorized_excess_p01,winsorized_excess_p99,
        winsorized_excess_return,membership_gate_status,is_investable_member
    ) VALUES(
        v_symbol_id,DATE '2100-03-09',5,'bsc-fixture-v1',repeat('a',64),
        0,0,0,0,'INDETERMINATE',false
    );
    INSERT INTO feat.labels_daily(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,
        entry_date,exit_date,label_status,stock_return,vnindex_return,excess_return,price_basis
    ) VALUES(
        v_symbol_id,DATE '2100-03-12',5,'bsc-fixture-v1',repeat('b',64),
        DATE '2100-03-15',DATE '2100-03-19','READY',0,0,0,'adjusted_as_of_exit'
    );
    INSERT INTO feat.phase2_label_targets_v3(
        symbol_id,signal_date,horizon_sessions,label_version,feature_set_hash,
        raw_excess_return,winsorized_excess_p01,winsorized_excess_p99,
        winsorized_excess_return,membership_gate_status,is_investable_member
    ) VALUES(
        v_symbol_id,DATE '2100-03-12',5,'bsc-fixture-v1',repeat('b',64),
        0,0,0,0,'INDETERMINATE',false
    );

    v_hash_before:=ops.phase2_label_target_chunk_input_hash(
        DATE '2100-03-09',DATE '2100-03-09'
    );

    v_bsc_html:='<tr><td>10/03/2100</td><td>105,000</td><td>1,000</td><td>1,000</td><td>105</td><td>0</td><td>0</td><td>104,000</td><td>110,000</td><td>90,000</td></tr>';
    v_bsc_cells:=jsonb_build_array('10/03/2100','105,000','1,000','1,000','105','0','0','104,000','110,000','90,000');
    v_bsc_row:=jsonb_build_object(
        'code','P2BSCFIX','trade_date','2100-03-10',
        'close_price_vnd','105000','matched_volume_shares','1000',
        'reference_price_vnd','104000','ceiling_price_vnd','110000','floor_price_vnd','90000',
        'source_cells',v_bsc_cells,'source_row_html',v_bsc_html
    );
    v_bsc_response:=jsonb_build_object(
        'success',true,'data',jsonb_build_object('total_pages',1,'html',v_bsc_html)
    );
    v_bsc_payload:=jsonb_build_object(
        'request_url','https://www.bsc.com.vn/wp-admin/admin-ajax.php',
        'source_page_url','https://www.bsc.com.vn/en/historical-data/?mck=P2BSCFIX',
        'request',jsonb_build_object(
            'action','filter_du_lieu_lich_su','mck','P2BSCFIX',
            'fromdate','2100-03-10','todate','2100-03-10',
            'type_form','history','page','1','items_per_page','20'
        ),
        'validation',jsonb_build_object(
            'vndirect_landing_id',v_vndirect_landing_id::text,
            'vndirect_source_row','0','vndirect_payload_sha256',v_vndirect_hash
        ),
        'response',v_bsc_response,'rows',jsonb_build_array(v_bsc_row)
    );
    v_bsc_bytes:=convert_to(v_bsc_response::text,'UTF8');
    v_bsc_hash:=encode(sha256(v_bsc_bytes),'hex');
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        v_ingest,'bsc','historical_data_ajax',v_fetched,'P2BSCFIX',
        v_bsc_payload,v_bsc_hash,v_bsc_bytes
    ) RETURNING landing_id INTO v_bsc_landing_id;

    v_materialized:=core.materialize_bsc_daily_price_limits(
        DATE '2100-03-10',DATE '2100-03-10',ARRAY[v_symbol_id]
    );
    IF v_materialized<>1 OR core.materialize_bsc_daily_price_limits(
        DATE '2100-03-10',DATE '2100-03-10',ARRAY[v_symbol_id]
    )<>0 THEN
        RAISE EXCEPTION 'BSC materialization must insert once and replay idempotently';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM core.phase2_execution_limit_evidence_for_day(
            v_symbol_id,DATE '2100-03-10'
        ) e
         WHERE e.symbol_id=v_symbol_id AND e.trade_date=DATE '2100-03-10'
           AND e.source='bsc' AND e.limit_up=110 AND e.limit_down=90
           AND e.evidence_landing_id=v_bsc_landing_id AND e.bar_landing_id=v_vndirect_landing_id
    ) THEN
        RAISE EXCEPTION 'exact BSC fallback evidence is missing or is not linked to its VNDIRECT bar';
    END IF;

    v_hash_after:=ops.phase2_label_target_chunk_input_hash(
        DATE '2100-03-09',DATE '2100-03-09'
    );
    IF v_hash_before IS NOT DISTINCT FROM v_hash_after THEN
        RAISE EXCEPTION 'adding BSC label evidence did not invalidate the label input hash';
    END IF;

    v_weight:=feat.phase2_exact_execution_weight(
        v_symbol_id,DATE '2100-03-10',DATE '2100-03-16'
    );
    IF v_weight IS DISTINCT FROM 1::double precision THEN
        RAISE EXCEPTION 'scalar execution weight did not admit exact BSC fallback evidence';
    END IF;
    v_batch_rows:=feat.refresh_phase2_execution_weights(
        DATE '2100-03-09',DATE '2100-03-12',DATE '2100-03-10',ARRAY[v_symbol_id]
    );
    IF v_batch_rows<>1 OR NOT EXISTS (
        SELECT 1 FROM feat.phase2_label_targets_v3 t
         WHERE t.symbol_id=v_symbol_id AND t.signal_date=DATE '2100-03-09'
           AND t.execution_weight=1
    ) OR EXISTS (
        SELECT 1 FROM feat.phase2_label_targets_v3 t
         WHERE t.symbol_id=v_symbol_id AND t.signal_date=DATE '2100-03-12'
           AND t.execution_weight IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'batched execution weight differs from the scalar BSC fallback result';
    END IF;

    -- A malformed BSC close must be rejected even if the row's own HTML and
    -- source-reported ceiling/floor values agree with its normalized payload.
    v_bad_html:='<tr><td>10/03/2100</td><td>105,001</td><td>1,000</td><td>1,000</td><td>105</td><td>0</td><td>0</td><td>104,000</td><td>110,000</td><td>90,000</td></tr>';
    v_bad_cells:=jsonb_build_array('10/03/2100','105,001','1,000','1,000','105','0','0','104,000','110,000','90,000');
    v_bad_row:=jsonb_set(v_bsc_row,'{close_price_vnd}','"105001"'::jsonb);
    v_bad_row:=jsonb_set(v_bad_row,'{source_cells}',v_bad_cells);
    v_bad_row:=jsonb_set(v_bad_row,'{source_row_html}',to_jsonb(v_bad_html));
    v_bad_response:=jsonb_build_object(
        'success',true,'data',jsonb_build_object('total_pages',1,'html',v_bad_html)
    );
    v_bad_payload:=jsonb_set(v_bsc_payload,'{response}',v_bad_response);
    v_bad_payload:=jsonb_set(v_bad_payload,'{rows}',jsonb_build_array(v_bad_row));
    v_bad_bytes:=convert_to(v_bad_response::text,'UTF8');
    v_bad_hash:=encode(sha256(v_bad_bytes),'hex');
    INSERT INTO raw.landings(
        ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes
    ) VALUES(
        v_ingest,'bsc','historical_data_ajax',v_fetched,'P2BSCFIX',
        v_bad_payload,v_bad_hash,v_bad_bytes
    ) RETURNING landing_id INTO v_bad_close_landing_id;
    v_failed:=false;
    v_error:=NULL;
    BEGIN
        INSERT INTO core.daily_price_limit_observations(
            symbol_id,source,trade_date,limit_up,limit_down,available_at,fetched_at,
            raw_landing_id,source_row,row_payload
        ) VALUES(
            v_symbol_id,'bsc',DATE '2100-03-10',110,90,v_fetched,v_fetched,
            v_bad_close_landing_id,0,v_bad_row
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
        v_failed:=v_error='BSC close/matched volume does not exactly reconcile to its VNDIRECT raw bar row';
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'BSC close that differs from the exact VNDIRECT bar was not rejected';
    END IF;

    -- An invalid but existing VNDIRECT observation blocks fallback. The test
    -- temporarily disables only its lineage trigger to model corrupted legacy
    -- evidence; normal inserts are separately checked above.
    v_failed:=false;
    v_error:=NULL;
    BEGIN
        INSERT INTO core.daily_price_limit_observations(
            symbol_id,source,trade_date,limit_up,limit_down,available_at,fetched_at,
            raw_landing_id,source_row,row_payload
        ) VALUES(
            v_symbol_id,'vndirect',DATE '2100-03-10',110,90,v_fetched,v_fetched,
            v_vndirect_landing_id,0,v_bar_rows->0
        );
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
        v_failed:=v_error='VNDIRECT price-limit values must equal the archived source row';
    END;
    IF NOT v_failed THEN
        RAISE EXCEPTION 'divergent VNDIRECT limit values were not rejected';
    END IF;

    ALTER TABLE core.daily_price_limit_observations
        DISABLE TRIGGER daily_price_limit_observations_verify_lineage;
    INSERT INTO core.daily_price_limit_observations(
        symbol_id,source,trade_date,limit_up,limit_down,available_at,fetched_at,
        raw_landing_id,source_row,row_payload
    ) VALUES(
        v_symbol_id,'vndirect',DATE '2100-03-10',110,90,v_fetched,v_fetched,
        v_vndirect_landing_id,0,v_bar_rows->0
    );
    ALTER TABLE core.daily_price_limit_observations
        ENABLE TRIGGER daily_price_limit_observations_verify_lineage;

    IF EXISTS (
        SELECT 1 FROM core.phase2_execution_limit_evidence_for_day(
            v_symbol_id,DATE '2100-03-10'
        ) e
    ) OR feat.phase2_exact_execution_weight(
        v_symbol_id,DATE '2100-03-10',DATE '2100-03-16'
    ) IS NOT NULL THEN
        RAISE EXCEPTION 'BSC fallback was used despite an existing divergent VNDIRECT observation';
    END IF;
    v_batch_rows:=feat.refresh_phase2_execution_weights(
        DATE '2100-03-09',DATE '2100-03-12',DATE '2100-03-10',ARRAY[v_symbol_id]
    );
    IF v_batch_rows<>1 OR EXISTS (
        SELECT 1 FROM feat.phase2_label_targets_v3 t
         WHERE t.symbol_id=v_symbol_id AND t.signal_date=DATE '2100-03-09'
           AND t.execution_weight IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'batched weight did not preserve NULL when direct evidence conflicts';
    END IF;
END;
$phase2_bsc_price_limits_fixture$;

ROLLBACK;

-- Synthetic source-backed observations, only for the fixed test symbols.
CREATE OR REPLACE FUNCTION pg_temp.synthetic_industry_observation(p_industry text,p_at timestamptz)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE body jsonb; lid bigint;
BEGIN
 SELECT jsonb_build_object('rows',jsonb_agg(jsonb_build_object('symbol',symbol,'exchange','HOSE','icb_lv2',p_industry) ORDER BY symbol))
 INTO body FROM core.symbols WHERE symbol IN ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE');
 INSERT INTO raw.landings(ingest_id,source,route,fetched_at,symbol,payload,payload_sha256,payload_bytes)
 VALUES(gen_random_uuid(),'vci','equity_list',p_at,NULL,body,encode(sha256(convert_to(body::text,'UTF8')),'hex'),convert_to(body::text,'UTF8')) RETURNING landing_id INTO lid;
 INSERT INTO core.security_master(symbol,first_observed_at,last_observed_at)
 SELECT symbol,p_at,p_at FROM core.symbols WHERE symbol IN ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE') ON CONFLICT(symbol) DO NOTHING;
 INSERT INTO core.security_observations(security_id,landing_id,provider_row_index,observed_on,observed_at,source,category,exchange,icb_lv2)
 SELECT m.security_id,lid,(row_number() OVER(ORDER BY m.symbol)-1)::integer,(p_at AT TIME ZONE 'Asia/Ho_Chi_Minh')::date,p_at,'vci','EXCHANGE_LISTED','HOSE',p_industry
 FROM core.security_master m WHERE m.symbol IN ('P2READY','P2ZERO','P2ENTRY','P2EXIT','P2MISS','P2EPISODE');
END $$;

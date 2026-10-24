-- Separate, point-in-time fundamental overlay matrix.
-- No source identifiers are pre-seeded: exact row IDs and units must be
-- verified from an archived provider frame before a mapping can be activated.
BEGIN;

CREATE TABLE IF NOT EXISTS feat.fundamental_industry_class_map (
    industry text PRIMARY KEY CHECK (industry <> ''),
    industry_class text NOT NULL CHECK (industry_class IN ('BANK','OTHER')),
    mapping_version text NOT NULL CHECK (mapping_version <> '')
);

CREATE TABLE IF NOT EXISTS feat.fundamental_line_item_map (
    source text NOT NULL CHECK (source='vci'),
    statement_type text NOT NULL CHECK (statement_type IN ('income_statement','balance_sheet','cash_flow')),
    row_id text NOT NULL CHECK (row_id <> ''),
    source_unit text,
    value_multiplier numeric NOT NULL CHECK (value_multiplier > 0),
    feature_key text NOT NULL CHECK (feature_key IN (
        'revenue','gross_profit','operating_profit','net_profit',
        'total_assets','total_liabilities','equity','operating_cash_flow',
        'bank_interest_income','bank_interest_expense','bank_net_interest_income',
        'bank_net_profit','bank_total_assets','bank_equity')),
    mapping_scope text NOT NULL CHECK (mapping_scope IN ('ALL','BANK')),
    mapping_version text NOT NULL CHECK (mapping_version <> ''),
    active boolean NOT NULL DEFAULT true,
    PRIMARY KEY(source,statement_type,row_id,mapping_scope,mapping_version),
    CHECK (
       (feature_key IN ('revenue','gross_profit','operating_profit','net_profit','bank_interest_income','bank_interest_expense','bank_net_interest_income','bank_net_profit') AND statement_type='income_statement') OR
       (feature_key IN ('total_assets','total_liabilities','equity','bank_total_assets','bank_equity') AND statement_type='balance_sheet') OR
       (feature_key='operating_cash_flow' AND statement_type='cash_flow')
    )
);
CREATE UNIQUE INDEX IF NOT EXISTS fundamental_line_item_one_active_mapping
    ON feat.fundamental_line_item_map(source,feature_key,mapping_scope)
    WHERE active;

CREATE TABLE IF NOT EXISTS feat.fundamental_features_daily (
    symbol_id bigint NOT NULL REFERENCES core.symbols(symbol_id),
    trade_date date NOT NULL,
    feature_version text NOT NULL DEFAULT 'fundamental-overlay-v1',
    mapping_hash text NOT NULL CHECK (mapping_hash ~ '^[0-9a-f]{64}$'),
    source text NOT NULL CHECK (source='vci'),
    industry text,
    latest_quarter_end date,
    pit_quarter_count smallint NOT NULL CHECK (pit_quarter_count >= 0),
    latest_pit_available_at timestamptz,
    listed_share_observation_id bigint REFERENCES core.listed_share_observations(observation_id),
    listed_shares_date date,
    listed_shares numeric(24,0),
    price_landing_id bigint REFERENCES raw.landings(landing_id),
    price_source_row integer,
    price_close_thousand_vnd numeric,
    pit_snapshot_ids bigint[] NOT NULL DEFAULT '{}',
    raw_landing_ids bigint[] NOT NULL DEFAULT '{}',
    ttm_revenue numeric,
    ttm_gross_profit numeric,
    ttm_operating_profit numeric,
    ttm_net_profit numeric,
    ttm_operating_cash_flow numeric,
    gross_margin_ttm numeric,
    operating_margin_ttm numeric,
    net_margin_ttm numeric,
    roe_ttm numeric,
    roa_ttm numeric,
    revenue_yoy_growth numeric,
    revenue_sequential_growth numeric,
    revenue_growth_acceleration numeric,
    liabilities_to_equity numeric,
    accruals_to_average_assets numeric,
    pe_ratio numeric,
    pb_ratio numeric,
    bank_ttm_interest_income numeric,
    bank_ttm_interest_expense numeric,
    bank_ttm_net_interest_income numeric,
    bank_ttm_net_profit numeric,
    bank_total_assets numeric,
    bank_equity numeric,
    bank_roe_ttm numeric,
    bank_roa_ttm numeric,
    bank_net_interest_to_interest_income numeric,
    rank_industry_net_margin numeric,
    rank_industry_roe numeric,
    rank_industry_roa numeric,
    rank_industry_revenue_growth numeric,
    rank_industry_leverage numeric,
    rank_industry_pe numeric,
    rank_industry_pb numeric,
    built_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(symbol_id,trade_date,feature_version,mapping_hash),
    CHECK (listed_shares IS NULL OR listed_shares > 0),
    CHECK (price_source_row IS NULL OR price_source_row >= 0)
);
CREATE INDEX IF NOT EXISTS fundamental_features_date_version_idx
    ON feat.fundamental_features_daily(trade_date,feature_version);
CREATE INDEX IF NOT EXISTS fundamental_features_industry_idx
    ON feat.fundamental_features_daily(trade_date,industry,feature_version);
-- Resolve one version per statement line at each signal cutoff without sorting
-- every historical version for every signal date.
CREATE INDEX IF NOT EXISTS fundamentals_pit_overlay_version_lookup
    ON core.fundamentals_pit(
        symbol_id,source,statement_type,period_type,period_end,row_id,
        available_at DESC,first_seen_at DESC,snapshot_id DESC)
    INCLUDE (unit,value,raw_landing_id)
    WHERE archive_managed;

CREATE OR REPLACE FUNCTION feat.build_fundamental_features(p_date_from date,p_date_to date)
RETURNS bigint
LANGUAGE plpgsql
AS $build_fundamental_features$
DECLARE
    affected bigint;
    v_mapping_hash text;
BEGIN
    IF p_date_from IS NULL OR p_date_to IS NULL OR p_date_from>p_date_to THEN
        RAISE EXCEPTION 'valid inclusive date range required';
    END IF;

    SELECT md5(definition)||md5('VN-Signal:'||definition) INTO v_mapping_hash
      FROM (SELECT coalesce((SELECT string_agg(source||'|'||statement_type||'|'||row_id||'|'||
                                      coalesce(source_unit,'<NULL>')||'|'||value_multiplier::text||'|'||
                                      feature_key||'|'||mapping_scope||'|'||mapping_version,';' ORDER BY
                                      source,statement_type,row_id,mapping_scope,mapping_version)
                               FROM feat.fundamental_line_item_map WHERE active),'') ||
                   '|industry='||coalesce((SELECT string_agg(industry||'|'||industry_class||'|'||mapping_version,';' ORDER BY industry)
                                             FROM feat.fundamental_industry_class_map),'') AS definition) x;

    DELETE FROM feat.fundamental_features_daily
     WHERE trade_date BETWEEN p_date_from AND p_date_to
       AND feature_version='fundamental-overlay-v1';

    WITH signal_base AS (
        SELECT DISTINCT f.symbol_id,f.trade_date,
               (f.trade_date::timestamp + time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh' AS as_of_at,
               ind.industry,
               px.model_c::numeric AS price_close_thousand_vnd,
               px.landing_id AS price_landing_id,px.source_row AS price_source_row
          FROM feat.features_daily f
          LEFT JOIN LATERAL (
              SELECT l.industry FROM core.listing_snapshots l
               WHERE l.symbol_id=f.symbol_id AND l.snapshot_date<=f.trade_date
               ORDER BY l.snapshot_date DESC LIMIT 1
          ) ind ON true
          LEFT JOIN core.vndirect_reference_adjustment_details px
            ON px.symbol_id=f.symbol_id AND px.trade_date=f.trade_date AND px.source='vndirect'
         WHERE f.feature_version='phase2-v2'
           AND f.trade_date BETWEEN p_date_from AND p_date_to
           AND EXISTS (
               SELECT 1 FROM core.fundamentals_pit p
                WHERE p.symbol_id=f.symbol_id AND p.archive_managed
                  AND p.source='vci' AND p.available_at<=((f.trade_date::timestamp + time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')
                  AND p.period_end<=f.trade_date
           )
    ),
    shares AS (
        SELECT s.*,
               sh.observation_id AS share_observation_id,
               sh.trade_date AS listed_shares_date,
               sh.listed_shares,
               sh.raw_landing_id AS shares_landing_id
          FROM signal_base s
          LEFT JOIN LATERAL (
              SELECT o.observation_id,o.trade_date,o.listed_shares,o.raw_landing_id
                FROM core.listed_share_observations o
               WHERE o.symbol_id=s.symbol_id AND o.trade_date<=s.trade_date
                 AND o.available_at<=s.as_of_at
               ORDER BY o.available_at DESC,o.trade_date DESC,o.observation_id DESC
               LIMIT 1
          ) sh ON true
    ),
    range_baselines AS (
        SELECT DISTINCT ON(symbol_id) symbol_id,trade_date
          FROM signal_base
         ORDER BY symbol_id,trade_date
    ),
    pit_event_dates AS MATERIALIZED (
        SELECT symbol_id,trade_date FROM range_baselines
        UNION
        SELECT DISTINCT p.symbol_id,eligible.trade_date
          FROM core.fundamentals_pit p
          JOIN LATERAL (
              SELECT f.trade_date
                FROM feat.features_daily f
               WHERE f.symbol_id=p.symbol_id AND f.feature_version='phase2-v2'
                 AND f.trade_date BETWEEN p_date_from AND p_date_to
                 AND p.period_end<=f.trade_date
                 AND p.available_at<=((f.trade_date::timestamp + time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh')
               ORDER BY f.trade_date
               LIMIT 1
          ) eligible ON true
         WHERE p.archive_managed AND p.source='vci'
    ),
    pit_signals AS (
        SELECT symbol_id,trade_date,
               (trade_date::timestamp + time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh' AS as_of_at
          FROM pit_event_dates
    ),
    pit_keys AS MATERIALIZED (
        SELECT DISTINCT symbol_id,source,statement_type,period_type,period_end,row_id
          FROM core.fundamentals_pit
         WHERE archive_managed AND source='vci'
    ),
    pit AS (
        SELECT s.symbol_id,s.trade_date,s.as_of_at,
               p.snapshot_id,p.raw_landing_id,p.source,p.statement_type,
               p.period_type,p.period_end,p.row_id,p.unit,p.value,
               p.available_at,p.first_seen_at
          FROM pit_signals s
          JOIN pit_keys k
            ON k.symbol_id=s.symbol_id AND k.period_end<=s.trade_date
          CROSS JOIN LATERAL (
              SELECT v.snapshot_id,v.raw_landing_id,v.source,v.statement_type,
                     v.period_type,v.period_end,v.row_id,v.unit,v.value,
                     v.available_at,v.first_seen_at
                FROM core.fundamentals_pit v
               WHERE v.archive_managed
                 AND v.symbol_id=k.symbol_id AND v.source=k.source
                 AND v.statement_type=k.statement_type AND v.period_type=k.period_type
                 AND v.period_end=k.period_end AND v.row_id=k.row_id
                 AND v.available_at<=s.as_of_at
               ORDER BY v.available_at DESC,v.first_seen_at DESC,v.snapshot_id DESC
               LIMIT 1
          ) p
    ),
    bank_status AS (
        SELECT i.industry, i.industry_class
          FROM feat.fundamental_industry_class_map i
    ),
    mapped AS (
        SELECT p.symbol_id,p.trade_date,p.period_type,p.period_end,p.snapshot_id,p.raw_landing_id,
               p.available_at,m.feature_key,m.mapping_scope,
               p.value*m.value_multiplier AS value
          FROM pit p
          JOIN feat.fundamental_line_item_map m
            ON m.active AND m.source=p.source AND m.statement_type=p.statement_type
           AND m.row_id=p.row_id AND m.source_unit IS NOT DISTINCT FROM p.unit
         WHERE m.mapping_scope IN ('ALL','BANK')
    ),
    periods AS (
        SELECT symbol_id,trade_date,period_type,period_end,
               max(value) FILTER(WHERE feature_key='revenue') AS revenue,
               max(value) FILTER(WHERE feature_key='gross_profit') AS gross_profit,
               max(value) FILTER(WHERE feature_key='operating_profit') AS operating_profit,
               max(value) FILTER(WHERE feature_key='net_profit') AS net_profit,
               max(value) FILTER(WHERE feature_key='total_assets') AS total_assets,
               max(value) FILTER(WHERE feature_key='total_liabilities') AS total_liabilities,
               max(value) FILTER(WHERE feature_key='equity') AS equity,
               max(value) FILTER(WHERE feature_key='operating_cash_flow') AS operating_cash_flow,
               max(value) FILTER(WHERE feature_key='bank_interest_income') AS bank_interest_income,
               max(value) FILTER(WHERE feature_key='bank_interest_expense') AS bank_interest_expense,
               max(value) FILTER(WHERE feature_key='bank_net_interest_income') AS bank_net_interest_income,
               max(value) FILTER(WHERE feature_key='bank_net_profit') AS bank_net_profit,
               max(value) FILTER(WHERE feature_key='bank_total_assets') AS bank_total_assets,
               max(value) FILTER(WHERE feature_key='bank_equity') AS bank_equity
          FROM mapped
         GROUP BY symbol_id,trade_date,period_type,period_end
    ),
    quarter_raw AS (
        SELECT * FROM periods WHERE period_type='quarter'
    ),
    quarter_windows AS (
        SELECT q.*,
               count(*) OVER w4 AS periods4,
               min(period_end) OVER w4 AS first_end4,
               count(revenue) OVER w4 AS revenue_count4,
               count(gross_profit) OVER w4 AS gross_count4,
               count(operating_profit) OVER w4 AS operating_count4,
               count(net_profit) OVER w4 AS profit_count4,
               count(operating_cash_flow) OVER w4 AS cash_flow_count4,
               sum(revenue) OVER w4 AS revenue_sum4,
               sum(gross_profit) OVER w4 AS gross_sum4,
               sum(operating_profit) OVER w4 AS operating_sum4,
               sum(net_profit) OVER w4 AS profit_sum4,
               sum(operating_cash_flow) OVER w4 AS cash_flow_sum4,
               sum(bank_interest_income) OVER w4 AS bank_interest_income_sum4,
               sum(bank_interest_expense) OVER w4 AS bank_interest_expense_sum4,
               sum(bank_net_interest_income) OVER w4 AS bank_nii_sum4,
               sum(bank_net_profit) OVER w4 AS bank_net_profit_sum4,
               count(bank_interest_income) OVER w4 AS bank_interest_income_count4,
               count(bank_interest_expense) OVER w4 AS bank_interest_expense_count4,
               count(bank_net_interest_income) OVER w4 AS bank_nii_count4,
               count(bank_net_profit) OVER w4 AS bank_net_profit_count4,
               lag(revenue) OVER w1 AS revenue_prev,
               lag(period_end) OVER w1 AS period_prev,
               lag(period_end,3) OVER w1 AS period_4back
          FROM quarter_raw q
          WINDOW w1 AS (PARTITION BY symbol_id,trade_date ORDER BY period_end),
                 w4 AS (PARTITION BY symbol_id,trade_date ORDER BY period_end ROWS BETWEEN 3 PRECEDING AND CURRENT ROW)
    ),
    quarter_ttm AS (
        SELECT q.*,
               (periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3) AS four_consecutive,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND revenue_count4=4 THEN revenue_sum4 END AS ttm_revenue,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND gross_count4=4 THEN gross_sum4 END AS ttm_gross_profit,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND operating_count4=4 THEN operating_sum4 END AS ttm_operating_profit,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND profit_count4=4 THEN profit_sum4 END AS ttm_net_profit,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND cash_flow_count4=4 THEN cash_flow_sum4 END AS ttm_operating_cash_flow,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND bank_interest_income_count4=4 THEN bank_interest_income_sum4 END AS bank_ttm_interest_income,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND bank_interest_expense_count4=4 THEN bank_interest_expense_sum4 END AS bank_ttm_interest_expense,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND bank_nii_count4=4 THEN bank_nii_sum4 END AS bank_ttm_net_interest_income,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND bank_net_profit_count4=4 THEN bank_net_profit_sum4 END AS bank_ttm_net_profit
          FROM quarter_windows q
    ),
    quarter_growth AS (
        SELECT q.*,
               lag(ttm_revenue,4) OVER (PARTITION BY symbol_id,trade_date ORDER BY period_end) AS ttm_revenue_year_ago,
               lag(ttm_revenue,5) OVER (PARTITION BY symbol_id,trade_date ORDER BY period_end) AS ttm_revenue_year_ago_prior_q,
               lag(ttm_revenue,1) OVER (PARTITION BY symbol_id,trade_date ORDER BY period_end) AS ttm_revenue_prior_q
          FROM quarter_ttm q
    ),
    quarter_latest AS (
        SELECT DISTINCT ON(symbol_id,trade_date)
               symbol_id,trade_date,period_end,ttm_revenue,ttm_gross_profit,ttm_operating_profit,
               ttm_net_profit,ttm_operating_cash_flow,bank_ttm_interest_income,
               bank_ttm_interest_expense,bank_ttm_net_interest_income,bank_ttm_net_profit,
               CASE WHEN revenue IS NOT NULL AND revenue_prev>0
                     AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_prev)::integer*4+extract(quarter FROM period_prev)::integer)=1
                    THEN revenue/revenue_prev-1 END AS revenue_sequential_growth,
               CASE WHEN ttm_revenue>0 AND ttm_revenue_year_ago>0 THEN ttm_revenue/ttm_revenue_year_ago-1 END AS revenue_yoy_growth,
               CASE WHEN ttm_revenue>0 AND ttm_revenue_year_ago>0 AND ttm_revenue_year_ago_prior_q>0
                    THEN (ttm_revenue/ttm_revenue_year_ago-1) -
                         (ttm_revenue_prior_q/ttm_revenue_year_ago_prior_q-1) END AS revenue_growth_acceleration
          FROM quarter_growth
         ORDER BY symbol_id,trade_date,period_end DESC
    ),
    balance_ranked AS (
        SELECT DISTINCT ON(symbol_id,trade_date,period_end)
               symbol_id,trade_date,period_end,total_assets,total_liabilities,equity,
               bank_net_profit,bank_total_assets,bank_equity
          FROM periods
         ORDER BY symbol_id,trade_date,period_end DESC,(period_type='quarter') DESC
    ),
    balance_latest AS (
        SELECT DISTINCT ON(symbol_id,trade_date) * FROM balance_ranked
         ORDER BY symbol_id,trade_date,period_end DESC
    ),
    balance_prior AS (
        SELECT b.symbol_id,b.trade_date,b.total_assets,b.equity,b.bank_total_assets,b.bank_equity
          FROM balance_ranked b JOIN balance_latest cur USING(symbol_id,trade_date)
         WHERE b.period_end=(cur.period_end-interval '1 year')::date
    ),
    lineage_periods AS (
        SELECT DISTINCT symbol_id,trade_date,period_type,period_end
          FROM mapped
    ),
    lineage_period_ranked AS (
        SELECT p.*,
               row_number() OVER (PARTITION BY symbol_id,trade_date,period_type ORDER BY period_end DESC) AS period_no
          FROM lineage_periods p
    ),
    lineage_summary AS (
        SELECT m.symbol_id,m.trade_date,
               max(m.available_at) AS latest_pit_available_at,
               array_agg(DISTINCT m.snapshot_id ORDER BY m.snapshot_id) AS snapshot_ids,
               array_agg(DISTINCT m.raw_landing_id ORDER BY m.raw_landing_id) AS landing_ids
          FROM mapped m
          JOIN lineage_period_ranked r
            ON r.symbol_id=m.symbol_id AND r.trade_date=m.trade_date
           AND r.period_type=m.period_type AND r.period_end=m.period_end
         WHERE (r.period_type='quarter' AND r.period_no<=9)
            OR (r.period_type='year' AND r.period_no<=2)
         GROUP BY m.symbol_id,m.trade_date
    ),
    pit_counts AS (
        SELECT symbol_id,trade_date,
               count(DISTINCT period_end) FILTER(WHERE statement_type='income_statement' AND period_type='quarter')::smallint AS pit_quarter_count
          FROM pit GROUP BY symbol_id,trade_date
    ),
    financial_snapshots AS (
        SELECT e.symbol_id,e.trade_date AS snapshot_date,q.period_end AS latest_quarter_end,
               coalesce(pc.pit_quarter_count,0) AS pit_quarter_count,ls.latest_pit_available_at,
               coalesce(ls.snapshot_ids,'{}'::bigint[]) AS pit_snapshot_ids,
               coalesce(ls.landing_ids,'{}'::bigint[]) AS pit_landing_ids,
               q.ttm_revenue,q.ttm_gross_profit,q.ttm_operating_profit,q.ttm_net_profit,q.ttm_operating_cash_flow,
               CASE WHEN q.ttm_revenue>0 THEN q.ttm_gross_profit/q.ttm_revenue END AS gross_margin_ttm,
               CASE WHEN q.ttm_revenue>0 THEN q.ttm_operating_profit/q.ttm_revenue END AS operating_margin_ttm,
               CASE WHEN q.ttm_revenue>0 THEN q.ttm_net_profit/q.ttm_revenue END AS net_margin_ttm,
               CASE WHEN b.equity>0 AND bp.equity>0 AND q.ttm_net_profit IS NOT NULL
                    THEN q.ttm_net_profit/((b.equity+bp.equity)/2) END AS roe_ttm,
               CASE WHEN b.total_assets>0 AND bp.total_assets>0 AND q.ttm_net_profit IS NOT NULL
                    THEN q.ttm_net_profit/((b.total_assets+bp.total_assets)/2) END AS roa_ttm,
               q.revenue_yoy_growth,q.revenue_sequential_growth,q.revenue_growth_acceleration,
               CASE WHEN b.equity>0 AND b.total_liabilities IS NOT NULL THEN b.total_liabilities/b.equity END AS liabilities_to_equity,
               CASE WHEN b.total_assets>0 AND bp.total_assets>0 AND q.ttm_net_profit IS NOT NULL AND q.ttm_operating_cash_flow IS NOT NULL
                    THEN (q.ttm_net_profit-q.ttm_operating_cash_flow)/((b.total_assets+bp.total_assets)/2) END AS accruals_to_average_assets,
               b.equity AS current_equity,
               q.bank_ttm_interest_income,q.bank_ttm_interest_expense,q.bank_ttm_net_interest_income,
               q.bank_ttm_net_profit,b.bank_total_assets,b.bank_equity,
               CASE WHEN b.bank_equity>0 AND bp.bank_equity>0 AND q.bank_ttm_net_profit IS NOT NULL
                    THEN q.bank_ttm_net_profit/((b.bank_equity+bp.bank_equity)/2) END AS bank_roe_ttm,
               CASE WHEN b.bank_total_assets>0 AND bp.bank_total_assets>0 AND q.bank_ttm_net_profit IS NOT NULL
                    THEN q.bank_ttm_net_profit/((b.bank_total_assets+bp.bank_total_assets)/2) END AS bank_roa_ttm,
               CASE WHEN q.bank_ttm_interest_income>0 AND q.bank_ttm_net_interest_income IS NOT NULL
                    THEN q.bank_ttm_net_interest_income/q.bank_ttm_interest_income END AS bank_net_interest_to_interest_income
          FROM pit_signals e
          LEFT JOIN quarter_latest q USING(symbol_id,trade_date)
          LEFT JOIN balance_latest b USING(symbol_id,trade_date)
          LEFT JOIN balance_prior bp USING(symbol_id,trade_date)
          LEFT JOIN pit_counts pc USING(symbol_id,trade_date)
          LEFT JOIN lineage_summary ls USING(symbol_id,trade_date)
    ),
    assembled AS (
        SELECT s.symbol_id,s.trade_date,s.industry,f.latest_quarter_end,
               coalesce(f.pit_quarter_count,0) AS pit_quarter_count,f.latest_pit_available_at,
               s.share_observation_id,s.listed_shares_date,s.listed_shares,
               s.price_landing_id,s.price_source_row,s.price_close_thousand_vnd,
               coalesce(f.pit_snapshot_ids,'{}'::bigint[]) AS pit_snapshot_ids,
               coalesce(f.pit_landing_ids,'{}'::bigint[]) ||
                 CASE WHEN s.shares_landing_id IS NOT NULL THEN ARRAY[s.shares_landing_id] ELSE '{}'::bigint[] END AS raw_landing_ids,
               f.ttm_revenue,f.ttm_gross_profit,f.ttm_operating_profit,f.ttm_net_profit,f.ttm_operating_cash_flow,
               f.gross_margin_ttm,f.operating_margin_ttm,f.net_margin_ttm,f.roe_ttm,f.roa_ttm,
               f.revenue_yoy_growth,f.revenue_sequential_growth,f.revenue_growth_acceleration,
               f.liabilities_to_equity,f.accruals_to_average_assets,
               CASE WHEN s.price_close_thousand_vnd>0 AND s.listed_shares>0 AND f.ttm_net_profit>0
                    THEN s.price_close_thousand_vnd*1000*s.listed_shares/f.ttm_net_profit END AS pe_ratio,
               CASE WHEN s.price_close_thousand_vnd>0 AND s.listed_shares>0 AND f.current_equity>0
                    THEN s.price_close_thousand_vnd*1000*s.listed_shares/f.current_equity END AS pb_ratio,
               CASE WHEN b.industry_class='BANK' THEN f.bank_ttm_interest_income END AS bank_ttm_interest_income,
               CASE WHEN b.industry_class='BANK' THEN f.bank_ttm_interest_expense END AS bank_ttm_interest_expense,
               CASE WHEN b.industry_class='BANK' THEN f.bank_ttm_net_interest_income END AS bank_ttm_net_interest_income,
               CASE WHEN b.industry_class='BANK' THEN f.bank_ttm_net_profit END AS bank_ttm_net_profit,
               CASE WHEN b.industry_class='BANK' THEN f.bank_total_assets END AS bank_total_assets,
               CASE WHEN b.industry_class='BANK' THEN f.bank_equity END AS bank_equity,
               CASE WHEN b.industry_class='BANK' THEN f.bank_roe_ttm END AS bank_roe_ttm,
               CASE WHEN b.industry_class='BANK' THEN f.bank_roa_ttm END AS bank_roa_ttm,
               CASE WHEN b.industry_class='BANK' THEN f.bank_net_interest_to_interest_income END AS bank_net_interest_to_interest_income
          FROM shares s
          LEFT JOIN LATERAL (
              SELECT fs.* FROM financial_snapshots fs
               WHERE fs.symbol_id=s.symbol_id AND fs.snapshot_date<=s.trade_date
               ORDER BY fs.snapshot_date DESC LIMIT 1
          ) f ON true
          LEFT JOIN bank_status b ON b.industry=s.industry
    ),
    ranked AS (
        SELECT a.*,
               CASE WHEN count(net_margin_ttm) OVER (PARTITION BY trade_date,industry)>=5 AND net_margin_ttm IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY net_margin_ttm)-1)::numeric /
                         nullif(count(net_margin_ttm) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_net_margin,
               CASE WHEN count(roe_ttm) OVER (PARTITION BY trade_date,industry)>=5 AND roe_ttm IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY roe_ttm)-1)::numeric /
                         nullif(count(roe_ttm) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_roe,
               CASE WHEN count(roa_ttm) OVER (PARTITION BY trade_date,industry)>=5 AND roa_ttm IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY roa_ttm)-1)::numeric /
                         nullif(count(roa_ttm) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_roa,
               CASE WHEN count(revenue_yoy_growth) OVER (PARTITION BY trade_date,industry)>=5 AND revenue_yoy_growth IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY revenue_yoy_growth)-1)::numeric /
                         nullif(count(revenue_yoy_growth) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_revenue_growth,
               CASE WHEN count(liabilities_to_equity) OVER (PARTITION BY trade_date,industry)>=5 AND liabilities_to_equity IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY liabilities_to_equity)-1)::numeric /
                         nullif(count(liabilities_to_equity) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_leverage,
               CASE WHEN count(pe_ratio) OVER (PARTITION BY trade_date,industry)>=5 AND pe_ratio IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY pe_ratio)-1)::numeric /
                         nullif(count(pe_ratio) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_pe,
               CASE WHEN count(pb_ratio) OVER (PARTITION BY trade_date,industry)>=5 AND pb_ratio IS NOT NULL
                    THEN (rank() OVER (PARTITION BY trade_date,industry ORDER BY pb_ratio)-1)::numeric /
                         nullif(count(pb_ratio) OVER (PARTITION BY trade_date,industry)-1,0) END AS rank_industry_pb
          FROM assembled a
    )
    INSERT INTO feat.fundamental_features_daily(
        symbol_id,trade_date,mapping_hash,source,industry,latest_quarter_end,pit_quarter_count,
        latest_pit_available_at,listed_share_observation_id,listed_shares_date,listed_shares,
        price_landing_id,price_source_row,price_close_thousand_vnd,pit_snapshot_ids,raw_landing_ids,
        ttm_revenue,ttm_gross_profit,ttm_operating_profit,ttm_net_profit,ttm_operating_cash_flow,
        gross_margin_ttm,operating_margin_ttm,net_margin_ttm,roe_ttm,roa_ttm,
        revenue_yoy_growth,revenue_sequential_growth,revenue_growth_acceleration,
        liabilities_to_equity,accruals_to_average_assets,pe_ratio,pb_ratio,
        bank_ttm_interest_income,bank_ttm_interest_expense,bank_ttm_net_interest_income,bank_ttm_net_profit,
        bank_total_assets,bank_equity,bank_roe_ttm,bank_roa_ttm,bank_net_interest_to_interest_income,
        rank_industry_net_margin,rank_industry_roe,rank_industry_roa,rank_industry_revenue_growth,
        rank_industry_leverage,rank_industry_pe,rank_industry_pb)
    SELECT symbol_id,trade_date,v_mapping_hash,'vci',industry,latest_quarter_end,pit_quarter_count,
           latest_pit_available_at,share_observation_id,listed_shares_date,listed_shares,
           price_landing_id,price_source_row,price_close_thousand_vnd,pit_snapshot_ids,raw_landing_ids,
           ttm_revenue,ttm_gross_profit,ttm_operating_profit,ttm_net_profit,ttm_operating_cash_flow,
           gross_margin_ttm,operating_margin_ttm,net_margin_ttm,roe_ttm,roa_ttm,
           revenue_yoy_growth,revenue_sequential_growth,revenue_growth_acceleration,
           liabilities_to_equity,accruals_to_average_assets,pe_ratio,pb_ratio,
           bank_ttm_interest_income,bank_ttm_interest_expense,bank_ttm_net_interest_income,bank_ttm_net_profit,
           bank_total_assets,bank_equity,bank_roe_ttm,bank_roa_ttm,bank_net_interest_to_interest_income,
           rank_industry_net_margin,rank_industry_roe,rank_industry_roa,rank_industry_revenue_growth,
           rank_industry_leverage,rank_industry_pe,rank_industry_pb
      FROM ranked;

    GET DIAGNOSTICS affected=ROW_COUNT;
    RETURN affected;
END;
$build_fundamental_features$;

COMMENT ON TABLE feat.fundamental_line_item_map IS
    'Exact provider row IDs and units accepted by the separate PIT fundamentals overlay. Empty until exact identifiers are verified from a real immutable raw statement frame; no guessed mapping is enabled.';
COMMENT ON TABLE feat.fundamental_features_daily IS
    'Separate point-in-time fundamentals overlay matrix. Inputs are archive-managed statement versions with available_at no later than the local 15:00 signal cutoff, and the latest listed-share observation already available. NULL means a mapped source input or required formula operand is absent.';
COMMENT ON FUNCTION feat.build_fundamental_features(date,date) IS
    'Rebuild the separate PIT fundamentals overlay for price-feature symbol dates in an inclusive range. Each symbol receives an in-range baseline snapshot with all prior PIT rows available as of that date, then only first-eligible PIT version events are recomputed and carried forward to daily price/share rows. Eligibility uses the local 15:00 cutoff and period_end; latest-version ties order by available_at, first_seen_at, snapshot_id descending. Ratios require positive denominators; P/E and P/B use same-day VNDIRECT model close (thousand VND) and point-in-time listed shares. Industry ranks require at least five non-null peers.';

COMMIT;

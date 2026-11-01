BEGIN;
-- Listed ordinary shares represent the parent holders' claim. Consolidated
-- profit/equity remain inputs for group returns, never valuation fallbacks.
ALTER TABLE feat.fundamental_line_item_map
 DROP CONSTRAINT IF EXISTS fundamental_line_item_map_feature_key_check,
 DROP CONSTRAINT IF EXISTS fundamental_line_item_map_check;
ALTER TABLE feat.fundamental_line_item_map ADD CONSTRAINT fundamental_line_item_map_feature_key_check
 CHECK(feature_key IN ('revenue','gross_profit','operating_profit','net_profit',
 'total_assets','total_liabilities','equity','operating_cash_flow',
 'bank_interest_income','bank_interest_expense','bank_net_interest_income',
 'bank_net_profit','bank_total_assets','bank_equity','parent_net_profit','parent_equity'));
ALTER TABLE feat.fundamental_line_item_map ADD CONSTRAINT fundamental_line_item_map_check CHECK(
 (feature_key IN ('revenue','gross_profit','operating_profit','net_profit','bank_interest_income',
 'bank_interest_expense','bank_net_interest_income','bank_net_profit','parent_net_profit') AND statement_type='income_statement') OR
 (feature_key IN ('total_assets','total_liabilities','equity','bank_total_assets','bank_equity','parent_equity') AND statement_type='balance_sheet') OR
 (feature_key='operating_cash_flow' AND statement_type='cash_flow'));
ALTER TABLE feat.fundamental_features_daily
 ADD COLUMN IF NOT EXISTS ttm_parent_net_profit numeric,
 ADD COLUMN IF NOT EXISTS parent_equity numeric;
DO $parent_valuation$
DECLARE d text:=pg_get_functiondef('feat.build_fundamental_features(date,date)'::regprocedure);
 a text; b text; patch record;
BEGIN
 IF position('|valuation=parent-v1' IN d)>0 THEN RETURN; END IF;
 FOR patch IN SELECT * FROM (VALUES
 ('|price_features=', '|valuation=parent-v1|price_features='),
 ('max(value) FILTER(WHERE feature_key=''net_profit'') AS net_profit,',
  'max(value) FILTER(WHERE feature_key=''net_profit'') AS net_profit,
               max(value) FILTER(WHERE feature_key=''parent_net_profit'') AS parent_net_profit,
               max(value) FILTER(WHERE feature_key=''parent_equity'') AS parent_equity,'),
 ('count(net_profit) OVER w4 AS profit_count4,',
  'count(net_profit) OVER w4 AS profit_count4,
               count(parent_net_profit) OVER w4 AS parent_profit_count4,
               sum(parent_net_profit) OVER w4 AS parent_profit_sum4,'),
 ('THEN profit_sum4 END AS ttm_net_profit,',
  'THEN profit_sum4 END AS ttm_net_profit,
               CASE WHEN periods4=4 AND (extract(year FROM period_end)::integer*4+extract(quarter FROM period_end)::integer) - (extract(year FROM period_4back)::integer*4+extract(quarter FROM period_4back)::integer)=3 AND parent_profit_count4=4 THEN parent_profit_sum4 END AS ttm_parent_net_profit,'),
 ('ttm_net_profit,ttm_operating_cash_flow,bank_ttm_interest_income,',
  'ttm_net_profit,ttm_parent_net_profit,ttm_operating_cash_flow,bank_ttm_interest_income,'),
 ('symbol_id,trade_date,period_end,total_assets,total_liabilities,equity,',
  'symbol_id,trade_date,period_end,total_assets,total_liabilities,equity,parent_equity,'),
 ('b.equity AS current_equity,','b.parent_equity AS current_parent_equity,
               q.ttm_parent_net_profit,'),
 ('f.ttm_net_profit>0','f.ttm_parent_net_profit>0'),
 ('/f.ttm_net_profit END AS pe_ratio','/f.ttm_parent_net_profit END AS pe_ratio'),
 ('f.current_equity','f.current_parent_equity'),
 ('f.liabilities_to_equity,f.accruals_to_average_assets,',
  'f.ttm_parent_net_profit,f.current_parent_equity AS parent_equity,
               f.liabilities_to_equity,f.accruals_to_average_assets,'),
 ('liabilities_to_equity,accruals_to_average_assets,pe_ratio,pb_ratio,',
  'ttm_parent_net_profit,parent_equity,
        liabilities_to_equity,accruals_to_average_assets,pe_ratio,pb_ratio,')
 ) AS patches(anchor,replacement)
 LOOP
  a:=patch.anchor;b:=patch.replacement;
  IF position(a IN d)=0 THEN RAISE EXCEPTION 'parent valuation patch anchor missing: %',a; END IF;
  d:=replace(d,a,b);
 END LOOP;
 EXECUTE d;
END;
$parent_valuation$;
COMMENT ON COLUMN feat.fundamental_features_daily.ttm_parent_net_profit IS
 'Four consecutive PIT quarters of explicitly mapped profit attributable to parent ordinary holders; never consolidated PAT fallback.';
COMMENT ON COLUMN feat.fundamental_features_daily.parent_equity IS
 'Explicitly mapped equity attributable to parent ordinary holders; never consolidated equity fallback. Missing input disables P/B.';
COMMIT;

-- Read-only PIT fundamentals coverage against the current V3 symbol/date scope.
-- This report intentionally separates: (1) in-scope price rows, (2) any archived
-- PIT statement available at the local 15:00 signal cutoff, and (3) an actually
-- materialized overlay row/usable fields. Archive presence is not field mapping.
-- A NULL overlay metric remains NULL; this query does not infer provider mappings.
-- Denominator: every current-hash phase2-v3 feature symbol/date, including rows
-- with no PIT statement, no mapping, unknown industry, or missing calculations.
-- Run only on the disposable report clone named below.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '5min';
DO $$ BEGIN
  IF current_database() <> 'vnsignal_phase2_report_20261019' THEN
    RAISE EXCEPTION 'diagnostic is restricted to vnsignal_phase2_report_20261019';
  END IF;
END $$;

WITH scope AS MATERIALIZED (
  SELECT f.symbol_id, f.trade_date,
         (f.trade_date::timestamp + time '15:00') AT TIME ZONE 'Asia/Ho_Chi_Minh' AS cutoff
    FROM feat.features_daily f
   WHERE f.feature_version='phase2-v3'
     AND f.feature_set_hash=feat.phase2_feature_set_hash_v3()
), archive_asof AS (
  SELECT s.symbol_id,s.trade_date,
         count(DISTINCT (p.statement_type,p.period_type,p.period_end)) AS available_statement_periods,
         count(DISTINCT p.statement_type) AS available_statement_types,
         max(p.period_end) AS latest_period_end,
         max(p.available_at) AS latest_version_available_at,
         count(*) FILTER (WHERE p.availability_is_assumed) AS assumed_line_versions,
         count(*) FILTER (WHERE NOT p.availability_is_assumed) AS observed_line_versions
    FROM scope s JOIN core.fundamentals_pit p
      ON p.symbol_id=s.symbol_id AND p.archive_managed AND p.period_end<=s.trade_date
     AND p.available_at<=s.cutoff
   GROUP BY s.symbol_id,s.trade_date
), joined AS (
  SELECT s.*, a.available_statement_periods,a.available_statement_types,
         a.latest_period_end,a.latest_version_available_at,
         a.assumed_line_versions,a.observed_line_versions,
         o.mapping_hash,o.industry,o.latest_quarter_end,o.pit_quarter_count,
         o.latest_pit_available_at,o.pit_snapshot_ids,
         o.ttm_revenue,o.ttm_gross_profit,o.ttm_operating_profit,o.ttm_net_profit,
         o.ttm_operating_cash_flow,o.gross_margin_ttm,o.operating_margin_ttm,
         o.net_margin_ttm,o.roe_ttm,o.roa_ttm,o.revenue_yoy_growth,
         o.revenue_sequential_growth,o.revenue_growth_acceleration,
         o.liabilities_to_equity,o.accruals_to_average_assets,o.pe_ratio,o.pb_ratio,
         o.bank_ttm_interest_income,o.bank_ttm_interest_expense,
         o.bank_ttm_net_interest_income,o.bank_ttm_net_profit,o.bank_total_assets,
         o.bank_equity,o.bank_roe_ttm,o.bank_roa_ttm,
         o.rank_industry_net_margin,o.rank_industry_roe,o.rank_industry_roa,
         o.rank_industry_revenue_growth,o.rank_industry_leverage,o.rank_industry_pe,
         o.rank_industry_pb
    FROM scope s
    LEFT JOIN archive_asof a USING(symbol_id,trade_date)
    LEFT JOIN LATERAL (
      -- The overlay primary key permits multiple mapping hashes. Select one
      -- latest materialization deterministically for coverage; this does not
      -- assert that its mapping is approved or current.
      SELECT o.* FROM feat.fundamental_features_daily o
       WHERE o.symbol_id=s.symbol_id AND o.trade_date=s.trade_date
         AND o.feature_version='fundamental-overlay-v1'
       ORDER BY o.built_at DESC,o.mapping_hash DESC LIMIT 1
    ) o ON true
)
SELECT date_trunc('year',trade_date)::date AS calendar_year,
       count(*) AS v3_symbol_dates_denominator,
       count(DISTINCT symbol_id) AS v3_symbols,
       count(*) FILTER (WHERE available_statement_periods>0) AS dates_with_any_pit_statement,
       count(*) FILTER (WHERE available_statement_types=3) AS dates_with_all_three_statement_types,
       count(*) FILTER (WHERE mapping_hash IS NOT NULL) AS dates_with_overlay_row,
       count(*) FILTER (WHERE mapping_hash IS NOT NULL AND latest_pit_available_at<=cutoff
                         AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date) AS dates_with_overlay_cutoff_valid,
       count(*) FILTER (WHERE mapping_hash IS NOT NULL AND
                         (latest_pit_available_at IS NULL OR latest_pit_available_at>cutoff
                          OR latest_quarter_end IS NULL OR latest_quarter_end>trade_date)) AS overlay_with_invalid_or_missing_pit_cutoff,
       count(*) FILTER (WHERE pit_snapshot_ids IS NOT NULL AND cardinality(pit_snapshot_ids)>0) AS dates_with_selected_pit_snapshots,
       count(*) FILTER (WHERE latest_quarter_end IS NOT NULL) AS dates_with_quarter,
       count(*) FILTER (WHERE industry IS NULL) AS overlay_rows_unknown_industry,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND ttm_revenue IS NOT NULL) AS ttm_revenue_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND ttm_net_profit IS NOT NULL) AS ttm_net_profit_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND roe_ttm IS NOT NULL) AS roe_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND roa_ttm IS NOT NULL) AS roa_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND revenue_yoy_growth IS NOT NULL) AS revenue_yoy_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND liabilities_to_equity IS NOT NULL) AS leverage_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND pe_ratio IS NOT NULL) AS pe_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND pb_ratio IS NOT NULL) AS pb_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND bank_ttm_net_interest_income IS NOT NULL) AS bank_nii_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND bank_roe_ttm IS NOT NULL) AS bank_roe_nonnull_pit_valid,
       count(*) FILTER (WHERE latest_pit_available_at<=cutoff AND latest_quarter_end IS NOT NULL AND latest_quarter_end<=trade_date AND rank_industry_roe IS NOT NULL) AS industry_roe_rank_nonnull_pit_valid,
       min(latest_quarter_end) AS earliest_overlay_quarter,
       max(latest_quarter_end) AS latest_overlay_quarter,
       max(trade_date) AS last_scope_date
  FROM joined
 GROUP BY 1
 ORDER BY 1;

-- Coverage by exchange is only reported when a timestamped PIT industry
-- observation supports an unambiguous exchange classification. Date-only
-- listing snapshots are not used as PIT evidence here; exchange is not safely
-- measurable from this overlay schema alone, so no exchange attribution is made.
-- Mapping coverage by source row ID/unit and bank-vs-nonbank denominator also
-- cannot be established safely without an approved, source-backed item map.

COMMIT;

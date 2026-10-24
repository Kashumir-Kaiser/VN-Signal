-- Bounded read-only evidence query for FPT VCI fundamental landing semantics.
-- Reads only the three previously archived FPT statement landings in the
-- report clone. It does not mutate database state or expand unrelated JSON.
\pset pager off
\pset tuples_only off
SELECT landing_id,source,route,symbol,ingest_id,fetched_at,payload_sha256,
       encode(sha256(payload_bytes),'hex')=lower(payload_sha256) AS checksum_ok,
       payload->'attributes' AS attributes,
       jsonb_array_length(payload->'rows') AS row_count
  FROM raw.landings
 WHERE landing_id IN (9798,9802,9803)
 ORDER BY landing_id;

WITH selected AS (
    SELECT l.landing_id,
           r.value->>'period' AS period,
           r.value->>'id' AS provider_id,
           r.value->>'name' AS provider_name,
           r.value->>'unit' AS unit,
           (r.value->>'value')::numeric AS value
      FROM raw.landings l
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') r(value)
     WHERE l.landing_id IN (9798,9802,9803)
       AND r.value->>'period' IN ('2025-Q1','2025-Q2','2025-Q3','2025-Q4')
       AND r.value->>'id' IN (
           'IS_REVENUE','IS_REVENUE_DEDUCTIONS','IS_NET_REVENUE',
           'IS_GROSS_PROFIT','IS_OPERATING_PROFIT','IS_NET_PROFIT_AFTER_TAX',
           'IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY',
           'CF_NET_CASH_FLOWS_FROM_OPERATING_ACTIVITIES')
)
SELECT landing_id,period,provider_id,provider_name,unit,value
  FROM selected
 ORDER BY landing_id,period,provider_id;

WITH selected AS (
    SELECT l.landing_id,
           r.value->>'period' AS period,
           r.value->>'id' AS provider_id,
           (r.value->>'value')::numeric AS value
      FROM raw.landings l
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') r(value)
     WHERE l.landing_id IN (9798,9802,9803)
       AND r.value->>'period' IN ('2025-Q1','2025-Q2','2025-Q3','2025-Q4')
       AND r.value->>'id' IN (
           'IS_REVENUE','IS_REVENUE_DEDUCTIONS','IS_NET_REVENUE',
           'IS_GROSS_PROFIT','IS_OPERATING_PROFIT','IS_NET_PROFIT_AFTER_TAX',
           'IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY',
           'CF_NET_CASH_FLOWS_FROM_OPERATING_ACTIVITIES')
)
SELECT landing_id,provider_id,count(*) AS quarter_count,
       sum(value) AS q1_q4_sum
  FROM selected
 GROUP BY landing_id,provider_id
 ORDER BY landing_id,provider_id;

-- Bounded Q1+Q2 sums for comparison with FPT's reviewed six-month totals.
WITH selected AS (
    SELECT r.value->>'period' AS period,
           r.value->>'id' AS provider_id,
           (r.value->>'value')::numeric AS value
      FROM raw.landings l
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') r(value)
     WHERE l.landing_id=9798
       AND r.value->>'period' IN ('2025-Q1','2025-Q2')
       AND r.value->>'id' IN ('IS_NET_REVENUE',
           'IS_PROFIT_AFTER_TAX_FOR_SHAREHOLDERS_OF_PARENT_COMPANY')
)
SELECT provider_id,sum(value) AS q1_q2_sum
  FROM selected
 GROUP BY provider_id
 ORDER BY provider_id;

WITH selected AS (
    SELECT r.value->>'period' AS period,
           (r.value->>'value')::numeric AS value
      FROM raw.landings l
      CROSS JOIN LATERAL jsonb_array_elements(l.payload->'rows') r(value)
     WHERE l.landing_id=9803
       AND r.value->>'period' IN ('2025-Q1','2025-Q2')
       AND r.value->>'id'='CF_NET_CASH_FLOWS_FROM_OPERATING_ACTIVITIES'
)
SELECT sum(value) AS q1_q2_operating_cash_flow
  FROM selected;

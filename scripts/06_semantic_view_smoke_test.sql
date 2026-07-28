-- Phase 6 smoke test: 10 business questions run directly against
-- LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW via SEMANTIC_VIEW(...) SQL
-- syntax (Cortex Analyst not available on this account tier -- see
-- scripts/publish_semantic_view.sql header). Results and latency recorded in
-- data/sources.md Phase 6 wrap.

-- Q1: Top 10 consignees by total landed cost
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  METRICS fact_shipments.total_shipments, fact_shipments.total_landed_cost_usd
  DIMENSIONS dim_consignee.consignee_name
) ORDER BY total_landed_cost_usd DESC NULLS LAST LIMIT 10;

-- Q2: Which consignees are single-sourced on HS chapter 87 (vehicles)?
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_consignee.consignee_name, dim_hs_code.hs_6, mart_concentration_metrics.is_single_source
  METRICS mart_concentration_metrics.max_supplier_hhi
  WHERE dim_hs_code.hs_2 = '87' AND mart_concentration_metrics.is_single_source = TRUE
) ORDER BY max_supplier_hhi DESC LIMIT 10;

-- Q3: China imports exposure by HS chapter
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_hs_code.hs_2, dim_hs_code.hs_2_description
  METRICS fact_shipments.total_shipments, fact_shipments.total_landed_cost_usd
  WHERE fact_shipments.origin_country_code = 'CN'
) ORDER BY total_landed_cost_usd DESC NULLS LAST LIMIT 10;

-- Q4: German suppliers of automotive parts (HS 8708)
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_supplier.supplier_name, dim_supplier.supplier_country_code, dim_hs_code.hs_4
  METRICS fact_shipments.total_shipments, fact_shipments.total_landed_cost_usd
  WHERE dim_supplier.supplier_country_code = 'DE' AND dim_hs_code.hs_4 = '8708'
) ORDER BY total_shipments DESC LIMIT 10;

-- Q5: Section 232 total exposure across steel + aluminum (HS 72/73/76)
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_hs_code.hs_2, dim_hs_code.hs_2_description
  METRICS fact_shipments.total_shipments, fact_shipments.total_landed_cost_usd, fact_shipments.avg_effective_duty_rate
  WHERE dim_country.is_section_232_target = TRUE AND dim_hs_code.hs_2 IN ('72', '73', '76')
) ORDER BY total_landed_cost_usd DESC NULLS LAST;

-- Q6: Top 20 freight forwarders by shipment count
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_consignee.consignee_name
  METRICS fact_shipments.total_shipments
  WHERE dim_consignee.is_forwarder = TRUE
) ORDER BY total_shipments DESC LIMIT 20;

-- Q7: Monthly shipment count trend for 2018
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_date.year, dim_date.month
  METRICS fact_shipments.total_shipments
  WHERE dim_date.year = 2018
) ORDER BY month;

-- Q8: Consignees with highest supplier concentration (HHI), min 5 shipments in the pair
SELECT * FROM (
  SELECT * FROM SEMANTIC_VIEW(
    LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
    DIMENSIONS dim_consignee.consignee_name, dim_hs_code.hs_6_description
    METRICS mart_concentration_metrics.max_supplier_hhi, fact_shipments.total_shipments
  )
) WHERE total_shipments >= 5
ORDER BY max_supplier_hhi DESC LIMIT 10;

-- Q9: Countries subject to Section 232 tariffs -- shipment counts from each
SELECT * FROM SEMANTIC_VIEW(
  LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  DIMENSIONS dim_country.country_name
  METRICS fact_shipments.total_shipments
  WHERE dim_country.is_section_232_target = TRUE
) ORDER BY total_shipments DESC;

-- Q10: Single-source consignees on HS 8708 (auto parts heading), name their sole supplier.
-- NOTE: an earlier draft tried to pull dim_supplier.supplier_name (via
-- fact_shipments) alongside mart_concentration_metrics.is_single_source in one
-- SEMANTIC_VIEW() call and hit: "The entities 'MART_CONCENTRATION_METRICS' and
-- 'FACT_SHIPMENTS' are not related" -- Snowflake's semantic view engine won't
-- implicitly join two fact-grain tables through a shared dimension (dim_consignee/
-- dim_hs_code); it requires a direct relationship between them, which this schema
-- doesn't define. Worked around by staying within the fact_shipments-connected
-- subgraph and doing the single-supplier-per-pair filter in outer SQL instead of
-- relying on the mart's precomputed is_single_source flag.
SELECT consignee_name, hs_6, supplier_name, total_shipments FROM (
  SELECT *, COUNT(DISTINCT supplier_name) OVER (PARTITION BY consignee_name, hs_6) AS supplier_count
  FROM (
    SELECT * FROM SEMANTIC_VIEW(
      LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
      DIMENSIONS dim_consignee.consignee_name, dim_hs_code.hs_6, dim_supplier.supplier_name
      METRICS fact_shipments.total_shipments
      WHERE dim_hs_code.hs_4 = '8708'
    )
  )
)
WHERE supplier_count = 1
ORDER BY total_shipments DESC LIMIT 10;

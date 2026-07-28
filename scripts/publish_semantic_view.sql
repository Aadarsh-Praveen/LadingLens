-- Native Snowflake SEMANTIC VIEW over the Gold star schema. Cortex Analyst is
-- not available on this account tier (SNOWFLAKE.CORTEX.ANALYST module absent),
-- so this is the semantic layer itself -- queryable directly via
-- SEMANTIC_VIEW(...) SQL syntax (see scripts/06_semantic_view_smoke_test.sql),
-- and the substrate a future Cortex Analyst REST endpoint would sit on top of
-- if/when the account is upgraded. See data/sources.md Phase 6 wrap for detail.
--
-- Syntax verified against Snowflake's CREATE SEMANTIC VIEW reference (fetched
-- live during Phase 6): DIMENSIONS/METRICS expressions require an explicit
-- `AS <sql_expr>` -- a bare `table.column WITH SYNONYMS (...)` is a syntax
-- error, which is what the first draft of this file hit.
--
-- dim_date.date_day/year/month and dim_hs_code.hs_4/hs_4_description/hs_6 were
-- added after the original draft omitted them -- without dim_date there was no
-- way to ask a time-trend question through the semantic layer, without hs_4
-- there was no way to filter to an HS heading (e.g. 8708, auto parts) rather
-- than a full HS-2 chapter, and without dim_hs_code.hs_6 as its own dimension
-- (it was only a join key / primary key) queries pairing it with
-- mart_concentration_metrics dimensions failed with "invalid identifier".

CREATE OR REPLACE SEMANTIC VIEW LADINGLENS_DB.SEMANTIC.LADINGLENS_SEMANTIC_VIEW
  TABLES (
    fact_shipments AS LADINGLENS_DB.GOLD.FACT_SHIPMENTS
      PRIMARY KEY (shipment_key),
    dim_consignee AS LADINGLENS_DB.GOLD.DIM_CONSIGNEE
      PRIMARY KEY (consignee_key),
    dim_supplier AS LADINGLENS_DB.GOLD.DIM_SUPPLIER
      PRIMARY KEY (supplier_key),
    dim_hs_code AS LADINGLENS_DB.GOLD.DIM_HS_CODE
      PRIMARY KEY (hs_6),
    dim_country AS LADINGLENS_DB.GOLD.DIM_COUNTRY
      PRIMARY KEY (country_code),
    dim_date AS LADINGLENS_DB.GOLD.DIM_DATE
      PRIMARY KEY (date_key),
    mart_concentration_metrics AS LADINGLENS_DB.GOLD.MART_CONCENTRATION_METRICS
      PRIMARY KEY (consignee_key, hs_6)
  )
  RELATIONSHIPS (
    fact_shipments (supplier_key) REFERENCES dim_supplier (supplier_key),
    fact_shipments (consignee_key) REFERENCES dim_consignee (consignee_key),
    fact_shipments (hs_6) REFERENCES dim_hs_code (hs_6),
    fact_shipments (origin_country_code) REFERENCES dim_country (country_code),
    fact_shipments (date_key) REFERENCES dim_date (date_key),
    mart_fk_consignee AS mart_concentration_metrics (consignee_key) REFERENCES dim_consignee (consignee_key),
    mart_fk_hs_code AS mart_concentration_metrics (hs_6) REFERENCES dim_hs_code (hs_6)
  )
  DIMENSIONS (
    fact_shipments.hs_6 AS fact_shipments.hs_6
      WITH SYNONYMS = ('HS code', 'HTS code', 'tariff code'),
    fact_shipments.origin_country_code AS fact_shipments.origin_country_code
      WITH SYNONYMS = ('country of origin', 'source country'),
    fact_shipments.hs_source_final AS fact_shipments.hs_source_final
      WITH SYNONYMS = ('classification method', 'HS source'),
    fact_shipments.consignee_party_type AS fact_shipments.consignee_party_type
      WITH SYNONYMS = ('consignee type', 'importer type'),
    dim_consignee.consignee_name AS dim_consignee.consignee_name
      WITH SYNONYMS = ('importer name', 'company name'),
    dim_consignee.is_forwarder AS dim_consignee.is_forwarder
      WITH SYNONYMS = ('freight forwarder', 'is forwarder'),
    dim_supplier.supplier_name AS dim_supplier.supplier_name
      WITH SYNONYMS = ('shipper name', 'exporter'),
    dim_supplier.supplier_country_code AS dim_supplier.supplier_country_code
      WITH SYNONYMS = ('supplier country'),
    dim_hs_code.hs_6 AS dim_hs_code.hs_6
      WITH SYNONYMS = ('HS-6 code', 'subheading'),
    dim_hs_code.hs_2 AS dim_hs_code.hs_2
      WITH SYNONYMS = ('HS chapter', 'chapter'),
    dim_hs_code.hs_2_description AS dim_hs_code.hs_2_description
      WITH SYNONYMS = ('chapter description'),
    dim_hs_code.hs_4 AS dim_hs_code.hs_4
      WITH SYNONYMS = ('HS heading', 'heading'),
    dim_hs_code.hs_4_description AS dim_hs_code.hs_4_description
      WITH SYNONYMS = ('heading description'),
    dim_hs_code.hs_6_description AS dim_hs_code.hs_6_description
      WITH SYNONYMS = ('product description', 'tariff description'),
    dim_country.country_name AS dim_country.country_name,
    dim_country.region AS dim_country.region,
    dim_country.is_section_232_target AS dim_country.is_section_232_target,
    dim_country.is_section_301_target AS dim_country.is_section_301_target,
    dim_date.date_day AS dim_date.date_day
      WITH SYNONYMS = ('date', 'shipment date'),
    dim_date.year AS dim_date.year,
    dim_date.month AS dim_date.month,
    mart_concentration_metrics.is_single_source AS mart_concentration_metrics.is_single_source
      WITH SYNONYMS = ('single-source', 'sole-source dependency'),
    mart_concentration_metrics.is_single_country AS mart_concentration_metrics.is_single_country
      WITH SYNONYMS = ('single-country', 'geographic concentration')
  )
  METRICS (
    fact_shipments.total_shipments AS COUNT(*)
      WITH SYNONYMS = ('shipment count', 'number of shipments'),
    fact_shipments.total_weight_kg AS SUM(fact_shipments.weight_kg)
      WITH SYNONYMS = ('total weight', 'aggregate weight'),
    fact_shipments.total_value_usd AS SUM(fact_shipments.shipment_value_usd)
      WITH SYNONYMS = ('total value', 'customs value'),
    fact_shipments.total_landed_cost_usd AS SUM(fact_shipments.estimated_landed_cost_usd)
      WITH SYNONYMS = ('landed cost', 'tariff exposure', 'total cost with duties'),
    fact_shipments.avg_effective_duty_rate AS AVG(fact_shipments.effective_duty_rate_pct)
      WITH SYNONYMS = ('average duty rate', 'mean tariff rate'),
    mart_concentration_metrics.max_supplier_hhi AS MAX(mart_concentration_metrics.supplier_hhi)
      WITH SYNONYMS = ('supplier concentration', 'HHI on suppliers'),
    mart_concentration_metrics.max_country_hhi AS MAX(mart_concentration_metrics.country_hhi)
      WITH SYNONYMS = ('country concentration', 'geographic HHI')
  )
  COMMENT = 'LadingLens Gold-layer semantic view: shipment-level tariff exposure and supplier/country concentration risk over the EU-auto/Vietnam-apparel scoped BoL population.';

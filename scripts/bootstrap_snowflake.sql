-- LadingLens — Snowflake bootstrap script
-- Creates the warehouse, database, schemas, and stage used by all later phases.
-- Run once in Snowsight (or via `snow sql -f scripts/bootstrap_snowflake.sql`).

CREATE WAREHOUSE IF NOT EXISTS LADINGLENS_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Compute for LadingLens dbt runs, EDA notebooks, and Streamlit app. XS + fast auto-suspend to conserve trial credits.';

CREATE DATABASE IF NOT EXISTS LADINGLENS_DB
    COMMENT = 'LadingLens: Tariff-Exposure & Supplier-Concentration Copilot. Holds all bronze/silver/gold data for the hackathon build.';

USE DATABASE LADINGLENS_DB;

CREATE SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Landing zone for unmodified source data: BoL CSVs, USITC HTS extracts, SEC 10-K text.';

CREATE SCHEMA IF NOT EXISTS BRONZE
    COMMENT = 'dbt Bronze layer: raw sources loaded as-is into typed tables, no cleaning applied.';

CREATE SCHEMA IF NOT EXISTS SILVER
    COMMENT = 'dbt Silver layer: cleaned, deduplicated, entity-resolved data (golden supplier records, HS-mapped shipments).';

CREATE SCHEMA IF NOT EXISTS GOLD
    COMMENT = 'dbt Gold layer: analytics-ready star schema (fact_shipments, dim_supplier, dim_product, dim_country, fact_tariff).';

CREATE SCHEMA IF NOT EXISTS SEMANTIC
    COMMENT = 'Cortex Analyst semantic views exposing business-friendly metrics (landed_cost, concentration_index, tariff_exposure).';

CREATE SCHEMA IF NOT EXISTS STAGE
    COMMENT = 'Internal stages used for file uploads (BoL CSVs, HTS files, 10-K text dumps) before COPY INTO raw tables.';

CREATE STAGE IF NOT EXISTS LADINGLENS_DB.STAGE.RAW_STAGE
    COMMENT = 'Internal stage for uploading raw BoL/HTS/10-K files ahead of Bronze-layer ingestion.';

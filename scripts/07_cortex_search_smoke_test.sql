-- Phase 7 smoke test: 10 realistic questions Phase 8's agent will translate into
-- SNOWFLAKE.CORTEX.SEARCH_PREVIEW calls against RISK_FACTORS_SEARCH.
--
-- Q5 swapped from Ford (never loaded -- not in RAW.SEC_10K_FILINGS or
-- config/target_tickers.yml's target universe at all) to Western Digital (WDC),
-- which had the earliest tariff mention (position 949) among WDC/HPQ/AMD.
-- Q9 (Tata Motors / TTM) restored to its original ticker after the Item 3.D
-- extraction fix recovered 185K chars of real risk-factor text (was empty).
--
-- Phase 10 note: SEARCH_PREVIEW's response shape appears to have drifted
-- between Snowflake releases (a plain ":results" key access has been
-- observed to fail against some accounts/versions). Each query below
-- captures the raw payload once and COALESCEs across the known shapes so
-- the smoke test degrades gracefully and reports which shape matched,
-- rather than erroring outright -- see data/sources.md's Platform
-- Observations section. Cortex Agent's own cortex_search tool consumption
-- is unaffected by this; it doesn't go through this direct-SQL path.

-- Q1: "What tariff-related risks does Apple describe in their 10-K?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "tariff-related risks", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "AAPL"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q2: "What supply chain concentration risks does Nike disclose?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "supply chain concentration risk", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "NKE"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q3: "Which risks does Walmart's 10-K mention about China trade policy?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "China trade policy risk", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "WMT"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q4: "What does Caterpillar say about steel and aluminum tariffs?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "steel and aluminum tariffs", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "CAT"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q5 (swapped from Ford, not loaded): "What tariff-related risks does Western Digital disclose?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "tariff risk", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "WDC"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q6: "What geopolitical risks are described for semiconductors?" (no filter)
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "geopolitical risks for semiconductors", "limit": 3, "columns": ["chunk_text","ticker","filing_year"]}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q7: "Which companies mention Section 301 tariffs as a specific risk?" (no filter)
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "Section 301 tariffs", "limit": 3, "columns": ["chunk_text","ticker","filing_year"]}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q8: "What supply chain diversification strategies do companies describe?" (no filter)
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "supply chain diversification strategy", "limit": 3, "columns": ["chunk_text","ticker","filing_year"]}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q9 (restored after TTM extraction fix): "How does Tata Motors describe US import risks?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "US import risks", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "TTM"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

-- Q10: "What does Deere say about agricultural equipment tariff exposure?"
WITH raw AS (
    SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH',
        '{"query": "agricultural equipment tariff exposure", "limit": 3, "columns": ["chunk_text","ticker","filing_year"], "filter": {"@eq": {"ticker": "DE"}}}'
    )) AS payload
)
SELECT
    COALESCE(payload:results, payload) AS results,
    IFF(payload:results IS NOT NULL, 'results-key format', 'alternative/raw format') AS shape_detected
FROM raw;

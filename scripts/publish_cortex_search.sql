-- Cortex Search service over 10-K/20-F risk-factor chunks (fact_10k_risk_chunks).
-- Chunked at stride=1500/width=1700 chars (200-char overlap) -- see
-- fact_10k_risk_chunks.sql header for why this differs from the original
-- 800/1000 spec (population is 2.3x the assumed size; 800/1000 would have
-- produced ~5,350 chunks). GES/LULU/MU chunks retain some contamination
-- (financial-statement/audit-report text) from an unresolved Item 1A
-- extraction bug -- see data/sources.md Phase 7 wrap.

CREATE OR REPLACE CORTEX SEARCH SERVICE LADINGLENS_DB.SEMANTIC.RISK_FACTORS_SEARCH
  ON chunk_text
  ATTRIBUTES ticker, filing_type, filing_year
  WAREHOUSE = LADINGLENS_WH
  TARGET_LAG = '1 hour'
  EMBEDDING_MODEL = 'snowflake-arctic-embed-m-v1.5'
AS (
    SELECT
        chunk_id,
        chunk_text,
        ticker,
        filing_type,
        filing_year,
        filing_date,
        chunk_start,
        chunk_end
    FROM LADINGLENS_DB.GOLD.FACT_10K_RISK_CHUNKS
);

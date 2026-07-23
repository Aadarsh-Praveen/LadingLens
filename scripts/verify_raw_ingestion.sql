-- LadingLens — Phase 2 raw ingestion sanity checks.
-- Run with: snow sql -f scripts/verify_raw_ingestion.sql --connection ladinglens

SELECT
    'BOL_SHIPMENTS' AS table_name,
    COUNT(*) AS row_count,
    MIN(ingested_at) AS earliest,
    MAX(ingested_at) AS latest
FROM LADINGLENS_DB.RAW.BOL_SHIPMENTS
UNION ALL
SELECT 'HTS_TARIFF_SCHEDULE', COUNT(*), MIN(ingested_at), MAX(ingested_at)
FROM LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE
UNION ALL
SELECT 'SEC_10K_FILINGS', COUNT(*), MIN(ingested_at), MAX(ingested_at)
FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS;

-- BoL top consignees by shipment count
SELECT consignee_name, COUNT(*) AS shipment_count
FROM LADINGLENS_DB.RAW.BOL_SHIPMENTS
WHERE consignee_name IS NOT NULL
GROUP BY 1
ORDER BY 2 DESC
LIMIT 20;

-- HTS top-level chapters
SELECT hs2, COUNT(*) AS line_count
FROM LADINGLENS_DB.RAW.HTS_TARIFF_SCHEDULE
GROUP BY 1
ORDER BY 1
LIMIT 10;

-- SEC 10-Ks loaded
SELECT ticker, filing_date, item_1a_length, item_7_length
FROM LADINGLENS_DB.RAW.SEC_10K_FILINGS
ORDER BY ticker;

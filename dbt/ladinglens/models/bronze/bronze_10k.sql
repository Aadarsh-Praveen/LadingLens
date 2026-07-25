{{
    config(
        materialized='table'
    )
}}

-- Bronze: typed, deduplicated SEC_10K_FILINGS. filing_type (10-K vs 20-F) was
-- logged directly at ingest time in Step 0 (scripts/ingest/03_sec_10k.py),
-- so it's passed through rather than re-inferred from the filing URL.

with source as (

    select
        cik,
        ticker,
        filing_type,
        filing_date,
        filing_url,
        item_1a_text,
        item_7_text,
        item_1a_length,
        item_7_length,
        ingested_at
    from {{ source('raw', 'sec_10k_filings') }}

),

deduped as (

    select *
    from source
    qualify row_number() over (partition by cik, filing_date order by ingested_at desc) = 1

)

select
    cik,
    ticker,
    coalesce(filing_type, '10-K') as filing_type,
    filing_date,
    filing_url,
    item_1a_text,
    item_7_text,
    item_1a_length,
    item_7_length,
    (item_1a_length >= 5000) as is_supply_chain_relevant,
    ingested_at
from deduped

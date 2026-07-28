-- Ticker <-> consignee link: enables Phase 8's agent to join concentration
-- analysis (golden_consignee_id) with 10-K risk-factor retrieval (ticker).
--
-- ticker_to_company is the REAL loaded ticker list (24, verified via
-- `SELECT DISTINCT ticker FROM RAW.SEC_10K_FILINGS`), not the phase-07 doc's
-- example recap, which named 5 tickers (MSFT, TSLA, AMZN, F, GM) that were
-- never in config/target_tickers.yml's target universe and don't exist in
-- this table, while omitting 6 that are actually loaded (CSCO, ETN, MU, PH,
-- TPR, VFC). No company_name column exists on RAW.SEC_10K_FILINGS, so this is
-- a hand-curated map, not a passthrough.

with filings_latest as (

    select ticker, cik, filing_type, filing_date, item_1a_text, item_1a_length
    from (
        select *,
               row_number() over (partition by ticker order by filing_date desc) as rn
        from {{ source('raw', 'sec_10k_filings') }}
        where item_1a_text is not null
    )
    where rn = 1

),

ticker_to_company as (

    select * from values
        ('AAPL', 'Apple Inc.'),
        ('AMD',  'Advanced Micro Devices, Inc.'),
        ('ANET', 'Arista Networks, Inc.'),
        ('CAT',  'Caterpillar Inc.'),
        ('CSCO', 'Cisco Systems, Inc.'),
        ('DE',   'Deere & Company'),
        ('ETN',  'Eaton Corporation plc'),
        ('GES',  'Guess?, Inc.'),
        ('HBI',  'HanesBrands Inc.'),
        ('HPQ',  'HP Inc.'),
        ('JNPR', 'Juniper Networks, Inc.'),
        ('LEVI', 'Levi Strauss & Co.'),
        ('LULU', 'Lululemon Athletica Inc.'),
        ('MU',   'Micron Technology, Inc.'),
        ('NKE',  'Nike, Inc.'),
        ('NVDA', 'NVIDIA Corporation'),
        ('PH',   'Parker Hannifin Corporation'),
        ('PVH',  'PVH Corp.'),
        ('RL',   'Ralph Lauren Corporation'),
        ('TPR',  'Tapestry, Inc.'),
        ('TTM',  'Tata Motors Limited'),
        ('VFC',  'VF Corporation'),
        ('WDC',  'Western Digital Corporation'),
        ('WMT',  'Walmart Inc.')
    as t(ticker, company_name)

),

-- SPLIT_PART(company_name, ' ', 1) on a name like 'Nike, Inc.' or 'Guess?, Inc.'
-- returns 'Nike,' / 'Guess?,' -- trailing punctuation on the first token that
-- silently breaks the LIKE match against punctuation-free canonical_name values
-- (verified: 'NIKE DE MEXICO...' and 'GUESS? INC.' both exist in
-- silver_consignee_golden and were false-negative 'none' matches before this
-- REGEXP_REPLACE strip was added). Genuinely-absent tickers (JNPR, LULU, NVDA,
-- TPR) are unaffected either way.
first_token as (

    select
        ticker,
        company_name,
        regexp_replace(split_part(company_name, ' ', 1), '[^A-Za-z0-9]', '') as company_first_token
    from ticker_to_company

),

consignee_match as (

    select
        tc.ticker,
        tc.company_name,
        cg.golden_consignee_id,
        case
            when upper(cg.canonical_name) = upper(tc.company_name) then 'exact'
            when upper(cg.canonical_name) like '%' || upper(tc.company_first_token) || '%' then 'partial'
            else 'none'
        end as match_confidence
    from first_token tc
    left join {{ ref('silver_consignee_golden') }} cg
        on upper(cg.canonical_name) like '%' || upper(tc.company_first_token) || '%'
    qualify row_number() over (
        partition by tc.ticker
        order by case when upper(cg.canonical_name) = upper(tc.company_name) then 0 else 1 end,
                 cg.total_shipments desc nulls last
    ) = 1

)

select
    f.ticker,
    tc.company_name,
    f.cik,
    f.filing_type as filing_type_latest,
    f.filing_date as filing_date_latest,
    f.item_1a_length as item_1a_length_latest,
    f.item_1a_length >= 5000 as is_supply_chain_relevant,
    cm.golden_consignee_id as matched_consignee_key,
    coalesce(cm.match_confidence, 'none') as match_confidence
from filings_latest f
join ticker_to_company tc on f.ticker = tc.ticker
left join consignee_match cm on f.ticker = cm.ticker

{{
    config(
        materialized='table'
    )
}}

-- Bronze: typed USITC HTS tariff schedule. 1:1 with RAW.HTS_TARIFF_SCHEDULE,
-- deduplicated on hts_number, with a best-effort numeric ad-valorem rate
-- parsed out of the free-text general_rate_text field.
--
-- general_rate_text formats observed (Phase 3/4 exploration):
--   'Free'                  -> ad_valorem_rate = 0.0
--   '3.4%'                  -> ad_valorem_rate = 0.034
--   '1.5c/kg', 'Free, under bond...', '10.5c/bbl', free-text notes, blank/whitespace
--                           -> ad_valorem_rate = NULL, specific_rate_raw preserves the original text

with source as (

    select
        hts_number,
        description,
        indent,
        units,
        general_rate_text,
        special_rate_text,
        column2_rate_text,
        footnotes,
        hs2,
        hs4,
        hs6,
        hs8,
        hs10,
        ingested_at
    from {{ source('raw', 'hts_tariff_schedule') }}

),

deduped as (

    select *
    from source
    qualify row_number() over (partition by hts_number order by ingested_at desc) = 1

)

select
    hts_number,
    description,
    indent,
    units,
    general_rate_text,
    special_rate_text,
    column2_rate_text,
    footnotes,
    hs2,
    hs4,
    hs6,
    hs8,
    hs10,
    case
        when trim(general_rate_text) = 'Free' then 0.0
        when regexp_like(trim(general_rate_text), '^[0-9]+(\\.[0-9]+)?%$')
            then try_to_double(replace(trim(general_rate_text), '%', '')) / 100.0
        else null
    end as ad_valorem_rate,
    case
        when trim(general_rate_text) = 'Free' then null
        when regexp_like(trim(general_rate_text), '^[0-9]+(\\.[0-9]+)?%$') then null
        when general_rate_text is not null and trim(general_rate_text) != '' then general_rate_text
        else null
    end as specific_rate_raw,
    ingested_at
from deduped

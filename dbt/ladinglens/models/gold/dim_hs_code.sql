-- HS-6 grain, aggregated up from bronze_hts's line-item (HS8/HS10) rows -- no row
-- in bronze_hts is itself at exactly HS-6 precision (every leaf carries a duty rate
-- at HS8/HS10; the nominal "HS-6 header" rows are bare labels like "Other:" with no
-- rate), so general_duty_rate_pct is an AVG across that HS-6's sub-headings and
-- hs_6_description is the shortest non-blank description among them (picking the
-- HS-6 header's own "Other:"-style label would be worthless as a standalone
-- description).
--
-- general_duty_rate_pct reuses bronze_hts.ad_valorem_rate (already parsed from
-- general_rate_text in Phase 2 as a 0-1 fraction; NULL for specific/compound rates
-- like '1.5¢/kg' that don't reduce to a clean percentage) rather than re-parsing
-- general_rate_text here. Scaled to percent (x100) per the project's percent-scale
-- convention for duty rates.
--
-- section_232_rate_pct / section_301_rate_pct are hard-coded per HS-2 chapter,
-- reflecting the CURRENT (Q3 2026) tariff regime -- not time-varying. See
-- fact_tariff_events for the historical record; time-conditional exposure is
-- deferred to Phase 8's scenario simulator.

with hs6_agg as (

    select
        hs6,
        hs4,
        hs2,
        avg(ad_valorem_rate) * 100 as general_duty_rate_pct
    from {{ ref('bronze_hts') }}
    where hs6 is not null
    group by 1, 2, 3

),

hs6_desc as (
    select hs6, description
    from {{ ref('bronze_hts') }}
    where hs6 is not null and description is not null and trim(description) != ''
    qualify row_number() over (partition by hs6 order by length(description) asc, hts_number asc) = 1
),

hs4_desc as (
    select hs4, description
    from {{ ref('bronze_hts') }}
    where hs4 is not null and description is not null and trim(description) != ''
    qualify row_number() over (partition by hs4 order by length(description) asc, hts_number asc) = 1
),

hs2_desc as (
    select hs2, description
    from {{ ref('bronze_hts') }}
    where hs2 is not null and description is not null and trim(description) != ''
    qualify row_number() over (partition by hs2 order by length(description) asc, hts_number asc) = 1
)

select
    a.hs6 as hs_6,
    d6.description as hs_6_description,
    a.hs4 as hs_4,
    d4.description as hs_4_description,
    a.hs2 as hs_2,
    d2.description as hs_2_description,
    a.general_duty_rate_pct,
    case
        when a.hs2 in ('72', '73') then 25.0  -- steel
        when a.hs2 = '76' then 25.0            -- aluminum (updated 2025)
        else 0.0
    end as section_232_rate_pct,
    case
        when a.hs2 in ('84', '85') then 25.0   -- machinery, electronics (List 1-3)
        when a.hs2 in ('39', '73') then 25.0   -- plastics, misc steel
        when a.hs2 in ('61', '62') then 7.5    -- apparel (List 4A, reduced)
        when a.hs2 = '87' then 25.0            -- base vehicles/parts (EVs excluded, see Phase 8)
        else 0.0
    end as section_301_rate_pct
from hs6_agg a
left join hs6_desc d6 on a.hs6 = d6.hs6
left join hs4_desc d4 on a.hs4 = d4.hs4
left join hs2_desc d2 on a.hs2 = d2.hs2

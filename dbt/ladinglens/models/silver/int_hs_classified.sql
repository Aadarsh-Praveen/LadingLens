{{
    config(
        materialized='table'
    )
}}

-- Parses int_hs_classified_raw.raw_response into a usable HS code and
-- status. Split out from the LLM-calling model so this parsing logic can be
-- iterated on and rebuilt for free -- see int_hs_classified_raw.sql's
-- header for why that model must not be casually rebuilt.
--
-- First pass only matched a bare 6-consecutive-digit run, which
-- miscategorized ~98% of what looked like "parse failures" as failures when
-- they were actually valid but shorter/differently-formatted responses
-- (a clean 4-digit HS-4 heading, or a dotted "8701.21" style code) -- real
-- parse failures (explanatory refusals, malformed codes) were only 0.05% of
-- the population. This version distinguishes all three shapes explicitly
-- rather than lumping format variance in with genuine failures.
--
-- Snowflake's regex engine (RE2) does not support lookahead/lookbehind --
-- '\d{4}(?!\d)' fails to compile ("no argument for repetition operator").
-- '\b\d{4}\b' (word-boundary) is the RE2-compatible equivalent and was
-- verified directly against Snowflake before use here.

with raw as (

    select product_text, raw_response
    from {{ ref('int_hs_classified_raw') }}

),

parsed as (

    select
        product_text,
        raw_response,
        -- Exact 6-digit code (highest priority, includes the 999999 sentinel)
        regexp_substr(raw_response, '\\d{6}') as hs6_match,
        -- Dotted format like "8701.21"
        regexp_substr(raw_response, '\\d{4}\\.\\d{2}') as dotted_match,
        -- Bare 4-digit heading, not part of a longer digit run
        regexp_substr(raw_response, '\\b\\d{4}\\b') as hs4_only_match
    from raw

),

classified as (

    select
        product_text,
        raw_response,
        case
            when hs6_match = '999999' then '999999'
            when hs6_match is not null then hs6_match
            when dotted_match is not null then replace(dotted_match, '.', '')
            when hs4_only_match is not null then hs4_only_match || '00'
            else null
        end as predicted_hs_6,
        case
            when hs6_match = '999999' then 'unclassifiable'
            when hs6_match is not null then 'classified_hs6'
            when dotted_match is not null then 'classified_hs6_dotted'
            when hs4_only_match is not null then 'classified_hs4_only'
            else 'parse_failed'
        end as classification_status
    from parsed

)

select * from classified

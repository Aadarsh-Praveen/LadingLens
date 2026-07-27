{{
    config(
        materialized='table'
    )
}}

-- Unified Silver fact: every shipment in silver_bol_shipments (origin-
-- country scoped) with a single hs_code_unified column populated from
-- whichever source got there first -- source field, Bronze regex
-- extraction, or Phase 5's LLM classification.
--
-- The lookup join to int_hs_classified uses normalize_product_text() (see
-- that macro's header) truncated to 200 chars, matching EXACTLY what
-- int_product_text_universe.sql used to build the classification
-- population -- any drift between the two would silently break the join
-- for rows that need LLM classification.

with source_shipments as (

    select * from {{ ref('silver_bol_shipments') }}

),

shipment_with_norm_text as (

    select
        s.*,
        left({{ normalize_product_text('s.text') }}, 200) as normalized_text_lookup
    from source_shipments s

),

unified as (

    select
        st.* exclude (normalized_text_lookup),
        c.predicted_hs_6,
        c.classification_status,
        c.raw_response as llm_raw_response,
        coalesce(st.harmonized_number_final, c.predicted_hs_6) as hs_code_unified,
        case
            when st.harmonized_number_final is not null and st.hs_source = 'source_field' then 'source_field'
            when st.harmonized_number_final is not null and st.hs_source = 'regex_from_text' then 'regex_from_text'
            when c.classification_status in ('classified_hs6', 'classified_hs6_dotted') then 'llm_classified_hs6'
            when c.classification_status = 'classified_hs4_only' then 'llm_classified_hs4'
            when c.classification_status = 'unclassifiable' then 'llm_unclassifiable'
            when c.classification_status = 'parse_failed' then 'llm_parse_failed'
            else 'unresolved'
        end as hs_source_final,
        left(coalesce(st.harmonized_number_final, c.predicted_hs_6), 4) as hs_4_final,
        left(coalesce(st.harmonized_number_final, c.predicted_hs_6), 2) as hs_2_final
    from shipment_with_norm_text st
    left join {{ ref('int_hs_classified') }} c
        on st.normalized_text_lookup = c.product_text

)

select * from unified

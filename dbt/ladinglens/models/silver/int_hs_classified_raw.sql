{{
    config(
        materialized='incremental',
        unique_key='product_text'
    )
}}

-- LLM classification of every distinct product text against its retrieved
-- HS-6 candidates. Prompt is deliberately hardened (see rules 1-4 below)
-- after Phase 5 retrieval diagnostics showed confident-wrong candidates are
-- common on vague inputs (household goods, generic spare parts) and on
-- short/generic specific descriptions (macaroni, bare vehicle makes) --
-- similarity score alone is not a reliable confidence signal here, so the
-- LLM is explicitly told not to trust it blindly, told to refuse (999999)
-- on genuinely vague inputs, and given permission to override the
-- candidate list entirely when the description is specific enough that the
-- LLM's own knowledge beats a bad retrieval.
--
-- DO NOT --full-refresh THIS MODEL CASUALLY. Every row costs a real
-- SNOWFLAKE.CORTEX.AI_COMPLETE call (~$20 for the full ~73K population).
-- This table originated from a one-time run, then had its raw output
-- renamed into this model's identity (ALTER TABLE ... RENAME) rather than
-- being rebuilt from this file, so dbt's own history doesn't show the
-- original run. Incremental materialization means a routine `dbt build`
-- (no --full-refresh) only processes product texts that don't already have
-- a row here -- for the current static population that's zero rows, making
-- an accidental re-run a safe no-op instead of a re-bill. Only an explicit
-- --full-refresh forces real re-computation; don't pass that flag to this
-- model without deliberately intending to re-spend.
--
-- int_hs_classified.sql is the downstream parsing layer that derives
-- predicted_hs_6/classification_status from raw_response -- rebuild that
-- one freely, it's just string parsing over already-paid-for LLM output.

with candidates as (

    -- LISTAGG's delimiter must be a literal, not a function call -- CHR(10)
    -- is rejected even though it's constant. Use a placeholder delimiter
    -- and swap in the real newline afterward.
    select
        product_text,
        replace(
            listagg(
                '  Candidate ' || rank || '. HS ' || hs6 || ' (' || round(sim, 2) || '): ' || hts_description,
                '@@NL@@'
            ) within group (order by rank),
            '@@NL@@', chr(10)
        ) as candidate_block
    from {{ ref('int_hs_candidates') }}
    group by product_text

),

prompted as (

    select
        product_text,
        candidate_block,
        'You are a customs classification expert. Given a shipment product description and up to 5 candidate HS-6 codes retrieved by semantic similarity, choose the single most-likely HS-6 code.' || chr(10) ||
        chr(10) ||
        'IMPORTANT RULES:' || chr(10) ||
        '1. The retrieved candidates may be wrong or misleading, especially for short/generic descriptions. Similarity scores near 0.55-0.70 often indicate the retrieval did not find a confident match; scores above 0.80 do NOT guarantee correctness (semantic similarity is not the same as customs correctness). Read the descriptions critically.' || chr(10) ||
        '2. If the product description is too vague to classify confidently (e.g., "GENERAL CARGO", "HOUSEHOLD GOODS AND PERSONAL EFFECTS", "SUPPLIES", "SPARE PARTS" with no material/context), respond with 999999. Being conservative is better than confidently wrong.' || chr(10) ||
        '3. If none of the 5 candidates fit but the description IS specific enough to classify (e.g., "MACARONI PRODUCTS" is clearly Chapter 19 pasta, not water heaters; "STUFFED PLUSH TOYS" is Chapter 95 toys), you may respond with the correct 6-digit HS code even if it is not in the candidate list. This is called "overriding the candidates."' || chr(10) ||
        '4. Otherwise, pick the candidate that best matches the product.' || chr(10) ||
        chr(10) ||
        'Product description: ' || product_text || chr(10) ||
        chr(10) ||
        'Candidate HS codes:' || chr(10) ||
        candidate_block || chr(10) ||
        chr(10) ||
        'Respond ONLY with the 6-digit HS code (no explanation, no HS prefix, no dots). Example valid responses: 720719, 870899, 999999.' as prompt
    from candidates

)

select
    product_text,
    candidate_block,
    prompt,
    trim(snowflake.cortex.ai_complete('llama3.1-8b', prompt)) as raw_response
from prompted

{% if is_incremental() %}
where product_text not in (select product_text from {{ this }})
{% endif %}

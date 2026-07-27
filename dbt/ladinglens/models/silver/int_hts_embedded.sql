{{
    config(
        materialized='table'
    )
}}

-- Cortex embeddings for distinct HS-6 tariff descriptions, for use as the
-- retrieval side of Phase 5's retrieval-augmented HS classifier. One
-- embedding per hs6 (not per hts_number/bronze_hts row) -- multiple 8/10
-- digit HTS lines can share the same 6-digit subheading, and we only need
-- one representative description per subheading to match against.
--
-- Chapters 98/99 excluded: administrative/special-classification provisions
-- (US goods returned, USMCA/trade-program cross-references, Section 301/232
-- overlays), not product categories. Their descriptions are generic
-- cross-referencing boilerplate ("Goods provided for in note X to this
-- subchapter") that embeds deceptively close to vague product descriptions
-- like "household goods" -- confirmed via Phase 5 retrieval diagnostics,
-- where these chapters showed up as confident-wrong top candidates on
-- ambiguous inputs. Excluding them here (retrieval candidate space) rather
-- than filtering downstream, since they should never be predicted at all.

with hts_hs6 as (

    select
        hs6,
        min(hs4) as hs4,
        min(hs2) as hs2,
        min(description) as description
    from {{ ref('bronze_hts') }}
    where hs6 is not null
      and description is not null
      and hs2 not in ('98', '99')
    group by hs6

)

select
    hs6,
    hs4,
    hs2,
    description,
    snowflake.cortex.embed_text_768('e5-base-v2', description) as embedding
from hts_hs6

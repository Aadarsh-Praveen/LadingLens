{{
    config(
        materialized='table'
    )
}}

-- Score each blocked candidate pair on embedding cosine similarity + char
-- similarity (normalized edit distance). match_score blends the two;
-- match_label buckets at the agreed thresholds (0.92 match / 0.80 review).

select
    c.name_a,
    c.name_b,
    c.country_a,
    c.country_b,
    c.blocking_key,
    c.length_diff,
    vector_cosine_similarity(ea.embedding, eb.embedding) as embed_sim,
    (1.0 - editdistance(c.name_a, c.name_b) / greatest(length(c.name_a), length(c.name_b))::float) as char_sim,
    0.7 * vector_cosine_similarity(ea.embedding, eb.embedding)
        + 0.3 * (1.0 - editdistance(c.name_a, c.name_b) / greatest(length(c.name_a), length(c.name_b))::float) as match_score,
    case
        when 0.7 * vector_cosine_similarity(ea.embedding, eb.embedding)
             + 0.3 * (1.0 - editdistance(c.name_a, c.name_b) / greatest(length(c.name_a), length(c.name_b))::float) >= 0.92 then 'match'
        when 0.7 * vector_cosine_similarity(ea.embedding, eb.embedding)
             + 0.3 * (1.0 - editdistance(c.name_a, c.name_b) / greatest(length(c.name_a), length(c.name_b))::float) >= 0.80 then 'review'
        else 'no_match'
    end as match_label
from {{ ref('int_supplier_pair_candidates') }} c
inner join {{ ref('int_supplier_embedded') }} ea on c.name_a = ea.shipper_name_norm
inner join {{ ref('int_supplier_embedded') }} eb on c.name_b = eb.shipper_name_norm

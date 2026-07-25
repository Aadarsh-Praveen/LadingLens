{{
    config(
        materialized='table'
    )
}}

-- Blocked candidate pairs for consignee entity resolution. Same structure as
-- int_supplier_pair_candidates.sql -- see that model's header comment,
-- including the placeholder-exclusion rationale.

select
    a.consignee_name_norm as name_a,
    b.consignee_name_norm as name_b,
    a.consignee_registered_country as country_a,
    b.consignee_registered_country as country_b,
    a.blocking_key,
    abs(length(a.consignee_name_norm) - length(b.consignee_name_norm)) as length_diff
from {{ ref('int_consignee_name_normalized') }} a
inner join {{ ref('int_consignee_name_normalized') }} b
    on a.blocking_key = b.blocking_key
   and a.consignee_name_norm < b.consignee_name_norm
where abs(length(a.consignee_name_norm) - length(b.consignee_name_norm)) < 20
  and a.is_placeholder = false
  and b.is_placeholder = false

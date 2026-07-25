{{
    config(
        materialized='table'
    )
}}

-- Blocked candidate pairs for supplier entity resolution. Self-join within
-- the same blocking_key (name-prefix + registered country) keeps the pair
-- count tractable versus a full O(n^2) cross-join across all ~44K names.
-- a.shipper_name_norm < b.shipper_name_norm avoids self-pairs and duplicate
-- (a,b)/(b,a) pairs. Length pre-filter drops obviously non-matching pairs
-- before the more expensive embedding/edit-distance scoring in the next step.
-- Placeholder names (is_placeholder=TRUE) are excluded from pairing entirely
-- -- they're absence-of-entity markers (TO ORDER, NOTIFY PARTY, UNKNOWN,
-- etc.), not real parties, and were forming hub-node over-merges.

select
    a.shipper_name_norm as name_a,
    b.shipper_name_norm as name_b,
    a.shipper_registered_country as country_a,
    b.shipper_registered_country as country_b,
    a.blocking_key,
    abs(length(a.shipper_name_norm) - length(b.shipper_name_norm)) as length_diff
from {{ ref('int_supplier_name_normalized') }} a
inner join {{ ref('int_supplier_name_normalized') }} b
    on a.blocking_key = b.blocking_key
   and a.shipper_name_norm < b.shipper_name_norm
where abs(length(a.shipper_name_norm) - length(b.shipper_name_norm)) < 20
  and a.is_placeholder = false
  and b.is_placeholder = false

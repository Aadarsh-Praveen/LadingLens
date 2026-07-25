{{
    config(
        materialized='table'
    )
}}

-- Golden consignee records: cluster-grain aggregation of
-- int_consignee_golden_map.sql, which does the actual UDTF connected-
-- components clustering (see that model's header for partitioning/singleton/
-- country-guard rationale).
--
-- THRESHOLD-CHOICE RATIONALE (match_score >= 0.92 to auto-merge, locked
-- during Phase 4 Silver): compression ratios here are modest (~1.2x on both
-- supplier and consignee) rather than aggressive, and that's a deliberate
-- precision-over-recall choice, not an unresolved bug. Investigation of the
-- Mercedes-Benz cluster confirmed the split is a genuine threshold-boundary
-- outcome: true same-entity pairs (e.g. "mercedes benz" <-> "mercedes benz
-- usa") and true different-entity pairs (e.g. "mercedes benz" <-> "mercedes
-- medical") both land in the 0.80-0.92 review band, so there is no threshold
-- that cleanly separates them -- lowering it to catch the former necessarily
-- lets in the latter. More importantly, several of the pairs that stay split
-- are NOT false negatives at all: DHL Belgium and DHL Luxembourg, or
-- Mercedes-Benz U.S. and Mercedes-Benz Vans LLC, are the same BRAND but
-- distinct LEGAL ENTITIES. Merging same-brand-different-legal-entity pairs
-- would falsely aggregate concentration exposure across independent
-- companies -- exactly the kind of error that would corrupt downstream
-- concentration analysis, which is the whole point of this table existing.
-- 0.92 was kept as the boundary that protects that distinction, at the
-- accepted cost of some legitimate same-entity variants staying split.

select
    golden_consignee_id,
    canonical_name,
    country,
    count(distinct consignee_name_raw) as raw_name_variants_count,
    sum(shipment_count) as total_shipments,
    any_value(sample_address) as sample_address
from {{ ref('int_consignee_golden_map') }}
group by golden_consignee_id, canonical_name, country

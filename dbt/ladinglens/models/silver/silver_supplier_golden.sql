{{
    config(
        materialized='table'
    )
}}

-- Golden supplier records: cluster-grain aggregation of
-- int_supplier_golden_map.sql, which does the actual UDTF connected-
-- components clustering (see that model's header for partitioning/singleton/
-- country-guard rationale). See silver_consignee_golden.sql for the
-- 0.92/0.80 threshold-choice rationale, which applies identically here.

select
    golden_supplier_id,
    canonical_name,
    country,
    count(distinct shipper_name_raw) as raw_name_variants_count,
    sum(shipment_count) as total_shipments,
    any_value(sample_address) as sample_address
from {{ ref('int_supplier_golden_map') }}
group by golden_supplier_id, canonical_name, country

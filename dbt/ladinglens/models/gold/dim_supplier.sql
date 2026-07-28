-- silver_supplier_golden has no is_forwarder column (it was computed upstream in
-- int_supplier_name_normalized.sql but dropped during cluster-grain aggregation,
-- since it's a per-raw-name attribute and the golden table aggregates by cluster).
-- Re-derived here on canonical_name using the same is_freight_forwarder() macro
-- rather than plumbing it through the Silver aggregation.

select
    golden_supplier_id as supplier_key,
    canonical_name as supplier_name,
    country as supplier_country_code,
    raw_name_variants_count,
    total_shipments,
    {{ is_freight_forwarder('canonical_name') }} as is_forwarder,
    sample_address
from {{ ref('silver_supplier_golden') }}

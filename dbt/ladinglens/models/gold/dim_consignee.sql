-- See dim_supplier.sql for why is_forwarder is re-derived here rather than
-- sourced from silver_consignee_golden.

select
    golden_consignee_id as consignee_key,
    canonical_name as consignee_name,
    country as consignee_country_code,
    raw_name_variants_count,
    total_shipments,
    {{ is_freight_forwarder('canonical_name') }} as is_forwarder,
    sample_address
from {{ ref('silver_consignee_golden') }}

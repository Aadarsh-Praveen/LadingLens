{{
    config(
        materialized='incremental',
        unique_key='shipper_name_norm'
    )
}}

-- Cortex embeddings for distinct normalized supplier names. Embeddings are
-- metered on Cortex AI credits -- only distinct normalized names are
-- embedded (never raw BoL rows), and incremental materialization means
-- re-runs only embed names that weren't already embedded in a prior run.

select
    shipper_name_norm,
    snowflake.cortex.embed_text_768('e5-base-v2', shipper_name_norm) as embedding
from (
    select distinct shipper_name_norm
    from {{ ref('int_supplier_name_normalized') }}
    where shipper_name_norm is not null
      and length(shipper_name_norm) >= 3
) distinct_names

{% if is_incremental() %}
where shipper_name_norm not in (select shipper_name_norm from {{ this }})
{% endif %}

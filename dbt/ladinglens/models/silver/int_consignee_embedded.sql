{{
    config(
        materialized='incremental',
        unique_key='consignee_name_norm'
    )
}}

-- Cortex embeddings for distinct normalized consignee names. Same
-- incremental/distinct-names-only design as int_supplier_embedded.sql -- see
-- that model's header comment.

select
    consignee_name_norm,
    snowflake.cortex.embed_text_768('e5-base-v2', consignee_name_norm) as embedding
from (
    select distinct consignee_name_norm
    from {{ ref('int_consignee_name_normalized') }}
    where consignee_name_norm is not null
      and length(consignee_name_norm) >= 3
) distinct_names

{% if is_incremental() %}
where consignee_name_norm not in (select consignee_name_norm from {{ this }})
{% endif %}

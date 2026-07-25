{{
    config(
        materialized='table'
    )
}}

-- Distinct consignee_name values from Bronze, normalized for entity
-- resolution. Same structure as int_supplier_name_normalized.sql -- see that
-- model's header comment for the most-common-combo rationale.

with combos as (

    select
        consignee_name,
        consignee_address,
        foreign_port_of_lading,
        count(*) as combo_count
    from {{ ref('bronze_bol') }}
    where consignee_name is not null
    group by consignee_name, consignee_address, foreign_port_of_lading

),

totals as (

    select
        consignee_name,
        sum(combo_count) as shipment_count
    from combos
    group by consignee_name

),

most_common_combo as (

    select
        consignee_name,
        consignee_address,
        foreign_port_of_lading
    from combos
    qualify row_number() over (
        partition by consignee_name
        order by combo_count desc, consignee_address
    ) = 1

)

select
    t.consignee_name as consignee_name_raw,
    {{ normalize_company_name('t.consignee_name') }} as consignee_name_norm,
    c.consignee_address,
    -- Party-registered-address country (for ER blocking), NOT shipment
    -- origin -- see extract_country_from_text.sql header for the distinction.
    {{ extract_country_from_text('c.consignee_address') }} as consignee_registered_country,
    {{ is_freight_forwarder('t.consignee_name') }} as is_forwarder,
    {{ is_placeholder_name('consignee_name_norm') }} as is_placeholder,
    left({{ normalize_company_name('t.consignee_name') }}, 8) || '|' ||
        coalesce({{ extract_country_from_text('c.consignee_address') }}, 'UNK') as blocking_key,
    t.shipment_count
from totals t
inner join most_common_combo c on t.consignee_name = c.consignee_name

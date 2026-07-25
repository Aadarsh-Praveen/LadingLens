{{
    config(
        materialized='table'
    )
}}

-- Distinct shipper_party_name values from Bronze, normalized for entity
-- resolution. Country is derived from shipper_address ONLY (no port
-- fallback -- see extract_country_from_text.sql header for why). Since the
-- same raw name can appear with more than one address/port combination, the
-- most frequent combination per name is used. blocking_key groups likely-
-- same-entity names together for the pairwise ER scoring in later steps;
-- rows with no derivable country fall into an 'UNK' block, handled by
-- embedding similarity alone at the ER stage.

with combos as (

    select
        shipper_party_name as shipper_name_raw,
        shipper_address,
        foreign_port_of_lading,
        count(*) as combo_count
    from {{ ref('bronze_bol') }}
    where shipper_party_name is not null
    group by shipper_party_name, shipper_address, foreign_port_of_lading

),

totals as (

    select
        shipper_name_raw,
        sum(combo_count) as shipment_count
    from combos
    group by shipper_name_raw

),

most_common_combo as (

    select
        shipper_name_raw,
        shipper_address,
        foreign_port_of_lading
    from combos
    qualify row_number() over (
        partition by shipper_name_raw
        order by combo_count desc, shipper_address
    ) = 1

)

select
    t.shipper_name_raw,
    {{ normalize_company_name('t.shipper_name_raw') }} as shipper_name_norm,
    c.shipper_address,
    -- Party-registered-address country (for ER blocking), NOT shipment
    -- origin -- see extract_country_from_text.sql header for the distinction.
    {{ extract_country_from_text('c.shipper_address') }} as shipper_registered_country,
    {{ is_freight_forwarder('t.shipper_name_raw') }} as is_forwarder,
    {{ is_placeholder_name('shipper_name_norm') }} as is_placeholder,
    left({{ normalize_company_name('t.shipper_name_raw') }}, 8) || '|' ||
        coalesce({{ extract_country_from_text('c.shipper_address') }}, 'UNK') as blocking_key,
    t.shipment_count
from totals t
inner join most_common_combo c on t.shipper_name_raw = c.shipper_name_raw

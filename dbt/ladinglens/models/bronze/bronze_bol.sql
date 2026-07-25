{{
    config(
        materialized='table'
    )
}}

-- Bronze: typed, sentinel-filtered, HS-enriched BOL_SHIPMENTS.
--
-- SENTINEL IDENTIFIER FILTER: three distinct sentinel-identifier families
-- were found in the NIST FEIII 2019 sample via iterative filter refinement
-- (Phase 4). Combined they account for ~78.7% of raw rows -- placeholder
-- identifiers assigned when a real BoL number was missing/redacted, not
-- genuine per-shipment keys. Phase 3 EDA's initial 36.2% estimate (a
-- divisibility-by-10^8 heuristic) caught only one of the three families. The
-- shape-based regex here ('^[1-9][0-9]{0,5}0{6,}$': a short non-zero prefix
-- followed by 6+ trailing zeros) catches all three cleanly, verified via
-- spot-check against both known sentinel values (correctly dropped) and
-- known real high-line-count BoLs like 2018010397391 (correctly kept --
-- these are genuine multi-container shipments with hundreds of line items,
-- not sentinels; an earlier round mistakenly treated them as sentinels and
-- introduced a compound content-key dedup to compensate, which was wrong and
-- has been reverted below).
--
-- DEDUP KEY: (identifier, container_number), NOT description_sequence_number.
-- Empirically verified on the worst-case group (identifier 2018040647536):
-- description_sequence_number stayed at 1 across 28 genuinely distinct
-- containers on the same BoL, so keying on it collapsed 28 containers into 1
-- row. container_number correctly distinguishes them, and is 100% populated
-- on sentinel-filtered rows (no fallback key needed). The ~47x repetition
-- within a single container is exact-duplicate raw-file repetition (same
-- date, status, HS code and text every time), safe to collapse with any
-- ORDER BY.
--
-- HS-FROM-TEXT EXTRACTION: for rows with no structured harmonized_number,
-- regex-extract an HS-like code from the free-text `text` field when it
-- explicitly says "HS CODE" (Phase 3 found this recovers coverage from 42.4%
-- toward ~56%).

with source as (

    select
        identifier,
        trade_update_date,
        run_date,
        vessel_name,
        port_of_unlading,
        estimated_arrival_date,
        foreign_port_of_lading,
        record_status_indicator,
        place_of_receipt,
        port_of_destination,
        foreign_port_of_destination,
        secondary_notify_party_1,
        actual_arrival_date,
        consignee_name,
        consignee_address,
        consignee_contact_name,
        consignee_comm_number_qualifier,
        consignee_comm_number,
        shipper_party_name,
        shipper_address,
        shipper_contact_name,
        shipper_comm_number_qualifier,
        shipper_comm_number,
        container_number,
        cast(description_sequence_number as number) as description_sequence_number,
        cast(piece_count as number) as piece_count,
        text,
        harmonized_number,
        cast(harmonized_value as number) as harmonized_value,
        cast(harmonized_weight as number) as harmonized_weight,
        harmonized_weight_unit,
        identified_orgs,
        ingested_at
    from {{ source('raw', 'bol_shipments') }}

),

sentinel_filtered as (

    select *
    from source
    where not (
        identifier is null
        or identifier = 0
        or regexp_like(to_varchar(identifier), '^[1-9][0-9]{0,5}0{6,}$')  -- short non-zero prefix + 6-or-more trailing zeros
    )
    and container_number is not null
    and trim(container_number) != ''

),

deduped as (

    select *
    from sentinel_filtered
    qualify row_number() over (
        partition by identifier, container_number
        order by trade_update_date desc
    ) = 1

)

select
    identifier,
    trade_update_date,
    run_date,
    vessel_name,
    port_of_unlading,
    estimated_arrival_date,
    foreign_port_of_lading,
    record_status_indicator,
    place_of_receipt,
    port_of_destination,
    foreign_port_of_destination,
    secondary_notify_party_1,
    actual_arrival_date,
    consignee_name,
    consignee_address,
    consignee_contact_name,
    consignee_comm_number_qualifier,
    consignee_comm_number,
    shipper_party_name,
    shipper_address,
    shipper_contact_name,
    shipper_comm_number_qualifier,
    shipper_comm_number,
    container_number,
    description_sequence_number,
    piece_count,
    text,
    harmonized_number,
    harmonized_value,
    harmonized_weight,
    harmonized_weight_unit,
    identified_orgs,
    case
        when harmonized_number is not null and harmonized_number != '' then harmonized_number
        when regexp_like(text, '.*HS[- ]?CODE:?\\s*[0-9]{4}\\.?[0-9]{2}.*', 'i')
            then regexp_substr(text, '[0-9]{4}\\.?[0-9]{2}', 1, 1, 'i')
        else null
    end as harmonized_number_final,
    case
        when harmonized_number is not null and harmonized_number != '' then 'source_field'
        when regexp_like(text, '.*HS[- ]?CODE:?\\s*[0-9]{4}\\.?[0-9]{2}.*', 'i') then 'regex_from_text'
        else null
    end as hs_source,
    ingested_at
from deduped

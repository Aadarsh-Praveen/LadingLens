{{
    config(
        materialized='table'
    )
}}

-- Final scoped fact-ready Silver table: bronze_bol shipments joined to
-- golden supplier/consignee entities, filtered to config/target_scope.yml's
-- HS chapters (87/84/39/61/62/73 -- vehicles, machinery, plastics, apparel,
-- steel) and origin countries (DE/BE/VN/ES/GB/FR/MX/CN).
--
-- Joins to the raw-name-grain golden maps (int_supplier_golden_map /
-- int_consignee_golden_map), not the cluster-grain golden tables, since
-- those are the only models keyed on the raw name string that appears on
-- each bronze_bol row. INNER JOIN is deliberate: a row with a NULL or
-- unmatched party name has no golden ID and isn't useful for entity-level
-- concentration analysis, so it's excluded here rather than carried as an
-- orphan FK -- this also means "no orphan golden_supplier_id/
-- golden_consignee_id" holds by construction, not just by convention.
--
-- shipment_origin_country is derived from foreign_port_of_lading, NOT
-- shipper/consignee address -- see extract_country_from_text.sql's header
-- for why "what country is this port in" and "what country is this party
-- registered in" are different questions answered by different logic. This
-- dataset's foreign_port_of_lading is formatted "City,Country" with the
-- country spelled out in full (verified directly against the data), so a
-- literal country-name match is reliable here. The same SPAIN-vs-Trinidad's
-- "Port of Spain" guard from extract_country_from_text is reused since
-- "Port of Spain,Trinidad" is a real value in this field.

with scoped as (

    select
        b.*,
        left(b.harmonized_number_final, 2) as hs_chapter,
        case
            when upper(b.foreign_port_of_lading) like '%GERMANY%' then 'DE'
            when upper(b.foreign_port_of_lading) like '%BELGIUM%' then 'BE'
            when upper(b.foreign_port_of_lading) like '%VIETNAM%' then 'VN'
            when upper(b.foreign_port_of_lading) like '%SPAIN%'
             and upper(b.foreign_port_of_lading) not like '%PORT OF SPAIN%'
             and upper(b.foreign_port_of_lading) not like '%TRINIDAD%' then 'ES'
            when upper(b.foreign_port_of_lading) like '%UNITED KINGDOM%'
              or upper(b.foreign_port_of_lading) like '%ENGLAND%'
              or upper(b.foreign_port_of_lading) like '%SCOTLAND%'
              or upper(b.foreign_port_of_lading) like '%WALES%' then 'GB'
            when upper(b.foreign_port_of_lading) like '%FRANCE%' then 'FR'
            when upper(b.foreign_port_of_lading) like '%MEXICO%' then 'MX'
            when upper(b.foreign_port_of_lading) like '%CHINA%' then 'CN'
            else null
        end as shipment_origin_country
    from {{ ref('bronze_bol') }} b

)

select
    s.identifier,
    s.container_number,
    s.trade_update_date,
    s.description_sequence_number,
    s.piece_count,
    s.harmonized_number_final,
    s.hs_source,
    s.hs_chapter,
    s.harmonized_value,
    s.harmonized_weight,
    s.harmonized_weight_unit,
    s.shipment_origin_country,
    s.foreign_port_of_lading,
    s.shipper_party_name,
    sup.golden_supplier_id,
    sup.canonical_name as supplier_canonical_name,
    sup.country as supplier_registered_country,
    s.consignee_name,
    con.golden_consignee_id,
    con.canonical_name as consignee_canonical_name,
    con.country as consignee_registered_country,
    case when con.is_forwarder then 'freight_forwarder' else 'importer' end as consignee_party_type,
    s.identified_orgs,
    s.ingested_at
from scoped s
inner join {{ ref('int_supplier_golden_map') }} sup on s.shipper_party_name = sup.shipper_name_raw
inner join {{ ref('int_consignee_golden_map') }} con on s.consignee_name = con.consignee_name_raw
where s.hs_chapter in ('87', '84', '39', '61', '62', '73')
  and s.shipment_origin_country in ('DE', 'BE', 'VN', 'ES', 'GB', 'FR', 'MX', 'CN')

-- Grain: one row per silver_bol_shipments_scoped row (89,200 shipments).
--
-- Column substitutions from the ideal spec (see Step 0 recon, data/sources.md
-- Phase 6 wrap for the full list):
--   - date_key sourced from trade_update_date (no actual_arrival_date column
--     exists anywhere in the pipeline -- this is CBP's last record-update date,
--     not literal vessel arrival).
--   - weight_kg derived from harmonized_weight + harmonized_weight_unit, converting
--     Pounds to kg explicitly (x 0.453592 lb->kg) rather than assuming the column is
--     already in kg. harmonized_weight_unit is NULL for a meaningful share of
--     populated-weight rows (6,585 of 40,592) -- those are left as raw, unit-
--     unconfirmed values rather than silently mislabeled.
--   - shipment_value_usd = harmonized_value (no _usd suffix on the source column;
--     no separate currency column exists, so USD is assumed per CBP filing
--     convention, not independently verified here).
--   - weight and value are both NULL for the same 48,608 of 89,200 rows (54.5%) --
--     this is the majority of the scoped population, not a minority edge case, so
--     estimated_landed_cost_usd is NULL for the same rows (see checkpoint report).
--   - piece_count maps 1:1, no substitution needed.
--   - teu has no substitute anywhere in Bronze/Silver/raw ingest and is omitted.
--
-- effective_duty_rate_pct / estimated_landed_cost_usd reflect the CURRENT (Q3 2026)
-- tariff regime only -- dim_country.is_section_232_target / is_section_301_target
-- and dim_hs_code's rate columns are static, not date-conditioned against
-- fact_tariff_events. Time-varying scenario logic is deferred to Phase 8.
--
-- hs_6 join key: hs_code_unified is NOT uniformly 6-digit-clean. regex_from_text
-- rows keep a literal dot (e.g. '8432.90'), and source_field rows carry the raw
-- harmonized_number_final precision (6/7/8/9/10 digits, straight off the CBP
-- manifest). Stripping dots then taking the first 6 digits recovers a clean HS-6
-- for the well-formed majority. It does NOT fully close the gap: ~3,265
-- llm_classified_hs4 rows are hs4-padded with '00' (the classifier only reached
-- HS4 confidence) and a residual handful of source_field rows have odd digit
-- counts (7 or 9) from upstream manifest corruption predating Phase 6 -- both
-- are real, quantified gaps against dim_hs_code, not a Phase 6 join bug. See
-- gold/schema.yml and data/sources.md for the exact counts.

with shipments as (

    select
        s.identifier,
        s.container_number,
        s.trade_update_date,
        s.golden_supplier_id,
        s.golden_consignee_id,
        left(replace(s.hs_code_unified, '.', ''), 6) as hs_6,
        s.shipment_origin_country,
        s.harmonized_value,
        s.harmonized_weight,
        s.harmonized_weight_unit,
        s.piece_count,
        s.hs_source_final,
        s.consignee_party_type
    from {{ ref('silver_bol_shipments_scoped') }} s

),

enriched as (

    select
        md5(shipments.identifier::varchar || '|' || shipments.container_number) as shipment_key,
        shipments.identifier as bol_identifier,
        shipments.container_number,
        shipments.trade_update_date as date_key,
        shipments.golden_supplier_id as supplier_key,
        shipments.golden_consignee_id as consignee_key,
        shipments.hs_6,
        shipments.shipment_origin_country as origin_country_code,
        case
            when shipments.harmonized_weight is null then null
            when upper(shipments.harmonized_weight_unit) = 'POUNDS' then shipments.harmonized_weight * 0.453592
            else shipments.harmonized_weight  -- 'Kilograms' or unit unconfirmed (NULL)
        end as weight_kg,
        shipments.harmonized_value as shipment_value_usd,
        shipments.piece_count,
        shipments.hs_source_final,
        shipments.consignee_party_type,
        d.general_duty_rate_pct,
        d.section_232_rate_pct,
        d.section_301_rate_pct,
        c.is_section_232_target,
        c.is_section_301_target
    from shipments
    left join {{ ref('dim_hs_code') }} d on shipments.hs_6 = d.hs_6
    left join {{ ref('dim_country') }} c on shipments.shipment_origin_country = c.country_code

)

select
    shipment_key,
    bol_identifier,
    container_number,
    date_key,
    supplier_key,
    consignee_key,
    hs_6,
    origin_country_code,
    weight_kg,
    shipment_value_usd,
    piece_count,
    hs_source_final,
    consignee_party_type,
    general_duty_rate_pct,
    section_232_rate_pct,
    section_301_rate_pct,
    (
        coalesce(general_duty_rate_pct, 0)
        + case when is_section_232_target then coalesce(section_232_rate_pct, 0) else 0 end
        + case when is_section_301_target then coalesce(section_301_rate_pct, 0) else 0 end
    ) as effective_duty_rate_pct,
    case
        when shipment_value_usd is not null then
            shipment_value_usd * (1 + (
                coalesce(general_duty_rate_pct, 0)
                + case when is_section_232_target then coalesce(section_232_rate_pct, 0) else 0 end
                + case when is_section_301_target then coalesce(section_301_rate_pct, 0) else 0 end
            ) / 100.0)
        else null
    end as estimated_landed_cost_usd
from enriched

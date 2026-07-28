-- Pre-computed HHI (0-1 fractional scale -- share squared, so a 0.4 share
-- contributes 0.16 to the sum; multiply by 10,000 for the conventional
-- DOJ/FTC economist scale) per (consignee, hs_6) pair.
--
-- Pivoted to shipment-COUNT-based shares rather than weight-based, per the
-- spec's own fallback instruction: fact_shipments.weight_kg is NULL for 48,608
-- of 89,200 rows (54.5%, the majority, not a minority edge case -- see
-- fact_shipments.sql header). A weight-based HHI would silently drop over half
-- the population from every consignee's concentration picture. Shipment count
-- is available for all 89,200 rows, so it drives supplier_share/country_share/
-- supplier_hhi/country_hhi/is_single_source/is_single_country here.
-- total_weight_kg and total_landed_cost_usd are carried through as informational
-- sums (NULL-safe SUM over whatever subset has weight/value data) but do not
-- feed the concentration math.

with consignee_hs_supplier as (

    select
        consignee_key,
        hs_6,
        supplier_key,
        origin_country_code,
        count(*) as supplier_shipment_count,
        sum(weight_kg) as supplier_weight_kg,
        sum(estimated_landed_cost_usd) as supplier_landed_cost_usd
    from {{ ref('fact_shipments') }}
    group by 1, 2, 3, 4

),

consignee_hs_totals as (

    select
        consignee_key,
        hs_6,
        sum(supplier_shipment_count) as total_shipment_count,
        sum(supplier_weight_kg) as total_weight_kg,
        sum(supplier_landed_cost_usd) as total_landed_cost_usd,
        count(distinct supplier_key) as supplier_count,
        count(distinct origin_country_code) as country_count
    from consignee_hs_supplier
    group by 1, 2

),

supplier_shares as (

    select
        chs.consignee_key,
        chs.hs_6,
        chs.supplier_key,
        chs.supplier_shipment_count * 1.0 / cht.total_shipment_count as supplier_share
    from consignee_hs_supplier chs
    join consignee_hs_totals cht using (consignee_key, hs_6)

),

country_shares as (

    select
        chs.consignee_key,
        chs.hs_6,
        chs.origin_country_code,
        sum(chs.supplier_shipment_count) * 1.0 / max(cht.total_shipment_count) as country_share
    from consignee_hs_supplier chs
    join consignee_hs_totals cht using (consignee_key, hs_6)
    group by 1, 2, 3

),

supplier_hhi as (

    select
        consignee_key,
        hs_6,
        sum(power(supplier_share, 2)) as supplier_hhi,
        max(supplier_share) as top_supplier_share
    from supplier_shares
    group by 1, 2

),

country_hhi as (

    select
        consignee_key,
        hs_6,
        sum(power(country_share, 2)) as country_hhi,
        max(country_share) as top_country_share
    from country_shares
    group by 1, 2

)

select
    t.consignee_key,
    t.hs_6,
    t.supplier_count,
    t.country_count,
    t.total_shipment_count,
    t.total_weight_kg,
    t.total_landed_cost_usd,
    sh.supplier_hhi,
    sh.top_supplier_share,
    ch.country_hhi,
    ch.top_country_share,
    case when sh.top_supplier_share > 0.70 then true else false end as is_single_source,
    case when ch.top_country_share > 0.70 then true else false end as is_single_country
from consignee_hs_totals t
join supplier_hhi sh using (consignee_key, hs_6)
join country_hhi ch using (consignee_key, hs_6)

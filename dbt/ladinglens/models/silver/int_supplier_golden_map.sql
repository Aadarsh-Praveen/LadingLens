{{
    config(
        materialized='table'
    )
}}

-- Raw-name-grain bridge from every supplier raw name to its golden cluster
-- assignment. This is the single place the CLUSTER_MATCHES UDTF connected-
-- components pass runs for suppliers -- silver_supplier_golden.sql
-- aggregates this to cluster grain for reporting, and silver_bol_shipments.sql
-- joins directly on shipper_name_raw to attach golden_supplier_id to each
-- shipment. Splitting it out this way means the clustering logic exists in
-- exactly one place; duplicating the UDTF call in both downstream models
-- would risk them silently drifting out of sync on a future edit.
--
-- See silver_supplier_golden.sql for the UDTF partitioning, singleton
-- handling, and country-guard rationale -- unchanged here, just relocated.

with matched_edges as (

    select
        name_a,
        name_b,
        1 as grp
    from {{ ref('int_supplier_pair_scored') }}
    where match_label = 'match'

),

cluster_pairs as (

    select
        ct.name as shipper_name_norm,
        ct.canonical as cluster_key
    from matched_edges e,
    table({{ target.database }}.silver.cluster_matches(e.name_a, e.name_b) over (partition by e.grp)) ct

),

all_names as (

    select distinct shipper_name_norm
    from {{ ref('int_supplier_name_normalized') }}
    where shipper_name_norm is not null

),

assignments as (

    -- singletons fall back to their own normalized name as cluster_key
    select
        a.shipper_name_norm,
        coalesce(cp.cluster_key, a.shipper_name_norm) as cluster_key
    from all_names a
    left join cluster_pairs cp on a.shipper_name_norm = cp.shipper_name_norm

),

member_detail as (

    -- fans out from normalized-name-level clusters back to raw-name grain,
    -- since raw_name_variants_count and total_shipments must be counted at
    -- the raw-name level (the same normalized name can already collapse
    -- multiple raw spellings before clustering ever runs)
    select
        asg.cluster_key,
        n.shipper_name_raw,
        n.shipper_name_norm,
        n.shipper_address,
        n.shipper_registered_country,
        n.is_forwarder,
        n.is_placeholder,
        n.shipment_count
    from assignments asg
    inner join {{ ref('int_supplier_name_normalized') }} n
        on asg.shipper_name_norm = n.shipper_name_norm

),

cluster_country as (

    -- blocking_key already restricts matched edges to one country per
    -- cluster, but a normalized name can carry raw variants from more than
    -- one registered country pre-clustering (different address, ambiguous
    -- derivation) -- pick the shipment-weighted majority as a guard.
    select cluster_key, shipper_registered_country as country
    from (
        select
            cluster_key,
            shipper_registered_country,
            sum(shipment_count) as country_shipments,
            row_number() over (
                partition by cluster_key
                order by sum(shipment_count) desc, shipper_registered_country
            ) as rn
        from member_detail
        group by cluster_key, shipper_registered_country
    )
    where rn = 1

),

representative as (

    -- most-shipped raw name variant stands in as the human-readable
    -- canonical_name and supplies the sample address for the cluster
    select cluster_key, shipper_name_raw as canonical_name, shipper_address as sample_address
    from (
        select
            cluster_key,
            shipper_name_raw,
            shipper_address,
            row_number() over (
                partition by cluster_key
                order by shipment_count desc, shipper_name_raw
            ) as rn
        from member_detail
    )
    where rn = 1

)

select
    md.shipper_name_raw,
    md.shipper_name_norm,
    md.cluster_key,
    md5(r.canonical_name || '|' || coalesce(cc.country, 'UNK')) as golden_supplier_id,
    r.canonical_name,
    cc.country,
    r.sample_address,
    md.is_forwarder,
    md.is_placeholder,
    md.shipment_count
from member_detail md
inner join representative r on md.cluster_key = r.cluster_key
inner join cluster_country cc on md.cluster_key = cc.cluster_key

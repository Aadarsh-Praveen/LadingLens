{{
    config(
        materialized='table'
    )
}}

-- Raw-name-grain bridge from every consignee raw name to its golden cluster
-- assignment. Same structure and rationale as int_supplier_golden_map.sql --
-- see that model's header comment.

with matched_edges as (

    select
        name_a,
        name_b,
        1 as grp
    from {{ ref('int_consignee_pair_scored') }}
    where match_label = 'match'

),

cluster_pairs as (

    select
        ct.name as consignee_name_norm,
        ct.canonical as cluster_key
    from matched_edges e,
    table({{ target.database }}.silver.cluster_matches(e.name_a, e.name_b) over (partition by e.grp)) ct

),

all_names as (

    select distinct consignee_name_norm
    from {{ ref('int_consignee_name_normalized') }}
    where consignee_name_norm is not null

),

assignments as (

    select
        a.consignee_name_norm,
        coalesce(cp.cluster_key, a.consignee_name_norm) as cluster_key
    from all_names a
    left join cluster_pairs cp on a.consignee_name_norm = cp.consignee_name_norm

),

member_detail as (

    select
        asg.cluster_key,
        n.consignee_name_raw,
        n.consignee_name_norm,
        n.consignee_address,
        n.consignee_registered_country,
        n.is_forwarder,
        n.is_placeholder,
        n.shipment_count
    from assignments asg
    inner join {{ ref('int_consignee_name_normalized') }} n
        on asg.consignee_name_norm = n.consignee_name_norm

),

cluster_country as (

    select cluster_key, consignee_registered_country as country
    from (
        select
            cluster_key,
            consignee_registered_country,
            sum(shipment_count) as country_shipments,
            row_number() over (
                partition by cluster_key
                order by sum(shipment_count) desc, consignee_registered_country
            ) as rn
        from member_detail
        group by cluster_key, consignee_registered_country
    )
    where rn = 1

),

representative as (

    select cluster_key, consignee_name_raw as canonical_name, consignee_address as sample_address
    from (
        select
            cluster_key,
            consignee_name_raw,
            consignee_address,
            row_number() over (
                partition by cluster_key
                order by shipment_count desc, consignee_name_raw
            ) as rn
        from member_detail
    )
    where rn = 1

)

select
    md.consignee_name_raw,
    md.consignee_name_norm,
    md.cluster_key,
    md5(r.canonical_name || '|' || coalesce(cc.country, 'UNK')) as golden_consignee_id,
    r.canonical_name,
    cc.country,
    r.sample_address,
    md.is_forwarder,
    md.is_placeholder,
    md.shipment_count
from member_detail md
inner join representative r on md.cluster_key = r.cluster_key
inner join cluster_country cc on md.cluster_key = cc.cluster_key

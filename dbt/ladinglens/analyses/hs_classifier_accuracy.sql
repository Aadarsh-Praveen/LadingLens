-- Evaluates the Phase 5 HS classifier (unified hs_code_unified) against
-- hs_eval_seed_v2 -- 30 rows sampled directly from silver_bol_shipments_
-- scoped's LLM-classified rows and hand-labeled against USITC HS-6
-- descriptions. Replaces the original hs_eval_seed: that seed's
-- product_description values didn't appear verbatim in Bronze for most
-- rows (only 12 of 30 matched anywhere in the full unscoped table), so no
-- join strategy could reliably evaluate more than half of it -- see
-- data/sources.md for the full history.
--
-- v2's product_text is copied verbatim from silver_bol_shipments_
-- classified.text at sampling time, so the join is a plain equality, not a
-- fuzzy LIKE match -- there's no formatting drift to compensate for and no
-- fan-out risk (each seed row's exact text should match itself, at most a
-- handful of shipments sharing byte-identical raw text).

with seed as (

    select
        product_text,
        correct_hs_6,
        left(correct_hs_6, 4) as correct_hs_4,
        left(correct_hs_6, 2) as correct_hs_2
    from {{ ref('hs_eval_seed_v2') }}

),

matched as (

    select
        s.product_text,
        s.correct_hs_6, s.correct_hs_4, s.correct_hs_2,
        c.hs_code_unified as predicted_hs_6,
        left(c.hs_code_unified, 4) as predicted_hs_4,
        left(c.hs_code_unified, 2) as predicted_hs_2
    from seed s
    left join {{ ref('silver_bol_shipments_classified') }} c
        on s.product_text = c.text

),

joined as (

    -- a handful of seed rows may match >1 shipment row sharing identical
    -- raw text; since they share the same text they necessarily share the
    -- same hs_code_unified, so dedup by seed row without needing a mode/
    -- majority-vote step.
    select distinct
        product_text, correct_hs_6, correct_hs_4, correct_hs_2,
        predicted_hs_6, predicted_hs_4, predicted_hs_2
    from matched

)

select
    count(*) as total_seed_rows,
    count(predicted_hs_6) as matched_seed_rows,

    sum(case when correct_hs_6 = predicted_hs_6 then 1 else 0 end) as exact_hs6_matches,
    sum(case when correct_hs_4 = predicted_hs_4 then 1 else 0 end) as hs4_matches,
    sum(case when correct_hs_2 = predicted_hs_2 then 1 else 0 end) as hs2_matches,

    sum(case when correct_hs_6 != '999999' and correct_hs_6 = predicted_hs_6 then 1 else 0 end) as clean_hs6_matches,
    sum(case when correct_hs_6 != '999999' then 1 else 0 end) as clean_total,

    sum(case when correct_hs_6 = '999999' and predicted_hs_6 = '999999' then 1 else 0 end) as correct_refusals,
    sum(case when correct_hs_6 = '999999' then 1 else 0 end) as total_ambiguous_seed_rows,

    round(100.0 * sum(case when correct_hs_6 = predicted_hs_6 then 1 else 0 end) / count(*), 1) as overall_hs6_pct,
    round(100.0 * sum(case when correct_hs_4 = predicted_hs_4 then 1 else 0 end) / count(*), 1) as overall_hs4_pct,
    round(100.0 * sum(case when correct_hs_2 = predicted_hs_2 then 1 else 0 end) / count(*), 1) as overall_hs2_pct
from joined

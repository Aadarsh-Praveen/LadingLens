-- ER evaluation: pairwise-agreement precision/recall/F1 of our
-- golden_consignee_id assignment against NIST's identified_orgs label, on
-- the subset of silver_bol_shipments rows where identified_orgs is
-- populated (~19% of raw BoL, much smaller once joined through the
-- HS/origin-scoped silver_bol_shipments table).
--
-- Pairwise-agreement framing (not exact-match): two labeled rows are a
-- "positive" pair under NIST if they share the same identified_orgs token,
-- and a "positive" pair under ours if they share the same
-- golden_consignee_id. This is the standard way to score a clustering
-- against a reference clustering without requiring the cluster labels
-- themselves to match syntactically (identified_orgs is a short token like
-- "BMW", ours is a full canonical name -- see caveat 1 below).
--
-- pair_universe restricts to pairs that are positive under EITHER side
-- (same our_id OR same nist_label), not the full n^2 cross-product of all
-- labeled rows. This keeps the self-join tractable and is the correct
-- universe for this metric: true negatives (pairs that both sides agree
-- are different entities) are the overwhelming majority of all possible
-- pairs and would swamp precision/recall with an uninformative constant if
-- included -- pairwise F1 for clustering evaluation is conventionally
-- computed over exactly this restricted universe.
--
-- CAVEATS (read before trusting the number):
-- 1. identified_orgs is short-form (often just "BMW" or "MERCEDES"), not a
--    full company name. nist_positive = "same short token" is therefore a
--    BROADER equivalence than our golden IDs necessarily reflect -- e.g. if
--    NIST tags both "BMW MANUFACTURING CORP" and "BMW AG" rows as "BMW",
--    that's one NIST-positive pair regardless of whether those two are
--    genuinely the same legal entity. This can inflate false_negative for
--    correct, conservative under-merges (see the locked-threshold rationale
--    in silver_consignee_golden.sql -- the same brand/legal-entity
--    distinction that keeps Mercedes-Benz USA and Mercedes-Benz Vans split
--    would read as a "miss" here even though it's the intended behavior).
-- 2. This F1 is measured on the blocking-selected candidate pool AND the
--    labeled subset -- not the full universe of possible pairs. Real ER
--    systems report both blocking-recall (did the true match even reach the
--    candidate-pair stage) and match-precision (did we call it correctly
--    once it did) as separate numbers; this single F1 conflates both,
--    computed only on rows that survived scope filtering into
--    silver_bol_shipments.
-- 3. If a raw BoL row has identified_orgs='BMW' and its golden_consignee_id
--    canonical_name is 'BMW MANUFACTURING CORP', that's still a correct
--    pairwise agreement as long as every row NIST tags 'BMW' shares our
--    golden_consignee_id -- token-vs-full-name text mismatch doesn't matter
--    to this metric, only cluster-membership agreement does.

with labeled as (

    select
        s.golden_consignee_id as our_id,
        b.identified_orgs as nist_label,
        s.identifier,
        s.container_number
    from {{ ref('silver_bol_shipments') }} s
    inner join {{ ref('bronze_bol') }} b
        on s.identifier = b.identifier
       and s.container_number = b.container_number
    where b.identified_orgs is not null

),

pair_universe as (

    select
        a.our_id as our_id_a,
        b.our_id as our_id_b,
        a.nist_label as nist_a,
        b.nist_label as nist_b
    from labeled a
    inner join labeled b
        on a.identifier < b.identifier
       and (a.our_id = b.our_id or a.nist_label = b.nist_label)

),

classified as (

    select
        case when nist_a = nist_b then 'nist_positive' else 'nist_negative' end as nist_verdict,
        case when our_id_a = our_id_b then 'our_positive' else 'our_negative' end as our_verdict
    from pair_universe

),

contingency as (

    select nist_verdict, our_verdict, count(*) as n_pairs
    from classified
    group by 1, 2

),

metrics as (

    select
        sum(case when nist_verdict = 'nist_positive' and our_verdict = 'our_positive' then n_pairs else 0 end) as true_positive,
        sum(case when nist_verdict = 'nist_negative' and our_verdict = 'our_positive' then n_pairs else 0 end) as false_positive,
        sum(case when nist_verdict = 'nist_positive' and our_verdict = 'our_negative' then n_pairs else 0 end) as false_negative,
        sum(case when nist_verdict = 'nist_negative' and our_verdict = 'our_negative' then n_pairs else 0 end) as true_negative,
        sum(n_pairs) as total_pairs
    from contingency

)

select
    true_positive,
    false_positive,
    false_negative,
    true_negative,
    total_pairs,
    true_positive / nullif(true_positive + false_positive, 0) as precision,
    true_positive / nullif(true_positive + false_negative, 0) as recall,
    2 * (true_positive / nullif(true_positive + false_positive, 0))
      * (true_positive / nullif(true_positive + false_negative, 0))
      / nullif(
          (true_positive / nullif(true_positive + false_positive, 0))
          + (true_positive / nullif(true_positive + false_negative, 0)),
          0
        ) as f1
from metrics

-- Singular test: replaces the originally-proposed `delta_usd > 0` test, which
-- was tautological -- mart_scenario_examples's own build query already
-- filters to delta_usd > 0, so that test could never fail by construction.
--
-- This instead asserts real UDF/procedure arithmetic on a known-good anchor
-- row: BMW MANUFACTURING CORP under "S232 doubles globally" for HS chapter 73
-- (steel) from Germany, which should show scenario_duty_rate_pct exactly
-- 25.0 percentage points above baseline_duty_rate_pct (the scenario's
-- additional_rate_pp). Caterpillar was the anchor originally proposed, but
-- CAT is not in the top-20-by-shipment-count consignee list this mart is
-- built from, so isn't present here -- BMW is the closest available
-- like-for-like substitute (same scenario, same HS chapter, same country).
-- CAT's own arithmetic was independently verified via direct CALL in Step 1.
--
-- Fails (returns a row) if the anchor row is missing OR its rate delta is
-- not exactly 25.0 -- catching a UDF arithmetic regression (this exact bug
-- class was caught and fixed once already during Phase 8: an earlier version
-- recomputed landed cost from an averaged rate instead of adding the
-- increment to the true baseline, producing wrong deltas even on matching
-- rows, not just phantom deltas on non-matching ones).

with anchor as (

    select scenario_duty_rate_pct, baseline_duty_rate_pct
    from {{ source('gold_external', 'mart_scenario_examples') }}
    where consignee_name = 'BMW MANUFACTURING CORP'
      and scenario_name = 'S232 doubles globally'
      and hs_chapter = '73'
      and origin_country = 'DE'

)

select *
from anchor
where scenario_duty_rate_pct - baseline_duty_rate_pct != 25.0

union all

select null, null
where (select count(*) from anchor) = 0

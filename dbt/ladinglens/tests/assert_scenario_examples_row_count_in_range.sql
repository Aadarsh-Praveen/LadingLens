-- Singular test: mart_scenario_examples row count sanity bound. The original
-- Phase 8 spec targeted 100-500 rows; the real, verified-correct count is 24
-- (see _gold_external_sources.yml for the full explanation: a since-fixed
-- arithmetic bug inflated an earlier build to 98 via phantom deltas, and only
-- 3 of 5 canonical scenarios have any representation in the top-20-consignee
-- population at all). Range set around the real number, wide enough to
-- tolerate a re-run picking up new shipment data without masking a real
-- regression (e.g. the mart coming back empty, or ballooning past a couple
-- hundred rows, which would suggest the arithmetic bug returned).

select count(*) as actual_row_count
from {{ source('gold_external', 'mart_scenario_examples') }}
having count(*) not between 10 and 200

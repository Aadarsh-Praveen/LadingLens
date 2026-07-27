-- Singular test: silver_bol_shipments_classified must have the exact same
-- row count as silver_bol_shipments (it's a 1:1 enrichment, not a filter).
-- dbt singular tests fail when the query returns any rows, so this returns
-- one row (with both counts) only when they differ.

with base as (
    select count(*) as n from {{ ref('silver_bol_shipments') }}
),
classified as (
    select count(*) as n from {{ ref('silver_bol_shipments_classified') }}
)
select base.n as base_count, classified.n as classified_count
from base, classified
where base.n != classified.n

-- Passthrough of the tariff_events seed with a surrogate key. See seeds/schema.yml
-- for scope/caveats -- notably that this table is NOT currently joined into
-- fact_shipments's effective_duty_rate_pct (that reflects only the current regime;
-- time-conditional exposure is deferred to Phase 8).

select
    row_number() over (order by event_date, event_type) as event_key,
    event_date as date_key,
    event_type,
    hs_scope,
    country_scope,
    rate_change_pp,
    description,
    source_url
from {{ ref('tariff_events') }}

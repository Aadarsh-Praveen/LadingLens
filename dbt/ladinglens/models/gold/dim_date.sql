-- Standard date spine, 2013-01-01 through 2026-12-31 (5,113 days). Lower bound
-- set generously below 2018 to cover silver_bol_shipments_scoped's earliest
-- trade_update_date (2014-06-18) with margin, since fact_shipments.date_key is
-- sourced from that column (see fact_shipments.sql header).

with date_spine as (

    select dateadd(day, seq, date '2013-01-01') as date_day
    from (
        select row_number() over (order by 1) - 1 as seq
        from table(generator(rowcount => 5200))
    )
    where dateadd(day, seq, date '2013-01-01') <= date '2026-12-31'

)

select
    date_day as date_key,
    date_day,
    extract(year from date_day) as year,
    extract(quarter from date_day) as quarter,
    extract(month from date_day) as month,
    extract(day from date_day) as day,
    dayname(date_day) as day_name,
    case when dayofweek(date_day) in (0, 6) then true else false end as is_weekend,
    concat('Q', extract(quarter from date_day), ' ', extract(year from date_day)) as fiscal_quarter_label
from date_spine

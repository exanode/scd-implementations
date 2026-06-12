-- postgres/scd4_history.sql
-- SCD Type 4: current table + separate history/audit table.
-- Current table always reflects latest state (Type 1 semantics).
-- History table captures every change with a changed_at timestamp.
-- Separating current from history keeps the hot read path fast; the history
-- table can be indexed and partitioned independently.

-- -----------------------------------------------
-- Step 1: log changes to history table before applying them
-- -----------------------------------------------
insert into dim_customer_scd4_history (
    customer_id, city, plan_tier, account_status, changed_at, changed_by
)
select
    target.customer_id,
    target.city,
    target.plan_tier,
    target.account_status,
    now(),
    'pipeline'

from dim_customer_scd4_current as target
inner join src_customers as source
    on target.customer_id = source.customer_id
where (
    target.city            is distinct from source.city            or
    target.plan_tier       is distinct from source.plan_tier       or
    target.account_status  is distinct from source.account_status
);


-- -----------------------------------------------
-- Step 2: apply changes to current table (Type 1 overwrite)
-- -----------------------------------------------
merge into dim_customer_scd4_current as target
using src_customers as source
on target.customer_id = source.customer_id

when matched and (
    target.city            is distinct from source.city            or
    target.plan_tier       is distinct from source.plan_tier       or
    target.account_status  is distinct from source.account_status
) then
    update set
        city           = source.city,
        plan_tier      = source.plan_tier,
        account_status = source.account_status,
        dbt_updated_at = now()

when not matched then
    insert (customer_id, email, city, plan_tier, account_status)
    values (source.customer_id, source.email, source.city, source.plan_tier, source.account_status);


-- -----------------------------------------------
-- Querying point-in-time state (approximate)
-- SCD4 doesn't store valid_to like SCD2; history rows have changed_at.
-- To reconstruct state at a given time, take the last history row before that time.
-- -----------------------------------------------
/*
select distinct on (customer_id)
    customer_id,
    plan_tier,
    changed_at
from dim_customer_scd4_history
where changed_at <= '2024-01-01 12:00:00'
order by customer_id, changed_at desc;
*/

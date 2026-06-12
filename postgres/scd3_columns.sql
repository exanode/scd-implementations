-- postgres/scd3_columns.sql
-- SCD Type 3: store current value + one prior value as columns.
-- Only tracks the last change; older history is lost.
-- Useful when "what changed most recently" is the only question being asked.

-- -----------------------------------------------
-- Initial load: no prior values
-- -----------------------------------------------
insert into dim_customer_scd3 (
    customer_id, email, city, plan_tier, prev_plan_tier,
    account_status, dbt_updated_at, plan_changed_at
)
select
    customer_id,
    email,
    city,
    plan_tier,
    null,     -- no prior on first load
    account_status,
    now(),
    null
from src_customers
on conflict (customer_id) do nothing;


-- -----------------------------------------------
-- Incremental update: shift current -> prev when plan_tier changes
-- -----------------------------------------------
update dim_customer_scd3 as target
set
    prev_plan_tier  = target.plan_tier,        -- shift current to prev
    plan_tier       = source.plan_tier,        -- write new current
    city            = source.city,
    account_status  = source.account_status,
    dbt_updated_at  = now(),
    plan_changed_at = case
                          when target.plan_tier is distinct from source.plan_tier
                          then now()
                          else target.plan_changed_at
                      end

from src_customers as source
where
    target.customer_id = source.customer_id
    and (
        target.plan_tier       is distinct from source.plan_tier      or
        target.city            is distinct from source.city           or
        target.account_status  is distinct from source.account_status
    );


-- -----------------------------------------------
-- Insert new customers
-- -----------------------------------------------
insert into dim_customer_scd3 (
    customer_id, email, city, plan_tier, prev_plan_tier,
    account_status, dbt_updated_at, plan_changed_at
)
select
    s.customer_id, s.email, s.city, s.plan_tier, null, s.account_status, now(), null
from src_customers s
where not exists (
    select 1 from dim_customer_scd3 t where t.customer_id = s.customer_id
);


-- -----------------------------------------------
-- Limitation: only one level of history.
-- If alice changes plan twice (starter -> professional -> enterprise),
-- prev_plan_tier will be 'professional', not 'starter'.
-- For full history use SCD Type 2.
-- -----------------------------------------------

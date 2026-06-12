-- postgres/scd1_upsert.sql
-- SCD Type 1: overwrite on change.
-- No history retained; only the current value is stored.
-- Uses MERGE (PostgreSQL 15+). For older versions see the INSERT ... ON CONFLICT version below.

-- -----------------------------------------------
-- Method 1: MERGE (PG 15+)
-- -----------------------------------------------
merge into dim_customer_scd1 as target
using src_customers as source
on target.customer_id = source.customer_id

when matched and (
    target.email           is distinct from source.email           or
    target.city            is distinct from source.city            or
    target.plan_tier       is distinct from source.plan_tier       or
    target.account_status  is distinct from source.account_status
) then
    update set
        email          = source.email,
        city           = source.city,
        plan_tier      = source.plan_tier,
        account_status = source.account_status,
        dbt_updated_at = now()

when not matched then
    insert (customer_id, email, city, plan_tier, account_status, dbt_updated_at)
    values (source.customer_id, source.email, source.city, source.plan_tier, source.account_status, now());


-- -----------------------------------------------
-- Method 2: INSERT ... ON CONFLICT (PG 9.5+)
-- Equivalent result; works on older Postgres versions.
-- -----------------------------------------------
/*
insert into dim_customer_scd1 (customer_id, email, city, plan_tier, account_status, dbt_updated_at)
select
    customer_id,
    email,
    city,
    plan_tier,
    account_status,
    now()
from src_customers

on conflict (customer_id) do update set
    email          = excluded.email,
    city           = excluded.city,
    plan_tier      = excluded.plan_tier,
    account_status = excluded.account_status,
    dbt_updated_at = now()
where (
    dim_customer_scd1.email           is distinct from excluded.email           or
    dim_customer_scd1.city            is distinct from excluded.city            or
    dim_customer_scd1.plan_tier       is distinct from excluded.plan_tier       or
    dim_customer_scd1.account_status  is distinct from excluded.account_status
);
*/


-- -----------------------------------------------
-- Idempotency check
-- Re-running this against the same source produces no additional changes.
-- -----------------------------------------------
-- select count(*) from dim_customer_scd1;  -- should remain stable

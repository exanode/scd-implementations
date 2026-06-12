-- snowflake/scd2_merge.sql
-- SCD Type 2 in Snowflake.
-- Uses two separate MERGE statements because Snowflake MERGE can't insert
-- and update the same target table in a single pass for SCD2.
-- Alternative: delete+insert (see benchmarks at bottom).

-- -----------------------------------------------
-- Step 1: compute hashdiff on source
-- -----------------------------------------------
create or replace temporary table src_customers_hashed as
select
    customer_id,
    email,
    city,
    plan_tier,
    account_status,
    md5(
        coalesce(email, '')         ||'|'||
        coalesce(city, '')          ||'|'||
        coalesce(plan_tier, '')     ||'|'||
        coalesce(account_status, '')
    ) as hashdiff,
    current_timestamp() as effective_from
from (
    select *,
           row_number() over (partition by customer_id order by updated_at desc) as rn
    from src_customers
)
where rn = 1;


-- -----------------------------------------------
-- Step 2: expire old current rows where hashdiff differs
-- -----------------------------------------------
merge into dim_customer_scd2 as target
using src_customers_hashed as source
on  target.customer_id = source.customer_id
and target.is_current   = true
and target.hashdiff    != source.hashdiff

when matched then
    update set
        valid_to   = source.effective_from,
        is_current = false;


-- -----------------------------------------------
-- Step 3: insert new current rows for changed/new customers
-- -----------------------------------------------
merge into dim_customer_scd2 as target
using src_customers_hashed as source
on  target.customer_id = source.customer_id
and target.is_current   = true

when not matched then
    insert (customer_id, email, city, plan_tier, account_status, hashdiff, valid_from, valid_to, is_current)
    values (
        source.customer_id,
        source.email,
        source.city,
        source.plan_tier,
        source.account_status,
        source.hashdiff,
        source.effective_from,
        null,
        true
    );


-- -----------------------------------------------
-- Benchmark: MERGE vs DELETE+INSERT
-- For Snowflake micro-partitions, DELETE+INSERT can be more efficient
-- because MERGE rewrites all affected micro-partitions twice (once for update, once for insert).
-- For large SCD2 tables (>100M rows), test both approaches with Query Profile.
-- DELETE+INSERT alternative:
-- -----------------------------------------------
/*
-- expire changed rows
update dim_customer_scd2 t
set valid_to = s.effective_from, is_current = false
from src_customers_hashed s
where t.customer_id = s.customer_id
  and t.is_current  = true
  and t.hashdiff   != s.hashdiff;

-- insert new rows
insert into dim_customer_scd2 (...)
select ... from src_customers_hashed s
where not exists (
    select 1 from dim_customer_scd2 t
    where t.customer_id = s.customer_id and t.is_current = true
);
*/

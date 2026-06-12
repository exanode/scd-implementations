-- snowflake/scd4_mini_dim.sql
-- SCD Type 4 in Snowflake.
-- Current table uses MERGE (Type 1 overwrite).
-- History table gets INSERT before the update; no deletes.
-- Uses Snowflake Streams to detect changes rather than doing a full source scan.

-- -----------------------------------------------
-- Optional: use a Stream on the source table for change detection
-- Creates a CDC-like change record without comparing every row
-- -----------------------------------------------
create stream if not exists src_customers_stream
on table src_customers
append_only = false;


-- -----------------------------------------------
-- When stream is consumed in a task or stored procedure:
-- -----------------------------------------------

-- Log changes to history table first
insert into dim_customer_scd4_history (customer_id, city, plan_tier, account_status, changed_at, changed_by)
select
    metadata$action,   -- INSERT / DELETE / UPDATE in stream
    customer_id,
    city,
    plan_tier,
    account_status,
    current_timestamp(),
    'stream_task'
from src_customers_stream
where metadata$action = 'INSERT'  -- in Snowflake streams, updates appear as DELETE+INSERT pairs
;


-- -----------------------------------------------
-- Without streams: direct comparison approach (same as Postgres version)
-- -----------------------------------------------
insert into dim_customer_scd4_history (customer_id, city, plan_tier, account_status, changed_at)
select
    t.customer_id,
    t.city,
    t.plan_tier,
    t.account_status,
    current_timestamp()
from dim_customer_scd4_current t
inner join src_customers s
    on t.customer_id = s.customer_id
where (
    t.city            is distinct from s.city            or
    t.plan_tier       is distinct from s.plan_tier       or
    t.account_status  is distinct from s.account_status
);


-- Overwrite current table
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
        dbt_updated_at = current_timestamp()

when not matched then
    insert (customer_id, email, city, plan_tier, account_status)
    values (source.customer_id, source.email, source.city, source.plan_tier, source.account_status);


-- -----------------------------------------------
-- Time Travel alternative:
-- Snowflake's native Time Travel (90 days default) can serve as
-- a lightweight SCD4-equivalent for recent history without the history table.
-- Use: SELECT * FROM dim_customer_scd4_current AT(TIMESTAMP => '2024-01-01'::timestamp)
-- Not suitable for history beyond the retention period.
-- -----------------------------------------------

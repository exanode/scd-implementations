-- snowflake/scd1_merge.sql
-- SCD Type 1 in Snowflake using MERGE.
-- Snowflake MERGE is deterministic when source has no duplicates on the join key.
-- Check for source duplicates first or use a deduped CTE.

merge into dim_customer_scd1 as target
using (
    -- deduplicate source in case of multiple rows per customer_id
    select *
    from (
        select
            *,
            row_number() over (partition by customer_id order by updated_at desc) as rn
        from src_customers
    )
    where rn = 1
) as source
on target.customer_id = source.customer_id

when matched and (
    target.email           != source.email           or target.email           is null or
    target.city            != source.city            or target.city            is null or
    target.plan_tier       != source.plan_tier       or target.plan_tier       is null or
    target.account_status  != source.account_status  or target.account_status  is null
) then
    update set
        email          = source.email,
        city           = source.city,
        plan_tier      = source.plan_tier,
        account_status = source.account_status,
        dbt_updated_at = current_timestamp()

when not matched then
    insert (customer_id, email, city, plan_tier, account_status, dbt_updated_at)
    values (source.customer_id, source.email, source.city, source.plan_tier, source.account_status, current_timestamp());


-- -----------------------------------------------
-- Snowflake Query Profile note:
-- For large tables, check that the MERGE uses a hash join (not broadcast).
-- If the source is small, Snowflake may broadcast it; acceptable for < ~50MB source.
-- Run: EXPLAIN USING TABULAR <merge statement> to inspect the plan.
-- -----------------------------------------------

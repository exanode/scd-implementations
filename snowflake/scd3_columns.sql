-- snowflake/scd3_columns.sql
-- SCD Type 3 in Snowflake.
-- Only tracks one prior value per tracked column.

merge into dim_customer_scd3 as target
using (
    select *,
           row_number() over (partition by customer_id order by updated_at desc) as rn
    from src_customers
) as source
on target.customer_id = source.customer_id
and source.rn = 1

when matched and (
    target.plan_tier       is distinct from source.plan_tier       or
    target.city            is distinct from source.city            or
    target.account_status  is distinct from source.account_status
) then
    update set
        prev_plan_tier  = iff(target.plan_tier is distinct from source.plan_tier,
                              target.plan_tier, target.prev_plan_tier),
        plan_tier       = source.plan_tier,
        city            = source.city,
        account_status  = source.account_status,
        dbt_updated_at  = current_timestamp(),
        plan_changed_at = iff(target.plan_tier is distinct from source.plan_tier,
                              current_timestamp(), target.plan_changed_at)

when not matched then
    insert (customer_id, email, city, plan_tier, prev_plan_tier, account_status, dbt_updated_at)
    values (source.customer_id, source.email, source.city, source.plan_tier, null, source.account_status, current_timestamp());

-- models/scd2_incremental.sql
-- SCD Type 2 implemented as a dbt incremental model.
-- On each run: detect changed rows, close them, insert new ones.
-- This is the manual incremental approach; compare with the dbt snapshot approach.

{{
    config(
        materialized='incremental',
        unique_key=['customer_id', 'valid_from'],
        incremental_strategy='merge',
        on_schema_change='fail'
    )
}}

with source as (
    select
        customer_id,
        email,
        city,
        plan_tier,
        account_status,
        updated_at,
        md5(
            coalesce(email, '')         ||'|'||
            coalesce(city, '')          ||'|'||
            coalesce(plan_tier, '')     ||'|'||
            coalesce(account_status, '')
        ) as hashdiff

    from {{ source('raw', 'src_customers') }}
),

{% if is_incremental() %}

-- detect what actually changed compared to current state
changed as (
    select s.*
    from source s
    left join {{ this }} t
        on s.customer_id = t.customer_id
        and t.is_current = true
    where t.customer_id is null
       or s.hashdiff != t.hashdiff
),

-- rows to expire: close the current record
to_expire as (
    select
        t.customer_id,
        t.valid_from,
        c.updated_at                            as valid_to,
        false                                   as is_current,
        t.email, t.city, t.plan_tier, t.account_status, t.hashdiff

    from {{ this }} t
    inner join changed c on t.customer_id = c.customer_id
    where t.is_current = true
),

-- new current rows
to_insert as (
    select
        customer_id,
        email,
        city,
        plan_tier,
        account_status,
        hashdiff,
        updated_at                              as valid_from,
        cast(null as {{ dbt.type_timestamp() }}) as valid_to,
        true                                    as is_current
    from changed
),

combined as (
    select * from to_expire
    union all
    select * from to_insert
)

select * from combined

{% else %}

-- full load: all rows loaded as current, no prior history
select
    customer_id,
    email,
    city,
    plan_tier,
    account_status,
    hashdiff,
    updated_at                              as valid_from,
    cast(null as {{ dbt.type_timestamp() }}) as valid_to,
    true                                    as is_current

from source

{% endif %}

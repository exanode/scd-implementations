-- snapshots/scd2_via_dbt_snapshot.sql
-- SCD Type 2 using dbt's native snapshot command.
-- dbt handles: hashdiff computation, valid_from/to windows, is_current flag.
-- Simplest approach; prefer this over manual incremental for standard SCD2.
-- Limitation: can't backfill; snapshot runs forward from the first execution date.

{% snapshot scd2_dim_customer %}

{{
    config(
        target_schema='scd_snapshots',
        unique_key='customer_id',
        strategy='check',
        check_cols=['email', 'city', 'plan_tier', 'account_status'],
        invalidate_hard_deletes=True
    )
}}

select
    customer_id,
    email,
    city,
    plan_tier,
    account_status,
    updated_at

from {{ source('raw', 'src_customers') }}

{% endsnapshot %}

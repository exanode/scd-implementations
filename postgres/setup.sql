-- setup.sql
-- Creates all SCD target tables for PostgreSQL lab.
-- Run once on a fresh database; seed data loaded separately.

-- -----------------------------------------------
-- SCD Type 1 target: overwrite on change
-- -----------------------------------------------
create table if not exists dim_customer_scd1 (
    customer_key    serial      primary key,
    customer_id     int         not null unique,
    email           varchar(200),
    city            varchar(100),
    plan_tier       varchar(50),
    account_status  varchar(20),
    dbt_updated_at  timestamp   not null default now()
);

-- -----------------------------------------------
-- SCD Type 2 target: full history with validity window
-- -----------------------------------------------
create table if not exists dim_customer_scd2 (
    customer_key    serial      primary key,
    customer_id     int         not null,
    email           varchar(200),
    city            varchar(100),
    plan_tier       varchar(50),
    account_status  varchar(20),
    hashdiff        char(32)    not null,  -- MD5 of tracked columns
    valid_from      timestamp   not null,
    valid_to        timestamp,             -- null = current record
    is_current      boolean     not null default true,
    dbt_created_at  timestamp   not null default now()
);

create index if not exists idx_scd2_customer_id on dim_customer_scd2 (customer_id);
create index if not exists idx_scd2_is_current  on dim_customer_scd2 (is_current);

-- -----------------------------------------------
-- SCD Type 3 target: keep current + one prior value
-- -----------------------------------------------
create table if not exists dim_customer_scd3 (
    customer_key        serial      primary key,
    customer_id         int         not null unique,
    email               varchar(200),
    city                varchar(100),
    plan_tier           varchar(50),
    prev_plan_tier      varchar(50),  -- previous value (one version)
    account_status      varchar(20),
    dbt_updated_at      timestamp   not null default now(),
    plan_changed_at     timestamp
);

-- -----------------------------------------------
-- SCD Type 4 target: current table + history mini-dimension
-- -----------------------------------------------
create table if not exists dim_customer_scd4_current (
    customer_key    serial      primary key,
    customer_id     int         not null unique,
    email           varchar(200),
    city            varchar(100),
    plan_tier       varchar(50),
    account_status  varchar(20),
    dbt_updated_at  timestamp   not null default now()
);

create table if not exists dim_customer_scd4_history (
    history_key     serial      primary key,
    customer_id     int         not null,
    city            varchar(100),
    plan_tier       varchar(50),
    account_status  varchar(20),
    changed_at      timestamp   not null,
    changed_by      varchar(50) default 'pipeline'
);

create index if not exists idx_scd4_hist_customer on dim_customer_scd4_history (customer_id);

-- seed data: source customers table used across all SCD variants
-- Represents a CRM system sending daily snapshots of customer records.

create table if not exists src_customers (
    customer_id     int         not null,
    email           varchar(200),
    city            varchar(100),
    plan_tier       varchar(50),  -- free | starter | professional | enterprise
    account_status  varchar(20),  -- active | suspended | churned
    updated_at      timestamp   not null default now(),
    primary key (customer_id)
);

-- initial load - day 0
insert into src_customers (customer_id, email, city, plan_tier, account_status, updated_at) values
  (1,  'alice@example.com',   'Mumbai',      'professional',  'active',    '2024-01-01 09:00:00'),
  (2,  'bob@example.com',     'Delhi',       'starter',       'active',    '2024-01-01 09:00:00'),
  (3,  'carol@example.com',   'Bengaluru',   'enterprise',    'active',    '2024-01-01 09:00:00'),
  (4,  'dave@example.com',    'Chennai',     'free',          'active',    '2024-01-01 09:00:00'),
  (5,  'eve@example.com',     'Hyderabad',   'starter',       'active',    '2024-01-01 09:00:00');

-- simulate day 1 changes:
--   alice upgrades to enterprise
--   bob moves city
--   dave account suspended
--   frank is a new customer
create table if not exists src_customers_day1 as select * from src_customers;

update src_customers_day1 set plan_tier = 'enterprise', updated_at = '2024-01-02 09:00:00' where customer_id = 1;
update src_customers_day1 set city = 'Pune',            updated_at = '2024-01-02 09:00:00' where customer_id = 2;
update src_customers_day1 set account_status = 'suspended', updated_at = '2024-01-02 09:00:00' where customer_id = 4;
insert into src_customers_day1 values (6, 'frank@example.com', 'Kolkata', 'free', 'active', '2024-01-02 09:00:00');

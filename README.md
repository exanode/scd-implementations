# scd-implementations

SCD Type 1, 2, 3, and 4 from scratch in PostgreSQL, Snowflake, and dbt.

Built to understand the trade-offs: when MERGE is better than delete+insert, how dbt snapshot compares to a manual incremental model, and what Snowflake's micro-partition writes look like under Query Profile.

---

## Coverage

| Type | PostgreSQL | Snowflake | dbt |
|------|-----------|-----------|-----|
| SCD1 | MERGE + ON CONFLICT | MERGE | - |
| SCD2 | MD5 hashdiff, expire+insert | Two-pass MERGE | snapshot + incremental model |
| SCD3 | current + prev column | MERGE with IFF | - |
| SCD4 | current table + history table | MERGE + Stream notes | - |

---

## Source table

`src_customers` - columns: `customer_id`, `email`, `city`, `plan_tier`, `account_status`, `updated_at`.

Docker loads the seed SQL on startup. `sample_data/seed_customers.sql` includes an initial load and a `src_customers_day1` snapshot simulating: alice upgrades plan, bob moves city, dave gets suspended, frank is a new customer.

---

## Setup

```bash
git clone https://github.com/sachin-ram/scd-implementations.git
cd scd-implementations
docker-compose up -d   # starts Postgres with seed data on port 5433

python -m venv env && source env/bin/activate
pip install -r requirements.txt
```

Connect:
```bash
psql -h localhost -p 5433 -U scduser -d scd_lab
```

---

## Running the SQL

```bash
# SCD1
psql -h localhost -p 5433 -U scduser -d scd_lab -f postgres/scd1_upsert.sql

# SCD2 - initial load, then simulate a change
psql ... -f postgres/scd2_merge.sql
# manually update src_customers or swap in src_customers_day1, then re-run to see history

# verify: one current row per customer
psql ... -c "select customer_id, plan_tier, valid_from, valid_to, is_current from dim_customer_scd2 order by customer_id, valid_from;"
```

---

## Integration tests

Requires the Docker container running.

```bash
pytest tests/ -v
```

Tests cover: SCD1 idempotency, SCD2 one-current-row invariant, SCD2 idempotent re-run, SCD2 change detection, SCD3 prev value preservation.

---

## Notes from building this

**MERGE vs delete+insert (Snowflake):** MERGE on large SCD2 tables is slower because it rewrites micro-partitions twice - once for the UPDATE (closing old rows) and once for the INSERT. For tables above ~100M rows, delete+insert via two separate statements writes fewer micro-partitions. The Query Profile's TableScan count shows this clearly.

**MD5 hashdiff:** Computing a single hash across all tracked columns avoids per-column comparisons in the WHERE clause. The `|` separator prevents field-boundary collisions (`'a' + '|bc'` ≠ `'a|' + 'bc'`).

**dbt snapshot vs manual incremental:** `dbt snapshot` handles hashdiff, windowing, and is_current automatically but runs forward from first execution - you can't insert history before that date. The manual incremental model in `models/scd2_incremental.sql` supports arbitrary backfill but needs explicit handling for the close/insert pattern.

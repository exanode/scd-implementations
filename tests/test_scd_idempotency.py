"""
SCD idempotency tests using a local PostgreSQL instance.
These are integration tests; they require docker-compose up to be running.
Skip them in CI unless a Postgres container is available.
"""

import os
import pytest
import psycopg2


DB_CONFIG = {
    "host": os.environ.get("PG_HOST", "localhost"),
    "port": int(os.environ.get("PG_PORT", 5433)),
    "dbname": os.environ.get("PG_DB", "scd_lab"),
    "user": os.environ.get("PG_USER", "scduser"),
    "password": os.environ.get("PG_PASSWORD", "scdpass"),
}


def get_conn():
    return psycopg2.connect(**DB_CONFIG)


@pytest.fixture(scope="module")
def conn():
    try:
        c = get_conn()
        yield c
        c.close()
    except psycopg2.OperationalError:
        pytest.skip("PostgreSQL not available")


def test_scd1_upsert_idempotency(conn):
    """Running SCD1 merge twice on the same source should not change row count."""
    cur = conn.cursor()

    # run once
    cur.execute(open("postgres/scd1_upsert.sql").read())
    conn.commit()
    cur.execute("select count(*) from dim_customer_scd1")
    count_after_first = cur.fetchone()[0]

    # run again - should be no-op
    cur.execute(open("postgres/scd1_upsert.sql").read())
    conn.commit()
    cur.execute("select count(*) from dim_customer_scd1")
    count_after_second = cur.fetchone()[0]

    assert count_after_first == count_after_second, (
        f"SCD1 re-run changed row count: {count_after_first} → {count_after_second}"
    )


def test_scd2_one_current_row_per_customer(conn):
    """After SCD2 merge, each customer_id must have exactly one is_current=true row."""
    cur = conn.cursor()
    cur.execute(open("postgres/scd2_merge.sql").read())
    conn.commit()

    cur.execute("""
        select customer_id, count(*)
        from dim_customer_scd2
        where is_current = true
        group by customer_id
        having count(*) > 1
    """)
    violations = cur.fetchall()
    assert violations == [], f"Multiple current rows found: {violations}"


def test_scd2_idempotent_rerun(conn):
    """Re-running SCD2 on unchanged source should not add rows."""
    cur = conn.cursor()
    cur.execute("select count(*) from dim_customer_scd2")
    before = cur.fetchone()[0]

    # same source, same data
    cur.execute(open("postgres/scd2_merge.sql").read())
    conn.commit()

    cur.execute("select count(*) from dim_customer_scd2")
    after = cur.fetchone()[0]

    assert before == after, f"SCD2 re-run added rows: {before} → {after}"


def test_scd2_change_creates_history(conn):
    """When source changes, old row gets closed and a new current row is inserted."""
    cur = conn.cursor()

    try:
        # swap in day1 data as the source
        cur.execute("alter table src_customers rename to src_customers_orig")
        cur.execute("alter table src_customers_day1 rename to src_customers")
        cur.execute(open("postgres/scd2_merge.sql").read())
        conn.commit()

        # alice (customer_id=1) upgraded plan → should have 2 rows: one closed, one current
        cur.execute("select count(*) from dim_customer_scd2 where customer_id = 1")
        row_count = cur.fetchone()[0]
    finally:
        # always restore regardless of whether assertion passes
        cur.execute("alter table src_customers rename to src_customers_day1")
        cur.execute("alter table src_customers_orig rename to src_customers")
        conn.commit()

    assert row_count == 2, f"Expected 2 rows for alice after plan change, got {row_count}"


def test_scd3_prev_value_preserved(conn):
    """After plan_tier change, prev_plan_tier should hold the old value."""
    cur = conn.cursor()

    # initial load
    cur.execute("truncate table dim_customer_scd3")
    cur.execute(open("postgres/scd3_columns.sql").read())
    conn.commit()

    # simulate alice upgrading: update source
    cur.execute("""
        update src_customers set plan_tier = 'enterprise', updated_at = now()
        where customer_id = 1
    """)
    conn.commit()
    cur.execute(open("postgres/scd3_columns.sql").read())
    conn.commit()

    cur.execute("select plan_tier, prev_plan_tier from dim_customer_scd3 where customer_id = 1")
    row = cur.fetchone()

    # restore
    cur.execute("update src_customers set plan_tier = 'professional' where customer_id = 1")
    conn.commit()

    assert row[0] == "enterprise", f"Expected plan_tier=enterprise, got {row[0]}"
    assert row[1] == "professional", f"Expected prev_plan_tier=professional, got {row[1]}"

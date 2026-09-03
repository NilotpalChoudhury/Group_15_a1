# BiteStream

BiteStream is a food delivery database system using PostgreSQL and MongoDB.

## PostgreSQL

The PostgreSQL implementation includes:

- Database schema and table definitions
- Indexes for query optimization
- Triggers and wallet audit logging
- Atomic checkout using a stored procedure
- Materialized views
- CTE and window-function analytics
- Query performance testing
- Python test data seeder

### SQL Files

| File | Purpose |
|---|---|
| `01_schema_ddl.sql` | Creates PostgreSQL tables and constraints |
| `02_indexes.sql` | Creates indexes for query optimization |
| `03_triggers_and_audit.sql` | Implements wallet triggers and audit logging |
| `04_stored_procedures.sql` | Implements the atomic checkout workflow |
| `05_materialized_views.sql` | Creates reporting materialized views |
| `06_window_analytics.sql` | Performs revenue analytics using CTEs and window functions |

### Data Seeder

The PostgreSQL data seeder is:

`data_generation/postgres_seeder.py`

It generates test users, restaurants, and orders.

Required dependency:

```text
psycopg2-binary

Install it with:

pip install -r data_generation/requirements.txt
PostgreSQL Testing

PostgreSQL queries were tested using:

EXPLAIN (ANALYZE, BUFFERS)

Index usage was verified for orders, restaurants, and wallet audit queries.

The PostgreSQL checkout workflow was also tested by verifying order creation, wallet balance changes, and wallet audit records.

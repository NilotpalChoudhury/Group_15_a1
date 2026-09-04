# BiteStream — Food Delivery & Real-Time Logistics

CS6.302 Software System Development — Assignment 1, Project 1 (BiteStream)

## 1. Overview

BiteStream models a food-delivery platform's persistence layer across two databases:

- **PostgreSQL** — the transactional core: `users`, `restaurants`, `orders`, and an immutable `wallet_audit_logs` ledger, with an atomic checkout stored procedure, an audit trigger, a partial unique index enforcing "one active order per user," a materialized view for revenue reporting, and a CTE/window-function analytics query.
- **MongoDB** — the flexible/high-volume/geospatial side: `menus` (nested categories/items/add-ons), `reviews` (ratings + sentiment tags), and `driverPings` (GeoJSON live location pings with a 2dsphere index and a TTL index).

## 2. Repository structure

```
<roll_number>_a1/
├── README.md
├── docs/
│   ├── relational_erd.png        # TODO — not yet created
│   └── mongo_schema_map.json     # TODO — not yet created
├── sql/
│   ├── 01_schema_ddl.sql
│   ├── 02_indexes.sql
│   ├── 03_triggers_and_audit.sql
│   ├── 04_stored_procedures.sql
│   ├── 05_materialized_views.sql
│   └── 06_window_analytics.sql
├── mongo/
│   ├── 01_collections_and_indexes.js
│   ├── 02_workflow3_geonear.js
│   └── 03_workflow4_facet.js
├── data_generation/
│   ├── postgres_seeder.py
│   ├── mongo_seeder.py
│   └── requirements.txt
└── performance/
    ├── postgres_explain_analyzes.txt
    └── mongo_execution_stats.json
```

## 3. Setup

### 3.1 PostgreSQL

Requires PostgreSQL 16 and a role that can `CREATE EXTENSION` (`01_schema_ddl.sql` creates `pgcrypto` itself for `gen_random_uuid()`).

Connection env vars read by `data_generation/postgres_seeder.py` (defaults shown):

```
PGHOST=localhost
PGPORT=5432
PGDATABASE=bitestream
PGUSER=postgres
PGPASSWORD=<set your own — do not commit a real password to the repo>
```

Run in this order:

```bash
psql -d bitestream -f sql/01_schema_ddl.sql
psql -d bitestream -f sql/02_indexes.sql
psql -d bitestream -f sql/03_triggers_and_audit.sql
psql -d bitestream -f sql/04_stored_procedures.sql
psql -d bitestream -f sql/05_materialized_views.sql

pip install -r data_generation/requirements.txt
python data_generation/postgres_seeder.py

# First population of the materialized view (must be non-concurrent the first time,
# since REFRESH CONCURRENTLY requires the view to already have data):
psql -d bitestream -c "REFRESH MATERIALIZED VIEW mv_restaurant_daily_revenue;"
# Afterwards, refresh without locking readers:
psql -d bitestream -c "SELECT fn_refresh_restaurant_daily_revenue();"

psql -d bitestream -f sql/06_window_analytics.sql
```

`postgres_seeder.py` seeds `users` and `restaurants` directly, then generates order/ledger volume by calling the **real** `sp_execute_checkout` procedure end-to-end (100,000 checkout attempts against a rotating pool of users). This means the seeded `orders` and `wallet_audit_logs` rows are produced by the actual stored procedure, row-locking, and audit trigger under load — it doubles as a stress test of Workflow 1, not just a data generator.

### 3.2 MongoDB

Requires MongoDB (tested on 8.0.28) and `mongosh`.

Connection env var read by `data_generation/mongo_seeder.py`:

```
MONGO_URI=mongodb://localhost:27017/
```

**Run `01_collections_and_indexes.js` before the seeder.** It drops and recreates `menus`, `reviews`, and `driverPings`, so running it after seeding will wipe your data.

```bash
mongosh bitestream mongo/01_collections_and_indexes.js

pip install -r data_generation/requirements.txt
python data_generation/mongo_seeder.py

mongosh bitestream mongo/02_workflow3_geonear.js
mongosh bitestream mongo/03_workflow4_facet.js
```

## 4. Assumptions

- **UUID primary keys** are used for all PostgreSQL entities (`users`, `restaurants`, `orders`, `wallet_audit_logs`), generated via `gen_random_uuid()`.
- **`wallet_audit_logs` is treated as a strictly immutable ledger** — beyond the required `AFTER UPDATE OF wallet_balance` trigger that writes audit rows, a `BEFORE UPDATE OR DELETE` trigger blocks any mutation of existing audit rows.
- **`SET TRANSACTION ISOLATION LEVEL` cannot be the first statement inside a PL/pgSQL procedure body** — PostgreSQL performs an internal catalog lookup before the procedure body executes, so `REPEATABLE READ` must be set by the *caller*:
  ```sql
  BEGIN;
  SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
  CALL sp_execute_checkout('USER_UUID', 'RESTAURANT_UUID', 250.00);
  COMMIT;
  ```
  Row-level locking inside the procedure itself is handled with `SELECT ... FOR UPDATE`, which is unaffected by this limitation.
- **`idx_active_user_order` enforces "one active order" for the lifetime of a row, not as a temporal state machine** — a user may have at most one row with status `PREPARING`/`DELIVERING` in the table at any time; every prior order must reach `DELIVERED` before that user can check out again. The seeder and any client code must respect this.
- **MongoDB `restaurant_id` fields (in `menus`/`reviews`) are plain integers 1–100**, while PostgreSQL `restaurants.id` is a UUID. The two are *not* foreign-key linked across databases — each store models restaurants independently, consistent with the assignment's polyglot-persistence premise.
- **Restaurant and driver coordinates are clustered in a single city bounding box** (~Hyderabad: lat 17.25–17.60, lon 78.30–78.60) so that Workflow 3's 5 km `$geoNear` radius reliably returns a non-empty, realistic result set.
- **`mongo_seeder.py`** generates 500,000 `driverPings` (satisfies "500k+"), 50,000 `reviews`, and 100 `menus` documents.

## 5. Workflows implemented

| Workflow | Description | File |
|---|---|---|
| 1 — Atomic Checkout | PL/pgSQL stored procedure: locks the wallet row, validates balance, deducts, inserts the order (fires the audit trigger) | `sql/04_stored_procedures.sql` |
| 2 — Window Analytics | 7-day moving average of revenue per restaurant + `DENSE_RANK()` venue ranking, over a full calendar spine (no gap days skipped) | `sql/06_window_analytics.sql` |
| 3 — Nearest Active Driver | `$geoNear` within 5 km of a restaurant, filtered to `active: true` | `mongo/02_workflow3_geonear.js` |
| 4 — Multi-Faceted Review Analytics | `$facet`: rating distribution, most frequent tags (`$unwind`), overall average rating | `mongo/03_workflow4_facet.js` |

## 6. Performance proof

### 6.1 Workflow 2 — PostgreSQL `EXPLAIN (ANALYZE, BUFFERS)`

**Key evidence:** the `daily_revenue` CTE reaches the `orders` table via a **Bitmap Index Scan on `idx_orders_status_created_at`** (not a sequential scan), examining ~200,000 matching rows through the index. Total execution time: **198.400 ms**.

```
Sort  (cost=43985.17..43985.67 rows=200 width=82) (actual time=196.750..197.339 rows=9000.00 loops=1)
  Sort Key: rv.revenue_rank, daily_revenue.restaurant_id, ((series.revenue_date)::date)
  Sort Method: quicksort  Memory: 948kB
  Buffers: shared hit=3364
  CTE reporting_period
    ->  Result  (cost=0.00..0.02 rows=1 width=8) (actual time=0.004..0.004 rows=1.00 loops=1)
  CTE daily_revenue
    ->  HashAggregate  (cost=6130.12..6523.18 rows=19653 width=38) (actual time=158.474..158.645 rows=100.00 loops=1)
          Group Key: o.restaurant_id, (date_trunc('day'::text, o.created_at))::date
          Batches: 1  Memory Usage: 569kB
          Buffers: shared hit=3364
          InitPlan 2
            ->  CTE Scan on reporting_period  (cost=0.00..0.02 rows=1 width=4) (actual time=0.001..0.002 rows=1.00 loops=1)
                  Storage: Memory  Maximum Storage: 17kB
          ->  Bitmap Heap Scan on orders o  (cost=1267.76..5630.10 rows=66667 width=26) (actual time=6.890..97.156 rows=200000.00 loops=1)
                Recheck Cond: (((status)::text = 'DELIVERED'::text) AND (created_at >= (InitPlan 2).col1))
                Heap Blocks: exact=3029
                Buffers: shared hit=3364
                ->  Bitmap Index Scan on idx_orders_status_created_at  (cost=0.00..1251.09 rows=66667 width=0) (actual time=6.319..6.320 rows=200000.00 loops=1)
                      Index Cond: (((status)::text = 'DELIVERED'::text) AND (created_at >= (InitPlan 2).col1))
                      Index Searches: 1
                      Buffers: shared hit=335
  ->  Merge Join  (cost=26986.08..37454.33 rows=200 width=82) (actual time=168.354..189.584 rows=9000.00 loops=1)
        Merge Cond: (daily_revenue.restaurant_id = rv.restaurant_id)
        Buffers: shared hit=3364
        ->  WindowAgg  (cost=26470.96..36436.22 rows=200000 width=56) (actual time=168.077..185.288 rows=9000.00 loops=1)
              Window: w1 AS (PARTITION BY daily_revenue.restaurant_id ORDER BY ((series.revenue_date)::date) ROWS BETWEEN '6'::bigint PRECEDING AND CURRENT ROW)
              Storage: Memory  Maximum Storage: 17kB
              Buffers: shared hit=3364
              ->  Merge Left Join  (cost=26470.92..30936.22 rows=200000 width=38) (actual time=168.052..172.233 rows=9000.00 loops=1)
                    Merge Cond: ((daily_revenue.restaurant_id = dr.restaurant_id) AND (((series.revenue_date)::date) = dr.revenue_date))
                    Buffers: shared hit=3364
                    ->  Sort  (cost=24676.36..25176.36 rows=200000 width=24) (actual time=167.984..169.735 rows=9000.00 loops=1)
                          Sort Key: daily_revenue.restaurant_id, ((series.revenue_date)::date)
                          Sort Method: quicksort  Memory: 806kB
                          Buffers: shared hit=3364
                          ->  Nested Loop  (cost=442.20..2964.72 rows=200000 width=24) (actual time=158.805..161.384 rows=9000.00 loops=1)
                                Buffers: shared hit=3364
                                ->  Nested Loop  (cost=0.01..20.03 rows=1000 width=8) (actual time=0.038..0.067 rows=90.00 loops=1)
                                      ->  CTE Scan on reporting_period rp  (cost=0.00..0.02 rows=1 width=8) (actual time=0.007..0.010 rows=1.00 loops=1)
                                            Storage: Memory  Maximum Storage: 17kB
                                      ->  Function Scan on generate_series series  (cost=0.01..10.01 rows=1000 width=8) (actual time=0.029..0.040 rows=90.00 loops=1)
                                ->  Materialize  (cost=442.19..445.19 rows=200 width=16) (actual time=1.764..1.770 rows=100.00 loops=90)
                                      Storage: Memory  Maximum Storage: 20kB
                                      Buffers: shared hit=3364
                                      ->  HashAggregate  (cost=442.19..444.19 rows=200 width=16) (actual time=158.761..158.780 rows=100.00 loops=1)
                                            Group Key: daily_revenue.restaurant_id
                                            Batches: 1  Memory Usage: 32kB
                                            Buffers: shared hit=3364
                                            ->  CTE Scan on daily_revenue  (cost=0.00..393.06 rows=19653 width=16) (actual time=158.481..158.702 rows=100.00 loops=1)
                                                  Storage: Memory  Maximum Storage: 22kB
                                                  Buffers: shared hit=3364
                    ->  Sort  (cost=1794.56..1843.69 rows=19653 width=38) (actual time=0.057..0.077 rows=100.00 loops=1)
                          Sort Key: dr.restaurant_id, dr.revenue_date
                          Sort Method: quicksort  Memory: 29kB
                          ->  CTE Scan on daily_revenue dr  (cost=0.00..393.06 rows=19653 width=38) (actual time=0.004..0.018 rows=100.00 loops=1)
                                Storage: Memory  Maximum Storage: 22kB
        ->  Sort  (cost=515.11..515.61 rows=200 width=42) (actual time=0.272..0.918 rows=8911.00 loops=1)
              Sort Key: rv.restaurant_id
              Sort Method: quicksort  Memory: 30kB
              ->  Subquery Scan on rv  (cost=501.99..507.47 rows=200 width=42) (actual time=0.156..0.235 rows=100.00 loops=1)
                    ->  WindowAgg  (cost=501.99..505.47 rows=200 width=42) (actual time=0.156..0.221 rows=100.00 loops=1)
                          Window: w1 AS (ORDER BY venue_totals.period_revenue ROWS UNBOUNDED PRECEDING)
                          Storage: Memory  Maximum Storage: 17kB
                          ->  Sort  (cost=501.97..502.47 rows=200 width=34) (actual time=0.151..0.159 rows=100.00 loops=1)
                                Sort Key: venue_totals.period_revenue DESC
                                Sort Method: quicksort  Memory: 29kB
                                ->  Subquery Scan on venue_totals  (cost=491.32..494.32 rows=200 width=34) (actual time=0.067..0.117 rows=100.00 loops=1)
                                      ->  HashAggregate  (cost=491.32..494.32 rows=200 width=34) (actual time=0.066..0.102 rows=100.00 loops=1)
                                            Group Key: daily_revenue_1.restaurant_id
                                            Batches: 1  Memory Usage: 56kB
                                            ->  CTE Scan on daily_revenue daily_revenue_1  (cost=0.00..393.06 rows=19653 width=34) (actual time=0.000..0.009 rows=100.00 loops=1)
                                                  Storage: Memory  Maximum Storage: 22kB
Planning:
  Buffers: shared hit=55
Planning Time: 1.134 ms
Execution Time: 198.400 ms
```

Full raw output: [`performance/postgres_explain_analyzes.txt`](performance/postgres_explain_analyzes.txt)

### 6.2 Workflow 3 — MongoDB `explain("executionStats")` ($geoNear)

**Key evidence:** the winning plan uses `GEO_NEAR_2DSPHERE` on `idx_driverPings_location_2dsphere` — no `COLLSCAN`. `totalKeysExamined` (146) is close to `totalDocsExamined` (143), showing the index is doing the filtering work, not a post-scan filter over the full collection.

```json
{
  "winningPlan": {
    "stage": "FETCH",
    "filter": { "active": { "$eq": true } },
    "inputStage": {
      "stage": "GEO_NEAR_2DSPHERE",
      "keyPattern": { "location": "2dsphere" },
      "indexName": "idx_driverPings_location_2dsphere"
    }
  },
  "executionStats": {
    "executionSuccess": true,
    "nReturned": 32,
    "executionTimeMillis": 50,
    "totalKeysExamined": 146,
    "totalDocsExamined": 143
  }
}
```

Full raw output: [`performance/mongo_execution_stats.json`](performance/mongo_execution_stats.json) → `workflow3_geonear`

### 6.3 Workflow 4 — MongoDB `explain("executionStats")` ($facet)

**Key evidence:** the initial `$match` (feeding all three facets) uses `IXSCAN` on `idx_reviews_restaurant` with a tight index bound (`[1, 1]`). `nReturned` (502) equals `totalDocsExamined` (502) — a 1:1 ratio, meaning the index isn't over-fetching before the facets run.

```json
{
  "winningPlan": {
    "stage": "PROJECTION_SIMPLE",
    "inputStage": {
      "stage": "FETCH",
      "inputStage": {
        "stage": "IXSCAN",
        "keyPattern": { "restaurant_id": 1 },
        "indexName": "idx_reviews_restaurant",
        "indexBounds": { "restaurant_id": ["[1, 1]"] }
      }
    }
  },
  "executionStats": {
    "executionSuccess": true,
    "nReturned": 502,
    "executionTimeMillis": 33,
    "totalKeysExamined": 502,
    "totalDocsExamined": 502
  }
}
```

Full raw output: [`performance/mongo_execution_stats.json`](performance/mongo_execution_stats.json) → `workflow4_facet`

## 7. Data volumes

| Collection / table | Volume |
|---|---|
| `restaurants` (Postgres) | 100 |
| `orders` (Postgres) | ~200,000+ seeded via `sp_execute_checkout` (see §6.1) |
| `wallet_audit_logs` (Postgres) | ~1 row per successful checkout (trigger-generated) |
| `menus` (Mongo) | 100 |
| `reviews` (Mongo) | 50,000 |
| `driverPings` (Mongo) | 500,000 |

Re-verify exact counts after your final seeding run with 
`SELECT COUNT(*) FROM orders;` / `SELECT COUNT(*) FROM wallet_audit_logs;` and `db.driverPings.countDocuments()`
 before writing these into the final submission.


# MongoDB

## Collections

MongoDB uses the following collections:

- `menus` — restaurant menu data
- `reviews` — customer ratings and reviews
- `driverPings` — real-time driver location telemetry

## Indexes

- `menus.restaurant_id`
- `menus.categories.name`
- `reviews.restaurant_id`
- `reviews.rating`
- `driverPings.location` — 2dsphere index
- `driverPings.created_at` — TTL index (7200 seconds)
- `driverPings.active`

## Workflow 3 — Nearest Active Driver

File:

`mongo/02_workflow3_geonear.js`

Uses `$geoNear` to find active drivers within 5 km of a restaurant.

The workflow uses the `driverPings.location` 2dsphere index.

Performance evidence:

`performance/workflow3_stats.json`

## Workflow 4 — Review Analytics

File:

`mongo/03_workflow4_facet.js`

Uses `$facet` to calculate:

- Rating distribution
- Most frequent sentiment tags
- Overall average rating

Performance evidence:

`performance/workflow4_stats.json`

Combined MongoDB performance evidence:

`performance/mongo_execution_stats.json`

## Data Generation

MongoDB test data is generated using:

`data_generation/mongo_seeder.py`

The seeder generates menus, reviews, and large-scale driver telemetry data.

## Schema Map

MongoDB schema information is documented in:

`docs/mongo_schema_map.json`
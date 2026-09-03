-- BiteStream | Materialized view for restaurant daily revenue
-- Run after 01_schema_ddl.sql.

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_restaurant_daily_revenue AS
SELECT
    o.restaurant_id,
    DATE_TRUNC('day', o.created_at)::DATE AS revenue_date,
    COUNT(*) AS order_count,
    SUM(o.total_amount)::DECIMAL(14,2) AS daily_revenue
FROM orders AS o
WHERE o.status = 'DELIVERED'
GROUP BY o.restaurant_id, DATE_TRUNC('day', o.created_at)::DATE
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_restaurant_daily_revenue
    ON mv_restaurant_daily_revenue (restaurant_id, revenue_date);

CREATE INDEX IF NOT EXISTS idx_mv_restaurant_daily_revenue_date
    ON mv_restaurant_daily_revenue (revenue_date DESC);

CREATE OR REPLACE FUNCTION fn_refresh_restaurant_daily_revenue()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_restaurant_daily_revenue;
END;
$$;

COMMIT;

-- First population:
-- REFRESH MATERIALIZED VIEW mv_restaurant_daily_revenue;
-- Later:
-- SELECT fn_refresh_restaurant_daily_revenue();

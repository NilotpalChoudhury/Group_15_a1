-- BiteStream | Workflow 2: CTE + Window Functions
-- 7-calendar-day moving average per restaurant and DENSE_RANK venue ranking.

WITH reporting_period AS (
    SELECT
        CURRENT_DATE - 89 AS first_revenue_date,
        CURRENT_DATE AS last_revenue_date
),
daily_revenue AS (
    SELECT
        o.restaurant_id,
        DATE_TRUNC('day', o.created_at)::DATE AS revenue_date,
        SUM(o.total_amount)::DECIMAL(14,2) AS daily_revenue
    FROM orders AS o
    WHERE o.status = 'DELIVERED'
      AND o.created_at >= (SELECT first_revenue_date FROM reporting_period)
    GROUP BY o.restaurant_id, DATE_TRUNC('day', o.created_at)::DATE
),
active_restaurants AS (
    SELECT DISTINCT restaurant_id
    FROM daily_revenue
),
calendar_days AS (
    SELECT
        ar.restaurant_id,
        series.revenue_date::DATE AS revenue_date
    FROM active_restaurants AS ar
    CROSS JOIN reporting_period AS rp
    CROSS JOIN LATERAL generate_series(
        rp.first_revenue_date,
        rp.last_revenue_date,
        INTERVAL '1 day'
    ) AS series(revenue_date)
),
calendarized_revenue AS (
    SELECT
        cd.restaurant_id,
        cd.revenue_date,
        COALESCE(dr.daily_revenue, 0.00)::DECIMAL(14,2) AS daily_revenue
    FROM calendar_days AS cd
    LEFT JOIN daily_revenue AS dr
      ON dr.restaurant_id = cd.restaurant_id
     AND dr.revenue_date = cd.revenue_date
),
moving_average AS (
    SELECT
        restaurant_id,
        revenue_date,
        daily_revenue,
        AVG(daily_revenue) OVER (
            PARTITION BY restaurant_id
            ORDER BY revenue_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )::DECIMAL(14,2) AS moving_avg_7_day
    FROM calendarized_revenue
),
venue_totals AS (
    SELECT
        restaurant_id,
        SUM(daily_revenue)::DECIMAL(14,2) AS period_revenue
    FROM daily_revenue
    GROUP BY restaurant_id
),
ranked_venues AS (
    SELECT
        restaurant_id,
        period_revenue,
        DENSE_RANK() OVER (ORDER BY period_revenue DESC) AS revenue_rank
    FROM venue_totals
)
SELECT
    ma.restaurant_id,
    ma.revenue_date,
    ma.daily_revenue,
    ma.moving_avg_7_day,
    rv.period_revenue,
    rv.revenue_rank
FROM moving_average AS ma
JOIN ranked_venues AS rv USING (restaurant_id)
ORDER BY rv.revenue_rank, ma.restaurant_id, ma.revenue_date;

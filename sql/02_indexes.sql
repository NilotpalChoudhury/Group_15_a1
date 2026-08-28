-- BiteStream | PostgreSQL indexes
-- Run after 01_schema_ddl.sql.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS idx_active_user_order
    ON orders (user_id)
    WHERE status IN ('PREPARING', 'DELIVERING');

CREATE INDEX IF NOT EXISTS idx_orders_restaurant_created_at
    ON orders (restaurant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_user_created_at
    ON orders (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_status_created_at
    ON orders (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_audit_user_timestamp
    ON wallet_audit_logs (user_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_audit_action_timestamp
    ON wallet_audit_logs (action_type, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_restaurants_name
    ON restaurants (name);

COMMIT;

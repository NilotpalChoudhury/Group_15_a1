-- BiteStream | PostgreSQL schema
-- PostgreSQL 14+ recommended.
BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(120) NOT NULL,
    wallet_balance DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_users_wallet_balance_nonnegative
        CHECK (wallet_balance >= 0.00)
);

CREATE TABLE IF NOT EXISTS restaurants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(160) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    CONSTRAINT chk_restaurants_latitude
        CHECK (latitude BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_restaurants_longitude
        CHECK (longitude BETWEEN -180.0 AND 180.0)
);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    restaurant_id UUID NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'PREPARING',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_orders_user
        FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT fk_orders_restaurant
        FOREIGN KEY (restaurant_id) REFERENCES restaurants(id),
    CONSTRAINT chk_orders_total_amount_positive
        CHECK (total_amount > 0.00),
    CONSTRAINT chk_orders_status
        CHECK (status IN ('PREPARING', 'DELIVERING', 'DELIVERED'))
);

CREATE TABLE IF NOT EXISTS wallet_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    amount_changed DECIMAL(10,2) NOT NULL,
    action_type VARCHAR(10) NOT NULL,
    balance_after DECIMAL(10,2) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT fk_wallet_audit_user
        FOREIGN KEY (user_id) REFERENCES users(id),
    CONSTRAINT chk_wallet_audit_action_type
        CHECK (action_type IN ('DEBIT', 'CREDIT')),
    CONSTRAINT chk_wallet_audit_balance_after
        CHECK (balance_after >= 0.00),
    CONSTRAINT chk_wallet_audit_amount_nonzero
        CHECK (amount_changed <> 0.00)
);

COMMENT ON TABLE wallet_audit_logs IS
'Immutable wallet balance-change audit trail. Inserts are performed by the wallet trigger.';

COMMIT;

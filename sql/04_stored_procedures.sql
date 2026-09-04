-- BiteStream | Workflow 1: Atomic Checkout
-- PostgreSQL 16

--
--   BEGIN;
--   SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
--   CALL sp_execute_checkout('USER_UUID', 'RESTAURANT_UUID', 250.00);
--   COMMIT;   -- or ROLLBACK; if CALL raised an exception


BEGIN;

CREATE OR REPLACE PROCEDURE sp_execute_checkout(
    p_user_id UUID,
    p_restaurant_id UUID,
    p_total_amount DECIMAL(10,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_balance DECIMAL(10,2);
BEGIN
    -- Validate checkout amount.
    IF p_total_amount IS NULL OR p_total_amount <= 0.00 THEN
        RAISE EXCEPTION USING
            ERRCODE = '22023',
            MESSAGE = 'Checkout amount must be greater than 0';
    END IF;

    -- Verify that the restaurant exists.
    IF NOT EXISTS (
        SELECT 1
        FROM restaurants
        WHERE id = p_restaurant_id
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23503',
            MESSAGE = 'Restaurant does not exist';
    END IF;

    -- Lock the user's wallet row.
    SELECT wallet_balance
    INTO v_current_balance
    FROM users
    WHERE id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION USING
            ERRCODE = '23503',
            MESSAGE = 'User does not exist';
    END IF;

    -- Check sufficient wallet balance.
    IF v_current_balance < p_total_amount THEN
        RAISE EXCEPTION USING
            ERRCODE = 'P0001',
            MESSAGE = 'Insufficient wallet balance';
    END IF;

    -- Deduct wallet balance.
    -- This automatically fires the wallet audit trigger.
    UPDATE users
    SET wallet_balance = wallet_balance - p_total_amount
    WHERE id = p_user_id;

    -- Create the order.
    INSERT INTO orders (
        user_id,
        restaurant_id,
        total_amount,
        status
    )
    VALUES (
        p_user_id,
        p_restaurant_id,
        p_total_amount,
        'PREPARING'
    );

END;
$$;

COMMIT;

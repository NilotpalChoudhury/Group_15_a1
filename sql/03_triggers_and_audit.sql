-- BiteStream | Wallet audit trigger
-- Run after 01_schema_ddl.sql.

BEGIN;

CREATE OR REPLACE FUNCTION fn_audit_wallet_balance_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_action VARCHAR(10);
    v_amount DECIMAL(10,2);
BEGIN
    IF NEW.wallet_balance > OLD.wallet_balance THEN
        v_action := 'CREDIT';
    ELSIF NEW.wallet_balance < OLD.wallet_balance THEN
        v_action := 'DEBIT';
    ELSE
        RETURN NEW;
    END IF;

    v_amount := ABS(NEW.wallet_balance - OLD.wallet_balance);

    INSERT INTO wallet_audit_logs (
        user_id, amount_changed, action_type, balance_after, timestamp
    )
    VALUES (
        NEW.id, v_amount, v_action, NEW.wallet_balance, NOW()
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_wallet_balance_audit ON users;

CREATE TRIGGER trg_users_wallet_balance_audit
AFTER UPDATE OF wallet_balance ON users
FOR EACH ROW
WHEN (OLD.wallet_balance IS DISTINCT FROM NEW.wallet_balance)
EXECUTE FUNCTION fn_audit_wallet_balance_change();

CREATE OR REPLACE FUNCTION fn_prevent_wallet_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'wallet_audit_logs is immutable: UPDATE/DELETE is not allowed';
END;
$$;

DROP TRIGGER IF EXISTS trg_wallet_audit_immutable ON wallet_audit_logs;

CREATE TRIGGER trg_wallet_audit_immutable
BEFORE UPDATE OR DELETE ON wallet_audit_logs
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_wallet_audit_mutation();

COMMIT;

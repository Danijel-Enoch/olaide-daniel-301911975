-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Student : Olaide Daniel (301911975)
-- File    : The transfer, the reversal, and a deliberately wrong version
-- =====================================================================
-- A transfer is the standard example of a transaction because every one of
-- the ACID properties is load-bearing:
--   Atomicity   - a debit without its credit destroys a customer's money
--   Consistency - the double-entry invariant must hold at COMMIT
--   Isolation   - two concurrent debits must not both see the same balance
--   Durability  - an acknowledged transfer must survive a crash
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. The correct transfer
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_transfer_funds(
        p_from_account BIGINT,
        p_to_account   BIGINT,
        p_amount       NUMERIC,
        p_ref          VARCHAR,
        p_channel      VARCHAR DEFAULT 'MOBILE',
        p_customer     BIGINT  DEFAULT NULL)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_txn_id      BIGINT;
    v_from        account%ROWTYPE;
    v_to          account%ROWTYPE;
    v_min_balance NUMERIC(18,2);
    v_initiator   BIGINT;
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'transfer amount must be positive, got %', p_amount
            USING ERRCODE = '22023';
    END IF;
    IF p_from_account = p_to_account THEN
        RAISE EXCEPTION 'cannot transfer to the same account (%)', p_from_account
            USING ERRCODE = '22023';
    END IF;

    -- Lock both accounts, ALWAYS in ascending account_id order. Two
    -- simultaneous transfers A->B and B->A would otherwise each hold the
    -- lock the other needs: a deadlock. Ordering the acquisition makes that
    -- cycle impossible. Demo D6 proves both halves of this claim.
    IF p_from_account < p_to_account THEN
        SELECT * INTO v_from FROM account WHERE account_id = p_from_account FOR UPDATE;
        SELECT * INTO v_to   FROM account WHERE account_id = p_to_account   FOR UPDATE;
    ELSE
        SELECT * INTO v_to   FROM account WHERE account_id = p_to_account   FOR UPDATE;
        SELECT * INTO v_from FROM account WHERE account_id = p_from_account FOR UPDATE;
    END IF;

    IF v_from.account_id IS NULL THEN
        RAISE EXCEPTION 'debit account % does not exist', p_from_account USING ERRCODE = '23503';
    END IF;
    IF v_to.account_id IS NULL THEN
        RAISE EXCEPTION 'credit account % does not exist', p_to_account USING ERRCODE = '23503';
    END IF;
    IF v_from.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'debit account % is %, not ACTIVE', v_from.account_number, v_from.status
            USING ERRCODE = '55000';
    END IF;
    IF v_to.status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'credit account % is %, not ACTIVE', v_to.account_number, v_to.status
            USING ERRCODE = '55000';
    END IF;
    IF v_from.currency <> v_to.currency THEN
        RAISE EXCEPTION 'currency mismatch: % vs %', v_from.currency, v_to.currency
            USING ERRCODE = '22023';
    END IF;

    SELECT min_balance INTO v_min_balance
      FROM account_product WHERE product_code = v_from.product_code;

    -- The business rule that makes isolation matter. The balance read here
    -- is only trustworthy because the row is locked above.
    IF v_from.balance - p_amount < v_min_balance THEN
        RAISE EXCEPTION
            'insufficient funds on %: balance %, requested %, minimum balance %',
            v_from.account_number, v_from.balance, p_amount, v_min_balance
            USING ERRCODE = '23514';
    END IF;

    v_initiator := COALESCE(p_customer, v_from.customer_id);

    INSERT INTO txn (txn_ref, txn_type, channel_code, amount, currency, status,
                     narration, initiated_by_customer, created_at, completed_at)
    VALUES (p_ref, 'TRANSFER', p_channel, p_amount, v_from.currency, 'SUCCESS',
            'Transfer ' || v_from.account_number || ' -> ' || v_to.account_number,
            v_initiator, now(), now())
    RETURNING txn_id INTO v_txn_id;

    INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after)
    VALUES (v_txn_id, v_from.account_id, 'DR', p_amount, v_from.balance - p_amount),
           (v_txn_id, v_to.account_id,   'CR', p_amount, v_to.balance   + p_amount);

    -- Written as balance = balance - amount, not balance = <value read earlier>.
    -- The second form is the lost-update bug demonstrated in D3.
    UPDATE account SET balance = balance - p_amount WHERE account_id = v_from.account_id;
    UPDATE account SET balance = balance + p_amount WHERE account_id = v_to.account_id;

    RETURN v_txn_id;
END $$;

-- ---------------------------------------------------------------------
-- 2. Reversal - a compensating transaction, never a DELETE
-- ---------------------------------------------------------------------
-- Deleting or editing a posting destroys the audit trail and makes the
-- statement a customer already saw unreproducible. A reversal is a new
-- transaction with the legs swapped, and the original is marked REVERSED.
CREATE OR REPLACE FUNCTION fn_reverse_txn(p_original_ref VARCHAR, p_reason TEXT)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_orig   txn%ROWTYPE;
    v_dr     ledger_entry%ROWTYPE;
    v_cr     ledger_entry%ROWTYPE;
    v_new_id BIGINT;
BEGIN
    SELECT * INTO v_orig FROM txn WHERE txn_ref = p_original_ref FOR UPDATE;
    IF v_orig.txn_id IS NULL THEN
        RAISE EXCEPTION 'transaction % not found', p_original_ref USING ERRCODE = 'no_data_found';
    END IF;
    IF v_orig.status = 'REVERSED' THEN
        RAISE EXCEPTION 'transaction % is already reversed', p_original_ref USING ERRCODE = '55000';
    END IF;

    SELECT * INTO v_dr FROM ledger_entry WHERE txn_id = v_orig.txn_id AND direction = 'DR';
    SELECT * INTO v_cr FROM ledger_entry WHERE txn_id = v_orig.txn_id AND direction = 'CR';

    -- swap the legs: the account that was credited is now debited
    v_new_id := fn_transfer_funds(v_cr.account_id, v_dr.account_id, v_orig.amount,
                                  'REV-' || p_original_ref, v_orig.channel_code);

    UPDATE txn SET narration = 'REVERSAL of ' || p_original_ref || ': ' || p_reason
     WHERE txn_id = v_new_id;
    UPDATE txn SET status = 'REVERSED' WHERE txn_id = v_orig.txn_id;

    RETURN v_new_id;
END $$;

-- ---------------------------------------------------------------------
-- 3. The WRONG transfer - kept deliberately, used only by demo D3
-- ---------------------------------------------------------------------
-- This is the read-modify-write pattern that application code falls into
-- when the balance is fetched into a variable, checked, and written back.
-- It is correct when run alone and loses money when run concurrently, which
-- is exactly why concurrency bugs reach production.
CREATE OR REPLACE FUNCTION fn_transfer_naive(
        p_from_account BIGINT, p_to_account BIGINT, p_amount NUMERIC, p_ref VARCHAR)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_bal_from NUMERIC(18,2);
    v_bal_to   NUMERIC(18,2);
    v_txn_id   BIGINT;
    v_cust     BIGINT;
BEGIN
    -- no FOR UPDATE: nothing stops another session reading the same value
    SELECT balance, customer_id INTO v_bal_from, v_cust FROM account WHERE account_id = p_from_account;
    SELECT balance INTO v_bal_to FROM account WHERE account_id = p_to_account;

    IF v_bal_from < p_amount THEN
        RAISE EXCEPTION 'insufficient funds (naive check): balance %, requested %',
            v_bal_from, p_amount USING ERRCODE = '23514';
    END IF;

    PERFORM pg_sleep(0.3);   -- stands in for application round-trip latency

    INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, narration,
                     initiated_by_customer, completed_at)
    VALUES (p_ref, 'TRANSFER', 'USSD', p_amount, 'SUCCESS', 'naive transfer', v_cust, now())
    RETURNING txn_id INTO v_txn_id;

    INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after)
    VALUES (v_txn_id, p_from_account, 'DR', p_amount, v_bal_from - p_amount),
           (v_txn_id, p_to_account,   'CR', p_amount, v_bal_to   + p_amount);

    -- the bug: writes back a value computed from a stale read
    UPDATE account SET balance = v_bal_from - p_amount WHERE account_id = p_from_account;
    UPDATE account SET balance = v_bal_to   + p_amount WHERE account_id = p_to_account;

    RETURN v_txn_id;
END $$;

-- ---------------------------------------------------------------------
-- 4. Helper: the two test accounts used by every demo, reset to a known state
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reset_demo_accounts()
RETURNS TABLE (account_id BIGINT, account_number CHAR(10), balance NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN
    -- remove anything previous demos posted
    DELETE FROM ledger_entry WHERE txn_id IN (SELECT txn_id FROM txn WHERE txn_ref LIKE 'DEMO-%' OR txn_ref LIKE 'REV-DEMO-%');
    DELETE FROM txn WHERE txn_ref LIKE 'DEMO-%' OR txn_ref LIKE 'REV-DEMO-%';

    UPDATE account SET balance = 100000.00, status = 'ACTIVE' WHERE account_id IN (900001, 900002);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'demo accounts missing - run Olaide_Daniel_301911975_Demo_Setup.sql first';
    END IF;

    RETURN QUERY SELECT a.account_id, a.account_number, a.balance
                   FROM account a WHERE a.account_id IN (900001, 900002) ORDER BY a.account_id;
END $$;

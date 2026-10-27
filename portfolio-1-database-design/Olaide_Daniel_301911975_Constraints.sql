-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Student : Olaide Daniel (301911975)
-- File    : Integrity constraints, domain rules and triggers
-- Depends : Olaide_Daniel_301911975_Schema.sql
-- =====================================================================
-- Every business rule that can be expressed declaratively is expressed
-- declaratively. Application code can be bypassed; the constraint cannot.
-- =====================================================================
SET search_path TO hdmb, public;

-- ---------------------------------------------------------------------
-- 1. Domain / CHECK constraints
-- ---------------------------------------------------------------------
ALTER TABLE customer
    ADD CONSTRAINT chk_customer_bvn_numeric  CHECK (bvn ~ '^[0-9]{11}$'),
    ADD CONSTRAINT chk_customer_kyc_tier     CHECK (kyc_tier BETWEEN 1 AND 3),
    ADD CONSTRAINT chk_customer_status       CHECK (status IN ('ACTIVE','DORMANT','FROZEN','CLOSED')),
    ADD CONSTRAINT chk_customer_adult        CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '18 years'),
    ADD CONSTRAINT chk_customer_email_shape  CHECK (email IS NULL OR email LIKE '%_@_%._%');

ALTER TABLE account
    ADD CONSTRAINT chk_account_number_numeric CHECK (account_number ~ '^[0-9]{10}$'),
    ADD CONSTRAINT chk_account_status         CHECK (status IN ('ACTIVE','DORMANT','FROZEN','CLOSED')),
    ADD CONSTRAINT chk_account_balance_sign   CHECK (balance >= 0),
    ADD CONSTRAINT chk_account_closed_after   CHECK (closed_at IS NULL OR closed_at >= opened_at),
    ADD CONSTRAINT chk_account_closed_state   CHECK ((status = 'CLOSED') = (closed_at IS NOT NULL));

ALTER TABLE account_product
    ADD CONSTRAINT chk_product_rate    CHECK (interest_rate_pa >= 0 AND interest_rate_pa <= 100),
    ADD CONSTRAINT chk_product_limits  CHECK (min_balance >= 0 AND daily_debit_limit > 0);

ALTER TABLE txn
    ADD CONSTRAINT chk_txn_amount_positive CHECK (amount > 0),
    ADD CONSTRAINT chk_txn_type   CHECK (txn_type IN ('TRANSFER','DEPOSIT','WITHDRAWAL','FEE','LOAN_DISB','LOAN_REPAY')),
    ADD CONSTRAINT chk_txn_status CHECK (status IN ('PENDING','SUCCESS','FAILED','REVERSED')),
    ADD CONSTRAINT chk_txn_completed_state CHECK (
        (status = 'PENDING' AND completed_at IS NULL) OR
        (status <> 'PENDING' AND completed_at IS NOT NULL)),
    -- a transaction is raised either by the customer (self service) or by
    -- a member of staff (branch/agent), never by both and never by neither
    ADD CONSTRAINT chk_txn_single_initiator CHECK (
        (initiated_by_customer IS NOT NULL) <> (initiated_by_staff IS NOT NULL));

ALTER TABLE ledger_entry
    ADD CONSTRAINT chk_entry_direction CHECK (direction IN ('DR','CR')),
    ADD CONSTRAINT chk_entry_amount    CHECK (amount > 0),
    ADD CONSTRAINT uq_entry_txn_account_dir UNIQUE (txn_id, account_id, direction);

ALTER TABLE loan
    ADD CONSTRAINT chk_loan_principal CHECK (principal > 0),
    ADD CONSTRAINT chk_loan_tenor     CHECK (tenor_months BETWEEN 1 AND 60),
    ADD CONSTRAINT chk_loan_status    CHECK (status IN ('ACTIVE','SETTLED','DEFAULTED','WRITTEN_OFF')),
    ADD CONSTRAINT chk_loan_dates     CHECK (due_on > disbursed_on);

ALTER TABLE loan_repayment
    ADD CONSTRAINT chk_repay_amount CHECK (amount > 0),
    ADD CONSTRAINT chk_repay_split  CHECK (principal_portion + interest_portion = amount),
    ADD CONSTRAINT chk_repay_parts  CHECK (principal_portion >= 0 AND interest_portion >= 0);

ALTER TABLE beneficiary
    ADD CONSTRAINT uq_beneficiary_per_customer UNIQUE (customer_id, bank_code, account_number),
    ADD CONSTRAINT chk_beneficiary_acct CHECK (account_number ~ '^[0-9]{10}$');

ALTER TABLE audit_log
    ADD CONSTRAINT chk_audit_action CHECK (action IN ('INSERT','UPDATE','DELETE'));

-- ---------------------------------------------------------------------
-- 2. One active current account per customer per product
--    Partial unique index: the rule applies to live accounts only, so a
--    customer may reopen a product after closing an earlier account.
-- ---------------------------------------------------------------------
CREATE UNIQUE INDEX uq_active_account_per_product
    ON account (customer_id, product_code)
    WHERE status = 'ACTIVE';

-- ---------------------------------------------------------------------
-- 3. Deferred constraint trigger: every transaction must balance
--    Checked at COMMIT, not per row, because the DR row necessarily
--    exists for a moment without its matching CR row.
-- ---------------------------------------------------------------------
CREATE FUNCTION assert_txn_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_dr NUMERIC(18,2);
    v_cr NUMERIC(18,2);
BEGIN
    SELECT COALESCE(SUM(amount) FILTER (WHERE direction = 'DR'), 0),
           COALESCE(SUM(amount) FILTER (WHERE direction = 'CR'), 0)
      INTO v_dr, v_cr
      FROM ledger_entry
     WHERE txn_id = NEW.txn_id;

    IF v_dr <> v_cr THEN
        RAISE EXCEPTION
            'unbalanced transaction %: debits %, credits %', NEW.txn_id, v_dr, v_cr
            USING ERRCODE = 'integrity_constraint_violation';
    END IF;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER trg_ledger_balanced
    AFTER INSERT OR UPDATE ON ledger_entry
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION assert_txn_balanced();

-- ---------------------------------------------------------------------
-- 4. Audit trigger on account (append-only history of balance changes)
-- ---------------------------------------------------------------------
CREATE FUNCTION log_account_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO audit_log (table_name, record_pk, action, old_row, new_row)
    VALUES ('account', NEW.account_id, TG_OP,
            to_jsonb(OLD) - 'balance' || jsonb_build_object('balance', OLD.balance),
            to_jsonb(NEW) - 'balance' || jsonb_build_object('balance', NEW.balance));
    RETURN NEW;
END $$;

CREATE TRIGGER trg_account_audit
    AFTER UPDATE OF balance, status ON account
    FOR EACH ROW EXECUTE FUNCTION log_account_change();

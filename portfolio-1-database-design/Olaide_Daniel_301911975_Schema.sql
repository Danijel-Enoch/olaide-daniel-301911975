-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Student : Olaide Daniel (301911975)
-- Case    : Harmony Digital Microfinance Bank (HDMB) - simulated
-- File    : Relational schema (DDL) - PostgreSQL 18
-- Run     : psql -f Olaide_Daniel_301911975_Schema.sql
-- =====================================================================
-- Design notes
--  * Money is NUMERIC(18,2); never FLOAT. Rounding errors in a ledger
--    are unrecoverable, and NUMERIC is exact decimal arithmetic.
--  * Balances are never stored only on the account row. Every movement
--    of money is a double-entry row in ledger_entry, and account.balance
--    is a maintained running total that must equal the ledger sum.
--  * Surrogate BIGINT keys are used for stability; the natural keys the
--    business uses (bvn, account_number, txn_ref) carry UNIQUE.
-- =====================================================================

DROP SCHEMA IF EXISTS hdmb CASCADE;
CREATE SCHEMA hdmb;
SET search_path TO hdmb, public;
-- set it at database level too, so every later session (and every script in
-- Portfolios 2-5) lands in the right schema without repeating the SET
ALTER DATABASE hdmb SET search_path TO hdmb, public;

-- ---------------------------------------------------------------------
-- 1. Reference / lookup relations
-- ---------------------------------------------------------------------
CREATE TABLE branch (
    branch_id     BIGSERIAL PRIMARY KEY,
    branch_code   CHAR(4)      NOT NULL UNIQUE,
    branch_name   VARCHAR(80)  NOT NULL,
    state         VARCHAR(40)  NOT NULL,
    city          VARCHAR(40)  NOT NULL,
    opened_on     DATE         NOT NULL
);

CREATE TABLE account_product (
    product_code       VARCHAR(12) PRIMARY KEY,
    product_name       VARCHAR(60)    NOT NULL,
    interest_rate_pa   NUMERIC(5,2)   NOT NULL,
    min_balance        NUMERIC(18,2)  NOT NULL,
    daily_debit_limit  NUMERIC(18,2)  NOT NULL
);

CREATE TABLE channel (
    channel_code  VARCHAR(10) PRIMARY KEY,
    channel_name  VARCHAR(40) NOT NULL,
    is_self_service BOOLEAN   NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 2. Party relations
-- ---------------------------------------------------------------------
CREATE TABLE customer (
    customer_id   BIGSERIAL PRIMARY KEY,
    bvn           CHAR(11)     NOT NULL UNIQUE,   -- bank verification number
    first_name    VARCHAR(40)  NOT NULL,
    last_name     VARCHAR(40)  NOT NULL,
    date_of_birth DATE         NOT NULL,
    phone         VARCHAR(15)  NOT NULL UNIQUE,
    email         VARCHAR(120),
    residential_address TEXT   NOT NULL,
    kyc_tier      SMALLINT     NOT NULL DEFAULT 1,
    home_branch_id BIGINT      NOT NULL REFERENCES branch(branch_id),
    status        VARCHAR(10)  NOT NULL DEFAULT 'ACTIVE',
    registered_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE staff (
    staff_id      BIGSERIAL PRIMARY KEY,
    staff_number  VARCHAR(10)  NOT NULL UNIQUE,
    full_name     VARCHAR(80)  NOT NULL,
    job_role      VARCHAR(30)  NOT NULL,
    branch_id     BIGINT       NOT NULL REFERENCES branch(branch_id),
    work_email    VARCHAR(120) NOT NULL UNIQUE,
    is_active     BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ---------------------------------------------------------------------
-- 3. Account relations
-- ---------------------------------------------------------------------
CREATE TABLE account (
    account_id     BIGSERIAL PRIMARY KEY,
    account_number CHAR(10)      NOT NULL UNIQUE,
    customer_id    BIGINT        NOT NULL REFERENCES customer(customer_id),
    product_code   VARCHAR(12)   NOT NULL REFERENCES account_product(product_code),
    currency       CHAR(3)       NOT NULL DEFAULT 'NGN',
    balance        NUMERIC(18,2) NOT NULL DEFAULT 0,
    status         VARCHAR(10)   NOT NULL DEFAULT 'ACTIVE',
    opened_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    closed_at      TIMESTAMPTZ
);

CREATE TABLE beneficiary (
    beneficiary_id BIGSERIAL PRIMARY KEY,
    customer_id    BIGINT      NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    bank_code      CHAR(3)     NOT NULL,
    account_number CHAR(10)    NOT NULL,
    alias          VARCHAR(40) NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 4. Money movement relations (double entry)
-- ---------------------------------------------------------------------
CREATE TABLE txn (
    txn_id        BIGSERIAL PRIMARY KEY,
    txn_ref       VARCHAR(24)   NOT NULL UNIQUE,   -- idempotency key from channel
    txn_type      VARCHAR(16)   NOT NULL,          -- TRANSFER | DEPOSIT | WITHDRAWAL | FEE | LOAN_DISB | LOAN_REPAY
    channel_code  VARCHAR(10)   NOT NULL REFERENCES channel(channel_code),
    amount        NUMERIC(18,2) NOT NULL,
    currency      CHAR(3)       NOT NULL DEFAULT 'NGN',
    status        VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    narration     VARCHAR(140),
    initiated_by_customer BIGINT REFERENCES customer(customer_id),
    initiated_by_staff    BIGINT REFERENCES staff(staff_id),
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    completed_at  TIMESTAMPTZ
);

CREATE TABLE ledger_entry (
    entry_id        BIGSERIAL PRIMARY KEY,
    txn_id          BIGINT        NOT NULL REFERENCES txn(txn_id),
    account_id      BIGINT        NOT NULL REFERENCES account(account_id),
    direction       CHAR(2)       NOT NULL,        -- DR | CR
    amount          NUMERIC(18,2) NOT NULL,
    balance_after   NUMERIC(18,2) NOT NULL,
    entry_ts        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5. Credit relations
-- ---------------------------------------------------------------------
CREATE TABLE loan (
    loan_id        BIGSERIAL PRIMARY KEY,
    loan_ref       VARCHAR(20)   NOT NULL UNIQUE,
    customer_id    BIGINT        NOT NULL REFERENCES customer(customer_id),
    disburse_account_id BIGINT   NOT NULL REFERENCES account(account_id),
    principal      NUMERIC(18,2) NOT NULL,
    interest_rate_pa NUMERIC(5,2) NOT NULL,
    tenor_months   SMALLINT      NOT NULL,
    status         VARCHAR(12)   NOT NULL DEFAULT 'ACTIVE',
    approved_by    BIGINT        REFERENCES staff(staff_id),
    disbursed_on   DATE          NOT NULL,
    due_on         DATE          NOT NULL
);

CREATE TABLE loan_repayment (
    repayment_id      BIGSERIAL PRIMARY KEY,
    loan_id           BIGINT        NOT NULL REFERENCES loan(loan_id) ON DELETE CASCADE,
    txn_id            BIGINT        NOT NULL REFERENCES txn(txn_id),
    amount            NUMERIC(18,2) NOT NULL,
    principal_portion NUMERIC(18,2) NOT NULL,
    interest_portion  NUMERIC(18,2) NOT NULL,
    paid_on           DATE          NOT NULL
);

-- ---------------------------------------------------------------------
-- 6. Audit relation (append only)
-- ---------------------------------------------------------------------
CREATE TABLE audit_log (
    audit_id    BIGSERIAL PRIMARY KEY,
    table_name  VARCHAR(40) NOT NULL,
    record_pk   BIGINT      NOT NULL,
    action      VARCHAR(10) NOT NULL,
    changed_by  VARCHAR(60) NOT NULL DEFAULT current_user,
    changed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    old_row     JSONB,
    new_row     JSONB
);

COMMENT ON TABLE  ledger_entry IS 'Double-entry journal: every txn must balance DR and CR to zero.';
COMMENT ON COLUMN account.balance IS 'Maintained running total; must equal SUM(CR)-SUM(DR) of its ledger entries.';

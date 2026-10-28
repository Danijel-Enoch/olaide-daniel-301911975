-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Student : Olaide Daniel (301911975)
-- File    : Negative tests - each block MUST fail. A model is only as
--           good as the writes it refuses.
-- Output  : evidence/Olaide_Daniel_301911975_Constraint_Tests.txt
-- =====================================================================
SET search_path TO hdmb, public;

\echo '--- T1 duplicate BVN must be rejected (UNIQUE) ---'
BEGIN;
INSERT INTO customer (bvn, first_name, last_name, date_of_birth, phone, residential_address, home_branch_id)
SELECT bvn, 'Clone', 'Attempt', DATE '1991-01-01', '08099999991', 'nowhere', 1
FROM customer WHERE customer_id = 13;
ROLLBACK;

\echo '--- T2 negative transaction amount must be rejected (CHECK) ---'
BEGIN;
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at)
VALUES ('HDMB-NEG-TEST-1', 'TRANSFER', 'USSD', -5000.00, 'SUCCESS', 13, now());
ROLLBACK;

\echo '--- T3 transaction with both initiators must be rejected (CHECK) ---'
BEGIN;
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, initiated_by_staff, completed_at)
VALUES ('HDMB-BOTH-TEST-1', 'TRANSFER', 'BRANCH', 5000.00, 'SUCCESS', 13, 2, now());
ROLLBACK;

\echo '--- T4 unknown channel must be rejected (FOREIGN KEY) ---'
BEGIN;
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at)
VALUES ('HDMB-FK-TEST-1', 'TRANSFER', 'TELEPATHY', 5000.00, 'SUCCESS', 13, now());
ROLLBACK;

\echo '--- T5 single-sided (unbalanced) posting must be rejected at COMMIT ---'
BEGIN;
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at)
VALUES ('HDMB-UNBAL-TEST-1', 'TRANSFER', 'USSD', 7500.00, 'SUCCESS', 13, now());
INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after)
SELECT txn_id, 13, 'DR', 7500.00, 0 FROM txn WHERE txn_ref = 'HDMB-UNBAL-TEST-1';
COMMIT;        -- expected: ERROR unbalanced transaction

\echo '--- T6 the same posting with both legs must succeed ---'
BEGIN;
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at)
VALUES ('HDMB-BAL-TEST-1', 'TRANSFER', 'USSD', 7500.00, 'SUCCESS', 13, now());
INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after)
SELECT txn_id, 13, 'DR', 7500.00, (SELECT balance - 7500 FROM account WHERE account_id = 13)
FROM txn WHERE txn_ref = 'HDMB-BAL-TEST-1';
INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after)
SELECT txn_id, 14, 'CR', 7500.00, (SELECT balance + 7500 FROM account WHERE account_id = 14)
FROM txn WHERE txn_ref = 'HDMB-BAL-TEST-1';
COMMIT;        -- expected: COMMIT

\echo '--- T7 second ACTIVE account on the same product must be rejected ---'
BEGIN;
INSERT INTO account (account_number, customer_id, product_code, status)
VALUES ('0999999991', 13, (SELECT product_code FROM account WHERE account_id = 13), 'ACTIVE');
ROLLBACK;

\echo '--- cleanup ---'
DELETE FROM ledger_entry WHERE txn_id IN (SELECT txn_id FROM txn WHERE txn_ref LIKE 'HDMB-%-TEST-%');
DELETE FROM txn WHERE txn_ref LIKE 'HDMB-%-TEST-%';

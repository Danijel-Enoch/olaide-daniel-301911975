-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Student : Olaide Daniel (301911975)
-- File    : Fixed starting state for the concurrency demonstrations
-- =====================================================================
-- Every demo starts from two accounts holding exactly NGN 100,000.00 each,
-- so the arithmetic in the transcripts can be checked by eye and the
-- experiments are repeatable.
-- =====================================================================

-- two dedicated demo customers (ids far above the generated range)
INSERT INTO customer (customer_id, bvn, first_name, last_name, date_of_birth, phone,
                      email, residential_address, kyc_tier, home_branch_id, status)
VALUES (900001, '88000000001', 'Demo', 'Alpha', '1990-05-14', '09000000001',
        'demo.alpha@hdmb.test', 'Concurrency Lab, Ikeja', 3, 1, 'ACTIVE'),
       (900002, '88000000002', 'Demo', 'Beta',  '1988-11-02', '09000000002',
        'demo.beta@hdmb.test',  'Concurrency Lab, Yaba',  3, 2, 'ACTIVE')
ON CONFLICT (customer_id) DO NOTHING;

INSERT INTO account (account_id, account_number, customer_id, product_code,
                     currency, balance, status, opened_at)
VALUES (900001, '9900000001', 900001, 'SAV-PLUS', 'NGN', 100000.00, 'ACTIVE', now()),
       (900002, '9900000002', 900002, 'SAV-PLUS', 'NGN', 100000.00, 'ACTIVE', now())
ON CONFLICT (account_id) DO UPDATE SET balance = 100000.00, status = 'ACTIVE';

-- the explicit ids above bypass the sequence; move it past them so ordinary
-- inserts do not later collide
SELECT setval('account_account_id_seq',  GREATEST(900002, (SELECT max(account_id)  FROM account))  + 1);
SELECT setval('customer_customer_id_seq', GREATEST(900002, (SELECT max(customer_id) FROM customer)) + 1);

-- SAV-PLUS carries a NGN 5,000.00 minimum balance, which is what makes the
-- insufficient-funds path in D2 a business rule rather than a sign check
SELECT product_code, min_balance FROM account_product WHERE product_code = 'SAV-PLUS';
SELECT account_id, account_number, product_code, balance, status
  FROM account WHERE account_id IN (900001, 900002) ORDER BY account_id;

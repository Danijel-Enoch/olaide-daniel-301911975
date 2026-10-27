-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Student : Olaide Daniel (301911975)
-- File    : Seed data (reference rows + generated operational volume)
-- Depends : Schema.sql, Constraints.sql
-- =====================================================================
-- The data set is generated, not hand typed, for two reasons:
--   1. setseed() makes it reproducible, so every query plan and timing
--      in Portfolio 2 can be re-created by the assessor.
--   2. Portfolio 2 needs enough rows for the planner to make real
--      choices. On 50 rows PostgreSQL always picks a sequential scan and
--      no index evidence is possible.
-- Target volume: 20,012 customers | 25,012 accounts | 250k transactions
--                | ~500k ledger entries
-- =====================================================================
SET search_path TO hdmb, public;
SELECT setseed(0.301911975);          -- reproducible pseudo-randomness

-- ---------------------------------------------------------------------
-- 1. Reference data
-- ---------------------------------------------------------------------
INSERT INTO branch (branch_code, branch_name, state, city, opened_on) VALUES
 ('HD01','Ikeja Main','Lagos','Ikeja','2016-03-01'),
 ('HD02','Yaba Digital','Lagos','Yaba','2017-06-15'),
 ('HD03','Victoria Island','Lagos','Lagos Island','2017-11-02'),
 ('HD04','Wuse II','FCT','Abuja','2018-02-19'),
 ('HD05','Garki','FCT','Abuja','2019-05-06'),
 ('HD06','Bodija','Oyo','Ibadan','2019-09-23'),
 ('HD07','Challenge','Oyo','Ibadan','2020-01-13'),
 ('HD08','Aba Road','Rivers','Port Harcourt','2020-08-10'),
 ('HD09','Ogui Road','Enugu','Enugu','2021-04-05'),
 ('HD10','Sabon Gari','Kano','Kano','2021-10-18'),
 ('HD11','Oke-Ado Agency','Oyo','Ibadan','2022-07-04'),
 ('HD12','Lekki Agency','Lagos','Lekki','2023-02-20');

INSERT INTO account_product (product_code, product_name, interest_rate_pa, min_balance, daily_debit_limit) VALUES
 ('SAV-BASIC','Harmony Basic Savings',      4.50,     0.00,   50000.00),
 ('SAV-PLUS','Harmony Savings Plus',        7.25,  5000.00,  500000.00),
 ('CUR-SME','SME Current Account',          0.00, 10000.00, 5000000.00),
 ('TGT-6M','Target Savings 6 Months',      10.00,  1000.00,   20000.00),
 ('TILL','Branch Till (internal)',           0.00,     0.00,99999999.00);

INSERT INTO channel (channel_code, channel_name, is_self_service) VALUES
 ('USSD','USSD *977#',           TRUE),
 ('MOBILE','Harmony Mobile App', TRUE),
 ('WEB','Internet Banking',      TRUE),
 ('POS','Agent POS Terminal',    FALSE),
 ('BRANCH','Branch Counter',     FALSE),
 ('ATM','ATM Network',           TRUE);

INSERT INTO staff (staff_number, full_name, job_role, branch_id, work_email, is_active)
SELECT 'HS' || lpad(g::text, 4, '0'),
       (ARRAY['Adewale Ogunleye','Chioma Nwosu','Ibrahim Danjuma','Funke Adeyemi','Tunde Bakare',
              'Ngozi Eze','Musa Bello','Bisi Ojo','Emeka Obi','Hauwa Sani','Segun Alabi','Grace Etim'])[1 + (g % 12)]
         || ' ' || g,
       (ARRAY['TELLER','TELLER','TELLER','OPERATIONS','CREDIT_OFFICER','BRANCH_MANAGER'])[1 + (g % 6)],
       1 + (g % 12),
       'staff' || g || '@hdmb.test',
       TRUE
FROM generate_series(1, 24) g;

-- ---------------------------------------------------------------------
-- 2. Internal till customers (one per branch) - the counterparty for
--    cash deposits and withdrawals, so cash movements stay double entry.
-- ---------------------------------------------------------------------
INSERT INTO customer (bvn, first_name, last_name, date_of_birth, phone, email,
                      residential_address, kyc_tier, home_branch_id, status)
SELECT lpad((90000000000 + b.branch_id)::text, 11, '0'),
       'HDMB', 'TILL-' || b.branch_code, DATE '1990-01-01',
       '0700' || lpad(b.branch_id::text, 7, '0'),
       'till.' || lower(b.branch_code) || '@hdmb.test',
       b.city || ' branch vault', 3, b.branch_id, 'ACTIVE'
FROM branch b;

INSERT INTO account (account_number, customer_id, product_code, balance, status, opened_at)
SELECT lpad((9000000000 + c.customer_id)::text, 10, '0'), c.customer_id, 'TILL',
       50000000.00, 'ACTIVE', now() - INTERVAL '3 years'
FROM customer c WHERE c.first_name = 'HDMB';

-- ---------------------------------------------------------------------
-- 3. Retail customers
-- ---------------------------------------------------------------------
INSERT INTO customer (bvn, first_name, last_name, date_of_birth, phone, email,
                      residential_address, kyc_tier, home_branch_id, status, registered_at)
SELECT lpad((22000000000 + g)::text, 11, '0'),
       (ARRAY['Olaide','Chinedu','Aisha','Tobi','Zainab','Kelechi','Yusuf','Folake','Dayo','Amaka',
              'Suleiman','Blessing','Uche','Halima','Ifeanyi','Temitope','Nasir','Oluwaseun','Rita','Gbenga'])[1 + (g % 20)],
       (ARRAY['Afolabi','Okonkwo','Bello','Adeniyi','Lawal','Nwachukwu','Abubakar','Oyelaran','Eze','Balogun',
              'Yakubu','Ilesanmi','Madu','Shehu','Anozie','Akinyele','Garba','Ajibade','Umeh','Sowande'])[1 + ((g / 20) % 20)],
       DATE '1960-01-01' + ((g * 37) % 14600),
       '080' || lpad(g::text, 8, '0'),
       'customer' || g || '@mail.test',
       (ARRAY['Ikeja','Yaba','Lekki','Wuse','Garki','Bodija','Challenge','Aba Road','Ogui','Sabon Gari'])[1 + (g % 10)]
         || ', ' || g || ' Harmony Close',
       1 + (g % 3),
       1 + (g % 12),
       CASE WHEN g % 50 = 0 THEN 'DORMANT' WHEN g % 997 = 0 THEN 'FROZEN' ELSE 'ACTIVE' END,
       now() - (((g * 13) % 1400) || ' days')::INTERVAL
FROM generate_series(1, 20000) g;

-- ---------------------------------------------------------------------
-- 4. Accounts: every retail customer holds a savings account, and every
--    fourth customer also runs an SME current account.
-- ---------------------------------------------------------------------
INSERT INTO account (account_number, customer_id, product_code, balance, status, opened_at)
SELECT lpad(c.customer_id::text, 10, '0'), c.customer_id,
       CASE WHEN c.customer_id % 7 = 0 THEN 'SAV-PLUS'
            WHEN c.customer_id % 11 = 0 THEN 'TGT-6M'
            ELSE 'SAV-BASIC' END,
       0.00,
       CASE WHEN c.status = 'ACTIVE' THEN 'ACTIVE' ELSE 'DORMANT' END,
       c.registered_at
FROM customer c WHERE c.first_name <> 'HDMB';

INSERT INTO account (account_number, customer_id, product_code, balance, status, opened_at)
SELECT lpad((30000000 + c.customer_id)::text, 10, '0'), c.customer_id, 'CUR-SME',
       0.00, 'ACTIVE', c.registered_at + INTERVAL '30 days'
FROM customer c
WHERE c.first_name <> 'HDMB' AND c.customer_id % 4 = 0 AND c.status = 'ACTIVE';

INSERT INTO beneficiary (customer_id, bank_code, account_number, alias)
SELECT c.customer_id,
       (ARRAY['058','011','044','033','057','232'])[1 + (c.customer_id % 6)],
       lpad(((c.customer_id * 7919) % 9999999999)::text, 10, '0'),
       'Beneficiary ' || c.customer_id
FROM customer c WHERE c.customer_id % 3 = 0 AND c.first_name <> 'HDMB';

-- ---------------------------------------------------------------------
-- 5. Operational volume
--    Bulk load disables the per-row triggers: the deferred balance check
--    would re-aggregate ledger_entry once per inserted row (O(n^2)).
--    Section 6 re-enables them and proves the invariant still holds.
-- ---------------------------------------------------------------------
ALTER TABLE ledger_entry DISABLE TRIGGER trg_ledger_balanced;
ALTER TABLE account      DISABLE TRIGGER trg_account_audit;

-- 5a. opening deposit for every retail account (cash in at the till)
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, narration,
                 initiated_by_staff, created_at, completed_at)
SELECT 'HDMB-OPEN-' || lpad(a.account_id::text, 10, '0'), 'DEPOSIT', 'BRANCH',
       (500000 + (a.account_id % 23) * 50000)::NUMERIC(18,2), 'SUCCESS', 'Account opening deposit',
       1 + (a.account_id % 24), a.opened_at, a.opened_at + INTERVAL '4 minutes'
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
WHERE c.first_name <> 'HDMB';

-- 5b. ordinary traffic: transfers, withdrawals, fees and deposits
INSERT INTO txn (txn_ref, txn_type, channel_code, amount, currency, status, narration,
                 initiated_by_customer, initiated_by_staff, created_at, completed_at)
SELECT 'HDMB-' || to_char(now() - ((g % 540) || ' days')::INTERVAL, 'YYYYMMDD') || '-' || lpad(g::text, 9, '0'),
       t.txn_type,
       t.channel_code,
       t.amount,
       'NGN',
       CASE WHEN g % 211 = 0 THEN 'FAILED' WHEN g % 503 = 0 THEN 'REVERSED' ELSE 'SUCCESS' END,
       t.narration,
       CASE WHEN t.channel_code IN ('USSD','MOBILE','WEB','ATM') THEN 1 + (g % 20000) ELSE NULL END,
       CASE WHEN t.channel_code IN ('USSD','MOBILE','WEB','ATM') THEN NULL ELSE 1 + (g % 24) END,
       now() - ((g % 540) || ' days')::INTERVAL - ((g % 1440) || ' minutes')::INTERVAL,
       now() - ((g % 540) || ' days')::INTERVAL - ((g % 1440) || ' minutes')::INTERVAL + INTERVAL '3 seconds'
FROM generate_series(1, 250000) g
CROSS JOIN LATERAL (
    SELECT CASE g % 10
             WHEN 0 THEN 'DEPOSIT' WHEN 1 THEN 'WITHDRAWAL' WHEN 2 THEN 'FEE'
             ELSE 'TRANSFER' END                                   AS txn_type,
           (ARRAY['USSD','MOBILE','WEB','POS','BRANCH','ATM'])[1 + (g % 6)] AS channel_code,
           CASE g % 10
             WHEN 2 THEN 52.50
             ELSE (500 + (g % 90) * 50)::NUMERIC(18,2)
           END                                                     AS amount,
           CASE g % 10
             WHEN 0 THEN 'Cash deposit'  WHEN 1 THEN 'Cash withdrawal'
             WHEN 2 THEN 'SMS alert fee' ELSE 'Transfer to beneficiary' END AS narration
) t;

-- 5c. ledger entries - two per transaction, so DR always equals CR
--     opening deposits: DR branch till, CR customer account
INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after, entry_ts)
SELECT t.txn_id, till.account_id, 'DR', t.amount, 0, t.completed_at
FROM txn t
JOIN account a   ON a.account_id = CAST(substring(t.txn_ref FROM 11) AS BIGINT)
JOIN customer ac ON ac.customer_id = a.customer_id
JOIN customer tc ON tc.home_branch_id = ac.home_branch_id AND tc.first_name = 'HDMB'
JOIN account till ON till.customer_id = tc.customer_id
WHERE t.txn_ref LIKE 'HDMB-OPEN-%';

INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after, entry_ts)
SELECT t.txn_id, a.account_id, 'CR', t.amount, 0, t.completed_at
FROM txn t
JOIN account a ON a.account_id = CAST(substring(t.txn_ref FROM 11) AS BIGINT)
WHERE t.txn_ref LIKE 'HDMB-OPEN-%';

--     ordinary traffic: the debited and credited side of each movement
INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after, entry_ts)
SELECT t.txn_id,
       CASE WHEN t.txn_type = 'DEPOSIT'
            THEN (SELECT account_id FROM account WHERE product_code = 'TILL'
                   ORDER BY account_id LIMIT 1 OFFSET (t.txn_id % 12))
            ELSE 1 + ((t.txn_id * 7) % 20000) END,
       'DR', t.amount, 0, t.completed_at
FROM txn t WHERE t.txn_ref NOT LIKE 'HDMB-OPEN-%';

INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after, entry_ts)
SELECT t.txn_id,
       CASE WHEN t.txn_type IN ('WITHDRAWAL','FEE')
            THEN (SELECT account_id FROM account WHERE product_code = 'TILL'
                   ORDER BY account_id LIMIT 1 OFFSET (t.txn_id % 12))
            ELSE 1 + ((t.txn_id * 13 + 5) % 20000) END,
       'CR', t.amount, 0, t.completed_at
FROM txn t WHERE t.txn_ref NOT LIKE 'HDMB-OPEN-%';

-- ---------------------------------------------------------------------
-- 6. Derive running balances, then re-enable the integrity triggers
-- ---------------------------------------------------------------------
WITH running AS (
    SELECT entry_id,
           SUM(CASE WHEN direction = 'CR' THEN amount ELSE -amount END)
             OVER (PARTITION BY account_id ORDER BY entry_ts, entry_id
                   ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS bal
    FROM ledger_entry
)
UPDATE ledger_entry le
   SET balance_after = r.bal
  FROM running r
 WHERE r.entry_id = le.entry_id;

UPDATE account a
   SET balance = COALESCE(s.net, 0)
  FROM (SELECT account_id,
               SUM(CASE WHEN direction = 'CR' THEN amount ELSE -amount END) AS net
          FROM ledger_entry GROUP BY account_id) s
 WHERE s.account_id = a.account_id;

ALTER TABLE ledger_entry ENABLE TRIGGER trg_ledger_balanced;
ALTER TABLE account      ENABLE TRIGGER trg_account_audit;

-- ---------------------------------------------------------------------
-- 7. Loan book
-- ---------------------------------------------------------------------
INSERT INTO loan (loan_ref, customer_id, disburse_account_id, principal, interest_rate_pa,
                  tenor_months, status, approved_by, disbursed_on, due_on)
SELECT 'LN-' || lpad(a.account_id::text, 8, '0'), a.customer_id, a.account_id,
       (50000 + (a.account_id % 20) * 25000)::NUMERIC(18,2), 18.00,
       (ARRAY[3,6,12,24])[1 + (a.account_id % 4)],
       CASE WHEN a.account_id % 23 = 0 THEN 'DEFAULTED'
            WHEN a.account_id % 5  = 0 THEN 'SETTLED' ELSE 'ACTIVE' END,
       1 + (a.account_id % 24),
       (now() - ((a.account_id % 400) || ' days')::INTERVAL)::DATE,
       (now() - ((a.account_id % 400) || ' days')::INTERVAL + INTERVAL '365 days')::DATE
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
WHERE c.first_name <> 'HDMB' AND a.account_id % 9 = 0 AND a.status = 'ACTIVE';

ANALYZE;

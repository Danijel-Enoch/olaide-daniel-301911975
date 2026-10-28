-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 1
-- Student : Olaide Daniel (301911975)
-- File    : Design verification - proves the model enforces its rules
-- Output  : evidence/Olaide_Daniel_301911975_Design_Verification.txt
-- =====================================================================
SET search_path TO hdmb, public;
\echo '=== 1. Relation volumes ==================================='
SELECT 'branch' AS relation, count(*) FROM branch
UNION ALL SELECT 'account_product', count(*) FROM account_product
UNION ALL SELECT 'channel',      count(*) FROM channel
UNION ALL SELECT 'staff',        count(*) FROM staff
UNION ALL SELECT 'customer',     count(*) FROM customer
UNION ALL SELECT 'account',      count(*) FROM account
UNION ALL SELECT 'beneficiary',  count(*) FROM beneficiary
UNION ALL SELECT 'txn',          count(*) FROM txn
UNION ALL SELECT 'ledger_entry', count(*) FROM ledger_entry
UNION ALL SELECT 'loan',         count(*) FROM loan
ORDER BY 1;

\echo '=== 2. Declared constraints per relation ==================='
SELECT rel.relname AS relation,
       count(*) FILTER (WHERE c.contype = 'p') AS pk,
       count(*) FILTER (WHERE c.contype = 'f') AS fk,
       count(*) FILTER (WHERE c.contype = 'u') AS uniq,
       count(*) FILTER (WHERE c.contype = 'c') AS checks
FROM pg_constraint c
JOIN pg_class rel ON rel.oid = c.conrelid
JOIN pg_namespace n ON n.oid = rel.relnamespace
WHERE n.nspname = 'hdmb'
GROUP BY rel.relname ORDER BY rel.relname;

\echo '=== 3. Double-entry invariant: every txn must balance ======'
SELECT count(*) AS unbalanced_transactions
FROM (
    SELECT txn_id,
           SUM(CASE WHEN direction = 'DR' THEN amount ELSE -amount END) AS diff
    FROM ledger_entry GROUP BY txn_id HAVING SUM(CASE WHEN direction = 'DR' THEN amount ELSE -amount END) <> 0
) bad;

\echo '=== 4. account.balance reconciles with the ledger =========='
SELECT count(*) AS accounts_out_of_balance
FROM account a
LEFT JOIN (SELECT account_id,
                  SUM(CASE WHEN direction = 'CR' THEN amount ELSE -amount END) AS net
             FROM ledger_entry GROUP BY account_id) l ON l.account_id = a.account_id
WHERE a.balance <> COALESCE(l.net, 0);

\echo '=== 5. No customer account is overdrawn ==================='
SELECT count(*) AS overdrawn_customer_accounts
FROM account WHERE balance < 0 AND product_code <> 'TILL';

\echo '=== 6. Referential integrity: orphaned ledger rows ========'
SELECT count(*) AS orphan_entries
FROM ledger_entry le
LEFT JOIN txn t ON t.txn_id = le.txn_id
LEFT JOIN account a ON a.account_id = le.account_id
WHERE t.txn_id IS NULL OR a.account_id IS NULL;

\echo '=== 7. Business view: balance sheet by product ============='
SELECT p.product_code, count(*) AS accounts,
       to_char(SUM(a.balance), 'FM999,999,999,990.00') AS total_balance
FROM account a JOIN account_product p ON p.product_code = a.product_code
GROUP BY p.product_code ORDER BY p.product_code;

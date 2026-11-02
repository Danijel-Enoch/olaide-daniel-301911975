-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 3
-- Student : Olaide Daniel (301911975)
-- File    : Post-experiment reconciliation
-- =====================================================================
-- The concurrency lab deliberately corrupts data (demo D3, part 1). This
-- script is run AFTER the full lab to prove the database was left consistent:
-- every transaction balances, every account.balance equals its ledger
-- position, and nothing was overdrawn.
-- =====================================================================
\echo '=== transactions where debits <> credits (must be 0) ==='
SELECT count(*) AS unbalanced_transactions FROM (
    SELECT txn_id FROM ledger_entry GROUP BY txn_id
     HAVING sum(CASE WHEN direction = 'DR' THEN amount ELSE -amount END) <> 0) bad;

\echo '=== accounts whose stored balance <> ledger position (must be 0) ==='
SELECT count(*) AS accounts_out_of_balance
FROM account a
LEFT JOIN (SELECT account_id, sum(CASE WHEN direction='CR' THEN amount ELSE -amount END) AS net
             FROM ledger_entry GROUP BY account_id) l ON l.account_id = a.account_id
WHERE a.balance <> COALESCE(l.net, 0);

\echo '=== overdrawn customer accounts (must be 0) ==='
SELECT count(*) AS overdrawn FROM account WHERE balance < 0 AND product_code <> 'TILL';

\echo '=== the demo accounts, as the lab left them ==='
SELECT a.account_id, a.account_number, a.balance AS stored_balance,
       COALESCE(sum(CASE WHEN le.direction='CR' THEN le.amount ELSE -le.amount END),0) AS ledger_net
FROM account a LEFT JOIN ledger_entry le ON le.account_id = a.account_id
WHERE a.account_id IN (900001, 900002)
GROUP BY a.account_id, a.account_number, a.balance ORDER BY a.account_id;

\echo '=== audit trail written during the lab ==='
SELECT count(*) AS audit_rows_for_demo_accounts,
       min(changed_at) AS first_change, max(changed_at) AS last_change
FROM audit_log WHERE record_pk IN (900001, 900002);

\echo '=== transaction status mix across the whole bank ==='
SELECT status, count(*) FROM txn GROUP BY status ORDER BY count(*) DESC;

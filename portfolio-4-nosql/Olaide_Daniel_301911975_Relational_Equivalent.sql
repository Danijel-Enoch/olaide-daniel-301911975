-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 4
-- Student : Olaide Daniel (301911975)
-- File    : The relational equivalent of document query M1
-- =====================================================================
-- This is the SAME mobile home screen that MongoDB serves with one
-- findOne(). In the normalised model it is four joins plus a correlated
-- statement query. Run with EXPLAIN ANALYZE so the comparison in the README
-- is measured rather than asserted.
-- =====================================================================
\pset pager off
\echo '=== relational home screen: customer + accounts + product + branch ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.customer_id, c.first_name || ' ' || c.last_name AS full_name, c.phone,
       c.kyc_tier, c.status,
       b.branch_code, b.branch_name, b.city,
       a.account_number, a.currency, a.balance, a.status AS account_status,
       p.product_code, p.product_name, p.interest_rate_pa, p.min_balance
FROM customer c
JOIN branch b          ON b.branch_id = c.home_branch_id
JOIN account a         ON a.customer_id = c.customer_id
JOIN account_product p ON p.product_code = a.product_code
WHERE c.customer_id = 41;

\echo '=== plus the statement the same screen shows (second round trip) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT le.entry_ts, t.txn_ref, t.txn_type, t.channel_code, t.status,
       le.direction, le.amount, le.balance_after
FROM ledger_entry le
JOIN txn t     ON t.txn_id = le.txn_id
JOIN account a ON a.account_id = le.account_id
WHERE a.customer_id = 41
ORDER BY le.entry_ts DESC, le.entry_id DESC
LIMIT 10;

\echo '=== the rows the application must then stitch together ==='
SELECT count(*) AS rows_returned_by_the_join
FROM customer c
JOIN account a ON a.customer_id = c.customer_id
WHERE c.customer_id = 41;

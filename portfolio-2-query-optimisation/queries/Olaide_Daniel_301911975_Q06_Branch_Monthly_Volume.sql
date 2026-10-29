-- Q6  Head-office report: transaction value per branch per month, 12 months.
--     Joins the two largest relations to reference data and aggregates.
--     Optimisation target: covering index so the ledger join is index-only.
SELECT b.branch_code, b.branch_name,
       date_trunc('month', le.entry_ts)::date AS month,
       count(DISTINCT t.txn_id) AS transactions,
       to_char(sum(le.amount) FILTER (WHERE le.direction = 'CR'), 'FM999,999,999,990.00') AS credited
FROM ledger_entry le
JOIN txn t      ON t.txn_id = le.txn_id AND t.status = 'SUCCESS'
JOIN account a  ON a.account_id = le.account_id AND a.product_code <> 'TILL'
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch b   ON b.branch_id = c.home_branch_id
WHERE le.entry_ts >= now() - INTERVAL '12 months'
GROUP BY b.branch_code, b.branch_name, month
ORDER BY b.branch_code, month;

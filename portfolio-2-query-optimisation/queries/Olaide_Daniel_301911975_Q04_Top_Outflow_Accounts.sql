-- Q4  AML / fraud watchlist: the 10 accounts with the largest debit outflow
--     in the last 30 days.
--     Optimisation target: (entry_ts, direction) range scan + aggregate.
SELECT a.account_number, c.first_name || ' ' || c.last_name AS customer,
       a.product_code, count(*) AS debit_count,
       to_char(sum(le.amount), 'FM999,999,999,990.00') AS total_out
FROM ledger_entry le
JOIN account a  ON a.account_id = le.account_id
JOIN customer c ON c.customer_id = a.customer_id
WHERE le.direction = 'DR'
  AND le.entry_ts >= now() - INTERVAL '30 days'
  AND a.product_code <> 'TILL'
GROUP BY a.account_number, customer, a.product_code
ORDER BY sum(le.amount) DESC
LIMIT 10;

-- Q5  Regulatory dormancy sweep: ACTIVE accounts with a positive balance and
--     no posting in 180 days. An anti-join over the whole ledger.
--     Optimisation target: let the (account_id, entry_ts) index answer the
--     NOT EXISTS probe instead of hashing every entry.
SELECT a.account_number, a.product_code, a.balance, a.opened_at::date AS opened,
       c.phone, b.branch_code
FROM account a
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch b   ON b.branch_id = c.home_branch_id
WHERE a.status = 'ACTIVE'
  AND a.product_code <> 'TILL'
  AND a.balance > 0
  AND NOT EXISTS (
        SELECT 1 FROM ledger_entry le
         WHERE le.account_id = a.account_id
           AND le.entry_ts >= now() - INTERVAL '180 days')
ORDER BY a.balance DESC
LIMIT 25;

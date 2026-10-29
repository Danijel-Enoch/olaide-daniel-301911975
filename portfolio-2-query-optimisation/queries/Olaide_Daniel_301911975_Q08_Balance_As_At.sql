-- Q8  Dispute resolution: what was this account's balance at a past instant?
--     Derived from the journal rather than from account.balance, which only
--     holds the position now.
--     Optimisation target: (account_id, entry_ts) index range scan.
SELECT a.account_number,
       to_char(a.balance, 'FM999,999,990.00') AS balance_now,
       to_char(COALESCE(sum(CASE WHEN le.direction = 'CR' THEN le.amount
                                 ELSE -le.amount END), 0), 'FM999,999,990.00') AS balance_as_at,
       count(le.entry_id) AS postings_counted
FROM account a
LEFT JOIN ledger_entry le
       ON le.account_id = a.account_id
      AND le.entry_ts <= now() - INTERVAL '90 days'
WHERE a.account_id = 4211
GROUP BY a.account_number, a.balance;

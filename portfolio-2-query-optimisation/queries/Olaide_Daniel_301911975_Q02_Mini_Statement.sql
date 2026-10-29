-- Q2  Mini statement: the 20 most recent postings on one account.
--     The single most frequent read in the mobile app.
--     Optimisation target: composite index (account_id, entry_ts DESC).
SELECT le.entry_ts, t.txn_ref, t.txn_type, t.channel_code,
       le.direction, le.amount, le.balance_after, t.narration
FROM ledger_entry le
JOIN txn t ON t.txn_id = le.txn_id
WHERE le.account_id = 4211
ORDER BY le.entry_ts DESC, le.entry_id DESC
LIMIT 20;

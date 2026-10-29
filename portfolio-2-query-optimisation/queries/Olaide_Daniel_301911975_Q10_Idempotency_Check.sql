-- Q10 Channel retry: before posting, the switch asks whether this reference
--      has already been processed. Must be O(log n) from day one - the unique
--      constraint on txn_ref already provides the index, and this query is
--      included to show what "already optimal" looks like in a plan.
SELECT t.txn_id, t.status, t.amount, t.completed_at
FROM txn t
WHERE t.txn_ref = 'HDMB-20261025-000119351';

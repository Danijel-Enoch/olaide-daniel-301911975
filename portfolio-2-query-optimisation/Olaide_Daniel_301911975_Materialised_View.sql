-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Student : Olaide Daniel (301911975)
-- File    : Optimisation step 2 - materialised view
-- =====================================================================
-- Q6 (branch volume per month, 12 months) did not improve from indexing, and
-- that is the correct outcome: it touches ~67% of a 549,590-row relation and
-- aggregates it. No access path can beat a sequential scan when the query
-- genuinely needs most of the table. The only way to make it fast is to stop
-- recomputing it - trade freshness for speed, which is legitimate here
-- because a head-office monthly report does not need second-level accuracy.
-- =====================================================================

DROP MATERIALIZED VIEW IF EXISTS mv_branch_monthly_volume;

CREATE MATERIALIZED VIEW mv_branch_monthly_volume AS
SELECT b.branch_id,
       b.branch_code,
       b.branch_name,
       date_trunc('month', le.entry_ts)::date          AS month,
       count(DISTINCT t.txn_id)                        AS transactions,
       sum(le.amount) FILTER (WHERE le.direction = 'CR') AS credited,
       sum(le.amount) FILTER (WHERE le.direction = 'DR') AS debited
FROM ledger_entry le
JOIN txn t      ON t.txn_id = le.txn_id AND t.status = 'SUCCESS'
JOIN account a  ON a.account_id = le.account_id AND a.product_code <> 'TILL'
JOIN customer c ON c.customer_id = a.customer_id
JOIN branch b   ON b.branch_id = c.home_branch_id
GROUP BY b.branch_id, b.branch_code, b.branch_name, month
WITH DATA;

-- A UNIQUE index is not optional: REFRESH MATERIALIZED VIEW CONCURRENTLY
-- requires one, and concurrent refresh is what keeps the report readable
-- while it is being rebuilt.
CREATE UNIQUE INDEX uq_mv_branch_month
    ON mv_branch_monthly_volume (branch_id, month);

ANALYZE mv_branch_monthly_volume;

\echo '--- materialised view size and row count ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_total_relation_size('mv_branch_monthly_volume')) AS size
FROM mv_branch_monthly_volume;

\echo '--- refresh cost (this is the price paid for the read speed) ---'
\timing on
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_branch_monthly_volume;
\timing off

\echo '--- the report, now served from the view ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT branch_code, branch_name, month, transactions,
       to_char(credited, 'FM999,999,999,990.00') AS credited
FROM mv_branch_monthly_volume
WHERE month >= date_trunc('month', now() - INTERVAL '12 months')::date
ORDER BY branch_code, month;

\echo '--- sample of the output rows ---'
SELECT branch_code, month, transactions,
       to_char(credited, 'FM999,999,999,990.00') AS credited
FROM mv_branch_monthly_volume
ORDER BY branch_code, month DESC
LIMIT 12;

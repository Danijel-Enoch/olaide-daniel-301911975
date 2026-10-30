-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Student : Olaide Daniel (301911975)
-- File    : Optimisation step 3 - query rewriting
-- =====================================================================
-- Indexes change the access path. Rewriting changes the plan shape. The same
-- question - "which active accounts have had no posting in 180 days?" - is
-- asked three ways below. All three return the same answer; the optimiser
-- does not treat them the same.
-- =====================================================================
\pset pager off

\echo '############ R1: NOT EXISTS (correlated anti-join) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM account a
WHERE a.status = 'ACTIVE' AND a.product_code <> 'TILL' AND a.balance > 0
  AND NOT EXISTS (SELECT 1 FROM ledger_entry le
                   WHERE le.account_id = a.account_id
                     AND le.entry_ts >= now() - INTERVAL '180 days');

\echo '############ R2: NOT IN (uncorrelated subquery) ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM account a
WHERE a.status = 'ACTIVE' AND a.product_code <> 'TILL' AND a.balance > 0
  AND a.account_id NOT IN (SELECT le.account_id FROM ledger_entry le
                            WHERE le.entry_ts >= now() - INTERVAL '180 days');

\echo '############ R3: LEFT JOIN ... IS NULL ############'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM account a
LEFT JOIN (SELECT DISTINCT account_id FROM ledger_entry
            WHERE entry_ts >= now() - INTERVAL '180 days') recent
       ON recent.account_id = a.account_id
WHERE a.status = 'ACTIVE' AND a.product_code <> 'TILL' AND a.balance > 0
  AND recent.account_id IS NULL;

\echo '############ all three must agree on the answer ############'
SELECT (SELECT count(*) FROM account a
         WHERE a.status='ACTIVE' AND a.product_code<>'TILL' AND a.balance>0
           AND NOT EXISTS (SELECT 1 FROM ledger_entry le WHERE le.account_id=a.account_id
                            AND le.entry_ts >= now() - INTERVAL '180 days')) AS r1_not_exists,
       (SELECT count(*) FROM account a
         WHERE a.status='ACTIVE' AND a.product_code<>'TILL' AND a.balance>0
           AND a.account_id NOT IN (SELECT le.account_id FROM ledger_entry le
                                     WHERE le.entry_ts >= now() - INTERVAL '180 days')) AS r2_not_in,
       (SELECT count(*) FROM account a
         LEFT JOIN (SELECT DISTINCT account_id FROM ledger_entry
                     WHERE entry_ts >= now() - INTERVAL '180 days') r ON r.account_id=a.account_id
         WHERE a.status='ACTIVE' AND a.product_code<>'TILL' AND a.balance>0
           AND r.account_id IS NULL) AS r3_left_join;

\echo '############ the NOT IN NULL trap ############'
-- NOT IN against a column that can be NULL is not an anti-join at all: a
-- single NULL in the subquery makes the whole predicate UNKNOWN and the
-- result empty. ledger_entry.account_id is NOT NULL so R2 is safe here, but
-- the same rewrite over a nullable column silently returns nothing. This is
-- why NOT EXISTS is the safer default.
SELECT count(*) AS rows_returned_when_subquery_contains_null
FROM account a
WHERE a.account_id NOT IN (SELECT CASE WHEN g = 1 THEN NULL ELSE g END
                             FROM generate_series(1, 5) g);

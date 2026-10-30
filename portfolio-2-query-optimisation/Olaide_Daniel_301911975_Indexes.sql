-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Student : Olaide Daniel (301911975)
-- File    : Optimisation step 1 - indexes
-- Depends : Portfolio 1 schema + seed data
-- =====================================================================
-- Each index below names the query it serves and the reason the existing
-- indexes cannot serve it. Indexes are not free: every one of them is extra
-- work on INSERT and UPDATE, which on a ledger means slower posting. They are
-- added one per demonstrated need, not speculatively.
-- =====================================================================

-- Re-runnable: drop first, so this script can be applied repeatedly while
-- comparing plans.
DROP INDEX IF EXISTS idx_customer_lastname_lower;
DROP INDEX IF EXISTS idx_ledger_account_ts;
DROP INDEX IF EXISTS idx_ledger_debit_recent;
DROP INDEX IF EXISTS idx_loan_active_due;
DROP INDEX IF EXISTS idx_beneficiary_account_number;
DROP INDEX IF EXISTS idx_txn_created_at_cover;

-- ---------------------------------------------------------------------
-- I1 -> Q1  Case-insensitive surname search
-- Why the existing indexes fail: there is no index on last_name at all, and
-- even one would be useless here because the predicate is lower(last_name).
-- A functional index stores the computed value, and text_pattern_ops makes a
-- prefix LIKE usable (the default collation cannot support LIKE 'x%').
-- ---------------------------------------------------------------------
CREATE INDEX idx_customer_lastname_lower
    ON customer (lower(last_name) text_pattern_ops);

-- ---------------------------------------------------------------------
-- I2 -> Q2, Q5, Q8  The account history access path
-- Why: ledger_entry is the largest relation (549,590 rows) and each of these
-- queries asks for "the postings of ONE account". With no index on account_id
-- the planner must read all of them.
-- Column order matters: account_id first (equality), then entry_ts DESC to
-- match the ORDER BY so no sort node is needed, then entry_id as tie-break.
-- INCLUDE carries the payload columns in the leaf pages, which allows an
-- index-only scan - the heap is not touched at all.
-- ---------------------------------------------------------------------
CREATE INDEX idx_ledger_account_ts
    ON ledger_entry (account_id, entry_ts DESC, entry_id DESC)
    INCLUDE (txn_id, direction, amount, balance_after);

-- ---------------------------------------------------------------------
-- I3 -> Q4  Recent debit outflow (AML watchlist)
-- Why a PARTIAL index: the predicate is always direction = 'DR'. Indexing
-- only those rows halves the index and lets the planner drop the recheck.
-- 30 days out of ~18 months of history is roughly 5% of rows - selective
-- enough for an index scan to beat a sequential scan.
-- ---------------------------------------------------------------------
CREATE INDEX idx_ledger_debit_recent
    ON ledger_entry (entry_ts DESC)
    INCLUDE (account_id, amount)
    WHERE direction = 'DR';

-- ---------------------------------------------------------------------
-- I4 -> Q7  Loan arrears
-- Why a PARTIAL index: only ACTIVE loans are ever chased, and they are a
-- minority of the 2,708 rows. The index holds just those, ordered by due_on,
-- so the overdue slice is a range scan over an already small structure.
-- ---------------------------------------------------------------------
CREATE INDEX idx_loan_active_due
    ON loan (due_on)
    INCLUDE (customer_id, principal, interest_rate_pa, approved_by, loan_ref)
    WHERE status = 'ACTIVE';

-- ---------------------------------------------------------------------
-- I5 -> Q9  Beneficiary reverse lookup
-- Why: uq_beneficiary_per_customer is (customer_id, bank_code, account_number).
-- Q9 searches account_number alone - a non-leading column - so that index
-- cannot be used for a seek. A dedicated index on the searched column can.
-- ---------------------------------------------------------------------
CREATE INDEX idx_beneficiary_account_number
    ON beneficiary (account_number);

-- ---------------------------------------------------------------------
-- I6 -> Q3  Channel dashboard (HYPOTHESIS, expected to be rejected)
-- The 90-day window is ~17% of txn. Textbook guidance is that an index stops
-- paying somewhere around 5-10% selectivity, because every heap row fetched
-- is a random read. This index is created so the planner's decision can be
-- OBSERVED rather than assumed; the covering columns at least give it the
-- option of an index-only scan. The outcome is reported honestly in the
-- analysis, and Step 2 (materialised view) is the real fix.
-- ---------------------------------------------------------------------
CREATE INDEX idx_txn_created_at_cover
    ON txn (created_at)
    INCLUDE (channel_code, status, amount);

-- ---------------------------------------------------------------------
-- Statistics must be refreshed, or the planner costs these new paths with
-- stale row estimates and may ignore them.
-- ---------------------------------------------------------------------
ANALYZE customer;
ANALYZE ledger_entry;
ANALYZE txn;
ANALYZE loan;
ANALYZE beneficiary;

\echo '--- index inventory (size on disk) ---'
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'hdmb'
ORDER BY pg_relation_size(indexrelid) DESC;

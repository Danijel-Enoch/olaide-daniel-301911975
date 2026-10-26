# Portfolio 1 — Plan: Database Design and Modelling

**Student:** Olaide Daniel (301911975) · **Marks:** 7

## Objective

Produce a conceptual, logical and physical design for the HDMB ledger that
makes incorrect data *impossible to write*, not merely unlikely.

## Steps

1. **Capture the business rules** in plain English before any table exists
   (section below). A rule that is not written down does not get enforced.
2. **Conceptual model** — identify entities, relationships and cardinality;
   draw the ER diagram (`..._ER_Diagram.md`).
3. **Logical model** — map to relations, choose primary keys (surrogate
   `BIGSERIAL` + UNIQUE on the natural business key), define foreign keys.
4. **Normalise** to 3NF/BCNF starting from the unnormalised teller spreadsheet
   HDMB would otherwise use (`..._Normalisation.md`).
5. **Physical implementation** — DDL in PostgreSQL 18 (`..._Schema.sql`).
6. **Integrity layer** — CHECK constraints, partial unique index, deferred
   constraint trigger for double entry, audit trigger (`..._Constraints.sql`).
7. **Reproducible data set** — seeded generation script at realistic volume
   (`..._Seed_Data.sql`).
8. **Prove it** — a verification script for the invariants and a negative-test
   script where every block must be *rejected* (`..._Verification.sql`,
   `..._Constraint_Tests.sql`). Outputs captured under `evidence/`.

## Business rules to enforce

| # | Rule | Where enforced |
|---|---|---|
| R1 | A BVN, phone, account number and transaction reference are each unique | `UNIQUE` |
| R2 | A customer must be at least 18 years old | `chk_customer_adult` |
| R3 | KYC tier is 1, 2 or 3 | `chk_customer_kyc_tier` |
| R4 | A transaction amount is strictly positive | `chk_txn_amount_positive` |
| R5 | A customer account may never be overdrawn; the internal branch till may | `chk_account_balance_sign` |
| R6 | Every transaction is raised by a customer **or** a staff member, never both | `chk_txn_single_initiator` |
| R7 | Money is conserved: debits must equal credits for every transaction | `trg_ledger_balanced` (deferred) |
| R8 | A closed account has a closing timestamp, and only a closed account has one | `chk_account_closed_state` |
| R9 | A customer may hold only one *active* account per product | `uq_active_account_per_product` |
| R10 | A loan repayment's principal + interest equals the amount paid | `chk_repay_split` |
| R11 | Balance and status changes are never silently overwritten | `trg_account_audit` → `audit_log` |

## Design decisions taken deliberately

* **`NUMERIC(18,2)`, never `FLOAT`, for money.** Binary floating point cannot
  represent 0.10 exactly; a ledger that drifts by kobo is unauditable.
* **Double entry instead of a single `amount` column.** A transfer is two rows
  (DR, CR) whose sum is zero. This makes R7 a database-level invariant that can
  be *checked*, and it makes reversal an insert rather than an update.
* **`account.balance` is maintained, not derived on read.** Summing 550,000
  ledger rows for every balance enquiry does not scale. The redundancy is
  deliberate and is reconciled against the ledger in `..._Verification.sql`
  (step 4) — a derived column is only safe if something proves it correct.
* **The balance check is a *deferred* constraint trigger.** A per-statement check
  would fail on the debit leg, before its credit leg exists. Deferring to COMMIT
  is what makes the invariant expressible at all.
* **A partial unique index for R9.** `UNIQUE (customer_id, product_code)` would
  stop a customer from ever reopening a product after closing an account; the
  `WHERE status = 'ACTIVE'` predicate encodes the rule as the business states it.
* **Internal till accounts** give cash deposits and withdrawals a real
  counterparty, so even cash movement is double entry.

# Portfolio 1 — Normalisation of the HDMB Ledger

**Student:** Olaide Daniel (301911975)

Normalisation is shown the way it actually happens in practice: starting from
the single flat sheet the bank would otherwise keep, and removing one class of
anomaly at a time. Each step states the functional dependencies that justify it.

---

## Step 0 — The unnormalised relation (UNF)

Before the database, HDMB operations kept one spreadsheet, one row per posting:

`TELLER_SHEET(txn_ref, date, channel, channel_name, teller_name, teller_branch,
branch_state, customer_bvn, customer_name, customer_phone, customer_branch,
account_number, product_code, product_name, interest_rate, min_balance,
amount, direction, balance_after, beneficiaries_saved, narration)`

Sample row (abbreviated), with the repeating group that makes it UNF:

| txn_ref | customer_name | account_number | product_name | amount | beneficiaries_saved |
|---|---|---|---|---|---|
| HDMB-20261019-000041 | Olaide Afolabi | 0000000013 | Harmony Basic Savings | 2,500.00 | `058/0123456789 "Mum"; 011/0987654321 "Landlord"` |

**Anomalies present**

* *Repeating group* — `beneficiaries_saved` holds many values in one cell, so
  "find everyone who saves beneficiary X" cannot be answered by the query engine.
* *Insertion* — a new account product cannot be recorded until somebody
  transacts on it.
* *Update* — correcting one customer's phone number means rewriting every row
  they ever transacted on; a partial update leaves two "truths".
* *Deletion* — deleting the last posting of a branch deletes the branch's
  existence.

---

## Step 1 — First Normal Form (1NF)

> **1NF:** every attribute holds a single atomic value; no repeating groups.

`beneficiaries_saved` is removed to its own relation, keyed by the customer and
the external account it points at:

`BENEFICIARY(customer_id, bank_code, account_number, alias)`
with `UNIQUE (customer_id, bank_code, account_number)` — the same beneficiary
cannot be saved twice by the same customer.

Composite text fields are also split: `customer_name` → `first_name`,
`last_name`, because searching and sorting on a surname is a real query
(`Olaide_Daniel_301911975_Queries.sql`, Q1).

The sheet is now a single flat relation keyed by `(txn_ref, account_number,
direction)` — a posting is identified by the transaction, the account and which
side of the journal it sits on.

---

## Step 2 — Second Normal Form (2NF)

> **2NF:** 1NF, and every non-key attribute is fully functionally dependent on
> the *whole* candidate key — no partial dependencies.

The functional dependencies in the 1NF relation:

```
FD1  txn_ref                          → date, channel, amount, narration, teller_name
FD2  account_number                   → customer_bvn, product_code, customer_branch
FD3  (txn_ref, account_number, direction) → balance_after
```

FD1 and FD2 are **partial dependencies** — each determines attributes from only
part of the key. `date` and `channel` depend on the transaction alone, yet they
are repeated on both the debit and the credit row of every transfer, so the two
copies can disagree. Decomposition:

| Relation | Key | Removes |
|---|---|---|
| `TXN(txn_id, txn_ref, txn_type, channel_code, amount, status, narration, initiator, created_at, completed_at)` | `txn_id` (UK `txn_ref`) | FD1 |
| `ACCOUNT(account_id, account_number, customer_id, product_code, currency, balance, status, opened_at, closed_at)` | `account_id` (UK `account_number`) | FD2 |
| `LEDGER_ENTRY(entry_id, txn_id, account_id, direction, amount, balance_after, entry_ts)` | `entry_id` (UK `txn_id, account_id, direction`) | keeps FD3 |

`balance_after` is correctly placed: it is the one attribute that genuinely
depends on the full key — *this* account's position after *this* posting.

---

## Step 3 — Third Normal Form (3NF)

> **3NF:** 2NF, and no non-key attribute is transitively dependent on the key
> through another non-key attribute.

Remaining transitive dependencies:

```
FD4  account_id    → customer_id → customer_bvn, customer_name, customer_phone, home_branch_id
FD5  account_id    → product_code → product_name, interest_rate_pa, min_balance, daily_debit_limit
FD6  customer_id   → home_branch_id → branch_name, state, city
FD7  txn_id        → channel_code → channel_name, is_self_service
FD8  staff_id      → branch_id → branch_name, state
```

Each right-hand tail is removed into the relation its determinant owns:

| New relation | Key | Removes |
|---|---|---|
| `CUSTOMER(customer_id, bvn, first_name, last_name, date_of_birth, phone, email, residential_address, kyc_tier, home_branch_id, status, registered_at)` | `customer_id` | FD4 |
| `ACCOUNT_PRODUCT(product_code, product_name, interest_rate_pa, min_balance, daily_debit_limit)` | `product_code` | FD5 |
| `BRANCH(branch_id, branch_code, branch_name, state, city, opened_on)` | `branch_id` | FD6, FD8 |
| `CHANNEL(channel_code, channel_name, is_self_service)` | `channel_code` | FD7 |
| `STAFF(staff_id, staff_number, full_name, job_role, branch_id, work_email, is_active)` | `staff_id` | — |

**What this buys the bank, concretely:** changing the interest rate on
*Harmony Savings Plus* is now one `UPDATE` of one row in `ACCOUNT_PRODUCT`
instead of an update of 2,857 account rows and 550,000 posting rows — and there
is no state in which half the rows carry the old rate.

---

## Step 4 — Boyce-Codd Normal Form (BCNF)

> **BCNF:** for every non-trivial dependency `X → Y`, `X` is a superkey.

Every relation is checked for a determinant that is not a key:

* `CUSTOMER` — candidate keys are `customer_id`, `bvn`, `phone`. Each is a
  superkey; no other attribute determines another (`kyc_tier` does not determine
  `status`, `home_branch_id` does not determine `email`). **In BCNF.**
* `ACCOUNT` — candidate keys `account_id`, `account_number`. **In BCNF.**
* `LEDGER_ENTRY` — candidate keys `entry_id` and `(txn_id, account_id, direction)`.
  `amount` is functionally determined by `txn_id` in the *current* product set
  (both legs carry the full amount), which is a dependency on part of a candidate
  key. It is retained deliberately: split settlements and fee-bearing transfers
  post legs of differing amounts, so the dependency is an artefact of today's
  product set rather than a true constraint, and normalising it away would have
  to be undone the moment a split payment is introduced. **Documented exception.**
* `TXN`, `BRANCH`, `STAFF`, `ACCOUNT_PRODUCT`, `CHANNEL`, `LOAN`,
  `LOAN_REPAYMENT`, `BENEFICIARY` — single candidate key each, no other
  determinants. **In BCNF.**

### 4NF note

`BENEFICIARY` and `ACCOUNT` both depend on `customer_id` but are independent of
one another. Had they been kept in one relation, a customer with 3 accounts and
4 beneficiaries would need 12 rows — a multi-valued dependency and a 4NF
violation. Keeping them separate avoids it.

---

## Step 5 — Deliberate denormalisation, and how it is kept honest

Two redundancies are kept on purpose:

| Redundant attribute | Why it is kept | How it is prevented from drifting |
|---|---|---|
| `account.balance` | A balance enquiry is the single most frequent operation in the bank. Deriving it means aggregating every posting the account has ever had — 550,000 rows at this scale, growing without limit. | Reconciled against `SUM(CR) - SUM(DR)` of the ledger in `..._Verification.sql` step 4 (result: 0 accounts out of balance). Updated only inside the same transaction as the posting (Portfolio 3). |
| `ledger_entry.balance_after` | Required for a statement line and for dispute resolution: what the balance *was* at that moment cannot be recomputed after a back-dated correction. | Written once, never updated. Treated as historical fact, not as derived data. |

This is the normalisation trade-off stated plainly: the design is normalised to
BCNF for everything that represents *truth*, and denormalised only where a
derived value is needed at read time — with a test that proves the derived value
still agrees with the truth.

# Portfolio 1 — Database Design and Modelling

**Student:** Olaide Daniel · **ID:** 301911975 · **Marks:** 7
**Case study:** Harmony Digital Microfinance Bank (HDMB) — see
[`../docs/Olaide_Daniel_301911975_Case_Study.md`](../docs/Olaide_Daniel_301911975_Case_Study.md)
**Engine:** PostgreSQL 18 (`postgres:18-alpine` in Docker)

---

## What this activity delivers

| Required evidence | File |
|---|---|
| Chosen case study description | [`../docs/Olaide_Daniel_301911975_Case_Study.md`](../docs/Olaide_Daniel_301911975_Case_Study.md) |
| ER diagram | [`Olaide_Daniel_301911975_ER_Diagram.md`](Olaide_Daniel_301911975_ER_Diagram.md) (Mermaid, renders on GitHub) |
| Relational schema | [`Olaide_Daniel_301911975_Schema.sql`](Olaide_Daniel_301911975_Schema.sql) |
| Keys and constraints | [`Olaide_Daniel_301911975_Constraints.sql`](Olaide_Daniel_301911975_Constraints.sql) |
| Normalisation explanation | [`Olaide_Daniel_301911975_Normalisation.md`](Olaide_Daniel_301911975_Normalisation.md) |
| Reproducible data set | [`Olaide_Daniel_301911975_Seed_Data.sql`](Olaide_Daniel_301911975_Seed_Data.sql) |
| Proof the design holds | [`evidence/Olaide_Daniel_301911975_Design_Verification.txt`](evidence/Olaide_Daniel_301911975_Design_Verification.txt) |
| Proof the design *refuses* bad writes | [`evidence/Olaide_Daniel_301911975_Constraint_Tests.txt`](evidence/Olaide_Daniel_301911975_Constraint_Tests.txt) |
| Design plan and decisions | [`Olaide_Daniel_301911975_Plan.md`](Olaide_Daniel_301911975_Plan.md) |

## The model in one paragraph

Twelve relations in schema `hdmb`. Parties (`customer`, `staff`) sit under
reference data (`branch`, `account_product`, `channel`). Each customer holds
`account` rows, and all money movement is recorded twice: a header row in `txn`
(what was attempted, through which channel, by whom, and whether it succeeded)
and two or more rows in `ledger_entry` (the debit and the credit). Credit is
`loan` + `loan_repayment`, where every repayment is also a `txn`, so the cash
and the credit record cannot disagree. `audit_log` is an append-only sink
written by trigger whenever a balance or account status changes.

## How to reproduce it

```bash
# 1. start a clean PostgreSQL 18 instance
docker run -d --name mit8103-pg \
  -e POSTGRES_PASSWORD=mit8103 -e POSTGRES_DB=hdmb \
  -p 55432:5432 postgres:18-alpine

# 2. build the schema, the integrity layer, then the data (in this order)
for f in Schema Constraints Seed_Data; do
  docker exec -i mit8103-pg psql -U postgres -d hdmb -v ON_ERROR_STOP=1 \
    < Olaide_Daniel_301911975_$f.sql
done

# 3. reproduce the evidence files
docker exec -i mit8103-pg psql -U postgres -d hdmb \
  < Olaide_Daniel_301911975_Verification.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb \
  < Olaide_Daniel_301911975_Constraint_Tests.sql
```

`Seed_Data.sql` calls `setseed(0.301911975)` and derives every value from
`generate_series`, so the data set — and therefore every query plan and timing
in Portfolio 2 — is identical on re-run. Load time: ~27 s.

## Results obtained

From [`evidence/Olaide_Daniel_301911975_Design_Verification.txt`](evidence/Olaide_Daniel_301911975_Design_Verification.txt):

| Relation | Rows |
|---|---|
| `customer` | 20,012 |
| `account` | 24,807 |
| `txn` | 274,795 |
| `ledger_entry` | 549,590 |
| `loan` | 2,708 |
| `beneficiary` | 6,666 |

| Invariant | Result |
|---|---|
| Transactions where debits ≠ credits | **0** |
| Accounts where `balance` ≠ ledger net | **0** |
| Overdrawn customer accounts | **0** |
| Orphaned ledger entries | **0** |

Declared constraints: 12 primary keys, 15 foreign keys, 10 unique constraints,
28 check constraints, 1 partial unique index, 2 triggers.

## The negative tests

A design is only as strong as the writes it rejects.
[`evidence/Olaide_Daniel_301911975_Constraint_Tests.txt`](evidence/Olaide_Daniel_301911975_Constraint_Tests.txt)
is the captured output of seven attempts to write invalid data. **Six must fail
and one must succeed** — all seven behaved as specified:

| Test | Attempt | Result |
|---|---|---|
| T1 | Duplicate BVN | `ERROR: duplicate key value violates unique constraint "customer_bvn_key"` |
| T2 | Transfer of −5,000.00 | `ERROR: violates check constraint "chk_txn_amount_positive"` |
| T3 | Transaction with both a customer and a staff initiator | `ERROR: violates check constraint "chk_txn_single_initiator"` |
| T4 | Transaction on channel `TELEPATHY` | `ERROR: violates foreign key constraint "txn_channel_code_fkey"` |
| T5 | Debit with no matching credit (money created) | `ERROR: unbalanced transaction 274804: debits 7500.00, credits 0.00` — raised at `COMMIT` |
| T6 | The same posting with both legs | `COMMIT` ✅ |
| T7 | Second active account on a product the customer already holds | `ERROR: duplicate key value violates unique constraint "uq_active_account_per_product"` |

T5 is the one worth reading closely. The debit insert *succeeds*, and the
transaction is only rejected at `COMMIT` — that is the deferred constraint
trigger doing the job no per-row check could do, because the debit leg must be
allowed to exist briefly without its credit leg.

## Known limitations

* `ledger_entry.amount` is functionally determined by `txn_id` in the current
  product set, a documented BCNF exception retained for future split
  settlements — reasoning in
  [`Olaide_Daniel_301911975_Normalisation.md`](Olaide_Daniel_301911975_Normalisation.md) §4.
* The seed script disables the two triggers during bulk load (an `O(n²)`
  re-aggregation otherwise) and re-enables them afterwards. The verification
  step then proves the invariant holds on the loaded data, so the shortcut is
  checked rather than assumed.
* Multi-currency is modelled (`currency` on `account` and `txn`) but not
  exercised; all seeded data is NGN. FX revaluation is out of scope.

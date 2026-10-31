# Portfolio 3 — Plan: Transactions and Concurrency

**Student:** Olaide Daniel (301911975) · **Marks:** 7

## Objective

Show that HDMB's transfer is correct **under concurrency**, by first building a
version that is wrong, proving it loses money, and then proving the correct
version refuses the same workload.

## Why a single script cannot demonstrate this

A concurrency anomaly does not exist in a serial script — it exists only when
two transactions overlap in time. Every demonstration here therefore runs
**two or three genuinely separate PostgreSQL sessions**, interleaved by a
harness (`Olaide_Daniel_301911975_Concurrency_Lab.py`) that records the
wall-clock arrival time of every line of output.

The timestamps are themselves evidence: when session B emits nothing for 1.2 s
and then returns an error, that silence is the row lock.

## Steps

1. **Build the transfer properly** (`..._Transfer_Procedures.sql`):
   `SELECT ... FOR UPDATE` on both accounts, acquired in ascending
   `account_id` order, balance checked after the lock, `balance = balance - x`
   rather than `balance = <previously read value>`.
2. **Build the wrong transfer too** — `fn_transfer_naive()`, the read-modify-write
   pattern that application code falls into. Keeping it in the repository is the
   point: the two are compared on identical workloads.
3. **Build a reversal** that compensates rather than deletes.
4. **Fix the starting state** (`..._Demo_Setup.sql`) at NGN 100,000.00 per
   account, posted as a real journalised deposit so that reconciliation
   arithmetic afterwards is exact.
5. **Run seven experiments**, each with its expectation written down *before*
   the transcript:

   | Demo | Concept | Mechanism exercised |
   |---|---|---|
   | D1 | Atomicity, and no dirty reads | `BEGIN`/`COMMIT`, MVCC visibility |
   | D2 | Rollback of a whole unit of work | exception → aborted transaction |
   | D3 | **Lost update** | missing vs present `FOR UPDATE` |
   | D4 | Non-repeatable read | READ COMMITTED vs REPEATABLE READ |
   | D5 | **Write skew** | REPEATABLE READ vs SERIALIZABLE (SQLSTATE 40001) |
   | D6 | **Deadlock**, detection and prevention | lock ordering (SQLSTATE 40P01) |
   | D7 | Compensating transaction | reversal + audit trigger |

6. **Reconcile afterwards** (`..._Reconciliation.sql`): D3 deliberately
   corrupts the data, so the lab must prove the database was left consistent.

## Success criteria

* The naive transfer must be *shown* to create money, with a number attached.
* The correct transfer must refuse the same workload, and the refusal must come
  *after* a measurable lock wait — proving it re-read the balance rather than
  merely getting lucky on timing.
* Every error must be reported with its SQLSTATE, because the retry logic an
  application needs depends on which one it is: `40001` and `40P01` are
  retryable; `23514` (insufficient funds) is not.

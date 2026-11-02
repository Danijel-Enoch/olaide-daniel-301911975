# Portfolio 3 — Transactions and Concurrency

**Student:** Olaide Daniel · **ID:** 301911975 · **Marks:** 7
**Engine:** PostgreSQL 18.6 · **Accounts under test:** 900001 and 900002, NGN 100,000.00 each

---

## Required evidence, and where it is

| Required | Where |
|---|---|
| Transaction examples (commit) | [`evidence/…_D1_Atomicity_And_Commit.txt`](evidence/Olaide_Daniel_301911975_D1_Atomicity_And_Commit.txt) |
| Rollback | [`evidence/…_D2_Rollback_And_Failure.txt`](evidence/Olaide_Daniel_301911975_D2_Rollback_And_Failure.txt) |
| Isolation | [`evidence/…_D4_Isolation_Levels.txt`](evidence/Olaide_Daniel_301911975_D4_Isolation_Levels.txt) · [`…_D5_Serializable_Write_Skew.txt`](evidence/Olaide_Daniel_301911975_D5_Serializable_Write_Skew.txt) |
| Concurrency issue | [`evidence/…_D3_Lost_Update.txt`](evidence/Olaide_Daniel_301911975_D3_Lost_Update.txt) · [`…_D6_Deadlock_And_Prevention.txt`](evidence/Olaide_Daniel_301911975_D6_Deadlock_And_Prevention.txt) |
| Control mechanism | `SELECT … FOR UPDATE`, ordered lock acquisition, SERIALIZABLE — in [`…_Transfer_Procedures.sql`](Olaide_Daniel_301911975_Transfer_Procedures.sql) |
| Output evidence | seven timestamped two-session transcripts in [`evidence/`](evidence) |
| Harness (reproducibility) | [`Olaide_Daniel_301911975_Concurrency_Lab.py`](Olaide_Daniel_301911975_Concurrency_Lab.py) |

Transcripts are text, not screenshots, deliberately: they carry the exact
SQLSTATE, the server-assigned process ids and millisecond arrival times, and
they diff across commits. Each file states what it demonstrates and what was
expected *before* the transcript it contains.

## 1. The result that matters — D3, lost update

Account 900001 holds NGN 100,000.00. Two sessions each try to send
NGN 60,000.00 out of it at the same moment. Only one can legitimately succeed.

### Part 1 — `fn_transfer_naive()`, no row lock

```
[t+01.110] [A] >> SELECT fn_transfer_naive(900001, 900002, 60000.00, 'DEMO-D3-NAIVE-A');
[t+01.161] [B] >> SELECT fn_transfer_naive(900001, 900002, 60000.00, 'DEMO-D3-NAIVE-B');
[t+01.436] [A]  274810        <- A succeeded
[t+01.490] [B]  274811        <- B succeeded too
```

Both committed, 54 ms apart. The damage:

| Check | Result |
|---|---|
| Final balance of 900001 | **40,000.00** |
| Debits allowed against a 100,000.00 balance | **2, totalling 120,000.00** |
| `account.balance` − ledger position (900001) | **+60,000.00** |
| `account.balance` − ledger position (900002) | **−60,000.00** |

**NGN 60,000.00 was created out of nothing.** Both sessions read 100,000.00,
both passed their own sufficiency check, and the second `UPDATE account SET
balance = <value read earlier> - 60000` overwrote the first. That is the lost
update anomaly, and the money is unrecoverable from the balance column alone.

Two points worth drawing out:

* **The double-entry trigger did not catch it.** `trg_ledger_balanced` checks
  that *each transaction* balances, and both of these did. The corruption is in
  the denormalised `account.balance`, which is exactly why Portfolio 1 pairs
  that denormalisation with a reconciliation test rather than trusting it.
* **It is the ledger that reveals the loss.** Had the design stored only a
  balance column, there would have been no way to detect, quantify or repair
  this. The 549,590-row journal is what makes the discrepancy computable.

### Part 2 — `fn_transfer_funds()`, `SELECT … FOR UPDATE`

Identical workload, same accounts, same amounts:

```
[t+06.489] [A] >> SELECT fn_transfer_funds(900001, 900002, 60000.00, 'DEMO-D3-SAFE-A');
[t+06.500] [A]  274812                       <- A holds the row lock
[t+06.894] [B] >> SELECT fn_transfer_funds(900001, 900002, 60000.00, 'DEMO-D3-SAFE-B');
                                             <- B: 1.2 s of silence. It is blocked.
[t+08.095] [A] >> COMMIT;
[t+08.112] [B] ERROR:  insufficient funds on 9900000001: balance 40000.00,
                       requested 60000.00, minimum balance 5000.00
```

| Check | Result |
|---|---|
| Final balance of 900001 | 40,000.00 after **one** 60,000.00 transfer |
| `account.balance` − ledger position | **0.00 on both accounts** |
| Second attempt | refused, SQLSTATE 23514 |

The 1.2-second gap is the proof. B did not fail because of a race it lost — it
**waited** for A's lock, then re-read the committed balance (40,000.00, not the
stale 100,000.00) and applied the rule to the true value. The error message
quoting `balance 40000.00` is the evidence that the re-read happened.

## 2. D1 — atomicity and the absence of dirty reads

With A's transfer uncommitted, A and an uninvolved session C read the same two
rows at the same instant:

| Reader | 900001 | 900002 |
|---|---|---|
| A (inside its own transaction, t+02.218) | 75,000.00 | 125,000.00 |
| C (uninvolved, t+02.729) | **100,000.00** | **100,000.00** |
| C (after A commits, t+04.132) | 75,000.00 | 125,000.00 |

The psql prompt in the transcript changes from `hdmb=#` to `hdmb=*#` for the
duration — the `*` marks an open transaction. PostgreSQL's MVCC means C never
sees A's uncommitted rows; a dirty read is not merely discouraged, it is
unavailable at every isolation level the engine offers.

## 3. D2 — rollback undoes valid work too

A makes a valid 10,000.00 transfer, then attempts 120,000.00 against a
100,000.00 balance with a 5,000.00 minimum:

```
ERROR:  insufficient funds on 9900000001: balance 90000.00, requested 120000.00,
        minimum balance 5000.00                                    (SQLSTATE 23514)
ERROR:  current transaction is aborted, commands ignored until end of transaction block
```

After `ROLLBACK`, both balances are 100,000.00 and `surviving_demo_d2_rows = 0`
— **the valid first transfer is gone as well.** The unit of atomicity is the
transaction, not the statement. For a channel that batches several postings,
that is the difference between an all-or-nothing settlement and a half-applied
one; it is also why the switch sends one `txn_ref` per logical operation.

## 4. D4 — the isolation level is the only thing that changed

Same query, same session, same row, read twice with B committing a 5,000.00
transfer in between:

| A's isolation level | First read | Second read | Anomaly |
|---|---|---|---|
| `read committed` (default) | 100,000.00 | **95,000.00** | Non-repeatable read |
| `repeatable read` | 95,000.00 | **95,000.00** | None — snapshot frozen |

After A commits, the same query returns 90,000.00, confirming A was reading a
snapshot rather than a cache. The operational consequence for HDMB: a
multi-query report (balance sheet by product, then by branch) run at READ
COMMITTED can produce two totals that do not agree, because each statement
takes a fresh snapshot. Such reports must run at REPEATABLE READ.

## 5. D5 — write skew, and the limit SERIALIZABLE saves

HDMB caps daily debits at NGN 50,000.00 per account. Each session sums today's
debits, sees 0.00, and posts 30,000.00. Neither writes a row the other read, so
**no row lock can detect this** — there is no common row to lock.

| Both sessions at | Outcome |
|---|---|
| `REPEATABLE READ` | Both commit. `total_debited_today = 60,000.00`, `daily_limit = 50,000.00` → **LIMIT BREACHED**, no error raised anywhere |
| `SERIALIZABLE` | `ERROR: could not serialize access due to read/write dependencies among transactions` (**SQLSTATE 40001**) on the second committer; total stays 30,000.00 → **within limit** |

This is the anomaly most likely to reach production, because it looks like
nothing is wrong: no deadlock, no error, no lost row — just a rule quietly
broken. The fix costs nothing in schema terms and is one line at the start of
the transaction, but it moves responsibility to the application: a 40001 means
*retry the whole transaction*, and code that does not retry converts a
correctness guarantee into a user-visible failure.

## 6. D6 — deadlock: cause, detection, prevention

**Caused** by unordered locking — A locks 900001 then wants 900002; B the
reverse. Session C observes the wait graph *inside* the one-second
`deadlock_timeout` window, before the detector acts:

```
[t+02.381] [C]  pid  | state  | wait_event_type |  wait_event
                1008 | active | Lock            | transactionid
                1009 | active | Lock            | transactionid
[t+03.023] [A] ERROR:  deadlock detected                              (SQLSTATE 40P01)
           DETAIL:  Process 1008 waits for ShareLock on transaction 1062; blocked by process 1009.
                    Process 1009 waits for ShareLock on transaction 1061; blocked by process 1008.
```

The `DETAIL` is the full cycle, printed by the server. PostgreSQL does not hang:
after `deadlock_timeout` it checks for a cycle, picks a victim and aborts it.

**Prevented** by `fn_transfer_funds()`, which always locks the lower
`account_id` first. The same two opposite-direction transfers then both
succeed — 900001 ends at 97,000.00 and 900002 at 103,000.00 (−7,000 +4,000),
`both_transfers_committed = 2`. A cycle cannot form if every transaction
acquires locks in the same global order, which is why that ordering is in the
function rather than left to the caller.

## 7. D7 — reversal without destroying history

| After | 900001 | 900002 |
|---|---|---|
| 18,500.00 transfer | 81,500.00 | 118,500.00 |
| reversal | 100,000.00 | 100,000.00 |

```
DEMO-D7-DISPUTED     | REVERSED | 18500.00 | Transfer 9900000001 -> 9900000002
REV-DEMO-D7-DISPUTED | SUCCESS  | 18500.00 | REVERSAL of DEMO-D7-DISPUTED: customer dispute …
```

All four ledger legs survive, the original is marked `REVERSED` rather than
edited or deleted, and `audit_log` carries the before/after of every balance
change (`81500.00 → 100000.00`, `118500.00 → 100000.00`). A second reversal of
the same transaction is refused: `ERROR: transaction DEMO-D7-DISPUTED is
already reversed`. The customer's original statement line remains
reproducible — which is the whole reason a bank compensates instead of deletes.

## 8. Error codes, and what an application must do with them

| SQLSTATE | Meaning here | Correct application response |
|---|---|---|
| `23514` | Insufficient funds / minimum balance | **Do not retry** — tell the customer |
| `40001` | Serialization failure (D5) | **Retry** the whole transaction |
| `40P01` | Deadlock, this session was the victim (D6) | **Retry**, ideally with ordered locking so it cannot recur |
| `55000` | Account frozen/closed, or already reversed (D7) | Do not retry — operations issue |
| `23505` | Duplicate `txn_ref` | Treat as already-processed (idempotent replay) |

Distinguishing retryable from non-retryable is the practical pay-off of this
portfolio: a retry loop around `23514` spams a customer who simply has no
money, and no retry around `40001` turns a solved problem into an outage.

## 9. The database was left consistent

D3 part 1 intentionally corrupts data, so the lab ends by proving the damage
was contained — [`evidence/…_Post_Lab_Reconciliation.txt`](evidence/Olaide_Daniel_301911975_Post_Lab_Reconciliation.txt):

| Check | Result |
|---|---|
| Transactions where debits ≠ credits | **0** |
| Accounts whose stored balance ≠ ledger position | **0** |
| Overdrawn customer accounts | **0** |
| Demo accounts | 97,000.00 / 103,000.00, both matching their ledger exactly |
| Audit rows written during the lab | 92 |

## 10. Reproducing it

```bash
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Demo_Setup.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Transfer_Procedures.sql
python3 Olaide_Daniel_301911975_Concurrency_Lab.py            # all seven demos
python3 Olaide_Daniel_301911975_Concurrency_Lab.py D3 D6      # or selected ones
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Reconciliation.sql
```

The harness needs only Python 3 (standard library — `pty`, `select`,
`subprocess`) and the running container.

## 11. Limitations

* The interleaving is produced by fixed pauses between statements, not by a
  load generator. It is reliable because each demo's critical section is held
  open deliberately (`pg_sleep(0.3)` in the naive transfer, an uncommitted
  transaction in D3 part 2) — but these are *demonstrations* of an anomaly, not
  measurements of how often it occurs under production load.
* Absolute timestamps depend on this machine. The orderings and the SQLSTATEs
  are the reproducible evidence.
* `fn_transfer_funds()` does not implement the daily-debit limit from D5. D5
  shows the anomaly on raw SQL to keep the mechanism visible; enforcing the
  limit in the function would need either SERIALIZABLE or a per-account
  counter row to lock, and that choice is outside this portfolio's scope.

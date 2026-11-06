# Evidence Index

**Student:** Olaide Daniel · **ID:** 301911975 · **Course:** MIT 8103 Advanced Database Systems

Every file below is **captured process output** — a command's stdout/stderr
redirected to a file. None of it was typed, edited or reformatted after capture,
which is why the files contain raw psql prompts, container process ids and
unrounded timings. Each row states what the file *proves* and the command that
regenerates it.

---

## Portfolio 1 — Database Design and Modelling

| File | What it proves | Regenerate with |
|---|---|---|
| [`…_Design_Verification.txt`](../portfolio-1-database-design/evidence/Olaide_Daniel_301911975_Design_Verification.txt) | Relation volumes (20,012 customers · 549,590 ledger entries); constraint inventory (12 PK, 15 FK, 10 UNIQUE, 28 CHECK); and the four invariants all at **0** — unbalanced transactions, accounts out of balance, overdrawn customer accounts, orphaned entries | `psql -f Olaide_Daniel_301911975_Verification.sql` |
| [`…_Constraint_Tests.txt`](../portfolio-1-database-design/evidence/Olaide_Daniel_301911975_Constraint_Tests.txt) | Seven attempted writes: **six rejected, one accepted**, each with its actual error. Includes the deferred trigger rejecting a single-sided posting at `COMMIT` | `psql -f Olaide_Daniel_301911975_Constraint_Tests.sql` |

## Portfolio 2 — Query Processing and Optimisation

| File | What it proves | Regenerate with |
|---|---|---|
| [`…_baseline_Plans.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_baseline_Plans.txt) | Full `EXPLAIN (ANALYZE, BUFFERS)` for all ten queries **before** optimisation, including `Parallel Seq Scan` with `Rows Removed by Filter: 183188` | `./Olaide_Daniel_301911975_Measure.sh baseline` |
| [`…_optimised_Plans.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_optimised_Plans.txt) | The same ten plans **after** optimisation, including `Index Only Scan … Heap Fetches: 0` | `./Olaide_Daniel_301911975_Measure.sh optimised` |
| [`…_baseline_Timings.csv`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_baseline_Timings.csv) · [`…_optimised_Timings.csv`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_optimised_Timings.csv) | Machine-readable best-of-three timings and scan methods — the source of the 54× and 89× figures | same two commands |
| [`…_Index_Creation.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_Index_Creation.txt) | The six indexes being created, and their size on disk (61 MB of new indexes) | `psql -f Olaide_Daniel_301911975_Indexes.sql` |
| [`…_Materialised_View.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_Materialised_View.txt) | Report at **0.234 ms** from the view vs 337.070 ms from base tables, and the **479.957 ms** refresh cost that pays for it | `psql -f Olaide_Daniel_301911975_Materialised_View.sql` |
| [`…_Query_Rewrites.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_Query_Rewrites.txt) | Same question three ways — 68.7 ms / 99.7 ms / 541.8 ms — all returning 6,046; plus `NOT IN` returning **0 rows** when the subquery contains NULL | `psql -f Olaide_Daniel_301911975_Query_Rewrites.sql` |
| [`…_Query_Results.txt`](../portfolio-2-query-optimisation/evidence/Olaide_Daniel_301911975_Query_Results.txt) | The actual result set of each of the ten queries | loop in README §7 |

## Portfolio 3 — Transactions and Concurrency

All seven are timestamped multi-session transcripts (`[t+nn.nnn] [A|B|C]`).
Each file carries its own "what this demonstrates" and "expected result"
header, written before the run.

| File | What it proves | Regenerate with |
|---|---|---|
| [`…_D1_Atomicity_And_Commit.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D1_Atomicity_And_Commit.txt) | Session A sees 75,000/125,000 uncommitted while session C sees 100,000/100,000 at the same instant — no dirty read; prompt shows `hdmb=*#` for the open transaction | `python3 …_Concurrency_Lab.py D1` |
| [`…_D2_Rollback_And_Failure.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D2_Rollback_And_Failure.txt) | SQLSTATE 23514, then `current transaction is aborted`, then after `ROLLBACK` both balances restored and `surviving_demo_d2_rows = 0` — the earlier **valid** transfer is gone too | `… D2` |
| [`…_D3_Lost_Update.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D3_Lost_Update.txt) | **The portfolio's central result.** Without `FOR UPDATE`: two 60,000 debits against a 100,000 balance both commit, discrepancy **+60,000/−60,000**. With `FOR UPDATE`: 1.2 s lock wait, second attempt refused, discrepancy **0.00** | `… D3` |
| [`…_D4_Isolation_Levels.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D4_Isolation_Levels.txt) | READ COMMITTED: 100,000 → 95,000 (non-repeatable read). REPEATABLE READ: 95,000 → 95,000, then 90,000 after commit | `… D4` |
| [`…_D5_Serializable_Write_Skew.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D5_Serializable_Write_Skew.txt) | REPEATABLE READ: `60000.00 / 50000.00 / LIMIT BREACHED` with no error. SERIALIZABLE: `could not serialize access due to read/write dependencies` (**40001**) and the limit holds | `… D5` |
| [`…_D6_Deadlock_And_Prevention.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D6_Deadlock_And_Prevention.txt) | Observer catches both sessions on `Lock/transactionid`, then `deadlock detected` (**40P01**) with the server's full wait graph; ordered locking then lets both opposite-direction transfers commit | `… D6` |
| [`…_D7_Reversal_And_Audit.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_D7_Reversal_And_Audit.txt) | Original marked `REVERSED`, compensating transaction with swapped legs, all four ledger legs intact, `audit_log` before/after values, duplicate reversal refused | `… D7` |
| [`…_Post_Lab_Reconciliation.txt`](../portfolio-3-transactions-concurrency/evidence/Olaide_Daniel_301911975_Post_Lab_Reconciliation.txt) | After the lab that deliberately corrupted data: **0** unbalanced transactions, **0** accounts out of balance, **0** overdrawn, 92 audit rows | `psql -f …_Reconciliation.sql` |

## Portfolio 4 — NoSQL and Advanced Data Models

| File | What it proves | Regenerate with |
|---|---|---|
| [`…_Load_Log.txt`](../portfolio-4-nosql/evidence/Olaide_Daniel_301911975_Load_Log.txt) | The ETL end to end: export line counts, staging, `mongoimport` with validators active, 1,988 + 42,924 documents loaded with **zero rejections**, and one stored document printed in full with `Decimal128` and `ISODate` types | `./Olaide_Daniel_301911975_Load.sh` |
| [`…_Query_Evidence.txt`](../portfolio-4-nosql/evidence/Olaide_Daniel_301911975_Query_Evidence.txt) | M1–M9: `EXPRESS_IXSCAN`, a multikey-index lookup into an embedded array, a sort served by a compound index (`docsExamined = 20` for 20 returned), two aggregation pipelines, `$merge` building 32,758 edges in 253 ms, `$graphLookup` reaching 13 accounts, **4 validator rejections + 1 acceptance**, and the unbalanced document the validator **accepts** | `mongosh hdmb --file …_Queries.js` |
| [`…_KeyValue_Evidence.txt`](../portfolio-4-nosql/evidence/Olaide_Daniel_301911975_KeyValue_Evidence.txt) | K1–K8: TTLs, `SET NX` returning nil on retry, the atomic Lua limit admitting **1 of 3** debits, parallel `INCR` giving **exactly 2000**, bounded list after `LTRIM`, sorted-set ranking, and the full key inventory with types and TTLs | `./Olaide_Daniel_301911975_KeyValue_Redis.sh` |
| [`…_Relational_Equivalent.txt`](../portfolio-4-nosql/evidence/Olaide_Daniel_301911975_Relational_Equivalent.txt) | The same home screen in SQL: 2.212 ms + 1.167 ms across two round trips and four joins — the basis for the honest "not an order of magnitude" comparison | `psql -f …_Relational_Equivalent.sql` |

## Portfolio 5 — Distributed and Cloud Database Exercise

| File | What it proves | Regenerate with |
|---|---|---|
| [`…_Replication_Evidence.txt`](../portfolio-5-distributed-cloud/evidence/Olaide_Daniel_301911975_Replication_Evidence.txt) | R1 topology (both standbys `streaming`, slots active, 549,590 rows on each node) · R2 `cannot execute INSERT in a read-only transaction` · R3 `write_lag` 11.6 ms / `flush_lag` 15.1 ms / `replay_lag` 46.0 ms · R4 the A-B-A whose **control failed** · R5 the blocked write with `wait_event = 'SyncRep'` while reads continue · R6 promotion, `00000002.history` timeline switch, **0 rows lost**, replica-2 orphaned | `./Olaide_Daniel_301911975_Replication_Lab.sh` (destructive) |
| [`…_Sync_Latency_Benchmark.txt`](../portfolio-5-distributed-cloud/evidence/Olaide_Daniel_301911975_Sync_Latency_Benchmark.txt) | Six alternating rounds with the mode verified before each: async **1.440 ms** (1.257–1.575) vs sync **2.147 ms** (2.041–2.216), **+49.1%** with non-overlapping ranges | `./Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh` |
| [`…_Sharding_Evidence.txt`](../portfolio-5-distributed-cloud/evidence/Olaide_Daniel_301911975_Sharding_Evidence.txt) | 100,000 rows distributed in 1.261 s; hash distribution 43,428/56,572 over near-equal account counts; single-shard pruning to **one** `Foreign Scan` (0.541 ms); cross-shard `Async Foreign Scan` (124.084 ms); `now()` **blocking pushdown** and shipping 41,448 wasted rows; a literal timestamp cutting the same query to **5.069 ms**; aggregate pushdown; and a sharded↔local join that cannot be pushed down | `psql -f Olaide_Daniel_301911975_Sharding.sql` |

---

## Cross-portfolio threads worth following

Three arguments run across activities, and the evidence can be read end to end:

1. **The lost update, three times.** `D3_Lost_Update.txt` shows it happening in
   SQL (NGN 60,000 created), `KeyValue_Evidence.txt` K4 shows the same workload
   losing nothing when the operation is atomic server-side, and
   `Design_Verification.txt` step 4 is the reconciliation test that makes the
   denormalised balance column safe to keep at all.
2. **The daily limit, two solutions.** `D5_Serializable_Write_Skew.txt` needs
   SERIALIZABLE plus retry-on-40001; `KeyValue_Evidence.txt` K3 solves the same
   rule with one atomic script and no isolation level — with durability traded
   away, which is why it guards a policy limit and not a balance.
3. **Integrity that cannot be bypassed vs integrity that can.**
   `Constraint_Tests.txt` T5 (deferred trigger rejects a single-sided posting)
   against `Query_Evidence.txt` M9 (MongoDB accepts DR 5,000 / CR 4,000). That
   pair is the reason PostgreSQL is the system of record and the NoSQL stores
   hold derived views.

## Three results that contradicted my recorded expectations

Kept deliberately, because an exercise where every result confirms an unstated
expectation is not evidence:

| Expectation | What happened | Evidence |
|---|---|---|
| An index would be rejected at ~17% selectivity | The **covering** index was used and won 1.8× — the 5–10% rule is about random heap reads, which a covering index removes | `…_optimised_Plans.txt` Q3 |
| `statement_timeout` would abort a write blocked on a synchronous standby | It does not — the commit is locally durable and the wait is uninterruptible | `…_Replication_Evidence.txt` R5 |
| One async→sync→async comparison would establish the cost of synchronous commit | Its control run came back **slower** than the sync run; the number was not reportable until a repeated-measures benchmark was written | `…_Replication_Evidence.txt` R4 → `…_Sync_Latency_Benchmark.txt` |

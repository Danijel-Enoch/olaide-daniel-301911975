# Portfolio 5 — Distributed and Cloud Database Exercise

**Student:** Olaide Daniel · **ID:** 301911975 · **Marks:** 6
**Cluster:** 1 primary + 2 streaming replicas + 2 shard nodes (PostgreSQL 18.6, docker compose)
**Data:** the same HDMB ledger as Portfolios 1–4 — 549,590 entries, seeded identically

---

## Required evidence, and where it is

| Required | Where |
|---|---|
| Distributed/cloud setup on the same case study | [`cluster/Olaide_Daniel_301911975_docker-compose.yml`](cluster/Olaide_Daniel_301911975_docker-compose.yml) + node bootstrap scripts |
| Replication | [`evidence/…_Replication_Evidence.txt`](evidence/Olaide_Daniel_301911975_Replication_Evidence.txt) R1–R3 |
| Consistency | R4–R5 + [`evidence/…_Sync_Latency_Benchmark.txt`](evidence/Olaide_Daniel_301911975_Sync_Latency_Benchmark.txt) |
| Availability / failover | R6 — promotion, timeline switch, data-loss count |
| Sharding | [`Olaide_Daniel_301911975_Sharding.sql`](Olaide_Daniel_301911975_Sharding.sql) → [`evidence/…_Sharding_Evidence.txt`](evidence/Olaide_Daniel_301911975_Sharding_Evidence.txt) |
| Deployment evidence | compose file, `pg_basebackup` clone log, `pg_stat_replication`, `pg_replication_slots` |
| Cloud discussion | [`Olaide_Daniel_301911975_Cloud_Deployment.md`](Olaide_Daniel_301911975_Cloud_Deployment.md) |

## 1. The cluster

```
       writes                    reads                      shards
  ┌──────────────┐        ┌──────────────┐          ┌──────────────┐
  │  pg-primary  │─ WAL ─▶│ pg-replica-1 │          │  pg-shard-a  │
  │   :55433     │        │   :55434     │          │   :55436     │
  │              │─ WAL ─▶│ pg-replica-2 │          │  pg-shard-b  │
  └──────────────┘        │   :55435     │          │   :55437     │
         └── postgres_fdw ───────────────────────────────────┘
```

Replicas bootstrap themselves: the entrypoint waits for the primary, runs
`pg_basebackup -Fp -Xs -R -S <slot>`, and starts in hot standby. The primary's
init script creates the replication role, two **physical replication slots**,
and the `pg_hba` rule for replication connections. Each node holds the full
549,590-row ledger; the shard nodes hold slices of a separate distributed table.

**Replication and sharding are not alternatives** and both are implemented:

| | Replication | Sharding |
|---|---|---|
| Copies | all data to every node | a slice to each node |
| Buys | availability, read capacity, durability | write capacity, data larger than one machine |
| Costs | write latency (synchronous) or stale reads (asynchronous) | cross-shard queries, no cross-shard joins |

## 2. Replication is working (R1–R3)

| Check | Result |
|---|---|
| `pg_stat_replication` | `replica_1` and `replica_2` both `streaming`, `0 bytes` behind |
| Replication slots | both `active`, WAL retained as needed |
| `pg_is_in_recovery()` | `f` on the primary, `t` on both standbys |
| Ledger rows on each node | 549,590 / 549,590 / 549,590 |
| Write on a standby | `ERROR: cannot execute INSERT in a read-only transaction` |
| Lag after a 20,000-row burst | `write_lag` 11.6 ms · `flush_lag` 15.1 ms · `replay_lag` **46.0 ms** |
| End-to-end visibility on the replica | ~400 ms (includes client round trips) |

The three lag columns matter separately, and the ordering in the output shows
why: WAL **arrives** (11.6 ms) before it is **flushed** (15.1 ms) before it is
**replayed and visible to readers** (46.0 ms). A read replica is behind by the
*replay* figure, not the arrival figure — so HDMB's balance screen must read the
primary, while dashboards may read a replica.

## 3. The cost of consistency, measured twice — because the first attempt failed

**This section is the methodological core of the portfolio and is reported as
it happened.**

Experiment R4 measured pgbench commit latency asynchronous → synchronous →
asynchronous, the third run being a control:

| Run | Mode (verified) | Latency |
|---|---|---|
| (a) | async | 1.640 ms |
| (b) | **sync** | 2.114 ms |
| (c) | async *control* | **2.703 ms** |

**The control failed.** It came back slower than the condition it was
controlling for, which means host load moved more than the setting did. The
"+29% for synchronous commit" that (a) and (b) suggest is therefore not
supported — it is a number from an experiment that failed its own control.

Two earlier defects had to be fixed before even getting this far, and both are
worth recording:

* `ALTER SYSTEM SET synchronous_standby_names = …; SELECT pg_reload_conf();`
  sent as **one** `psql -c` string fails with `ERROR: ALTER SYSTEM cannot run
  inside a transaction block`, because `-c` wraps a multi-statement string in an
  implicit transaction. The first version of the lab swallowed that error and
  went on to "measure" synchronous replication that had never been enabled —
  reporting sync as *faster* than async. `set_sync()` now sends the statements
  separately and **prints `SHOW synchronous_standby_names` and each standby's
  `sync_state` before any number is taken.**
* Setting `synchronous_standby_names` in the compose `command:` deadlocked the
  cluster at startup: the primary blocked on its own `CREATE DATABASE`, waiting
  for a standby that could not exist until the primary was up. The setting is
  now applied at runtime — which is also better pedagogy, since it turns the
  trade-off into an experiment.

So the measurement was redone properly
([`Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh`](Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh)):
six alternating rounds of 500 commits, mode verified before each round.

| Round | Mode | Latency | TPS |
|---|---|---|---|
| 1 | async | 1.257 ms | 795 |
| 2 | **sync** | 2.216 ms | 451 |
| 3 | async | 1.575 ms | 635 |
| 4 | **sync** | 2.041 ms | 490 |
| 5 | async | 1.488 ms | 672 |
| 6 | **sync** | 2.185 ms | 458 |

| | n | mean | median | range |
|---|---|---|---|---|
| Asynchronous | 3 | **1.440 ms** | 1.488 ms | 1.257 – 1.575 |
| Synchronous | 3 | **2.147 ms** | 2.185 ms | 2.041 – 2.216 |

**Mean difference: +0.707 ms (+49.1%)**, and the two ranges **do not overlap** —
every synchronous round was slower than every asynchronous round. The cost is
now attributable to the setting rather than to ambient load.

Scale caveat stated plainly: this is two containers on one host, so the WAL
acknowledgement travels over loopback. Across two availability zones (1–2 ms
RTT) the overhead would be substantially larger. HDMB should still pay it on
the ledger — a lost transfer costs more than a slow one.

## 4. CAP, as an experiment rather than a diagram (R5)

With `replica_1` verified as `sync`, the synchronous standby was stopped and a
write attempted:

```
  after 5 seconds the INSERT has STILL not returned - it is blocked
 pid | state  | wait_event_type | wait_event |            query
-----+--------+-----------------+------------+---------------------------
 357 | active | IPC             | SyncRep    | INSERT INTO repl_probe …
reads still served: 20900 probe rows
```

* The write **blocked**, visible as `wait_event = 'SyncRep'`.
* **Reads continued to be served** throughout — the node was healthy.
* Reverting `synchronous_standby_names` to `''` **released the pending commit
  immediately**, and the next write succeeded with the standby still down.

The cluster chose **consistency**: rather than acknowledge a write it could not
replicate, it refused to acknowledge the write at all. What was sacrificed was
*write* availability specifically, which is a more precise statement than "CAP
says pick two".

One finding came out of being wrong: I expected `statement_timeout` to abort the
blocked write. **It does not.** The commit is already durable on the primary;
what is outstanding is the standby's acknowledgement, and PostgreSQL will not
abandon it — cancelling the client would leave a commit that is locally durable
but never acknowledged to the application. The experiment was redesigned to
*observe* the blocked backend instead of timing it out, which is stronger
evidence than the timeout would have produced.

## 5. Failover (R6)

| Step | Observed |
|---|---|
| Before the failure | both standbys `0 bytes` behind; primary at `0/2370BAC0`; 20,902 probe rows |
| Primary killed | writes impossible cluster-wide — **a standby cannot promote itself** |
| Write on the unpromoted standby | `ERROR: cannot execute INSERT in a read-only transaction` |
| `pg_promote(wait => true)` | returned `t`; `pg_is_in_recovery()` → `f` |
| Timeline | `00000002.history` created: `1  0/2370BB38  no recovery target specified` |
| First write on the new primary | succeeded, `id = 20923` |
| **Rows lost** | **0** (20,902 before → 20,902 surviving) |
| `replica-2` | still a standby, stuck at `0/2370BB38` on the **old** timeline |

Three things this makes concrete:

1. **The timeline increment is the anti-split-brain mechanism.** The promoted
   node generates WAL on timeline 2; the old primary, if it came back, would be
   on timeline 1 and cannot silently rejoin as a peer.
2. **Zero data loss was luck, not design** — both standbys happened to be fully
   caught up. With asynchronous replication and writes in flight, everything in
   the ~46 ms replay window would have been lost. That is the argument for a
   synchronous standby on a ledger.
3. **The slow part of failover is not the promotion.** `pg_promote()` took
   under two seconds. `replica-2` is now orphaned on a superseded timeline and
   needs `pg_rewind` or a fresh basebackup before it can follow the new primary
   — and that is the work a managed cloud database automates.

## 6. Sharding (S1)

`ledger_distributed` is **hash-partitioned on `account_id`** across two nodes
through `postgres_fdw`. The shard key was chosen because every query that must
stay fast carries it; sharding by branch would have put most of the bank in
Lagos, and sharding by date would have sent every write to one shard.

100,000 entries loaded in **1.074 s** (`batch_size '1000'` on the foreign
servers — without batching, remote inserts go one row at a time):

| Shard | Rows | Distinct accounts | Value |
|---|---|---|---|
| `ledger_distributed_s0` (shard-a) | 43,428 | 12,456 | 20,058,957,142.50 |
| `ledger_distributed_s1` (shard-b) | 56,572 | 12,351 | 32,135,250,660.00 |

**The distribution is a finding, not a flaw to hide.** Accounts are split almost
exactly evenly (12,456 vs 12,351), but *rows* are 43/57. Hash sharding balances
**keys**, not **load** — some accounts simply transact more. A shard key can be
perfectly uniform and still produce an unbalanced cluster, which is why capacity
planning has to look at rows per shard rather than keys per shard.

| Query | Plan | Time |
|---|---|---|
| `WHERE account_id = 4211` (shard key present) | **one** `Foreign Scan`, predicate pushed as `WHERE ((account_id = 4211))` | **0.681 ms** |
| 30-day aggregate, no shard key | `Append` over **two** `Async Foreign Scan`s | 123.967 ms |

Partition pruning removed the other shard from the plan entirely — the
coordinator did not contact it at all. The cross-shard query used PostgreSQL
18's **asynchronous** append, scanning both nodes concurrently rather than
sequentially.

## 7. The limits of sharding (S2)

### Predicate pushdown is not automatic

The 30-day aggregate above produced this remote SQL:

```
Remote SQL: SELECT direction, amount, entry_ts FROM public.ledger_shard
Filter: (entry_ts >= (now() - '30 days'::interval))
Rows Removed by Filter: 41411
```

**No `WHERE` clause reached the shard.** `now()` is a `STABLE` function whose
value must be fixed by the coordinator's transaction, so `postgres_fdw` will not
send it. Every row was shipped across the network and 41,411 of 43,428 were
discarded locally — 95% waste.

Computing the boundary first and passing a literal fixes it:

```
Remote SQL: SELECT direction, amount FROM public.ledger_shard
            WHERE ((entry_ts >= '2026-10-06 22:28:43.372388+00'))
```

| Same query | Time |
|---|---|
| With `now()` in the predicate | 123.967 ms |
| With a literal timestamp | **3.394 ms** |

**A 36× improvement from pushdown alone**, with no change to indexes, hardware
or data. And with a pushdown-safe predicate the **aggregate** pushes down too
(S2 step 11): each shard returns 2 aggregated rows instead of ~2,000 raw ones.

### A join across the shard boundary cannot be pushed down at all

`account` lives on the coordinator; `ledger_distributed` lives on the shards.
The plan ships rows back and joins centrally:

```
Hash Join
  ->  Append
        ->  Async Foreign Scan on ledger_distributed_s0
        ->  Async Foreign Scan on ledger_distributed_s1
  ->  Hash  ->  Seq Scan on hdmb.account  (24,807 rows)
```

110.514 ms, and it would scale with the data shipped rather than with the answer
returned. This is the real price of sharding: **the shard key must match the
access pattern, because queries that cross it cost network round trips instead
of index lookups.** A query by account is one shard; a query by date or by
branch is all of them.

## 8. What this means for HDMB

The cloud mapping, indicative costs and migration path are in
[`Olaide_Daniel_301911975_Cloud_Deployment.md`](Olaide_Daniel_301911975_Cloud_Deployment.md).
The conclusion is deliberately conservative: **HDMB should not shard.**
549,590 ledger rows and 194 MB fit comfortably on one node, and S1 demonstrates
the technique at a scale where it is not yet justified. The right architecture
today is a Multi-AZ managed PostgreSQL with one asynchronous read replica, the
indexes from Portfolio 2, and the transaction discipline from Portfolio 3 —
and the specific signals that would change that answer are listed in §7 of the
cloud document.

## 9. Reproducing it

```bash
cd cluster
docker compose -f Olaide_Daniel_301911975_docker-compose.yml up -d
# the primary seeds itself from the Portfolio 1 scripts (~30 s), then the
# standbys clone it with pg_basebackup (~20 s)
cd ..
docker exec -i mit8103-primary psql -U postgres -d hdmb < Olaide_Daniel_301911975_Sharding.sql
./Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh
./Olaide_Daniel_301911975_Replication_Lab.sh     # R6 fails the primary over
```

Run the benchmark **before** the replication lab: R6 promotes a standby and
leaves the cluster on a new timeline, so re-running anything afterwards needs
`docker compose … down -v && up -d`.

## 10. Limitations

* **No WAL archiving, so no point-in-time recovery.** This is the largest gap
  between this cluster and a deployment, and the first thing I would add.
* **Failover is manual.** R6 shows why that is unacceptable in production: a
  standby cannot promote itself, so writes stop until a human acts. Production
  needs Patroni/repmgr or a managed control plane.
* **`replica-2` is left orphaned** after R6 rather than rewound. Doing the
  `pg_rewind` is the obvious next exercise.
* **Laboratory security.** Plain-text passwords, no TLS between nodes, and
  nodes trusting the compose network. The compose file says so explicitly.
* **One host.** All five nodes share a kernel, a disk and a loopback interface,
  which is why §3 states the scale caveat rather than presenting +49.1% as a
  figure that would transfer to a real multi-AZ deployment.
* **Sharding is one-way here.** `ledger_distributed` is populated by a bulk
  `INSERT … SELECT`; there is no dual-write, no rebalancing and no resharding,
  all of which a production sharded system needs.

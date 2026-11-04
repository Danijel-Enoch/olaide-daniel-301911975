# Portfolio 5 — Plan: Distributed and Cloud Database Exercise

**Student:** Olaide Daniel (301911975) · **Marks:** 6

## Objective

Run HDMB's ledger on more than one node, and measure what that costs — rather
than describe replication and sharding in the abstract.

## Why a real cluster instead of a discussion

The assessment allows a "discussion or setup". A discussion of CAP can be
written from a textbook; a cluster makes the trade-off produce a number and an
error message. Everything below runs on five containers built by
[`cluster/Olaide_Daniel_301911975_docker-compose.yml`](cluster/Olaide_Daniel_301911975_docker-compose.yml),
seeded from the **same** Portfolio 1 schema and data.

```
       writes                    reads                      shards
  ┌──────────────┐        ┌──────────────┐          ┌──────────────┐
  │  pg-primary  │─ WAL ─▶│ pg-replica-1 │          │  pg-shard-a  │
  │   :55433     │        │   :55434     │          │   :55436     │
  │              │─ WAL ─▶│ pg-replica-2 │          │  pg-shard-b  │
  └──────────────┘        │   :55435     │          │   :55437     │
         └── postgres_fdw ───────────────────────────────────┘
```

**Replication and sharding solve different problems and are both implemented:**

| | Replication | Sharding |
|---|---|---|
| Copies | all data to every node | a slice of the data to each node |
| Buys | availability, read capacity, durability | write capacity, data larger than one machine |
| Costs | write latency (if synchronous), stale reads (if not) | cross-shard queries, no cross-shard joins |

## Experiments

| # | Experiment | What it must produce |
|---|---|---|
| R1 | Topology | `pg_stat_replication` showing both standbys streaming, slots retaining WAL |
| R2 | Standbys are read-only | A server-side refusal, not a convention |
| R3 | Replication lag under a 20,000-row burst | `write_lag` / `flush_lag` / `replay_lag` in milliseconds |
| R4 | Cost of synchronous commit | pgbench latency, **async → sync → async**, so the difference cannot be ambient load |
| R5 | CAP, concretely | Stop the *synchronous* standby and watch writes block while reads continue |
| R6 | Failover | Promote a standby, show the timeline switch, count rows lost |
| S1 | Hash sharding over 2 nodes | Row distribution, single-shard pruning, cross-shard aggregation |
| S2 | The limits of sharding | A join between sharded and local data, and predicate pushdown |

## Method notes decided in advance

* **A-B-A measurement for R4.** Measuring async once and sync once proves
  nothing about which setting caused the difference; the third measurement
  returns to async and must reproduce the first.
  *(Outcome: the control did **not** reproduce — it came back slower than the
  synchronous run. That invalidated the single A-B-A, so
  `Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh` was added: six alternating
  rounds with means and ranges, which resolved the difference cleanly. Both
  results are reported in README §3.)*
* **Verify the setting before trusting the measurement.** `set_sync()` prints
  `SHOW synchronous_standby_names` and the `sync_state` of each standby before
  any number is taken. This was added after the first version of the script
  "measured" synchronous replication that had never been enabled — see §3 of
  the README.
* **Derive R5's conclusion from the captured output**, not from a narration
  written in advance. The script branches on whether the write actually
  blocked.
* **R6 is destructive** and runs last; re-running the lab needs
  `docker compose down -v && up -d`.

## Deliverables

| File | Contents |
|---|---|
| `cluster/…_docker-compose.yml` | The five-node cluster |
| `cluster/…_Primary_Init.sh` | Replication role, slots, `pg_hba` rule |
| `cluster/…_Replica_Entrypoint.sh` | `pg_basebackup` clone + hot standby start |
| `cluster/…_Shard_Init.sql` | The per-shard table and its indexes |
| `…_Replication_Lab.sh` | R1–R6, with verification built in |
| `…_Sync_Latency_Benchmark.sh` | Repeated-measures version of R4, added after its control failed |
| `…_Sharding.sql` | S1–S2 |
| `…_Cloud_Deployment.md` | How this maps onto a managed cloud database, with the parts that do not map |
| `evidence/` | Captured output of everything above |

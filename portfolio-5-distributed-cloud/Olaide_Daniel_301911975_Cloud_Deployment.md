# Portfolio 5 — Cloud Deployment of the HDMB Ledger

**Student:** Olaide Daniel (301911975)

The cluster in this portfolio is a local five-container deployment. This
document maps it onto a managed cloud database, and is explicit about which
parts map cleanly, which parts a managed service does better, and which
problems no managed service removes.

---

## 1. What HDMB actually needs from a deployment

Working backwards from the case study rather than from a product list:

| Requirement | Source |
|---|---|
| A transfer, once acknowledged, must never be lost | Portfolio 3 — it is money |
| Balance enquiry and statements must stay fast under read load | Portfolio 2 Q2/Q8 |
| Regulatory retention of the journal, with point-in-time recovery | `ledger_entry` is the audit trail |
| Survive the loss of one availability zone | A bank cannot be offline for a day |
| Data residency in Nigeria where required | CBN guidance on customer data |
| A team of one or two DBAs, not a platform team | A microfinance bank's reality |

The last row is the one that decides the architecture. Everything in this
portfolio was built by hand; a bank this size should not be hand-building
failover.

## 2. Target architecture

```
                    ┌──────────────── Region: af-south-1 (or eu-west-1) ────────────────┐
   mobile/USSD      │   ┌──────────────┐          ┌──────────────┐                      │
   channels ───────▶│   │   AZ-a       │          │   AZ-b       │                      │
                    │   │  PRIMARY     │◀─ sync ─▶│  STANDBY     │   (Multi-AZ)         │
                    │   └──────┬───────┘          └──────────────┘                      │
   reporting ──────▶│          │ async                                                  │
   dashboards       │   ┌──────▼───────┐                                                │
                    │   │ READ REPLICA │  (dashboards, Portfolio 2 Q3/Q6)               │
                    │   └──────────────┘                                                │
                    │   WAL archive ──▶ object storage (PITR, 35-day window)            │
                    └────────────────────────────────────────────────────────────────────┘
```

| Local component | Managed equivalent |
|---|---|
| `pg-primary` + `pg-replica-1` with `synchronous_standby_names` | **Multi-AZ instance** (AWS RDS / Aurora, Azure Database for PostgreSQL Flexible Server zone-redundant HA, Google Cloud SQL HA) — the standby is synchronous and the failover is automatic |
| `pg-replica-2` (async) | **Read replica**, endpoint given to reporting tools only |
| `pg_basebackup` in the replica entrypoint | Provisioning a replica is one API call |
| `pg_promote()` run by hand in R6 | Automatic failover, typically 30–120 s, with the DNS endpoint moved for you |
| Nothing in the local cluster | **WAL archiving + point-in-time recovery**, which the local cluster does not have at all |
| `postgres_fdw` shards (S1) | Not a managed feature. Sharding stays an application concern, or means Citus (Azure Cosmos DB for PostgreSQL) |

## 3. The specific numbers that drive the choice

From [`evidence/Olaide_Daniel_301911975_Replication_Evidence.txt`](evidence/Olaide_Daniel_301911975_Replication_Evidence.txt):

* Synchronous commit cost **+49.1%** on write latency — 1.440 ms asynchronous
  against 2.147 ms synchronous, measured over six alternating rounds with
  non-overlapping ranges
  ([`evidence/…_Sync_Latency_Benchmark.txt`](evidence/Olaide_Daniel_301911975_Sync_Latency_Benchmark.txt)).
  That is *between two containers on one host*. Across two availability zones
  the round trip is 1–2 ms rather than tens of microseconds, so the real cost is
  larger. HDMB should still pay it on the ledger — a lost transfer costs more
  than a slow one — and it is exactly why only the Multi-AZ standby is
  synchronous while the reporting replica is not.
* Asynchronous `replay_lag` was **~46 ms** under a 20,000-row burst, and
  end-to-end visibility on the replica was measured at **~400 ms** including
  client round trips. That is the window in which a read replica can return a
  balance that is already stale, so the balance screen must read the primary
  while dashboards may read the replica.
* Failover lost **0 rows**, but only because both standbys happened to be fully
  caught up (`behind_primary = 0 bytes`) at the instant the primary was killed.
  With an asynchronous standby and writes in flight, anything inside that
  ~46 ms window would have been lost — which is the entire argument for keeping
  a synchronous standby on the ledger.

## 4. What a managed service does better

1. **Automatic failover.** R6 showed the real cost of doing it by hand: a
   standby cannot promote itself, so writes stop until a human intervenes, and
   the *other* standby is then orphaned on an old timeline and needs
   `pg_rewind` or a fresh clone. That recovery work, not the promotion, is what
   makes manual failover slow.
2. **Backups and PITR.** The local cluster has none. A managed service gives
   continuous WAL archiving and restore-to-timestamp with no code.
3. **Patching.** PostgreSQL minor releases carry data-corruption fixes; a
   managed service applies them in a maintenance window.
4. **Monitoring that already exists.** `pg_stat_replication` had to be queried
   by hand in R1; managed services alarm on replica lag out of the box.

## 5. What a managed service does *not* solve

| Problem | Why it remains |
|---|---|
| Choosing sync vs async | A business decision about acceptable data loss. The platform exposes the switch; it cannot decide for you |
| Write skew and lost updates | Portfolio 3's anomalies are properties of the *application's* transactions. Multi-AZ does not change isolation semantics |
| Query and index design | Portfolio 2's 54× and 89× wins came from indexes, not hardware. A bigger instance would have hidden the problem at a monthly cost |
| Sharding | No managed PostgreSQL shards a table for you. The shard-key choice in S1 is still the engineer's |
| Cross-shard joins | A distributed-systems constraint, not a product gap |
| Data residency | Region availability is a procurement question; `af-south-1` exists, but not every service is in it |

## 6. Cost and sizing, honestly estimated

HDMB at the volume modelled here (`ledger_entry` 194 MB with indexes, 275 k
transactions, ~25 k accounts) is **small**. Indicative monthly figures for a
Multi-AZ instance plus one read replica, at published on-demand rates:

| Item | Sizing | Indicative cost/month |
|---|---|---|
| Primary + synchronous standby (Multi-AZ) | 2 vCPU / 8 GB | ≈ US$ 230–300 |
| One asynchronous read replica | 2 vCPU / 8 GB | ≈ US$ 115–150 |
| Storage + backups | 100 GB gp3 + 100 GB backup | ≈ US$ 25–35 |
| **Total** | | **≈ US$ 370–485** |

Treat these as order-of-magnitude: rates differ by region and by provider, and
reserved/committed-use pricing cuts them substantially. The point is the
conclusion, which is robust to the exact numbers — **this workload does not
need sharding.** 550,000 ledger rows fit comfortably on one node, and S1
demonstrates sharding at a scale where it is not yet justified. Introducing it
now would buy write capacity HDMB does not need, at the cost of losing
cross-shard joins (S2) and ad-hoc SQL.

## 7. When sharding would become justified

The trigger is not a row count but one of these:

* the working set stops fitting in the largest single instance's memory, so the
  index-only scans Portfolio 2 depends on start hitting disk;
* write throughput saturates one primary's WAL device — at which point adding
  replicas does not help, because every replica replays every write;
* regulation forces data for different markets into different jurisdictions,
  which is sharding by geography whether or not it is called that.

Until one of those is true, the correct engineering answer for HDMB is a
Multi-AZ managed PostgreSQL with one read replica, the indexes from Portfolio 2,
and the transaction discipline from Portfolio 3.

## 8. Migration path from this repository

1. Provision Multi-AZ PostgreSQL 18, private subnets only, TLS required.
2. Apply `Olaide_Daniel_301911975_Schema.sql` then `..._Constraints.sql`.
3. Load real data with `pg_dump`/`pg_restore`; `..._Seed_Data.sql` is synthetic
   and must not reach production.
4. Apply `..._Indexes.sql` and `..._Materialised_View.sql`, then `ANALYZE`.
5. Deploy `..._Transfer_Procedures.sql` **without** `fn_transfer_naive()`,
   which exists only to demonstrate the bug in D3.
6. Create the read replica; point dashboards and the materialised-view refresh
   at it, and the balance/transfer paths at the primary.
7. Set `synchronous_standby_names` to the Multi-AZ standby and confirm with the
   `set_sync()` check from the lab — a setting that has not been verified in
   `pg_stat_replication` has not been applied.
8. Replace the lab's plain-text passwords with a secrets manager and IAM auth,
   and restrict `pg_hba`/security groups to the application subnets. The
   compose file says this explicitly: it is a laboratory, not a deployment.

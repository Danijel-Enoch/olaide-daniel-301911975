# Portfolio 2 — Query Processing and Optimisation

**Student:** Olaide Daniel · **ID:** 301911975 · **Marks:** 7
**Engine:** PostgreSQL 18.6 on `postgres:18-alpine`, 549,590-row ledger
**Data:** identical to Portfolio 1 (`setseed(0.301911975)`), so every number below is reproducible

---

## Required evidence, and where it is

| Required | File |
|---|---|
| SQL queries | [`queries/`](queries) — ten files, each with its business purpose |
| Query results | [`evidence/Olaide_Daniel_301911975_Query_Results.txt`](evidence/Olaide_Daniel_301911975_Query_Results.txt) |
| Execution plans | [`evidence/Olaide_Daniel_301911975_baseline_Plans.txt`](evidence/Olaide_Daniel_301911975_baseline_Plans.txt) · [`evidence/Olaide_Daniel_301911975_optimised_Plans.txt`](evidence/Olaide_Daniel_301911975_optimised_Plans.txt) |
| Indexing / optimisation evidence | [`Olaide_Daniel_301911975_Indexes.sql`](Olaide_Daniel_301911975_Indexes.sql) · [`evidence/Olaide_Daniel_301911975_Index_Creation.txt`](evidence/Olaide_Daniel_301911975_Index_Creation.txt) |
| Performance analysis | this document, §2–§6 |

## 1. Headline result

| Query | Business purpose | Baseline | Optimised | Change | Plan change |
|---|---|---|---|---|---|
| Q1 | Support: surname search | 4.526 ms | **0.915 ms** | **4.9× faster** | Seq Scan → Bitmap Heap Scan on functional index |
| Q2 | Mobile app: mini statement | 17.453 ms | **0.323 ms** | **54× faster** | Parallel Seq Scan → **Index Only Scan** |
| Q3 | Ops: channel failure rate | 25.378 ms | **13.818 ms** | 1.8× faster | Parallel Seq Scan → **Index Only Scan** (hypothesis was wrong) |
| Q4 | AML: top debit outflow | 45.815 ms | **24.117 ms** | 1.9× faster | Parallel Seq Scan → Index Only Scan on partial index |
| Q5 | Regulatory dormancy sweep | 105.757 ms | **40.258 ms** | 2.6× faster | Anti-join now probes the index |
| Q6 | Head office: branch monthly volume | 337.070 ms | 347.755 ms | **no change** | Plan unchanged — see §4 |
| Q6-MV | same report, materialised | 337.070 ms | **0.234 ms** | **1,441× faster** | Aggregate removed from the read path |
| Q7 | Credit control: arrears | 2.724 ms | **2.339 ms** | 1.2× faster | Index Only Scan on partial index |
| Q8 | Dispute: balance as at date | 14.895 ms | **0.168 ms** | **89× faster** | Parallel Seq Scan → Index Only Scan |
| Q9 | Fraud: beneficiary reverse lookup | 0.462 ms | **0.100 ms** | 4.6× faster | Seq Scan → Index Scan |
| Q10 | Switch: idempotency check | 0.055 ms | 0.058 ms | unchanged | Already an Index Scan — correctly left alone |

Measured by `Olaide_Daniel_301911975_Measure.sh`, best of three runs per query,
`EXPLAIN (ANALYZE, BUFFERS)`. Raw CSVs:
[`baseline`](evidence/Olaide_Daniel_301911975_baseline_Timings.csv) ·
[`optimised`](evidence/Olaide_Daniel_301911975_optimised_Timings.csv).

## 2. The two large wins, and why they are large

**Q2 (mini statement) and Q8 (balance as at date): 54× and 89×.**

Baseline plan fragment (`Olaide_Daniel_301911975_baseline_Plans.txt`):

```
->  Parallel Seq Scan on ledger_entry le
      Filter: (account_id = 4211)
      Rows Removed by Filter: 183196
```

The database read **549,590 rows to return 20**. `Rows Removed by Filter` is the
single most useful number in a plan: it is the work that was wasted.

After `idx_ledger_account_ts (account_id, entry_ts DESC, entry_id DESC) INCLUDE (...)`:

```
->  Index Only Scan using idx_ledger_account_ts on ledger_entry le
      Index Cond: (account_id = 4211)
      Heap Fetches: 0
```

Three separate improvements happen at once, and the plan shows each:

1. **`Index Cond` instead of `Filter`** — the rows are *located* rather than
   scanned and discarded.
2. **`Index Only Scan` with `Heap Fetches: 0`** — the `INCLUDE` columns put the
   whole answer in the index leaf pages, so the table itself is never touched.
3. **No `Sort` node** — the index is declared `entry_ts DESC`, which matches the
   query's `ORDER BY`, so the sort disappears entirely. Had the index been
   declared `ASC`, PostgreSQL could still have walked it backwards, but a
   mismatched *composite* order would have reintroduced the sort.

This is the one optimisation that matters commercially: the mini statement is
the most-executed read in the bank, and at 17 ms per call it would consume a
CPU core at roughly 60 requests/second. At 0.32 ms the same core serves ~3,000.

## 3. Where the hypothesis was wrong — Q3

I predicted the planner would **reject** an index on `txn(created_at)` because
the 90-day window is ~17% of the relation, well past the usual 5–10% crossover.
It used the index anyway, and got 1.8× faster.

The reason is in the index definition: it is
`(created_at) INCLUDE (channel_code, status, amount)` — every column Q3 needs.
The 5–10% rule of thumb assumes each matching index entry costs a *random heap
read* to fetch the row. A covering index removes that cost entirely, so the
crossover moves much further out. The lesson is specific, not general: **a
covering index is viable at selectivities where an ordinary index is not.**

Being wrong here is more instructive than being right would have been — the
rule of thumb is about heap access, not about index access, and this is the
case that separates the two.

## 4. Where optimisation legitimately failed — Q6

Q6 aggregates 12 months of the ledger (~67% of 549,590 rows) across four joins.
Indexing changed nothing (337 ms → 348 ms, i.e. noise), and the plan still
reads:

```
->  Parallel Seq Scan on ledger_entry le
```

**That is the optimiser being right.** When a query genuinely needs most of a
table, a sequential scan with read-ahead is the cheapest way to get it, and an
index merely adds a layer of indirection. No access path can fix a query whose
work is inherent.

The fix is therefore to stop doing the work at read time
([`Olaide_Daniel_301911975_Materialised_View.sql`](Olaide_Daniel_301911975_Materialised_View.sql)):

| | Value |
|---|---|
| Report from base tables | 337.070 ms |
| Report from `mv_branch_monthly_volume` | **0.234 ms** |
| Materialised view size | 120 kB (567 rows) |
| Cost of `REFRESH MATERIALIZED VIEW CONCURRENTLY` | 479.957 ms |

The honest statement of the trade-off: reads become 1,441× faster, the report
becomes **as stale as the refresh interval**, and the refresh itself costs more
than the original query. It is worth it only because this is a monthly
head-office report — nobody needs it accurate to the second. The same trade
would be unacceptable for an account balance, which is why `account.balance` is
maintained transactionally (Portfolio 3) rather than materialised.
`CONCURRENTLY` is used so the report stays readable during the rebuild, and
that is what the `UNIQUE` index on the view exists for.

## 5. Plan shape: the same question asked three ways

From [`evidence/Olaide_Daniel_301911975_Query_Rewrites.txt`](evidence/Olaide_Daniel_301911975_Query_Rewrites.txt) —
"which active accounts have had no posting in 180 days?", all three returning
**6,046**:

| Formulation | Plan chosen | Time |
|---|---|---|
| `NOT EXISTS` | **Nested Loop Anti Join** (probes `idx_ledger_account_ts`) | **68.745 ms** |
| `LEFT JOIN ... IS NULL` | Hash Anti Join (builds a hash of 173,134 rows) | 99.686 ms |
| `NOT IN (subquery)` | Seq Scan + hashed `SubPlan` over all 549,590 rows | **541.755 ms — 7.9× slower** |

`NOT IN` is the slowest because it cannot become an anti-join: the plan shows
`NOT (ANY (account_id = (hashed SubPlan 1).col1))` with a `Seq Scan on
ledger_entry` underneath it, reading every row before filtering.

There is also a **correctness** reason to prefer `NOT EXISTS`, demonstrated at
the end of the same file: if the subquery can return `NULL`, `NOT IN` evaluates
to `UNKNOWN` for every row and the query returns **0 rows** instead of an error.
The captured output shows exactly that. `ledger_entry.account_id` is `NOT NULL`,
so R2 is safe here — but a query whose correctness depends on a `NOT NULL`
constraint somewhere else is a bug waiting for a schema change.

## 6. The cost side of the ledger

Optimisation is a trade, and only reporting the gains would be dishonest:

| Cost | Measured |
|---|---|
| New index storage | **61 MB** against an 81 MB `ledger_entry` heap — the indexes are ~75% of the table they accelerate |
| `ledger_entry` total size with indexes | 194 MB |
| Write amplification | Every `INSERT` into `ledger_entry` now maintains two extra B-trees. On a bank's write path this is the real price, and it is why `idx_ledger_debit_recent` is *partial* — it indexes only `direction = 'DR'`, so credit postings skip it |
| Materialised view staleness | Up to one refresh interval |
| Refresh cost | 479.957 ms per refresh, held off the read path |

`ANALYZE` is run at the end of `..._Indexes.sql` for a reason: a new index the
planner has no statistics for may simply be ignored, which looks exactly like
"the index did not help".

## 7. Reproducing all of it

```bash
# baseline (indexes from Portfolio 1 only)
./Olaide_Daniel_301911975_Measure.sh baseline

# apply the optimisation layers
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Indexes.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Materialised_View.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Query_Rewrites.sql

# re-measure
./Olaide_Daniel_301911975_Measure.sh optimised
```

`Olaide_Daniel_301911975_Indexes.sql` begins with `DROP INDEX IF EXISTS`, so the
baseline/optimised cycle can be repeated as often as needed.

## 8. Limitations of this measurement

* Single node, single client, warm cache, no concurrent load — these timings
  are *plan quality*, not throughput. Behaviour under concurrency is
  Portfolio 3's subject.
* Timings come from one machine (Docker on macOS, OrbStack). Absolute
  milliseconds will differ on the assessor's hardware; the **plan shapes and
  the ratios** are the reproducible part.
* `Q4`/`Q5` still scan `account` sequentially (24,807 rows). An index was not
  added because at that size the scan is ~1 ms and an extra index would cost
  more on the write path than it returns.

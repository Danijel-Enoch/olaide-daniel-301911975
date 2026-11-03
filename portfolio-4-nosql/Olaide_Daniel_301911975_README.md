# Portfolio 4 — NoSQL and Advanced Data Models

**Student:** Olaide Daniel · **ID:** 301911975 · **Marks:** 7
**Engines:** MongoDB 8.3.13 (document) · Redis 7.4.12 (key-value) · source data from PostgreSQL 18.6
**Same case study:** Harmony Digital Microfinance Bank — the documents are *derived from* the Portfolio 1 ledger, not re-invented

---

## Required evidence, and where it is

| Required | Where |
|---|---|
| NoSQL model on the same case study | [`Olaide_Daniel_301911975_Document_Model.js`](Olaide_Daniel_301911975_Document_Model.js) |
| Document example | `customer_profile`, `txn_event` — [stored document in the load log](evidence/Olaide_Daniel_301911975_Load_Log.txt) |
| Key-value example | [`Olaide_Daniel_301911975_KeyValue_Redis.sh`](Olaide_Daniel_301911975_KeyValue_Redis.sh) → [evidence](evidence/Olaide_Daniel_301911975_KeyValue_Evidence.txt) |
| Graph example | `$graphLookup` over `transfer_edge` — M6/M7 in [query evidence](evidence/Olaide_Daniel_301911975_Query_Evidence.txt) |
| Column-family example | §7 below (Cassandra model — designed, not deployed; labelled as such) |
| Implementation evidence | [`evidence/`](evidence) — load log, query/plan output, validation results, Redis transcript |
| Explanation of suitability | §4, §6, §8, §9 |

## 1. The model

| Collection | Documents | Avg size | Shape | Why |
|---|---|---|---|---|
| `customer_profile` | 1,988 | 2,957 B | Customer with branch, accounts, beneficiaries and 10 recent postings **embedded** | Served whole to the mobile home screen |
| `txn_event` | 42,924 | 637 B | One transaction with its journal **legs embedded** | Append-only; a transaction is always read as a whole |
| `transfer_edge` | 32,758 | 174 B | `from_account → to_account` edge, derived by `$merge` | Graph traversal for fraud work |

Data 31.68 MB, indexes 0.95 MB (as loaded).

**The rule applied throughout: embed what is read together and bounded;
reference what is unbounded or shared.**

* `branch` is **embedded** in the profile: small, slow-changing, needed on every
  read. The duplication across 1,988 documents is the price of removing a join.
* `accounts` is **embedded**: a customer holds a handful, and they are never
  read without their owner.
* `recent_activity` is **embedded but bounded at 10** — the validator enforces
  `maxItems: 10`. Embedding the *full* history would grow each document without
  limit toward the hard 16 MB BSON ceiling, so the full history lives in
  `txn_event` instead. This is the single most important modelling decision in
  the portfolio: the same reasoning that makes embedding right for accounts
  makes it wrong for transactions.

## 2. It is a real ETL

[`Olaide_Daniel_301911975_Export_Documents.sql`](Olaide_Daniel_301911975_Export_Documents.sql)
projects the relational ledger into Extended JSON; `Load.sh` moves it and runs
`mongoimport`. Two details in that SQL carry most of the thinking:

```sql
'balance', json_build_object('$numberDecimal', a.balance::text)   -- not a JSON number
'ts',      json_build_object('$date', to_char(... 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
```

* **Money is `$numberDecimal`.** BSON's default numeric type is a 64-bit double,
  which cannot represent 0.10 exactly — the identical reason Portfolio 1 uses
  `NUMERIC(18,2)` rather than `FLOAT`. The documents arrive as `Decimal128`, and
  the validator *requires* `bsonType: 'decimal'`, so a JSON number is rejected
  (test V2 below).
* **Timestamps are `$date`.** Emitted as strings they would sort
  lexicographically and range-query incorrectly across time zones.

A defect found and fixed during this work: the first extract took the newest
60,000 transactions bank-wide but only the first 2,000 customers' profiles, so
the two collections described **different populations** and the statement query
returned nothing. The export now restricts events to transactions involving the
same customer slice. Consistency of an extract matters as much as its shape —
the commit history records the fix.

## 3. Queries and their plans

From [`evidence/Olaide_Daniel_301911975_Query_Evidence.txt`](evidence/Olaide_Daniel_301911975_Query_Evidence.txt):

| # | Query | Plan | Docs examined | Returned |
|---|---|---|---|---|
| M1 | Home screen by `customer_id` | `EXPRESS_IXSCAN(uq_customer_id)` | 1 | 1 |
| M2 | Who owns account `0000000041`? | `FETCH ← IXSCAN(ix_account_number)` | 1 | 1 |
| M3 | 20 newest events for an account | `LIMIT ← FETCH ← IXSCAN(ix_leg_account_time)` | 20 | 20 |
| M4 | Channel dashboard (90 days) | aggregation `$match → $group → $sort` | — | 6 channels |
| M5 | Top debit outflow (30 days) | `$unwind → $match → $group → $sort` | — | 10 accounts |
| M6 | Build `transfer_edge` via `$merge` | pipeline write | 32,758 edges in **253 ms** | — |
| M7 | `$graphLookup`, 4 hops | recursive traversal | 13 accounts reached | — |

Two plans worth noting:

* **M2 uses a multikey index.** `accounts` is an array *inside* the document,
  and `{'accounts.account_number': 1}` indexes every element of it, so
  "who owns this account" examines **one** document rather than 1,988. An
  embedded array does not mean an unindexable array.
* **M3 needs no sort stage.** `{'legs.account_number': 1, created_at: -1}`
  satisfies the match *and* the sort order, exactly as the composite
  `(account_id, entry_ts DESC)` index does in Portfolio 2 — the same principle
  expressed in a different engine. `docsExamined = 20` for 20 returned is the
  ideal ratio.

## 4. Document vs relational, measured

The same home screen, both ways, both warm:

| | MongoDB | PostgreSQL |
|---|---|---|
| Operations | **1** `findOne()` | 2 queries (4-join + statement) |
| Server execution | 0 ms reported, 1–2 ms wall clock | 2.212 ms + 1.167 ms = **3.379 ms** |
| Rows/documents the application must assemble | 1 document, already shaped | 1 join row + 10 statement rows to stitch |
| Joins | 0 | 4 |

Evidence: M1 above and
[`evidence/Olaide_Daniel_301911975_Relational_Equivalent.txt`](evidence/Olaide_Daniel_301911975_Relational_Equivalent.txt).

**The honest conclusion: this is not an order-of-magnitude win.** PostgreSQL
serves an indexed four-join in about 3 ms, and anyone claiming NoSQL is "100×
faster" here is comparing against an unindexed schema. The genuine advantages
are (a) one network round trip instead of two, which matters on a mobile
connection far more than 2 ms of server time, and (b) the application receives
the object it wanted instead of a result set it must reassemble. Those are real
engineering benefits; raw latency is not the argument.

## 5. What the validators enforce — and what they cannot

Four writes that must be refused, one that must succeed (M8):

| Test | Attempt | Result |
|---|---|---|
| V1 | `kyc_tier: 9` | **REJECTED** — Document failed validation |
| V2 | `balance: 1000.10` as a JSON double | **REJECTED** — `bsonType: 'decimal'` required |
| V3 | `status: 'ZOMBIE'` | **REJECTED** — not in `enum` |
| V4 | Transaction with a single leg (money from nowhere) | **REJECTED** — `legs` `minItems: 2` |
| V5 | The same transaction with both legs | **ACCEPTED** ✅ |

Then the important negative result (M9):

```
unbalanced document (DR 5000 vs CR 4000) -> ACCEPTED
detected only by querying for it afterwards: DR=5000.00 CR=4000.00
```

**A document with debits of 5,000 and credits of 4,000 is accepted without
complaint.** `$jsonSchema` validates one document against a structural
contract; it cannot express an arithmetic relationship *between* array
elements. PostgreSQL's `trg_ledger_balanced` (Portfolio 1) enforces exactly
that rule, and the deferred constraint trigger has no MongoDB equivalent.

Three consequences follow, and they are the heart of this portfolio:

1. **Validation is opt-in here.** The collection would accept anything at all
   without the validator; a `CHECK` constraint cannot be forgotten, a
   `$jsonSchema` can. Four of the five tests above pass only because the model
   was written defensively.
2. **Cross-document invariants are the application's problem.** MongoDB 8 does
   support multi-document ACID transactions, but no declarative constraint
   spans documents. "This account's balance equals the sum of its postings" has
   nowhere to live except application code — and application code is what
   Portfolio 3 D3 proved can be bypassed.
3. **Therefore PostgreSQL stays the system of record.** The document store is a
   *derived read model*. That is not a concession, it is the design: it is why
   `Export_Documents.sql` runs one way only.

## 6. Key-value model (Redis) — eight patterns

Full transcript: [`evidence/Olaide_Daniel_301911975_KeyValue_Evidence.txt`](evidence/Olaide_Daniel_301911975_KeyValue_Evidence.txt).

| # | Pattern | Mechanism | Result |
|---|---|---|---|
| K1 | Session token | `SET … EX 900` | TTL 900 s, expires without a cleanup job |
| K2 | Idempotent retry | `SET … NX EX 86400` | first `OK`, retry `nil` — a UNIQUE constraint without a table |
| K3 | **Daily debit limit** | Lua script, atomic check-and-increment | 1 of 3 × 30,000 admitted against a 50,000 limit |
| K4 | **Atomic counter** | `INCR` ×1,000 from two parallel clients | expected 2000, actual **2000** |
| K5 | Cached balance | `SET … EX 30` | the TTL *is* the consistency policy |
| K6 | Recent activity | `LPUSH` + `LTRIM 0 3` | length bounded at 4, no delete job |
| K7 | Channel league table | `ZADD` / `ZREVRANGE` | top-3 by value, `O(log n)`; USSD ranked 5 |
| K8 | Inventory of keys | `KEYS`, `TYPE`, `TTL` | 7 keys, 1.38 MB, every one disposable |

### K3 and K4 are the analytically interesting ones

**K3 solves Portfolio 3's write-skew anomaly a completely different way.** In
D5, two REPEATABLE READ transactions each checked the 50,000 daily limit, each
passed, and together breached it — the fix there was `SERIALIZABLE` plus a
retry loop around SQLSTATE 40001. Here the check and the increment are a single
server-side Lua script, so no two clients can interleave between them:

```
attempt 1 -> 1|30000|ALLOWED
attempt 2 -> 0|30000|LIMIT_EXCEEDED
attempt 3 -> 0|30000|LIMIT_EXCEEDED
```

No isolation level, no retry, no serialization failure to handle. The
trade-off is explicit: this counter is **not durable** the way a committed
PostgreSQL row is, so it is safe for a *policy* limit (where failing open for
a few seconds after a crash is tolerable) and unsafe for the balance itself.

**K4 is the direct counterpart of the D3 lost update.** The same workload —
two clients incrementing the same value 1,000 times each — loses updates when
the application does read→compute→write (D3: NGN 60,000 created out of
nothing), and loses nothing when the operation is atomic inside the server
(2,000 exactly). The lesson generalises: `UPDATE account SET balance = balance
- x` is correct for the same reason `INCR` is, and `balance = <value read
earlier>` is wrong for the same reason a Redis `GET`/`SET` pair would be.

## 7. Column-family model (Cassandra) — designed, not deployed

Cassandra was **not** deployed; this section is a design with its reasoning, and
is labelled as such rather than presented as evidence.

The HDMB workload that suits a wide-column store is the **customer statement at
scale**: an append-only, time-ordered, partition-per-account read that must
stay fast as the ledger grows past what one node can hold.

```cql
CREATE TABLE statement_by_account (
    account_number  text,          -- partition key: all of one account's
    entry_month     text,          --   postings, bucketed by month
    entry_ts        timestamp,     -- clustering key, newest first
    entry_id        bigint,
    txn_ref         text,
    txn_type        text,
    channel         text,
    direction       text,
    amount          decimal,
    balance_after   decimal,
    PRIMARY KEY ((account_number, entry_month), entry_ts, entry_id)
) WITH CLUSTERING ORDER BY (entry_ts DESC, entry_id DESC);
```

Why this shape:

* **`(account_number, entry_month)` as the partition key, not `account_number`
  alone.** A single-key partition would grow forever; Cassandra partitions
  should stay bounded (tens of MB). Monthly buckets bound them, at the cost of
  needing one query per month for a long statement — a trade stated, not hidden.
* **`CLUSTERING ORDER BY entry_ts DESC`** stores rows in the order they are
  read, so "last 20 postings" is a sequential read of the partition's head with
  no sort.
* **No joins exist in CQL**, so `channel`, `txn_type` and `txn_ref` are
  denormalised into every row. Writing them 549,590 times is acceptable because
  writes are cheap (log-structured) and the read pattern is fixed.
* **Query-first design.** The table is named after the question it answers. A
  second question ("all postings on channel X") needs a *second table*, written
  at the same time — the opposite of the relational approach where one
  normalised schema answers questions nobody anticipated.

That last point is the real difference between the families, and it is why
HDMB would not put its ledger in Cassandra while it is still 550 k rows on one
node: the flexibility of ad-hoc SQL is worth more than the write scalability it
does not yet need.

## 8. Graph model — running, via `$graphLookup`

A dedicated graph database (Neo4j) was not deployed either; instead the graph
*traversal* is demonstrated on data that is actually loaded, which is the
stronger evidence.

`transfer_edge` is built by an aggregation pipeline that **writes** (`$merge`):
32,758 edges from the transaction legs in 253 ms — MongoDB's equivalent of the
materialised view in Portfolio 2. The fraud question "where did this money go?"
is then a recursive traversal:

```
seed edge: 0000003688 -> 0000001139
accounts reached within 4 hops: 13
  hop 0  0000001139 -> 0000013548   NGN 950.00
  …
```

`restrictSearchWithMatch: { amount: { $gt: 500 } }` prunes the walk mid-traversal
— the filter is applied at every hop, not afterwards.

The equivalent in PostgreSQL is a `WITH RECURSIVE` CTE, and for 3–4 hops it
would perform comparably. The case for a true graph database only becomes
compelling at unbounded depth ("is there *any* path between these two
accounts?"), where each extra hop is another join for the relational planner
and a pointer hop for a native graph engine. HDMB's fraud rules are
depth-bounded, so this is honestly a *modelling* exercise, not a performance
argument.

## 9. Suitability: which store for which HDMB job

| Workload | Store | Reason |
|---|---|---|
| Posting a transfer, balances, loans | **PostgreSQL** | Needs atomicity, cross-row invariants, declarative constraints that cannot be bypassed (Portfolio 3 D3) |
| Mobile home screen, statement feed | **MongoDB** | Read as one aggregate; one round trip; no reassembly in the app |
| Channel/branch dashboards | Either | Both do it well; the materialised view (P2) and `$merge` (M6) are the same idea |
| Session tokens, rate limits, idempotency, cached balance | **Redis** | Small, hot, atomic, and naturally expiring — expiry is not a relational concept |
| Fraud "follow the money" | MongoDB `$graphLookup` today; a graph DB if depth becomes unbounded | Depth-bounded traversal does not justify another engine |
| Ledger at 100× this volume | Cassandra (per §7) | Query-first, partition-bounded, write-scalable — accepting the loss of ad-hoc querying |

**Conclusion: polyglot persistence with one system of record.** PostgreSQL owns
the truth; MongoDB and Redis own derived, rebuildable views of it. Every key in
Redis and every document in MongoDB can be reconstructed from the ledger, which
is what makes it safe to trade consistency for speed in those two stores — and
what would make it unsafe to do so in the ledger itself.

## 10. Reproducing it

```bash
docker run -d --name mit8103-mongo -p 57017:27017 mongo:8
docker run -d --name mit8103-redis -p 56379:6379 redis:7-alpine

# 1. model (collections, validators, indexes)
docker cp Olaide_Daniel_301911975_Document_Model.js mit8103-mongo:/tmp/model.js
docker exec mit8103-mongo mongosh --quiet --file /tmp/model.js

# 2. ETL out of PostgreSQL and into MongoDB
./Olaide_Daniel_301911975_Load.sh

# 3. queries, plans, validation tests
docker cp Olaide_Daniel_301911975_Queries.js mit8103-mongo:/tmp/q.js
docker exec mit8103-mongo mongosh hdmb --quiet --file /tmp/q.js

# 4. key-value patterns
./Olaide_Daniel_301911975_KeyValue_Redis.sh

# 5. the relational equivalent, for the comparison in §4
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Relational_Equivalent.sql
```

`Queries.js` selects its demonstration account from the data at runtime, so it
keeps working if the extract is regenerated at a different size.

## 11. Limitations

* **Single-node MongoDB.** No replica set, so no read concern / write concern
  experiments and no multi-document transaction demonstration (which requires
  a replica set). Replication and consistency levels are Portfolio 5's subject.
* **Cassandra and Neo4j are designs, not deployments** (§7, §8). They are
  labelled that way rather than presented as implementation evidence.
* **The MongoDB timings are single-client and warm**, like Portfolio 2's. They
  compare plan quality, not throughput.
* **`transfer_edge` is a snapshot.** It is rebuilt by re-running M6; there is no
  incremental maintenance, which a production fraud graph would need.
* The ledger graph is sparse (32,758 edges over ~20,000 accounts), so the
  `$graphLookup` seed had to be *searched for* rather than picked arbitrarily —
  most accounts' money trails terminate at the first hop. The script does that
  search explicitly rather than quietly presenting a cherry-picked result.

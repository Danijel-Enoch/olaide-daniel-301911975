# References, Sources and Tools

**Student:** Olaide Daniel · **ID:** 301911975 · **Course:** MIT 8103 Advanced Database Systems

---

## 1. Software used (all official images, unmodified)

| Software | Version | Source |
|---|---|---|
| PostgreSQL | 18.6 | Docker Official Image `postgres:18-alpine` — <https://hub.docker.com/_/postgres> |
| MongoDB | 8.3.13 | Docker Official Image `mongo:8` — <https://hub.docker.com/_/mongo> |
| Redis | 7.4.12 | Docker Official Image `redis:7-alpine` — <https://hub.docker.com/_/redis> |
| `pgbench` | 18.6 | Bundled with PostgreSQL |
| `mongoimport` / `mongosh` | bundled | Bundled with the MongoDB image |
| Docker Engine (OrbStack) | 29.8.2 | <https://orbstack.dev> |
| Python | 3.x standard library only (`pty`, `select`, `subprocess`, `termios`) | <https://docs.python.org/3/> |
| Mermaid | GitHub-native rendering | <https://mermaid.js.org/syntax/entityRelationshipDiagram.html> |

No third-party libraries, frameworks or extensions were installed beyond
`postgres_fdw`, which ships with PostgreSQL.

## 2. Primary technical documentation consulted

* PostgreSQL 18 Documentation — *Constraints*: <https://www.postgresql.org/docs/18/ddl-constraints.html>
* PostgreSQL 18 Documentation — *Using EXPLAIN*: <https://www.postgresql.org/docs/18/using-explain.html>
* PostgreSQL 18 Documentation — *Index-Only Scans and Covering Indexes*: <https://www.postgresql.org/docs/18/indexes-index-only-scans.html>
* PostgreSQL 18 Documentation — *Partial Indexes*: <https://www.postgresql.org/docs/18/indexes-partial.html>
* PostgreSQL 18 Documentation — *Transaction Isolation*: <https://www.postgresql.org/docs/18/transaction-iso.html>
* PostgreSQL 18 Documentation — *Explicit Locking* (`FOR UPDATE`, deadlocks): <https://www.postgresql.org/docs/18/explicit-locking.html>
* PostgreSQL 18 Documentation — *PostgreSQL Error Codes* (SQLSTATE 23514, 40001, 40P01, 55000): <https://www.postgresql.org/docs/18/errcodes-appendix.html>
* PostgreSQL 18 Documentation — *Materialized Views* / `REFRESH … CONCURRENTLY`: <https://www.postgresql.org/docs/18/sql-refreshmaterializedview.html>
* PostgreSQL 18 Documentation — *Log-Shipping Standby Servers* and *Hot Standby*: <https://www.postgresql.org/docs/18/warm-standby.html>
* PostgreSQL 18 Documentation — *Synchronous Replication*: <https://www.postgresql.org/docs/18/warm-standby.html#SYNCHRONOUS-REPLICATION>
* PostgreSQL 18 Documentation — *`pg_basebackup`*: <https://www.postgresql.org/docs/18/app-pgbasebackup.html>
* PostgreSQL 18 Documentation — *Table Partitioning*: <https://www.postgresql.org/docs/18/ddl-partitioning.html>
* PostgreSQL 18 Documentation — *`postgres_fdw`*: <https://www.postgresql.org/docs/18/postgres-fdw.html>
* MongoDB Manual 8.0 — *Schema Validation* (`$jsonSchema`): <https://www.mongodb.com/docs/manual/core/schema-validation/>
* MongoDB Manual 8.0 — *Data Model Design* (embedding vs referencing): <https://www.mongodb.com/docs/manual/core/data-model-design/>
* MongoDB Manual 8.0 — *`$graphLookup`*: <https://www.mongodb.com/docs/manual/reference/operator/aggregation/graphLookup/>
* MongoDB Manual 8.0 — *`$merge`*: <https://www.mongodb.com/docs/manual/reference/operator/aggregation/merge/>
* MongoDB Manual 8.0 — *Multikey Indexes*: <https://www.mongodb.com/docs/manual/core/indexes/index-types/index-multikey/>
* MongoDB Manual 8.0 — *`Decimal128` / modelling monetary data*: <https://www.mongodb.com/docs/manual/tutorial/model-monetary-data/>
* MongoDB Manual 8.0 — *Document limit (16 MB)*: <https://www.mongodb.com/docs/manual/reference/limits/>
* Redis Documentation — *Transactions and atomicity*, *`SET` options*, *`EXPIRE`*, *Lua scripting (`EVAL`)*, *Sorted sets*: <https://redis.io/docs/latest/>
* Apache Cassandra 5.0 Documentation — *Data modelling: partition and clustering keys* (used for the §7 design sketch in Portfolio 4): <https://cassandra.apache.org/doc/latest/cassandra/developing/data-modeling/>

## 3. Concepts attributed to their original sources

* **Normalisation (1NF–3NF) and the relational model** — E. F. Codd, "A
  Relational Model of Data for Large Shared Data Banks," *Communications of the
  ACM* 13(6), 1970.
* **Boyce–Codd Normal Form** — R. F. Boyce and E. F. Codd, 1974.
* **ACID** — T. Haerder and A. Reuter, "Principles of Transaction-Oriented
  Database Recovery," *ACM Computing Surveys* 15(4), 1983.
* **Isolation levels and the anomalies they permit (including write skew)** —
  H. Berenson, P. Bernstein, J. Gray, J. Melton, E. O'Neil and P. O'Neil,
  "A Critique of ANSI SQL Isolation Levels," *SIGMOD*, 1995.
* **CAP theorem** — E. Brewer, 2000; formalised by S. Gilbert and N. Lynch,
  "Brewer's Conjecture and the Feasibility of Consistent, Available,
  Partition-Tolerant Web Services," *ACM SIGACT News* 33(2), 2002.
* **Serializable Snapshot Isolation** (the mechanism behind the SQLSTATE 40001
  observed in Portfolio 3 D5) — D. R. K. Ports and K. Grittner, "Serializable
  Snapshot Isolation in PostgreSQL," *VLDB*, 2012.
* **Polyglot persistence** — M. Fowler and P. Sadalage, *NoSQL Distilled*,
  Addison-Wesley, 2012.

## 4. Data

**All data in this portfolio is synthetic.** It is generated by
`portfolio-1-database-design/Olaide_Daniel_301911975_Seed_Data.sql`, which calls
`setseed(0.301911975)` and derives every value from `generate_series` and
literal name arrays. No real customer, account, transaction or personal data of
any kind is present, and no external data set was imported. Names, BVNs, phone
numbers, account numbers and addresses are all fabricated by that script.

Harmony Digital Microfinance Bank does not exist. Branch locations, product
names and the channel mix are modelled on the publicly documented operating
pattern of Nigerian microfinance banks; no internal information from any real
institution was used.

## 5. Cloud cost figures

The indicative monthly costs in
`portfolio-5-distributed-cloud/Olaide_Daniel_301911975_Cloud_Deployment.md` §6
are order-of-magnitude estimates derived from publicly listed on-demand pricing
for managed PostgreSQL offerings (AWS RDS, Azure Database for PostgreSQL
Flexible Server, Google Cloud SQL) as at November 2026. They are labelled as
indicative in that document; they are not quotations, and they vary by region
and commitment term.

## 6. AI assistance

Declared separately and in detail in
[`Olaide_Daniel_301911975_AI_Use_Declaration.md`](Olaide_Daniel_301911975_AI_Use_Declaration.md).

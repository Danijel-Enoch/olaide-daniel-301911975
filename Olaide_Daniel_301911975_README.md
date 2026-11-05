# MIT 8103 Advanced Database Systems — Practical Database Portfolio

**Student:** Olaide Daniel
**Student ID:** 301911975
**Programme:** Master of Information Technology
**Session:** 2026/2027, First Semester — Continuous Assessment (40 marks)
**Case study:** Harmony Digital Microfinance Bank (HDMB) — a simulated Nigerian microfinance bank
**Repository:** <https://github.com/arizonal2014/MIT8103_Portfolio_Generator>

---

## The selected organisation, in one paragraph

**Harmony Digital Microfinance Bank (HDMB)** is a simulated Nigerian
microfinance bank: twelve branches, ~20,000 customers, and a digital-first
channel mix (USSD `*977#`, mobile app, internet banking, ATM, agent POS, branch
counter). Its core system is a **double-entry ledger** — a record of every naira
entering, leaving, or moving inside the bank. Its users are customers,
tellers, agents, operations and reconciliation officers, credit officers,
branch managers, and auditors. The database stores parties, accounts, every
transaction and its journal legs, the loan book, and an append-only audit
trail; it must support transfers, cash deposits and withdrawals, reversals,
statements, dormancy sweeps, arrears reporting, and regulatory audit.

Full statement: [`docs/Olaide_Daniel_301911975_Case_Study.md`](docs/Olaide_Daniel_301911975_Case_Study.md).
**All five portfolio activities use this one case study**, and Portfolios 2–5
run on the *same* data set produced by Portfolio 1.

## Portfolio contents

| # | Activity | Marks | Folder | Headline result |
|---|---|---|---|---|
| 1 | [Database Design and Modelling](portfolio-1-database-design/Olaide_Daniel_301911975_README.md) | 7 | `portfolio-1-database-design/` | 12 relations in BCNF, 28 CHECK constraints, deferred double-entry trigger; 7/7 negative tests behave as specified |
| 2 | [Query Processing and Optimisation](portfolio-2-query-optimisation/Olaide_Daniel_301911975_README.md) | 7 | `portfolio-2-query-optimisation/` | 10 queries measured before/after: **54×** and **89×** on the two hottest reads, **1,441×** via materialised view |
| 3 | [Transactions and Concurrency](portfolio-3-transactions-concurrency/Olaide_Daniel_301911975_README.md) | 7 | `portfolio-3-transactions-concurrency/` | Lost update reproduced (NGN 60,000 created from nothing), then prevented; write skew, deadlock and failover of isolation levels, all as timestamped two-session transcripts |
| 4 | [NoSQL and Advanced Data Models](portfolio-4-nosql/Olaide_Daniel_301911975_README.md) | 7 | `portfolio-4-nosql/` | MongoDB document model via real ETL (1,988 + 42,924 docs), `$graphLookup` traversal, 8 Redis key-value patterns |
| 5 | [Distributed and Cloud Database Exercise](portfolio-5-distributed-cloud/Olaide_Daniel_301911975_README.md) | 6 | `portfolio-5-distributed-cloud/` | 5-node cluster: streaming replication, measured cost of synchronous commit, failover with timeline switch, hash sharding over `postgres_fdw` |
| — | [Final documentation and reflection](docs/Olaide_Daniel_301911975_Documentation.md) | 6 | `docs/` | LMS summary, technical reflection, AI-use declaration, references |

## Repository structure

```
Olaide_Daniel_301911975/
├── Olaide_Daniel_301911975_README.md            <- this file
├── docs/
│   ├── Olaide_Daniel_301911975_Case_Study.md            selected organisation
│   ├── Olaide_Daniel_301911975_Documentation.md         the 2-3 page LMS submission
│   ├── Olaide_Daniel_301911975_Reflection.md            individual technical reflection
│   ├── Olaide_Daniel_301911975_AI_Use_Declaration.md    AI-use declaration
│   ├── Olaide_Daniel_301911975_References.md            sources and tools
│   └── Olaide_Daniel_301911975_Evidence_Index.md        every evidence file, and what it proves
├── portfolio-1-database-design/        schema, constraints, ER model, normalisation, seed, tests
├── portfolio-2-query-optimisation/     10 queries, measurement harness, indexes, plans, analysis
├── portfolio-3-transactions-concurrency/  transfer procedures, 7-demo concurrency lab, reconciliation
├── portfolio-4-nosql/                  MongoDB model + ETL + queries, Redis key-value lab
└── portfolio-5-distributed-cloud/      5-node cluster, replication lab, sharding, cloud design
    └── cluster/                        docker compose + node bootstrap scripts
```

Each portfolio folder contains a `Olaide_Daniel_301911975_Plan.md` (what was
intended, and the expectations recorded *before* measuring), a
`Olaide_Daniel_301911975_README.md` (what happened, with numbers), and an
`evidence/` directory holding captured output.

## Engines used

| Engine | Version | Used for |
|---|---|---|
| PostgreSQL | 18.6 (`postgres:18-alpine`) | Portfolios 1, 2, 3, 5 |
| MongoDB | 8.3.13 (`mongo:8`) | Portfolio 4 — document model |
| Redis | 7.4.12 (`redis:7-alpine`) | Portfolio 4 — key-value model |
| Docker / OrbStack | 29.8.2 | All of it |

## Reproducing the whole portfolio from scratch

```bash
# ---- Portfolios 1-3: single PostgreSQL node -------------------------
docker run -d --name mit8103-pg -e POSTGRES_PASSWORD=mit8103 \
  -e POSTGRES_DB=hdmb -p 55432:5432 postgres:18-alpine

cd portfolio-1-database-design
for f in Schema Constraints Seed_Data; do
  docker exec -i mit8103-pg psql -U postgres -d hdmb -v ON_ERROR_STOP=1 \
    < Olaide_Daniel_301911975_$f.sql
done
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Verification.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Constraint_Tests.sql

cd ../portfolio-2-query-optimisation
./Olaide_Daniel_301911975_Measure.sh baseline
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Indexes.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Materialised_View.sql
./Olaide_Daniel_301911975_Measure.sh optimised

cd ../portfolio-3-transactions-concurrency
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Demo_Setup.sql
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Transfer_Procedures.sql
python3 Olaide_Daniel_301911975_Concurrency_Lab.py          # 7 demos
docker exec -i mit8103-pg psql -U postgres -d hdmb < Olaide_Daniel_301911975_Reconciliation.sql

# ---- Portfolio 4: MongoDB + Redis ----------------------------------
docker run -d --name mit8103-mongo -p 57017:27017 mongo:8
docker run -d --name mit8103-redis -p 56379:6379 redis:7-alpine
cd ../portfolio-4-nosql
docker cp Olaide_Daniel_301911975_Document_Model.js mit8103-mongo:/tmp/model.js
docker exec mit8103-mongo mongosh --quiet --file /tmp/model.js
./Olaide_Daniel_301911975_Load.sh
docker cp Olaide_Daniel_301911975_Queries.js mit8103-mongo:/tmp/q.js
docker exec mit8103-mongo mongosh hdmb --quiet --file /tmp/q.js
./Olaide_Daniel_301911975_KeyValue_Redis.sh

# ---- Portfolio 5: 5-node cluster -----------------------------------
cd ../portfolio-5-distributed-cloud/cluster
docker compose -f Olaide_Daniel_301911975_docker-compose.yml up -d
cd ..
docker exec -i mit8103-primary psql -U postgres -d hdmb < Olaide_Daniel_301911975_Sharding.sql
./Olaide_Daniel_301911975_Replication_Lab.sh     # destructive: fails the primary over
```

Everything is reproducible by design: `Seed_Data.sql` calls
`setseed(0.301911975)` and derives every value from `generate_series`, so the
data — and therefore every query plan in Portfolio 2 — is identical on re-run.

## How this portfolio is meant to be read

Three conventions run through all five activities:

1. **Expectations are recorded before measurements.** Each `Plan.md` states what
   I expected to find. Two of Portfolio 2's hypotheses and one of Portfolio 5's
   turned out to be wrong, and the READMEs say so — an optimisation exercise in
   which every result confirms an unstated expectation is not evidence.
2. **Evidence is captured output, not screenshots.** Text files carry exact
   SQLSTATEs, process ids, millisecond timings and full execution plans, and
   they diff across commits. (Screenshots of the same material are in the LMS
   submission where images are expected.)
3. **Failures are kept.** `fn_transfer_naive()` is committed *because* it is
   wrong; the unbalanced-document test is kept *because* MongoDB accepts it;
   the first version of the replication lab measured a setting that was never
   enabled, and the fix plus the reason is in the commit history.

## Naming convention

Every file follows `Surname_Firstname_StudentID_DocumentType` as required by the
submission instructions, inside the folder `Olaide_Daniel_301911975`. Folder
names for the five activities follow the structure suggested in the assessment
brief.

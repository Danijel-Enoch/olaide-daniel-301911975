# Portfolio 4 — Plan: NoSQL and Advanced Data Models

**Student:** Olaide Daniel (301911975) · **Marks:** 7

## Objective

Model the **same** HDMB case study in NoSQL stores, driven by a read pattern
the relational model serves badly — and state plainly what is given up in
exchange.

## The honest motivation

A NoSQL section that exists "because the assessment asks for one" is worth
little. Two HDMB access patterns genuinely argue for a different store:

1. **The mobile home screen.** Customer, accounts, product terms, branch and
   the ten most recent postings. In the normalised schema that is a four-table
   join plus a second query — and the application then has to stitch the
   result back into one object. The data is *read* as one aggregate, so it can
   be *stored* as one aggregate.
2. **Hot, short-lived state.** Session tokens, retry/idempotency markers,
   daily debit counters, cached balances. All small, all read constantly, all
   with a natural expiry. A relational table has no concept of expiry; keeping
   this state in PostgreSQL means a session table plus a delete job.

These map onto two different NoSQL families, so both are implemented:
**document** (MongoDB 8) and **key-value** (Redis 7).

## Steps

1. **Document model** (`..._Document_Model.js`) — collections, `$jsonSchema`
   validators, indexes. Design rule: *embed what is read together and bounded;
   reference what is unbounded or shared.*
2. **A real ETL, not retyped data** (`..._Export_Documents.sql` + `..._Load.sh`):
   PostgreSQL → MongoDB Extended JSON (JSONL) → `mongoimport`. The documents
   must be derived from the relational source, or the two models are not
   describing the same bank.
3. **Queries that matter** (`..._Queries.js`): the home screen, ownership
   lookup across an embedded array, a statement, two aggregation pipelines
   mirroring Portfolio 2's Q3 and Q4, a pipeline that *writes* (`$merge`), and
   a graph traversal (`$graphLookup`).
4. **Test the validators** — four writes that must be refused and one that must
   succeed, mirroring Portfolio 1's negative tests.
5. **Find the limit of the validators** — demonstrate a rule the document model
   *cannot* express, where Portfolio 1's trigger can.
6. **Key-value model** (`..._KeyValue_Redis.sh`) — eight patterns, including the
   atomic daily-limit script that solves Portfolio 3's write-skew anomaly
   without isolation levels.
7. **Measure the relational equivalent** (`..._Relational_Equivalent.sql`) so
   the comparison is a measurement and not a claim.
8. **Column-family and graph models** — designed and justified in the README.
   MongoDB's `$graphLookup` supplies a *running* graph traversal; Cassandra is
   presented as a design, clearly labelled as modelled rather than deployed.

## What I expected to find

| Expectation | Why |
|---|---|
| The document read beats the join, but not dramatically | PostgreSQL serves an indexed 4-join in a couple of milliseconds. The real win should be round trips and application complexity, not raw latency |
| Money must be `Decimal128`, never a JSON number | BSON's default is a double; the 0.10 problem is identical to `FLOAT` in SQL |
| Validators will catch per-document errors | `$jsonSchema` is a per-document contract |
| Validators will **not** catch "debits = credits" | That is a relationship between array elements, not a property of one value |
| Redis `INCR` will not lose updates | It is a single-key server-side operation, unlike read-modify-write |

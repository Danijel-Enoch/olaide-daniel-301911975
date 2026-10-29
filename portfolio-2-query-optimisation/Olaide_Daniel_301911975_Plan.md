# Portfolio 2 — Plan: Query Processing and Optimisation

**Student:** Olaide Daniel (301911975) · **Marks:** 7

## Objective

Take ten queries HDMB actually runs, measure them, make them faster by
changing the *access path* and the *plan shape*, and report what the optimiser
really did — including where the optimisation failed.

## Method (chosen so the numbers mean something)

1. **Pick queries from the business, not from the schema.** Each of the ten
   queries in `queries/` corresponds to a real screen or report named in the
   case study: mini statement, support search, AML watchlist, dormancy sweep,
   arrears, branch report, dispute resolution, channel dashboard, fraud
   reverse-lookup, channel retry check.
2. **Measure before changing anything** — `Olaide_Daniel_301911975_Measure.sh baseline`.
3. **Best of three runs, not the first run.** A cold first run measures the
   buffer cache, not the plan. Taking the fastest of three removes most of that.
4. **`EXPLAIN (ANALYZE, BUFFERS)`**, not `EXPLAIN` alone: estimated cost is the
   planner's opinion, `actual time` and `rows` are the facts, and `BUFFERS`
   shows whether the pages came from memory or disk.
5. **Three optimisation techniques, in increasing cost to the business:**
   * indexes (`..._Indexes.sql`) — cheap, transparent to the application;
   * query rewriting (`..._Query_Rewrites.sql`) — free at runtime, needs a code change;
   * materialised view (`..._Materialised_View.sql`) — fastest reads, but the
     data is now stale between refreshes, which is a business decision and not
     a technical one.
6. **Re-measure identically** — `Measure.sh optimised` — and compare.

## Hypotheses recorded in advance

| Query | Expectation before measuring | Why |
|---|---|---|
| Q2, Q8 | Large win | Single-account lookup against the 549,590-row ledger; a composite index turns a full scan into a seek |
| Q1, Q9 | Win | Predicate on an unindexed / non-leading column |
| Q4, Q7 | Moderate win | Partial index over a selective subset |
| Q3 | **Index rejected** | 90 days ≈ 17% of rows, past the usual 5–10% point where random heap reads cost more than a sequential scan |
| Q6 | **No index will help** | Aggregates ~67% of the ledger; needs pre-computation, not a better path |
| Q10 | No change | Already served by the `txn_ref` unique index |

Recording the expectation first is the point: an optimisation exercise where
every result "confirms" an unstated expectation is not evidence of anything.
Two of these hypotheses turned out to be wrong — see the README.

## Deliverables

| File | Contents |
|---|---|
| `queries/` | The ten SQL queries, one per file, each with the business reason and the optimisation target |
| `Olaide_Daniel_301911975_Measure.sh` | Measurement harness (best of three, writes plans + CSV) |
| `Olaide_Daniel_301911975_Indexes.sql` | Six indexes, each with its justification; re-runnable |
| `Olaide_Daniel_301911975_Query_Rewrites.sql` | Same question asked three ways, with plans |
| `Olaide_Daniel_301911975_Materialised_View.sql` | Pre-computed branch report + refresh cost |
| `evidence/*_baseline_*`, `evidence/*_optimised_*` | Full plans and timings before and after |

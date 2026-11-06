# AI Use Declaration

**Student:** Olaide Daniel · **ID:** 301911975
**Course:** MIT 8103 Advanced Database Systems — First Semester Continuous Assessment
**Date:** 5 November 2026

This declaration is made under §11 of the assessment brief, which requires a
statement of the AI tool used, what it was used for, and how the output was
reviewed, corrected, tested or verified.

---

## 1. The AI tool used

**Claude (Anthropic), via the Claude Code command-line interface**, running the
Claude Opus model. No other AI tool was used.

## 2. What it was used for

| Used for | Detail |
|---|---|
| Drafting SQL and scripts | First drafts of the DDL, the constraint layer, the seed generator, the ten Portfolio 2 queries, the index set, the transfer procedures, the Python concurrency harness, the MongoDB model and ETL, the Redis script, the docker-compose cluster and the replication/sharding labs |
| Drafting documentation | First drafts of the README files, the normalisation walkthrough, the ER model, and this portfolio's written analysis |
| Explaining engine behaviour | Interpreting `EXPLAIN (ANALYZE, BUFFERS)` output, PostgreSQL SQLSTATE semantics, MongoDB plan stages, and `postgres_fdw` pushdown rules |
| Debugging | Diagnosing the specific failures listed in §4 |

## 3. What it was **not** used for

* No AI tool produced any of the **results** reported in this portfolio. Every
  number, plan, timing, error message and transcript in `evidence/` is the
  captured output of a script executed against a real database engine running
  in Docker on the submitting machine.
* No evidence file was hand-written, edited after capture, or reformatted.
  They are redirected process output, which is why they contain raw psql
  prompts, container process ids and unrounded millisecond timings.

## 4. How the output was reviewed, corrected and verified

Verification was **execution**: every script was run, and several AI-drafted
scripts were wrong until corrected. The corrections are visible in the commit
history, and the substantive ones are documented in the portfolio READMEs
because the failures are themselves instructive:

| Defect in the drafted work | How it surfaced | Correction |
|---|---|---|
| `CHECK (balance >= 0)` applied to internal branch till accounts | Seed load aborted: `new row for relation "account" violates check constraint` | Constraint amended to exempt `TILL` accounts, with the reasoning recorded (Portfolio 1) |
| Ambiguous `account_id` between a PL/pgSQL OUT parameter and the table column | `ERROR: column reference "account_id" is ambiguous` at run time | OUT parameters renamed with an `r_` prefix; `CREATE OR REPLACE` cannot change them, so an explicit `DROP FUNCTION` was added |
| Demo balances written straight into `account.balance` | Reconciliation in demo D3 showed a 100,000.00 "discrepancy" that was really an unjournalised opening balance | Opening balance posted as a real double-entry deposit, so later discrepancies are attributable to the experiment |
| MongoDB extract took profiles for one customer slice and events for another | Statement query M3 returned 0 rows | Event extract restricted to the same customer slice (Portfolio 4 §2) |
| `ts_sort` ordering helper leaked into exported documents | Visible in the stored document | Key subtracted before the document is emitted |
| `ALTER SYSTEM` sent in a multi-statement `psql -c` string | Silent failure: the replication lab "measured" synchronous commit that had never been enabled, and reported *lower* latency for sync than async | Mode now set with separate `-c` commands and **verified** via `SHOW` and `pg_stat_replication` before any measurement; an A-B-A measurement added (Portfolio 5 §3) |
| `synchronous_standby_names` set at container boot | The primary deadlocked on its own `CREATE DATABASE` during initialisation | Setting moved to a runtime experiment; the failure is documented as evidence of the trade-off |
| `statement_timeout` expected to interrupt a synchronous-replication wait | The write hung instead of timing out | Experiment redesigned to *observe* the blocked backend's `wait_event = 'SyncRep'`, which is stronger evidence |
| Sharding script not re-runnable: `DROP TABLE … CASCADE` removes the foreign-table partitions but leaves the real tables populated on the shard nodes | A final audit of every quoted figure against its committed evidence file found the committed sharding evidence contained `duplicate key value violates unique constraint "ledger_shard_pkey"` on the load step, while the write-up quoted an earlier successful run | Added a `TRUNCATE` that postgres_fdw propagates to the shard nodes, re-ran the exercise cleanly, and corrected every affected figure in the write-ups (the pushdown gain is 24×, not the 36× quoted from the earlier run) |

Two further verification habits were applied throughout:

1. **Expectations were recorded before measurement** (each `Plan.md`). Three
   recorded hypotheses were falsified by the results — Portfolio 2 Q3, where a
   covering index was used at a selectivity where a plain index would have been
   rejected; Portfolio 2 Q6, where indexing correctly achieved nothing; and
   Portfolio 5 R5, where `statement_timeout` did not apply. The READMEs report
   these as wrong rather than quietly adjusting the expectation.
2. **Conclusions are derived from captured output.** Portfolio 5's CAP section
   branches on whether the write actually blocked, so the write-up cannot
   contradict its own evidence.
3. **Every quoted figure was checked against its evidence file** in a final
   audit pass, mechanically rather than by eye. It compared each number in the
   READMEs with the committed `evidence/` output and found two mismatches — a
   row count quoted from a superseded run, and the sharding evidence described
   above. Both were corrected at the source rather than in the prose. A claim
   that cannot be located in a captured file is not a claim I am making.

## 5. Responsibility

I remain responsible for the accuracy, originality and understanding of
everything submitted. The design decisions — the double-entry ledger over a
single-row transfer, `account_id` as the shard key, `NUMERIC`/`Decimal128` for
money, PostgreSQL as the single system of record with MongoDB and Redis as
derived views — are decisions I can explain and defend, including the
alternatives rejected and why. Every claim in this portfolio is traceable to a
file in `evidence/` that can be regenerated by re-running the documented
commands.

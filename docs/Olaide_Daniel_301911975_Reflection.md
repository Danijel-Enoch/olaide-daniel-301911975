# Individual Technical Reflection

**Student:** Olaide Daniel · **ID:** 301911975
**Course:** MIT 8103 Advanced Database Systems — First Semester Continuous Assessment

---

## 1. The decision everything else followed from

The first real choice was whether a transfer is one row or two. The obvious
schema is `transfer(from_account, to_account, amount)`, and I rejected it early:
a deposit has no sender and a withdrawal has no receiver, so both columns become
nullable and the rule "exactly one of these is present" leaks into application
code; a reversal has to either delete history or store a negative amount; and
there is nowhere to record what the balance *was* when the posting happened.

Choosing double entry cost more work in Portfolio 1 — a deferred constraint
trigger, two rows per movement, 549,590 ledger rows instead of 275,000 — and it
paid for itself three times:

* In Portfolio 2, `balance_after` made "what was this balance 90 days ago"
  answerable from an index-only scan (89× faster after indexing).
* In Portfolio 3, the lost update was **quantifiable** — the ledger said
  −20,000 while `account.balance` said 40,000, so I could state that exactly
  NGN 60,000 had been created. With only a balance column I would have had a
  wrong number and no way to prove it was wrong.
* In Portfolio 4, the legs embedded naturally into one document, and the
  journal was what made the graph of money flow derivable at all.

The lesson I did not expect: **the value of a design often shows up two
activities later.** I would not have predicted that a modelling decision made
for integrity reasons would be what made a concurrency bug measurable.

## 2. What went wrong, and what each failure taught

I kept the failures rather than quietly fixing them, because they are where the
understanding actually came from.

**The constraint that was too strict.** `CHECK (balance >= 0)` seemed obviously
right until the seed load aborted on a branch till at −3.4 billion. The till is
the bank's own control account; money paid out across the counter legitimately
leaves it negative. I had encoded a rule about *customer* accounts as a rule
about *all* accounts. Fixing it in the constraint (and not in the data) is the
point — the model was wrong, not the load.

**The measurement that measured nothing.** My first replication lab sent
`ALTER SYSTEM SET synchronous_standby_names = 'replica_1'; SELECT
pg_reload_conf();` as a single `psql -c` string. That wraps both statements in
an implicit transaction, and `ALTER SYSTEM` cannot run in one — so it errored,
the error went to `/dev/null`, and the script went on to "measure" synchronous
replication that had never been enabled. It reported sync as *faster* than
async. I only caught it because the `sync_state` column in the output still
read `async` while the narration claimed otherwise.

That was the single most useful mistake in the portfolio. Two habits came out
of it: **verify that a setting took effect before measuring anything under it**
(`set_sync()` now prints `SHOW` and `pg_stat_replication` first), and **derive
conclusions from captured output rather than writing them in advance** (the CAP
section now branches on whether the write actually blocked, so the write-up
cannot contradict its own evidence).

**The control that failed.** Having fixed the mechanism, the A-B-A measurement
gave async 1.640 ms → sync 2.114 ms → async **2.703 ms**. The control run was
slower than the condition it was controlling for, which means host load had
moved more than the setting did. The tempting move was to report the first two
numbers and a tidy "+29% for synchronous commit" — a number that happened to
point the right way, taken from an experiment that had just failed its own
control.

Instead I wrote a repeated-measures benchmark: six alternating rounds of 500
commits, mode verified before each, means and ranges reported. That resolved it
properly — asynchronous **1.440 ms** (range 1.257–1.575) against synchronous
**2.147 ms** (range 2.041–2.216), a **+49.1%** difference with the two ranges
not overlapping at all. Every synchronous round was slower than every
asynchronous round, so the cost is attributable to the setting rather than to
ambient load. The first experiment was not wrong about the direction; it simply
could not resolve the difference against host noise with one sample each.

What I take from this is narrower than "repeat your measurements": **a control
exists to be believed when it fails.** The A-B-A told me my number was unsafe,
and the only honest responses were to design an experiment that could resolve
it or to report that I could not measure it. Publishing the tidy number anyway
would have been undetectable in the write-up, and wrong.

**The extract that described two different banks.** The first MongoDB ETL took
profiles for the first 2,000 customers and events for the newest 60,000
transactions bank-wide. Both looked fine in isolation; the statement query
returned zero rows because almost no profiled customer had an exported event.
Consistency of an extract matters as much as its shape — and a query returning
nothing is a better failure than a query returning something plausible.

**The timeout that did not apply.** I expected `statement_timeout` to cut short
a write blocked on a synchronous standby. It does not: the commit is already
durable locally, and what is outstanding is the standby's acknowledgement.
Redesigning the experiment to *observe* the blocked backend
(`wait_event = 'SyncRep'`) produced better evidence than the timeout would have.

## 3. Where my expectations were wrong

I recorded expectations in each `Plan.md` before measuring, which made being
wrong visible instead of forgettable.

* I predicted the planner would **reject** an index for the channel dashboard at
  ~17% selectivity, citing the 5–10% rule of thumb. It used the index and got
  1.8× faster. The rule of thumb is about the *random heap reads* each index
  match costs; a covering index removes them entirely, so the crossover moves
  much further out. The rule is about heap access, not index access — a
  distinction I had been repeating without understanding.
* I predicted no index would help the branch monthly report, and that was
  right — but for a reason worth stating: when a query genuinely needs 67% of a
  table, a sequential scan *is* the optimal plan, and the optimiser refusing my
  index was the optimiser being correct. The fix was to stop computing the
  answer at read time, not to find a cleverer path.
* I assumed MongoDB's `$jsonSchema` would be a reasonable substitute for
  declarative constraints. It validates one document against a structural
  contract and cannot express "debits must equal credits", because that is an
  arithmetic relationship between array elements. The collection accepted
  DR 5,000 against CR 4,000 without complaint. That result decided the
  architecture in Portfolio 4: PostgreSQL stays the system of record and the
  document store is a derived read model.

## 4. The thing I would do differently

**I would have built the verification harness before the first script, not after
the first wrong result.** Portfolios 1 and 2 were written, then checked.
Portfolios 3, 4 and 5 were written with their checks attached — negative tests
that must fail, reconciliation that runs after the experiment that corrupts the
data, a setting that prints itself before being measured under. The later
activities took less time per unit of trustworthy evidence, and I would now
treat "how will I know this is wrong?" as part of writing the script rather
than a step after it.

Two smaller things: I would choose demonstration data by *property* rather than
by hard-coded id from the start (the MongoDB query script now searches for an
account with enough events, and for a graph seed whose destination also sends
money — both added after hard-coded choices produced empty results); and I would
have set up WAL archiving in the cluster, because its absence is the most
obvious gap between my Portfolio 5 and anything that could be called a
deployment.

## 5. What I can now explain that I could not before

* Why `UPDATE account SET balance = balance - x` is correct and
  `balance = <value read earlier>` is not — and that it is the *same* principle
  that makes Redis `INCR` safe where a `GET`/`SET` pair is not.
* Why write skew needs SERIALIZABLE rather than row locks: neither transaction
  writes a row the other read, so there is nothing to lock.
* Which SQLSTATEs an application should retry (40001, 40P01) and which it must
  not (23514) — the practical pay-off of Portfolio 3, since a retry loop around
  "insufficient funds" spams a customer who simply has no money, and no retry
  around a serialization failure turns a solved problem into an outage.
* Why a 10-element embedded array and an unbounded one are completely different
  design decisions, and how the 16 MB document limit separates them.
* Why sharding is the wrong answer for HDMB today, and what specific signal —
  working set exceeding one instance's memory, WAL device saturation, or a data
  residency rule — would change that.

## 6. Honest limitations of this portfolio

* Timings come from one laptop running Docker; plan shapes and ratios are the
  reproducible part, absolute milliseconds are not.
* All measurement is single-client. Nothing here measures throughput under
  concurrent production load, and Portfolio 3's anomalies are demonstrations
  that they *can* happen, not measurements of how often they do.
* Cassandra and Neo4j are designs with reasoning, not deployments, and are
  labelled that way.
* The cluster has no WAL archiving, so it has no point-in-time recovery — the
  single largest gap against a real deployment, and the first thing I would add.

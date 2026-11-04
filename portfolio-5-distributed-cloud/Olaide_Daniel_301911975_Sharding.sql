-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 5
-- Student : Olaide Daniel (301911975)
-- File    : Horizontal sharding with declarative partitioning + postgres_fdw
-- Run on  : the primary, acting as coordinator
-- =====================================================================
-- Replication copies ALL the data to EVERY node and buys availability and
-- read capacity. Sharding splits the data so each node holds a slice, and
-- buys write capacity and a data set larger than one machine. They solve
-- different problems and are used together here.
--
-- The shard key is account_id, chosen because:
--   * the queries that must stay fast ("this account's postings", "this
--     customer's statement") all carry it, so they reach exactly one shard;
--   * hashing it spreads load evenly, unlike sharding by branch (Lagos would
--     hold most of the bank) or by date (every write would hit one shard).
-- =====================================================================
\pset pager off
SET search_path TO public;

DROP TABLE IF EXISTS ledger_distributed CASCADE;
DROP SERVER IF EXISTS shard_a CASCADE;
DROP SERVER IF EXISTS shard_b CASCADE;

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

\echo '=== 1. declare the shard nodes ==='
-- async_capable lets PostgreSQL 18 scan both shards CONCURRENTLY rather than
-- one after the other; batch_size turns row-by-row remote inserts into
-- batched ones, which is the difference between minutes and seconds on load
CREATE SERVER shard_a FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg-shard-a', port '5432', dbname 'hdmb',
             fetch_size '10000', batch_size '1000', async_capable 'true');
CREATE SERVER shard_b FOREIGN DATA WRAPPER postgres_fdw
    OPTIONS (host 'pg-shard-b', port '5432', dbname 'hdmb',
             fetch_size '10000', batch_size '1000', async_capable 'true');

CREATE USER MAPPING FOR postgres SERVER shard_a OPTIONS (user 'postgres', password 'mit8103');
CREATE USER MAPPING FOR postgres SERVER shard_b OPTIONS (user 'postgres', password 'mit8103');

\echo '=== 2. one logical table, two physical nodes ==='
CREATE TABLE ledger_distributed (
    entry_id      BIGINT        NOT NULL,
    txn_id        BIGINT        NOT NULL,
    account_id    BIGINT        NOT NULL,
    direction     CHAR(2)       NOT NULL,
    amount        NUMERIC(18,2) NOT NULL,
    balance_after NUMERIC(18,2) NOT NULL,
    entry_ts      TIMESTAMPTZ   NOT NULL
) PARTITION BY HASH (account_id);

CREATE FOREIGN TABLE ledger_distributed_s0
    PARTITION OF ledger_distributed FOR VALUES WITH (MODULUS 2, REMAINDER 0)
    SERVER shard_a OPTIONS (schema_name 'public', table_name 'ledger_shard');

CREATE FOREIGN TABLE ledger_distributed_s1
    PARTITION OF ledger_distributed FOR VALUES WITH (MODULUS 2, REMAINDER 1)
    SERVER shard_b OPTIONS (schema_name 'public', table_name 'ledger_shard');

\echo '=== 3. distribute 100,000 ledger entries across the shards ==='
\timing on
INSERT INTO ledger_distributed (entry_id, txn_id, account_id, direction, amount, balance_after, entry_ts)
SELECT entry_id, txn_id, account_id, direction, amount, balance_after, entry_ts
FROM hdmb.ledger_entry
ORDER BY entry_id
LIMIT 100000;
\timing off

ANALYZE ledger_distributed_s0;
ANALYZE ledger_distributed_s1;

\echo '=== 4. how the rows actually landed (hash distribution) ==='
SELECT tableoid::regclass AS shard, count(*) AS rows,
       count(DISTINCT account_id) AS distinct_accounts,
       to_char(sum(amount), 'FM999,999,999,990.00') AS value
FROM ledger_distributed GROUP BY 1 ORDER BY 1;

\echo '=== 5. SINGLE-SHARD query: the shard key is in the predicate ==='
-- partition pruning should leave exactly ONE Foreign Scan in the plan
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
SELECT entry_id, direction, amount, balance_after, entry_ts
FROM ledger_distributed
WHERE account_id = 4211
ORDER BY entry_ts DESC
LIMIT 10;

\echo '=== 6. CROSS-SHARD aggregate: no shard key, both nodes scanned ==='
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
SELECT direction, count(*) AS postings, sum(amount) AS total
FROM ledger_distributed
WHERE entry_ts >= now() - INTERVAL '30 days'
GROUP BY direction;

\echo '=== 7. the result of that cross-shard aggregate ==='
SELECT direction, count(*) AS postings,
       to_char(sum(amount), 'FM999,999,999,990.00') AS total
FROM ledger_distributed
WHERE entry_ts >= now() - INTERVAL '30 days'
GROUP BY direction ORDER BY direction;

\echo '=== 8. THE LIMITATION: a join between sharded and local data ==='
-- account lives only on the coordinator; ledger_distributed lives on the
-- shards. The join cannot be pushed down to either shard, so rows must be
-- shipped back and joined centrally. This is the cost of sharding, and it is
-- why the shard key has to match the access pattern.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
SELECT a.account_number, count(*) AS postings, sum(ld.amount) AS total
FROM ledger_distributed ld
JOIN hdmb.account a ON a.account_id = ld.account_id
WHERE ld.direction = 'DR' AND ld.entry_ts >= now() - INTERVAL '7 days'
GROUP BY a.account_number
ORDER BY total DESC
LIMIT 5;

\echo '=== 9. where each node thinks its data is ==='
SELECT srvname AS server, srvoptions FROM pg_foreign_server ORDER BY srvname;
SELECT ftrelid::regclass AS foreign_table, ftoptions FROM pg_foreign_table ORDER BY 1;

\echo '=== 10. PREDICATE PUSHDOWN: now() is not pushed, a literal is ==='
-- Step 6 shipped every row to the coordinator and filtered locally, because
-- now() is a STABLE function that postgres_fdw will not send to a remote
-- node (its value must be fixed by the coordinator's transaction). Computing
-- the boundary first and passing a literal lets the WHERE clause travel with
-- the query, so each shard filters its own rows and only matches cross the
-- network. Same answer, far less traffic.
SELECT (now() - INTERVAL '30 days')::timestamptz AS cutoff \gset
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
SELECT direction, count(*) AS postings, sum(amount) AS total
FROM ledger_distributed
WHERE entry_ts >= :'cutoff'::timestamptz
GROUP BY direction;

\echo '=== 11. and the aggregate itself pushed down to each shard ==='
-- With a pushdown-safe predicate the remote SQL can also carry the GROUP BY,
-- so each shard returns a handful of aggregated rows instead of thousands of
-- raw ones.
EXPLAIN (ANALYZE, VERBOSE, COSTS OFF)
SELECT * FROM (
    SELECT direction, count(*) AS postings, sum(amount) AS total
    FROM ledger_distributed_s0 WHERE entry_ts >= :'cutoff'::timestamptz GROUP BY direction
    UNION ALL
    SELECT direction, count(*), sum(amount)
    FROM ledger_distributed_s1 WHERE entry_ts >= :'cutoff'::timestamptz GROUP BY direction
) per_shard ORDER BY direction;

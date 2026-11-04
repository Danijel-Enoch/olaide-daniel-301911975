-- =====================================================================
-- MIT 8103 - Portfolio 5 | Olaide Daniel (301911975)
-- Runs on each shard node. A shard holds a horizontal slice of
-- ledger_entry and nothing else: no customers, no accounts, no joins to
-- other shards. That restriction is the whole discipline of sharding.
-- =====================================================================
CREATE TABLE ledger_shard (
    entry_id      BIGINT        NOT NULL,
    txn_id        BIGINT        NOT NULL,
    account_id    BIGINT        NOT NULL,
    direction     CHAR(2)       NOT NULL CHECK (direction IN ('DR','CR')),
    amount        NUMERIC(18,2) NOT NULL CHECK (amount > 0),
    balance_after NUMERIC(18,2) NOT NULL,
    entry_ts      TIMESTAMPTZ   NOT NULL,
    PRIMARY KEY (entry_id)
);

-- the shard key is account_id: every query that matters ("this account's
-- postings") carries it, so it can be answered by a single shard
CREATE INDEX ix_shard_account_ts ON ledger_shard (account_id, entry_ts DESC);
CREATE INDEX ix_shard_entry_ts   ON ledger_shard (entry_ts DESC);

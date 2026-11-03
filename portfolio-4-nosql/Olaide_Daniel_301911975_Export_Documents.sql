-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 4
-- Student : Olaide Daniel (301911975)
-- File    : ETL step 1 - project the relational ledger into documents
-- =====================================================================
-- The NoSQL model is not a different case study: it is the SAME HDMB data,
-- reshaped around how the mobile app reads it. This script emits MongoDB
-- Extended JSON, one document per line (JSONL), ready for mongoimport.
--
-- Two decisions visible in the SQL below are the whole point of the exercise:
--   * money is emitted as {"$numberDecimal": "..."} and never as a JSON
--     number, because MongoDB's default numeric type is a 64-bit double and
--     a binary float cannot hold 0.10 exactly - the same reason Portfolio 1
--     uses NUMERIC(18,2) rather than FLOAT;
--   * timestamps are emitted as {"$date": "...Z"} in UTC so they arrive as
--     BSON dates, not strings, and can be range-queried and indexed.
-- =====================================================================
\pset tuples_only on
\pset format unaligned
\pset pager off

-- ---------------------------------------------------------------------
-- A. customer_profile - one aggregate document per customer
--    Replaces the 4-join assembly the mobile home screen needs in SQL
--    (customer + account + product + branch) plus a statement query.
-- ---------------------------------------------------------------------
\o /tmp/hdmb_customer_profile.jsonl
SELECT json_strip_nulls(json_build_object(
    '_id',        'CUST-' || lpad(c.customer_id::text, 7, '0'),
    'customer_id', c.customer_id,
    'bvn',         c.bvn,
    'name',        json_build_object('first', c.first_name, 'last', c.last_name,
                                     'full', c.first_name || ' ' || c.last_name),
    'phone',       c.phone,
    'email',       c.email,
    'kyc_tier',    c.kyc_tier,
    'status',      c.status,
    'registered_at', json_build_object('$date',
                       to_char(c.registered_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
    -- branch is EMBEDDED, not referenced: it is small, slow-changing
    -- reference data and every read of the profile needs it
    'branch',      json_build_object('code', b.branch_code, 'name', b.branch_name,
                                     'state', b.state, 'city', b.city),
    -- accounts are embedded because they are only ever read with their owner
    -- and a customer holds at most a handful (bounded array)
    'accounts',    (SELECT COALESCE(json_agg(json_build_object(
                        'account_number', a.account_number,
                        'product', json_build_object('code', p.product_code, 'name', p.product_name,
                                                     'interest_rate_pa', p.interest_rate_pa::text::numeric,
                                                     'min_balance', json_build_object('$numberDecimal', p.min_balance::text)),
                        'currency', a.currency,
                        'balance', json_build_object('$numberDecimal', a.balance::text),
                        'status', a.status,
                        'opened_at', json_build_object('$date',
                            to_char(a.opened_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'))
                      ) ORDER BY a.account_id), '[]'::json)
                    FROM account a JOIN account_product p ON p.product_code = a.product_code
                    WHERE a.customer_id = c.customer_id),
    'beneficiaries', (SELECT COALESCE(json_agg(json_build_object(
                        'bank_code', bn.bank_code, 'account_number', bn.account_number,
                        'alias', bn.alias) ORDER BY bn.beneficiary_id), '[]'::json)
                      FROM beneficiary bn WHERE bn.customer_id = c.customer_id),
    -- recent_activity is a BOUNDED embedded array (10 newest postings). The
    -- full history stays in the txn_event collection; embedding all of it
    -- would grow the document without limit and hit the 16MB BSON cap.
    -- ts_sort exists only to give json_agg a deterministic order and is
    -- subtracted from each element before it reaches the document
    'recent_activity', (SELECT COALESCE(json_agg((ra - 'ts_sort') ORDER BY (ra->>'ts_sort') DESC), '[]'::json)
                        FROM (SELECT jsonb_build_object(
                                 'txn_ref', t.txn_ref, 'type', t.txn_type, 'channel', t.channel_code,
                                 'direction', le.direction, 'status', t.status,
                                 'amount', json_build_object('$numberDecimal', le.amount::text),
                                 'balance_after', json_build_object('$numberDecimal', le.balance_after::text),
                                 'account_number', a2.account_number,
                                 'ts', json_build_object('$date',
                                     to_char(le.entry_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
                                 'ts_sort', to_char(le.entry_ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS')) AS ra
                              FROM ledger_entry le
                              JOIN account a2 ON a2.account_id = le.account_id
                              JOIN txn t ON t.txn_id = le.txn_id
                              WHERE a2.customer_id = c.customer_id
                              ORDER BY le.entry_ts DESC, le.entry_id DESC
                              LIMIT 10) s),
    'totals', (SELECT json_build_object(
                   'account_count', count(*),
                   'deposit_balance', json_build_object('$numberDecimal', COALESCE(sum(a.balance), 0)::text))
               FROM account a WHERE a.customer_id = c.customer_id)
))::text
FROM customer c
JOIN branch b ON b.branch_id = c.home_branch_id
WHERE c.first_name <> 'HDMB'          -- exclude internal till customers
  AND c.customer_id <= 2000           -- a 2,000-customer slice keeps the import fast
ORDER BY c.customer_id;
\o

-- ---------------------------------------------------------------------
-- B. txn_event - one document per transaction, legs embedded
--    An append-only event collection: the document is written once and
--    never updated, which is the access pattern a document store is best at.
-- ---------------------------------------------------------------------
\o /tmp/hdmb_txn_event.jsonl
SELECT json_strip_nulls(json_build_object(
    '_id',      t.txn_ref,
    'txn_type', t.txn_type,
    'channel',  t.channel_code,
    'status',   t.status,
    'amount',   json_build_object('$numberDecimal', t.amount::text),
    'currency', t.currency,
    'narration', t.narration,
    'created_at', json_build_object('$date',
        to_char(t.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
    'completed_at', CASE WHEN t.completed_at IS NULL THEN NULL ELSE json_build_object('$date',
        to_char(t.completed_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) END,
    'initiator', CASE WHEN t.initiated_by_customer IS NOT NULL
                      THEN json_build_object('kind', 'CUSTOMER', 'customer_id', t.initiated_by_customer)
                      ELSE json_build_object('kind', 'STAFF', 'staff_id', t.initiated_by_staff) END,
    -- the journal legs are embedded: a transaction is read as a whole, and
    -- this is the join that disappears compared with the relational model
    'legs', (SELECT json_agg(json_build_object(
                 'account_number', a.account_number,
                 'customer_id', a.customer_id,
                 'branch_code', br.branch_code,
                 'product_code', a.product_code,
                 'direction', le.direction,
                 'amount', json_build_object('$numberDecimal', le.amount::text),
                 'balance_after', json_build_object('$numberDecimal', le.balance_after::text)
               ) ORDER BY le.direction)
             FROM ledger_entry le
             JOIN account a ON a.account_id = le.account_id
             JOIN customer c2 ON c2.customer_id = a.customer_id
             JOIN branch br ON br.branch_id = c2.home_branch_id
             WHERE le.txn_id = t.txn_id)
))::text
FROM txn t
-- The event slice must cover the SAME customers as the profile slice above,
-- or the two collections describe different populations and every join-free
-- read lands on a customer whose events are missing. Consistency of the
-- extract matters as much as its shape.
WHERE t.txn_ref NOT LIKE 'DEMO-%' AND t.txn_ref NOT LIKE 'REV-DEMO-%'
  AND EXISTS (SELECT 1
                FROM ledger_entry le
                JOIN account a ON a.account_id = le.account_id
               WHERE le.txn_id = t.txn_id
                 AND a.customer_id BETWEEN 13 AND 2000)
ORDER BY t.created_at DESC
LIMIT 60000;
\o

\pset tuples_only off
\echo '--- export complete; line counts: ---'

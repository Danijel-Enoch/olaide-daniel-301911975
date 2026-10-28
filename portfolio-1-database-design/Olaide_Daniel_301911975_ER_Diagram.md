# Portfolio 1 — Entity Relationship Model

**Student:** Olaide Daniel (301911975) · Case study: Harmony Digital Microfinance Bank (HDMB)

The diagram is written in Mermaid, which GitHub renders natively — so the model
is version-controlled text that diffs across commits rather than a flat image
that silently goes stale. For the LMS upload, the rendered diagram is captured
as a screenshot from the GitHub view of this file (it can also be exported with
`npx @mermaid-js/mermaid-cli -i <this file> -o er.png`).

## 1. Conceptual / logical ER diagram

```mermaid
erDiagram
    BRANCH          ||--o{ CUSTOMER        : "is home branch of"
    BRANCH          ||--o{ STAFF           : employs
    CUSTOMER        ||--o{ ACCOUNT         : holds
    CUSTOMER        ||--o{ BENEFICIARY     : saves
    CUSTOMER        ||--o{ LOAN            : borrows
    CUSTOMER        ||--o{ TXN             : "initiates (self-service)"
    STAFF           ||--o{ TXN             : "posts (branch/agent)"
    STAFF           ||--o{ LOAN            : approves
    ACCOUNT_PRODUCT ||--o{ ACCOUNT         : "defines terms of"
    CHANNEL         ||--o{ TXN             : "carries"
    ACCOUNT         ||--o{ LEDGER_ENTRY    : "is posted to"
    TXN             ||--|{ LEDGER_ENTRY    : "is journalised as"
    LOAN            ||--o{ LOAN_REPAYMENT  : "is repaid by"
    TXN             ||--o| LOAN_REPAYMENT  : "settles"
    ACCOUNT         ||--o{ LOAN            : "receives disbursement"

    BRANCH {
        bigint  branch_id   PK
        char    branch_code UK "HD01..HD12"
        varchar branch_name
        varchar state
        varchar city
        date    opened_on
    }
    CUSTOMER {
        bigint   customer_id    PK
        char     bvn            UK "11 digits"
        varchar  first_name
        varchar  last_name
        date     date_of_birth      "must be 18+"
        varchar  phone          UK
        varchar  email
        text     residential_address
        smallint kyc_tier           "1-3"
        bigint   home_branch_id FK
        varchar  status            "ACTIVE|DORMANT|FROZEN|CLOSED"
        timestamptz registered_at
    }
    STAFF {
        bigint  staff_id     PK
        varchar staff_number UK
        varchar full_name
        varchar job_role
        bigint  branch_id    FK
        varchar work_email   UK
        boolean is_active
    }
    ACCOUNT_PRODUCT {
        varchar product_code      PK
        varchar product_name
        numeric interest_rate_pa
        numeric min_balance
        numeric daily_debit_limit
    }
    ACCOUNT {
        bigint  account_id     PK
        char    account_number UK "10 digits"
        bigint  customer_id    FK
        varchar product_code   FK
        char    currency
        numeric balance           "maintained running total"
        varchar status            "one ACTIVE per product"
        timestamptz opened_at
        timestamptz closed_at
    }
    CHANNEL {
        varchar channel_code PK "USSD|MOBILE|WEB|POS|BRANCH|ATM"
        varchar channel_name
        boolean is_self_service
    }
    TXN {
        bigint  txn_id       PK
        varchar txn_ref      UK "idempotency key"
        varchar txn_type        "TRANSFER|DEPOSIT|WITHDRAWAL|FEE|LOAN_DISB|LOAN_REPAY"
        varchar channel_code FK
        numeric amount          "> 0"
        char    currency
        varchar status          "PENDING|SUCCESS|FAILED|REVERSED"
        varchar narration
        bigint  initiated_by_customer FK "XOR with staff"
        bigint  initiated_by_staff    FK
        timestamptz created_at
        timestamptz completed_at
    }
    LEDGER_ENTRY {
        bigint  entry_id      PK
        bigint  txn_id        FK
        bigint  account_id    FK
        char    direction        "DR|CR"
        numeric amount           "> 0"
        numeric balance_after
        timestamptz entry_ts
    }
    LOAN {
        bigint  loan_id             PK
        varchar loan_ref            UK
        bigint  customer_id         FK
        bigint  disburse_account_id FK
        numeric principal
        numeric interest_rate_pa
        smallint tenor_months
        varchar status                 "ACTIVE|SETTLED|DEFAULTED|WRITTEN_OFF"
        bigint  approved_by         FK
        date    disbursed_on
        date    due_on
    }
    LOAN_REPAYMENT {
        bigint  repayment_id      PK
        bigint  loan_id           FK
        bigint  txn_id            FK
        numeric amount
        numeric principal_portion
        numeric interest_portion
        date    paid_on
    }
    AUDIT_LOG {
        bigint  audit_id   PK
        varchar table_name
        bigint  record_pk
        varchar action
        varchar changed_by
        timestamptz changed_at
        jsonb   old_row
        jsonb   new_row
    }
```

`AUDIT_LOG` is intentionally drawn without relationships: it is an append-only
sink written by a trigger and holds *soft* references (`table_name` + `record_pk`)
so it survives the deletion of the row it describes.

## 2. Cardinality and participation, stated

| Relationship | Reading |
|---|---|
| BRANCH → CUSTOMER | One branch is home to zero or many customers; every customer has exactly one home branch (mandatory). |
| CUSTOMER → ACCOUNT | A customer holds zero or many accounts; every account belongs to exactly one customer. At most one *ACTIVE* account per product. |
| TXN → LEDGER_ENTRY | **One-to-many, minimum two.** This is the critical cardinality: a transaction with one leg is money created out of nothing, and `trg_ledger_balanced` rejects it. |
| ACCOUNT → LEDGER_ENTRY | An account accumulates zero or many postings; entries are never updated or deleted, only offset by a reversal. |
| TXN → initiator | Exactly one of (customer, staff) — an exclusive-or relationship, enforced by `chk_txn_single_initiator` rather than by two optional foreign keys alone. |
| LOAN → LOAN_REPAYMENT | A loan has zero or many repayments; each repayment is also a `TXN`, so the cash and the credit record can never disagree. |

## 3. Why the transfer is not a single row

The obvious design is `transfer(from_account, to_account, amount)`. It was
rejected:

* A deposit has no sender and a withdrawal has no receiver, so both columns
  become nullable and the rule "one of them must be present" leaks into
  application code.
* A reversal has to either delete the row (destroying history) or add a negative
  amount (breaking `amount > 0`).
* There is no place to record what each account's balance *was*, so a disputed
  statement cannot be reconstructed.

Double entry solves all three: a deposit is DR till / CR customer, a reversal is
a new transaction with the legs swapped, and `balance_after` preserves the
account's position at the moment of posting.

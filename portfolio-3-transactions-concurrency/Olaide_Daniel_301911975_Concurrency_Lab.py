#!/usr/bin/env python3
"""
=====================================================================
MIT 8103 Advanced Database Systems - Portfolio 3
Student : Olaide Daniel (301911975)
File    : Concurrency laboratory - orchestrates real concurrent sessions
=====================================================================
A concurrency anomaly cannot be demonstrated from a single psql script: it
only exists when two transactions overlap in time. This harness opens two
(or three) genuinely separate PostgreSQL sessions, each on its own pseudo
terminal so psql stays line-buffered, sends statements to them in a
controlled interleaving, and records every line of output with the wall-clock
time it arrived.

The timestamps are the evidence. When session B produces no output for two
seconds and then returns, that gap IS the lock wait.

Usage:  python3 Olaide_Daniel_301911975_Concurrency_Lab.py [D1 D2 ...]
Output: evidence/Olaide_Daniel_301911975_D<n>_<name>.txt
=====================================================================
"""
import os
import pty
import select
import subprocess
import sys
import termios
import time
from pathlib import Path

CONTAINER = "mit8103-pg"
EVIDENCE = Path(__file__).resolve().parent / "evidence"
# A TTY *inside* the container is what keeps psql line-buffered, which is what
# makes the arrival timestamps meaningful. `stty -echo` then stops the container
# terminal echoing the statements back, which would duplicate every line.
PSQL = ["docker", "exec", "-i", "-t", CONTAINER, "sh", "-c",
        "stty -echo; exec psql -U postgres -d hdmb -q -P pager=off"]


class Session:
    """One psql process on its own pty, so output is line-buffered."""

    def __init__(self, tag, log):
        self.tag = tag
        self.log = log
        master, slave = pty.openpty()
        # turn off terminal echo: the harness logs what it sends, and psql -e
        # already echoes each statement. Echo as well would duplicate it.
        attrs = termios.tcgetattr(slave)
        attrs[3] &= ~termios.ECHO
        termios.tcsetattr(slave, termios.TCSANOW, attrs)
        self.proc = subprocess.Popen(PSQL, stdin=slave, stdout=slave,
                                     stderr=slave, close_fds=True)
        os.close(slave)
        self.fd = master

    def send(self, sql):
        self.log.note(self.tag, ">> " + sql.strip())
        os.write(self.fd, (sql.rstrip() + "\n").encode())

    def close(self):
        try:
            os.write(self.fd, b"\\q\n")
        except OSError:
            pass
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        os.close(self.fd)


class Log:
    """Merged, timestamped transcript of every session."""

    def __init__(self):
        self.t0 = time.time()
        self.lines = []

    def note(self, tag, text):
        self.lines.append((time.time() - self.t0, tag, text))

    def drain(self, sessions, seconds):
        """Read whatever the sessions emit for `seconds`, timestamping lines."""
        fds = {s.fd: s for s in sessions}
        buf = {s.fd: b"" for s in sessions}
        deadline = time.time() + seconds
        while time.time() < deadline:
            ready, _, _ = select.select(list(fds), [], [], max(0.0, deadline - time.time()))
            for fd in ready:
                try:
                    chunk = os.read(fd, 8192)
                except OSError:
                    continue
                if not chunk:
                    continue
                buf[fd] += chunk
                while b"\n" in buf[fd]:
                    line, buf[fd] = buf[fd].split(b"\n", 1)
                    text = line.decode(errors="replace").replace("\r", "").rstrip()
                    if text:
                        self.note(fds[fd].tag, text)
        for fd, left in buf.items():
            text = left.decode(errors="replace").replace("\r", "").strip()
            if text:
                self.note(fds[fd].tag, text)

    def render(self, title, narrative, expected):
        out = []
        out.append("=" * 78)
        out.append(title)
        out.append("=" * 78)
        out.append("Student : Olaide Daniel (301911975)")
        out.append("Captured: " + time.strftime("%Y-%m-%d %H:%M:%S %Z"))
        out.append("")
        out.append("WHAT THIS DEMONSTRATES")
        for line in narrative.strip().splitlines():
            out.append("  " + line.strip())
        out.append("")
        out.append("EXPECTED RESULT")
        for line in expected.strip().splitlines():
            out.append("  " + line.strip())
        out.append("")
        out.append("TRANSCRIPT  (t = seconds from start of demo; >> = statement sent)")
        out.append("-" * 78)
        for t, tag, text in self.lines:
            out.append(f"[t+{t:06.3f}] [{tag}] {text}")
        out.append("-" * 78)
        return "\n".join(out) + "\n"


# ---------------------------------------------------------------------
# Demo definitions. A step is (session_tag, sql, pause_seconds) or
# ("#", comment_text, pause_seconds) for a marker line in the transcript.
# ---------------------------------------------------------------------
RESET = "SELECT * FROM fn_reset_demo_accounts();"
SHOW = ("SELECT account_id, account_number, balance FROM account "
        "WHERE account_id IN (900001, 900002) ORDER BY account_id;")

DEMOS = {}

DEMOS["D1"] = dict(
    name="Atomicity_And_Commit",
    title="D1 - ATOMICITY: a committed transfer, and what other sessions see before COMMIT",
    narrative="""
    Session A performs a NGN 25,000.00 transfer inside an explicit transaction.
    Session C (an uninvolved observer) reads the same two accounts before and
    after A commits. A sees its own uncommitted change; C does not.
    """,
    expected="""
    - Inside A's transaction: 900001 = 75,000.00 and 900002 = 125,000.00
    - At the same moment in C: still 100,000.00 / 100,000.00 (no dirty read)
    - After A commits: C now sees 75,000.00 / 125,000.00
    - Both ledger legs exist and the transaction balances
    """,
    sessions="AC",
    steps=[
        ("A", RESET, 0.6),
        ("A", SHOW, 0.5),
        ("#", "A opens a transaction and transfers NGN 25,000.00 from 900001 to 900002", 0),
        ("A", "BEGIN;", 0.3),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 25000.00, 'DEMO-D1-TRANSFER') AS new_txn_id;", 0.8),
        ("A", SHOW, 0.5),
        ("#", "C reads the SAME rows while A is still uncommitted - PostgreSQL never", 0),
        ("#", "permits a dirty read, so C must still see the pre-transfer balances", 0),
        ("C", SHOW, 0.8),
        ("#", "A commits", 0),
        ("A", "COMMIT;", 0.6),
        ("C", SHOW, 0.8),
        ("C", "SELECT t.txn_ref, t.status, le.direction, le.amount, le.balance_after "
              "FROM txn t JOIN ledger_entry le ON le.txn_id = t.txn_id "
              "WHERE t.txn_ref = 'DEMO-D1-TRANSFER' ORDER BY le.direction;", 0.8),
    ],
)

DEMOS["D2"] = dict(
    name="Rollback_And_Failure",
    title="D2 - ROLLBACK: a failed business rule undoes the whole unit of work",
    narrative="""
    Session A makes a valid NGN 10,000.00 transfer, then attempts a second
    transfer of NGN 120,000.00 which breaches the minimum-balance rule. The
    exception aborts the transaction; the first, perfectly valid transfer is
    rolled back with it. That is atomicity at the level of the unit of work,
    not the statement.
    """,
    expected="""
    - First transfer succeeds inside the transaction
    - Second raises: insufficient funds ... (SQLSTATE 23514)
    - Any statement after the error is refused: 'current transaction is aborted'
    - After ROLLBACK both balances are back to 100,000.00
    - No DEMO-D2 rows survive in txn or ledger_entry
    """,
    sessions="A",
    steps=[
        ("A", RESET, 0.6),
        ("A", "BEGIN;", 0.3),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 10000.00, 'DEMO-D2-VALID') AS ok_txn;", 0.8),
        ("A", SHOW, 0.5),
        ("#", "now a transfer that breaches the NGN 5,000.00 minimum balance", 0),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 120000.00, 'DEMO-D2-TOOBIG') AS should_fail;", 0.9),
        ("#", "the transaction is now in an aborted state - prove it", 0),
        ("A", SHOW, 0.6),
        ("A", "ROLLBACK;", 0.5),
        ("#", "after rollback: balances restored AND the valid transfer is gone too", 0),
        ("A", SHOW, 0.5),
        ("A", "SELECT count(*) AS surviving_demo_d2_rows FROM txn WHERE txn_ref LIKE 'DEMO-D2%';", 0.6),
    ],
)

DEMOS["D3"] = dict(
    name="Lost_Update",
    title="D3 - LOST UPDATE: the same workload with and without row locking",
    narrative="""
    Account 900001 holds NGN 100,000.00. Two sessions each try to send
    NGN 60,000.00 out of it at the same instant. Only one can legitimately
    succeed.
    PART 1 uses fn_transfer_naive(): it reads the balance, checks it, waits
    (standing in for application latency) and writes back balance - amount.
    PART 2 repeats the identical workload through fn_transfer_funds(), which
    locks the row with SELECT ... FOR UPDATE and writes balance = balance - x.
    """,
    expected="""
    PART 1 - both sessions read 100,000.00, both pass their own check, both
             commit. The second UPDATE overwrites the first: the account ends
             at 40,000.00 having paid out 120,000.00. NGN 60,000.00 has been
             created from nothing, and account.balance no longer reconciles
             with the ledger.
    PART 2 - the second session blocks on the row lock until the first
             commits, then re-reads the real balance and is correctly refused
             with 'insufficient funds'. Final balance 40,000.00 after a single
             successful 60,000.00 transfer, and the ledger reconciles.
    """,
    sessions="AB",
    steps=[
        ("A", RESET, 0.6),
        ("A", SHOW, 0.5),
        ("#", "=========== PART 1: fn_transfer_naive (no row lock) ===========", 0),
        ("A", "SELECT fn_transfer_naive(900001, 900002, 60000.00, 'DEMO-D3-NAIVE-A') AS a_txn;", 0.05),
        ("B", "SELECT fn_transfer_naive(900001, 900002, 60000.00, 'DEMO-D3-NAIVE-B') AS b_txn;", 1.6),
        ("A", SHOW, 0.6),
        ("#", "reconciliation check: does account.balance still equal the ledger?", 0),
        ("A", "SELECT a.account_id, a.balance AS stored_balance, "
              "COALESCE(sum(CASE WHEN le.direction='CR' THEN le.amount ELSE -le.amount END),0) AS ledger_net, "
              "a.balance - COALESCE(sum(CASE WHEN le.direction='CR' THEN le.amount ELSE -le.amount END),0) AS discrepancy "
              "FROM account a LEFT JOIN ledger_entry le ON le.account_id = a.account_id "
              "WHERE a.account_id IN (900001,900002) GROUP BY a.account_id, a.balance ORDER BY a.account_id;", 0.8),
        ("A", "SELECT count(*) AS debits_allowed_against_one_balance, sum(le.amount) AS total_paid_out "
              "FROM ledger_entry le JOIN txn t ON t.txn_id=le.txn_id "
              "WHERE t.txn_ref LIKE 'DEMO-D3-NAIVE%' AND le.direction='DR';", 0.7),
        ("#", "=========== PART 2: fn_transfer_funds (SELECT FOR UPDATE) ===========", 0),
        ("A", RESET, 0.8),
        ("A", SHOW, 0.5),
        ("A", "BEGIN;", 0.3),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 60000.00, 'DEMO-D3-SAFE-A') AS a_txn;", 0.4),
        ("#", "B now attempts the same thing and MUST block on A's row lock", 0),
        ("B", "SELECT fn_transfer_funds(900001, 900002, 60000.00, 'DEMO-D3-SAFE-B') AS b_txn;", 1.2),
        ("#", "B has produced no output above: it is waiting. A commits now", 0),
        ("A", "COMMIT;", 1.5),
        ("#", "B woke up, re-read the real balance and was refused", 0),
        ("A", SHOW, 0.6),
        ("A", "SELECT a.account_id, a.balance AS stored_balance, "
              "COALESCE(sum(CASE WHEN le.direction='CR' THEN le.amount ELSE -le.amount END),0) AS ledger_net, "
              "a.balance - COALESCE(sum(CASE WHEN le.direction='CR' THEN le.amount ELSE -le.amount END),0) AS discrepancy "
              "FROM account a LEFT JOIN ledger_entry le ON le.account_id = a.account_id "
              "WHERE a.account_id IN (900001,900002) GROUP BY a.account_id, a.balance ORDER BY a.account_id;", 0.8),
    ],
)

DEMOS["D4"] = dict(
    name="Isolation_Levels",
    title="D4 - ISOLATION LEVELS: the same read, under READ COMMITTED and REPEATABLE READ",
    narrative="""
    Session A reads a balance, session B transfers money and commits, then A
    reads the same row again inside the same transaction.
    PART 1 runs A at READ COMMITTED (PostgreSQL's default).
    PART 2 runs A at REPEATABLE READ.
    Nothing about the query changes - only the isolation level.
    """,
    expected="""
    PART 1 (READ COMMITTED): A's second read returns a DIFFERENT value. This
            is a non-repeatable read. Each statement takes a fresh snapshot,
            so a report made of several queries can be internally inconsistent.
    PART 2 (REPEATABLE READ): A's second read returns the SAME value it saw
            first, even though B's commit is already durable. A's snapshot is
            fixed at the start of the transaction.
    """,
    sessions="AB",
    steps=[
        ("A", RESET, 0.6),
        ("#", "=========== PART 1: A at READ COMMITTED (the default) ===========", 0),
        ("A", "BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;", 0.3),
        ("A", "SELECT current_setting('transaction_isolation') AS isolation_level;", 0.4),
        ("A", "SELECT balance AS a_first_read FROM account WHERE account_id = 900001;", 0.5),
        ("#", "B transfers 5,000.00 out of 900001 and commits", 0),
        ("B", "SELECT fn_transfer_funds(900001, 900002, 5000.00, 'DEMO-D4-RC') AS b_txn;", 1.0),
        ("#", "A re-reads the same row in the same still-open transaction", 0),
        ("A", "SELECT balance AS a_second_read FROM account WHERE account_id = 900001;", 0.6),
        ("A", "COMMIT;", 0.4),
        ("#", "=========== PART 2: A at REPEATABLE READ ===========", 0),
        ("A", "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;", 0.3),
        ("A", "SELECT current_setting('transaction_isolation') AS isolation_level;", 0.4),
        ("A", "SELECT balance AS a_first_read FROM account WHERE account_id = 900001;", 0.5),
        ("#", "B transfers another 5,000.00 and commits", 0),
        ("B", "SELECT fn_transfer_funds(900001, 900002, 5000.00, 'DEMO-D4-RR') AS b_txn;", 1.0),
        ("A", "SELECT balance AS a_second_read FROM account WHERE account_id = 900001;", 0.6),
        ("#", "A's snapshot is frozen. Outside the transaction the new value is visible", 0),
        ("A", "COMMIT;", 0.4),
        ("A", "SELECT balance AS a_read_after_commit FROM account WHERE account_id = 900001;", 0.6),
    ],
)

DEMOS["D5"] = dict(
    name="Serializable_Write_Skew",
    title="D5 - WRITE SKEW and SERIALIZABLE: a limit two transactions can break together",
    narrative="""
    HDMB enforces a daily debit limit of NGN 50,000.00 per account. Each
    session checks the limit by summing today's debits, and each then posts a
    NGN 30,000.00 debit. Individually both checks pass; together they breach
    the limit by 10,000.00. This is write skew - neither transaction writes a
    row the other read, so no row lock can catch it.
    PART 1 runs both at REPEATABLE READ. PART 2 runs both at SERIALIZABLE.
    """,
    expected="""
    PART 1 (REPEATABLE READ): both commit. Total debited = 60,000.00 against a
            50,000.00 limit. The rule is broken with no error anywhere.
    PART 2 (SERIALIZABLE): PostgreSQL's predicate locking detects that the two
            transactions cannot be serialised and aborts one with
            SQLSTATE 40001 (could not serialize access due to read/write
            dependencies). The application must retry, and the limit holds.
    """,
    sessions="AB",
    steps=[
        ("A", RESET, 0.6),
        ("A", "DELETE FROM ledger_entry WHERE txn_id IN (SELECT txn_id FROM txn WHERE txn_ref LIKE 'DEMO-D5%'); "
              "DELETE FROM txn WHERE txn_ref LIKE 'DEMO-D5%';", 0.5),
        ("#", "=========== PART 1: both sessions at REPEATABLE READ ===========", 0),
        ("A", "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;", 0.2),
        ("B", "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;", 0.2),
        ("A", "SELECT COALESCE(sum(le.amount),0) AS a_sees_debited_today FROM ledger_entry le "
              "JOIN txn t ON t.txn_id=le.txn_id WHERE le.account_id=900001 AND le.direction='DR' "
              "AND t.txn_ref LIKE 'DEMO-D5%';", 0.4),
        ("B", "SELECT COALESCE(sum(le.amount),0) AS b_sees_debited_today FROM ledger_entry le "
              "JOIN txn t ON t.txn_id=le.txn_id WHERE le.account_id=900001 AND le.direction='DR' "
              "AND t.txn_ref LIKE 'DEMO-D5%';", 0.4),
        ("#", "both saw 0.00 debited, so both believe a 30,000.00 debit is within the 50,000.00 limit", 0),
        ("A", "INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at) "
              "VALUES ('DEMO-D5-RR-A','WITHDRAWAL','ATM',30000.00,'SUCCESS',900001,now());", 0.3),
        ("A", "INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after) "
              "SELECT txn_id, 900001, 'DR', 30000.00, 70000.00 FROM txn WHERE txn_ref='DEMO-D5-RR-A' "
              "UNION ALL SELECT txn_id, 900002, 'CR', 30000.00, 130000.00 FROM txn WHERE txn_ref='DEMO-D5-RR-A';", 0.3),
        ("B", "INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at) "
              "VALUES ('DEMO-D5-RR-B','WITHDRAWAL','ATM',30000.00,'SUCCESS',900001,now());", 0.3),
        ("B", "INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after) "
              "SELECT txn_id, 900001, 'DR', 30000.00, 70000.00 FROM txn WHERE txn_ref='DEMO-D5-RR-B' "
              "UNION ALL SELECT txn_id, 900002, 'CR', 30000.00, 130000.00 FROM txn WHERE txn_ref='DEMO-D5-RR-B';", 0.3),
        ("A", "COMMIT;", 0.5),
        ("B", "COMMIT;", 0.7),
        ("A", "SELECT sum(le.amount) AS total_debited_today, 50000.00 AS daily_limit, "
              "CASE WHEN sum(le.amount) > 50000 THEN 'LIMIT BREACHED' ELSE 'within limit' END AS outcome "
              "FROM ledger_entry le JOIN txn t ON t.txn_id=le.txn_id "
              "WHERE le.account_id=900001 AND le.direction='DR' AND t.txn_ref LIKE 'DEMO-D5-RR%';", 0.8),
        ("#", "=========== PART 2: both sessions at SERIALIZABLE ===========", 0),
        ("A", "DELETE FROM ledger_entry WHERE txn_id IN (SELECT txn_id FROM txn WHERE txn_ref LIKE 'DEMO-D5%'); "
              "DELETE FROM txn WHERE txn_ref LIKE 'DEMO-D5%';", 0.5),
        ("A", "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;", 0.2),
        ("B", "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;", 0.2),
        ("A", "SELECT COALESCE(sum(le.amount),0) AS a_sees_debited_today FROM ledger_entry le "
              "JOIN txn t ON t.txn_id=le.txn_id WHERE le.account_id=900001 AND le.direction='DR' "
              "AND t.txn_ref LIKE 'DEMO-D5%';", 0.4),
        ("B", "SELECT COALESCE(sum(le.amount),0) AS b_sees_debited_today FROM ledger_entry le "
              "JOIN txn t ON t.txn_id=le.txn_id WHERE le.account_id=900001 AND le.direction='DR' "
              "AND t.txn_ref LIKE 'DEMO-D5%';", 0.4),
        ("A", "INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at) "
              "VALUES ('DEMO-D5-SER-A','WITHDRAWAL','ATM',30000.00,'SUCCESS',900001,now());", 0.3),
        ("A", "INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after) "
              "SELECT txn_id, 900001, 'DR', 30000.00, 70000.00 FROM txn WHERE txn_ref='DEMO-D5-SER-A' "
              "UNION ALL SELECT txn_id, 900002, 'CR', 30000.00, 130000.00 FROM txn WHERE txn_ref='DEMO-D5-SER-A';", 0.3),
        ("B", "INSERT INTO txn (txn_ref, txn_type, channel_code, amount, status, initiated_by_customer, completed_at) "
              "VALUES ('DEMO-D5-SER-B','WITHDRAWAL','ATM',30000.00,'SUCCESS',900001,now());", 0.3),
        ("B", "INSERT INTO ledger_entry (txn_id, account_id, direction, amount, balance_after) "
              "SELECT txn_id, 900001, 'DR', 30000.00, 70000.00 FROM txn WHERE txn_ref='DEMO-D5-SER-B' "
              "UNION ALL SELECT txn_id, 900002, 'CR', 30000.00, 130000.00 FROM txn WHERE txn_ref='DEMO-D5-SER-B';", 0.3),
        ("A", "COMMIT;", 0.6),
        ("#", "A committed first. B must now be refused if the two are not serialisable", 0),
        ("B", "COMMIT;", 1.0),
        ("B", "ROLLBACK;", 0.4),
        ("A", "SELECT COALESCE(sum(le.amount),0) AS total_debited_today, 50000.00 AS daily_limit, "
              "CASE WHEN COALESCE(sum(le.amount),0) > 50000 THEN 'LIMIT BREACHED' ELSE 'within limit' END AS outcome "
              "FROM ledger_entry le JOIN txn t ON t.txn_id=le.txn_id "
              "WHERE le.account_id=900001 AND le.direction='DR' AND t.txn_ref LIKE 'DEMO-D5-SER%';", 0.8),
    ],
)

DEMOS["D6"] = dict(
    name="Deadlock_And_Prevention",
    title="D6 - DEADLOCK: how to cause one, how the server resolves it, how to prevent it",
    narrative="""
    PART 1 creates a deadlock on purpose: A locks account 900001 then wants
    900002; B locks 900002 then wants 900001. Session C inspects pg_locks
    while both are stuck.
    PART 2 runs the same two opposite-direction transfers through
    fn_transfer_funds(), which always locks the lower account_id first.
    """,
    expected="""
    PART 1 - the second waiter is aborted by the deadlock detector with
             SQLSTATE 40P01 'deadlock detected'. The server breaks the cycle
             itself after deadlock_timeout; it does not hang forever.
    PART 2 - both transfers succeed. Ordered lock acquisition makes the
             waits-for cycle impossible, so there is nothing to detect.
    """,
    sessions="ABC",
    steps=[
        ("A", RESET, 0.6),
        ("#", "=========== PART 1: deliberate deadlock (unordered locking) ===========", 0),
        ("A", "BEGIN;", 0.2),
        ("B", "BEGIN;", 0.2),
        ("A", "SELECT account_id, balance FROM account WHERE account_id = 900001 FOR UPDATE;", 0.5),
        ("B", "SELECT account_id, balance FROM account WHERE account_id = 900002 FOR UPDATE;", 0.5),
        ("#", "each session now holds one lock and asks for the other - the cycle", 0),
        ("A", "SELECT account_id, balance FROM account WHERE account_id = 900002 FOR UPDATE;", 0.2),
        ("B", "SELECT account_id, balance FROM account WHERE account_id = 900001 FOR UPDATE;", 0.15),
        ("#", "C inspects the wait graph NOW, inside the 1s deadlock_timeout window,", 0),
        ("#", "before the detector has had a chance to break the cycle", 0),
        ("C", "SELECT pid, state, wait_event_type, wait_event, left(query, 46) AS waiting_on "
              "FROM pg_stat_activity WHERE datname='hdmb' AND wait_event_type='Lock';", 0.5),
        ("#", "deadlock_timeout elapses and the detector fires, aborting one victim", 0),
        ("#", "(waiting below for the detector, which is why there is a pause here)", 1.5),
        ("A", "SELECT 'A still alive' AS a_state;", 0.8),
        ("B", "SELECT 'B still alive' AS b_state;", 0.8),
        ("A", "ROLLBACK;", 0.3),
        ("B", "ROLLBACK;", 0.5),
        ("#", "=========== PART 2: the same workload through ordered locking ===========", 0),
        ("A", RESET, 0.8),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 7000.00, 'DEMO-D6-ORDERED-A') AS a_txn;", 0.05),
        ("B", "SELECT fn_transfer_funds(900002, 900001, 4000.00, 'DEMO-D6-ORDERED-B') AS b_txn;", 1.5),
        ("A", SHOW, 0.6),
        ("A", "SELECT count(*) AS both_transfers_committed FROM txn WHERE txn_ref LIKE 'DEMO-D6-ORDERED%';", 0.6),
    ],
)

DEMOS["D7"] = dict(
    name="Reversal_And_Audit",
    title="D7 - COMPENSATING TRANSACTION: reversing a disputed transfer without losing history",
    narrative="""
    A customer disputes a NGN 18,500.00 transfer. Operations reverses it.
    The reversal is a new transaction with the legs swapped; nothing is
    deleted or edited, and the audit trigger records every balance change.
    """,
    expected="""
    - Balances return to 100,000.00 / 100,000.00
    - The original transaction still exists, with status REVERSED
    - A new transaction REV-DEMO-D7 exists with the opposite legs
    - audit_log holds one row per balance change, old and new value visible
    - Attempting to reverse the same transaction twice is refused
    """,
    sessions="A",
    steps=[
        ("A", RESET, 0.6),
        ("A", "SELECT fn_transfer_funds(900001, 900002, 18500.00, 'DEMO-D7-DISPUTED') AS original_txn;", 0.7),
        ("A", SHOW, 0.5),
        ("#", "the customer disputes it; operations reverses", 0),
        ("A", "SELECT fn_reverse_txn('DEMO-D7-DISPUTED', 'customer dispute - unauthorised transfer') AS reversal_txn;", 0.8),
        ("A", SHOW, 0.5),
        ("A", "SELECT txn_ref, status, amount, narration FROM txn "
              "WHERE txn_ref IN ('DEMO-D7-DISPUTED','REV-DEMO-D7-DISPUTED') ORDER BY txn_id;", 0.6),
        ("A", "SELECT t.txn_ref, le.account_id, le.direction, le.amount, le.balance_after "
              "FROM txn t JOIN ledger_entry le ON le.txn_id=t.txn_id "
              "WHERE t.txn_ref IN ('DEMO-D7-DISPUTED','REV-DEMO-D7-DISPUTED') "
              "ORDER BY t.txn_id, le.direction;", 0.7),
        ("#", "the audit trail written by trg_account_audit", 0),
        ("A", "SELECT audit_id, record_pk AS account_id, action, "
              "(old_row->>'balance')::numeric AS balance_before, "
              "(new_row->>'balance')::numeric AS balance_after, changed_by "
              "FROM audit_log WHERE record_pk IN (900001,900002) ORDER BY audit_id DESC LIMIT 6;", 0.8),
        ("#", "a second reversal of the same transaction must be refused", 0),
        ("A", "SELECT fn_reverse_txn('DEMO-D7-DISPUTED', 'duplicate attempt') AS should_fail;", 0.8),
    ],
)


def run_demo(key):
    demo = DEMOS[key]
    log = Log()
    sessions = {tag: Session(tag, log) for tag in demo["sessions"]}
    log.drain(list(sessions.values()), 1.0)       # swallow psql banners
    log.lines.clear()
    log.t0 = time.time()
    try:
        for tag, payload, pause in demo["steps"]:
            if tag == "#":
                log.note("--", "### " + payload)
            else:
                sessions[tag].send(payload)
            if pause:
                log.drain(list(sessions.values()), pause)
        log.drain(list(sessions.values()), 1.2)   # final settle
    finally:
        for s in sessions.values():
            s.close()
    text = log.render(demo["title"], demo["narrative"], demo["expected"])
    EVIDENCE.mkdir(exist_ok=True)
    path = EVIDENCE / f"Olaide_Daniel_301911975_{key}_{demo['name']}.txt"
    path.write_text(text)
    print(f"{key}: {len(log.lines)} transcript lines -> {path.name}")
    return text


if __name__ == "__main__":
    wanted = sys.argv[1:] or sorted(DEMOS)
    for k in wanted:
        if k not in DEMOS:
            sys.exit(f"unknown demo {k}; available: {', '.join(sorted(DEMOS))}")
        run_demo(k)

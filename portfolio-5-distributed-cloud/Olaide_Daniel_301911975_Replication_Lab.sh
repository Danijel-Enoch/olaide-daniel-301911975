#!/bin/zsh
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 5
# Student : Olaide Daniel (301911975)
# File    : Replication, consistency and failover laboratory
# Usage   : ./Olaide_Daniel_301911975_Replication_Lab.sh
# Needs   : the cluster from cluster/Olaide_Daniel_301911975_docker-compose.yml
# =====================================================================
# Experiments R1-R6. R6 FAILS THE PRIMARY OVER DEPERMANENTLY: re-run the
# compose file with `down -v` then `up -d` before running the lab again.
# =====================================================================
set -e
PRIMARY=mit8103-primary
R1=mit8103-replica1
R2=mit8103-replica2
EV=evidence/Olaide_Daniel_301911975_Replication_Evidence.txt

pq()  { docker exec $1 psql -U postgres -d hdmb -P pager=off -q "${@:2}" 2>&1 | tr -d '\r' }
pqt() { docker exec $1 psql -U postgres -d hdmb -t -A -q "${@:2}" 2>&1 | tr -d '\r' }

exec > >(tee $EV) 2>&1
print "MIT 8103 Portfolio 5 - replication, consistency and failover evidence"
print "Student : Olaide Daniel (301911975)"
print "Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"
print "Cluster : 1 primary + 2 streaming replicas + 2 shards (docker compose)"

print "\n======================================================================"
print "R1  TOPOLOGY - who is streaming what, and how far behind"
print "======================================================================"
pq $PRIMARY -c "SELECT application_name, client_addr, state, sync_state,
       sent_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replay_behind,
       coalesce(replay_lag::text, '0') AS replay_lag
  FROM pg_stat_replication ORDER BY application_name;"
print "# replication slots retaining WAL on the primary:"
pq $PRIMARY -c "SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
  FROM pg_replication_slots ORDER BY slot_name;"
print "# each node's role:"
for n in $PRIMARY $R1 $R2; do
    print "  $(printf '%-18s' $n) in_recovery=$(pqt $n -c 'SELECT pg_is_in_recovery()')  ledger_rows=$(pqt $n -c 'SELECT count(*) FROM hdmb.ledger_entry')"
done

print "\n======================================================================"
print "R2  THE REPLICAS ARE READ-ONLY - enforced by the server, not by policy"
print "======================================================================"
print "# attempting a write on replica-1:"
pq $R1 -c "INSERT INTO hdmb.branch (branch_code, branch_name, state, city, opened_on)
           VALUES ('HD99','Rogue Branch','Lagos','Ikeja', CURRENT_DATE);"
print "# a read on the same node, at the same moment:"
pq $R1 -c "SELECT count(*) AS branches_visible_on_replica FROM hdmb.branch;"

print "\n======================================================================"
print "R3  REPLICATION LAG UNDER A WRITE BURST (both standbys asynchronous)"
print "======================================================================"
pq $PRIMARY -c "ALTER SYSTEM SET synchronous_standby_names = ''; SELECT pg_reload_conf();" > /dev/null
pq $PRIMARY -c "DROP TABLE IF EXISTS repl_probe;
                CREATE TABLE repl_probe (id bigserial primary key, payload text, written_at timestamptz default clock_timestamp());" > /dev/null
print "# 20,000 rows inserted on the primary, then lag sampled immediately:"
pq $PRIMARY -c "INSERT INTO repl_probe (payload) SELECT repeat('x', 200) FROM generate_series(1, 20000);"
pq $PRIMARY -c "SELECT application_name, sync_state,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS behind_bytes,
       coalesce(write_lag::text,'-')  AS write_lag,
       coalesce(flush_lag::text,'-')  AS flush_lag,
       coalesce(replay_lag::text,'-') AS replay_lag
  FROM pg_stat_replication ORDER BY application_name;"
print "# rows visible on each node a moment later:"
for n in $PRIMARY $R1 $R2; do
    print "  $(printf '%-18s' $n) repl_probe_rows=$(pqt $n -c 'SELECT count(*) FROM repl_probe')"
done
print "# end-to-end visibility delay, measured from the row's own timestamp:"
pqt $R1 -c "SELECT 'replica-1 saw the last row ' ||
       round(extract(epoch FROM (clock_timestamp() - max(written_at))) * 1000) || ' ms after it was written'
  FROM repl_probe;"

print "\n======================================================================"
print "R4  THE COST OF SYNCHRONOUS COMMIT - measured, not asserted"
print "======================================================================"
cat > /tmp/probe.sql <<'BENCH'
INSERT INTO repl_probe (payload) VALUES ('latency probe');
BENCH
docker cp /tmp/probe.sql $PRIMARY:/tmp/probe.sql > /dev/null

print "# (a) ASYNCHRONOUS: commit returns as soon as the primary's WAL is on disk"
pq $PRIMARY -c "ALTER SYSTEM SET synchronous_standby_names = ''; SELECT pg_reload_conf();" > /dev/null
docker exec $PRIMARY pgbench -U postgres -d hdmb -n -c 1 -t 300 -f /tmp/probe.sql 2>&1 \
  | grep -E "latency average|tps" | tr -d '\r'

print "# (b) SYNCHRONOUS: commit waits for replica-1 to confirm the WAL too"
pq $PRIMARY -c "ALTER SYSTEM SET synchronous_standby_names = 'replica_1'; SELECT pg_reload_conf();" > /dev/null
sleep 2
pq $PRIMARY -c "SELECT application_name, sync_state FROM pg_stat_replication ORDER BY 1;"
docker exec $PRIMARY pgbench -U postgres -d hdmb -n -c 1 -t 300 -f /tmp/probe.sql 2>&1 \
  | grep -E "latency average|tps" | tr -d '\r'

print "\n======================================================================"
print "R5  CAP, MADE CONCRETE - a synchronous standby that stops answering"
print "======================================================================"
print "# synchronous_standby_names is still 'replica_1'. Stop that standby:"
docker stop $R1 > /dev/null
print "  replica-1 stopped"
print "# now attempt a write on the primary, with a 4-second statement timeout:"
docker exec $PRIMARY psql -U postgres -d hdmb -P pager=off -q \
  -c "SET statement_timeout = '4s';" \
  -c "INSERT INTO repl_probe (payload) VALUES ('write during sync standby outage');" 2>&1 | tr -d '\r'
print "# the primary is NOT down - reads still work perfectly:"
pqt $PRIMARY -c "SELECT 'reads still served: ' || count(*) || ' probe rows' FROM repl_probe;"
print "#"
print "# This is the CAP trade-off in one experiment. The cluster chose"
print "# CONSISTENCY: rather than acknowledge a write it could not replicate,"
print "# it refused to acknowledge the write at all. Choosing AVAILABILITY is"
print "# one command - and it silently accepts the risk of losing that write:"
pq $PRIMARY -c "ALTER SYSTEM SET synchronous_standby_names = ''; SELECT pg_reload_conf();" > /dev/null
sleep 1
pq $PRIMARY -c "INSERT INTO repl_probe (payload) VALUES ('write after reverting to async');"
docker start $R1 > /dev/null; sleep 8
print "# replica-1 restarted and caught up from its slot:"
pq $PRIMARY -c "SELECT application_name, state, sync_state,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS behind
  FROM pg_stat_replication ORDER BY application_name;"

print "\n======================================================================"
print "R6  FAILOVER - promoting a standby after the primary is lost"
print "======================================================================"
print "# position of each node immediately before the failure:"
pq $PRIMARY -c "SELECT application_name, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS behind_primary
  FROM pg_stat_replication ORDER BY application_name;"
PRIMARY_LSN=$(pqt $PRIMARY -c "SELECT pg_current_wal_lsn()")
ROWS_BEFORE=$(pqt $PRIMARY -c "SELECT count(*) FROM repl_probe")
print "  primary WAL position : $PRIMARY_LSN"
print "  probe rows on primary: $ROWS_BEFORE"

print "\n# >>> killing the primary <<<"
docker stop $PRIMARY > /dev/null
print "  primary stopped. Writes are now impossible anywhere: a standby cannot"
print "  promote itself, which is why production clusters run an external"
print "  failover manager (Patroni, repmgr, or a managed service's control plane)."
print "# replica-1 state while unpromoted:"
pq $R1 -c "SELECT pg_is_in_recovery() AS still_a_standby, pg_last_wal_replay_lsn() AS replayed_to;"
print "# attempting a write on the unpromoted standby:"
pq $R1 -c "INSERT INTO repl_probe (payload) VALUES ('write before promotion');"

print "\n# >>> promoting replica-1 <<<"
pqt $R1 -c "SELECT pg_promote(wait => true, wait_seconds => 30)"
sleep 2
print "# replica-1 after promotion:"
pq $R1 -c "SELECT pg_is_in_recovery() AS still_a_standby,
                  pg_current_wal_lsn()  AS now_generating_wal_at;"
print "# timeline history - a promotion increments the timeline, which is how"
print "# PostgreSQL prevents the old primary rejoining and causing split brain:"
docker exec $R1 sh -c 'ls /var/lib/postgresql/18/docker/pg_wal/*.history 2>/dev/null && cat /var/lib/postgresql/18/docker/pg_wal/*.history' 2>&1 | tr -d '\r'
print "# the new primary accepts writes:"
pq $R1 -c "INSERT INTO repl_probe (payload) VALUES ('first write on the promoted node') RETURNING id;"
print "# data loss check - rows on the old primary vs the new one:"
ROWS_AFTER=$(pqt $R1 -c "SELECT count(*) FROM repl_probe WHERE payload <> 'first write on the promoted node'")
print "  rows on old primary before the failure : $ROWS_BEFORE"
print "  rows surviving on the promoted node    : $ROWS_AFTER"
print "  rows lost                              : $(( ROWS_BEFORE - ROWS_AFTER ))"
print "# replica-2 is now orphaned: it still follows the OLD primary's timeline"
pq $R2 -c "SELECT pg_is_in_recovery() AS still_a_standby, pg_last_wal_replay_lsn() AS stuck_at;"
print "#"
print "# Re-pointing replica-2 at the new primary requires pg_rewind or a fresh"
print "# basebackup. That work - not the promotion itself - is what makes manual"
print "# failover slow, and what a managed cloud database automates."

print "\n======================================================================"
print "CLUSTER STATE AT END OF LAB"
print "======================================================================"
docker ps --filter "name=mit8103-" --format '  {{.Names}}  {{.Status}}'
print "\n# To reset: docker compose -f cluster/Olaide_Daniel_301911975_docker-compose.yml down -v && up -d"

#!/bin/zsh
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 5
# Student : Olaide Daniel (301911975)
# File    : Repeated-measures benchmark - the real cost of synchronous commit
# Usage   : ./Olaide_Daniel_301911975_Sync_Latency_Benchmark.sh
# =====================================================================
# WHY THIS SCRIPT EXISTS
# Experiment R4 in the replication lab measured async, then sync, then async
# again as a control. The control FAILED: the second async run came back
# slower (2.703 ms) than the synchronous run (2.114 ms), which means ambient
# load on the host moved more than the setting being tested. A single A-B-A
# therefore could not support any claim about the cost of synchronous commit,
# and reporting the raw A-vs-B difference would have been reporting noise.
#
# This benchmark alternates the two modes over several rounds and reports the
# mean and the spread of each, so the signal can be separated from the drift.
# =====================================================================
set -e
PRIMARY=mit8103-primary
ROUNDS=6
TXNS=500
EV=evidence/Olaide_Daniel_301911975_Sync_Latency_Benchmark.txt

exec > >(tee $EV) 2>&1
print -r -- "MIT 8103 Portfolio 5 - cost of synchronous commit (repeated measures)"
print -r -- "Student : Olaide Daniel (301911975)"
print -r -- "Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"
print -r -- "Design  : $ROUNDS alternating rounds of $TXNS single-row commits each,"
print -r -- "          mode switched and VERIFIED before every round."
print ""

set_sync() {
    docker exec $PRIMARY psql -U postgres -d hdmb -q \
        -c "ALTER SYSTEM SET synchronous_standby_names = '$1'" \
        -c "SELECT pg_reload_conf()" > /dev/null 2>&1
    sleep 2
    docker exec $PRIMARY psql -U postgres -d hdmb -t -A \
        -c "SELECT string_agg(application_name || '=' || sync_state, ' ') FROM pg_stat_replication" 2>/dev/null | tr -d '\r'
}

docker exec $PRIMARY psql -U postgres -d hdmb -q \
    -c "DROP TABLE IF EXISTS bench_probe" \
    -c "CREATE TABLE bench_probe (id bigserial primary key, payload text)" > /dev/null
print -r -- 'INSERT INTO bench_probe (payload) VALUES (:scale);' > /tmp/bench.sql
print -r -- "INSERT INTO bench_probe (payload) VALUES ('probe');" > /tmp/bench.sql
docker cp /tmp/bench.sql $PRIMARY:/tmp/bench.sql > /dev/null

run_round() {                      # run_round <mode-label> <standby-names>
    state=$(set_sync "$2")
    out=$(docker exec $PRIMARY pgbench -U postgres -d hdmb -n -c 1 -t $TXNS -f /tmp/bench.sql 2>&1 | tr -d '\r')
    lat=$(print "$out" | grep 'latency average' | sed 's/.*= *\([0-9.]*\).*/\1/')
    tps=$(print "$out" | grep '^tps' | sed 's/.*= *\([0-9.]*\).*/\1/')
    printf '  round %-2s %-6s  state[%-28s]  latency %7s ms   tps %10s\n' "$3" "$1" "$state" "$lat" "$tps"
    print -r -- "$lat" >> /tmp/lat_$1.txt
}

rm -f /tmp/lat_async.txt /tmp/lat_sync.txt
print -r -- "--- alternating rounds ---"
for r in $(seq $ROUNDS); do
    if (( r % 2 == 1 )); then run_round async ""          $r
    else                      run_round sync  "replica_1" $r
    fi
done
set_sync "" > /dev/null

print ""
print -r -- "--- summary ---"
python3 - <<'PY'
import statistics as st
def load(p):
    return [float(x) for x in open(p).read().split()]
a = load('/tmp/lat_async.txt'); s = load('/tmp/lat_sync.txt')
def line(label, v):
    print(f"  {label:<12} n={len(v)}  mean={st.mean(v):.3f} ms  "
          f"median={st.median(v):.3f} ms  min={min(v):.3f}  max={max(v):.3f}")
line('ASYNCHRONOUS', a); line('SYNCHRONOUS', s)
d = st.mean(s) - st.mean(a)
print(f"\n  mean difference         : {d:+.3f} ms ({d/st.mean(a)*100:+.1f}%)")
print(f"  async spread (max-min)  : {max(a)-min(a):.3f} ms")
print(f"  sync  spread (max-min)  : {max(s)-min(s):.3f} ms")
overlap = max(a) >= min(s)
print()
if abs(d) < (max(a)-min(a)) or overlap:
    print("  VERDICT: the difference between the two modes is NOT separable from")
    print("  run-to-run variation on this host - the ranges overlap. The honest")
    print("  conclusion is that at this scale (two containers on one machine,")
    print("  loopback networking, sub-millisecond round trip) the cost of")
    print("  synchronous commit is below the measurement noise of the")
    print("  environment. It is NOT a finding that synchronous replication is")
    print("  free: the cost is proportional to the network round trip, and")
    print("  across two real availability zones (1-2 ms RTT) it would dominate")
    print("  these numbers. This environment simply cannot measure it.")
else:
    print("  VERDICT: the two modes are separable - the mean difference exceeds")
    print("  the run-to-run spread of the asynchronous baseline, so the cost is")
    print("  attributable to the setting rather than to ambient load.")
PY
print ""
print -r -- "--- what the primary reports now ---"
docker exec $PRIMARY psql -U postgres -d hdmb -c "SELECT application_name, sync_state FROM pg_stat_replication ORDER BY 1;" 2>&1 | tr -d '\r'

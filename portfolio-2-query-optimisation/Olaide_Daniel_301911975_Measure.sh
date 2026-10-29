#!/bin/zsh
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 2
# Student : Olaide Daniel (301911975)
# File    : Measurement harness
# Usage   : ./Olaide_Daniel_301911975_Measure.sh baseline|optimised
#
# For every query in queries/, runs EXPLAIN (ANALYZE, BUFFERS) three times
# and keeps the fastest execution - the first run pays for cold shared
# buffers, so comparing first runs would measure cache state, not the plan.
# Writes the full plans plus a CSV of the best execution time per query.
# =====================================================================
set -e
label=${1:?usage: Measure.sh baseline|optimised}
runs=3
out="evidence/Olaide_Daniel_301911975_${label}_Plans.txt"
csv="evidence/Olaide_Daniel_301911975_${label}_Timings.csv"
PG=mit8103-pg

{
  echo "MIT 8103 Portfolio 2 - query plans (${label})"
  echo "Student : Olaide Daniel (301911975)"
  echo "Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Engine  : $(docker exec $PG psql -U postgres -d hdmb -t -A -c 'SELECT version()')"
  echo "Method  : EXPLAIN (ANALYZE, BUFFERS), best of ${runs} runs"
  echo
} > "$out"
echo "query,best_execution_ms,planning_ms,scan_method" > "$csv"

for f in queries/*.sql; do
  name=$(basename "$f" .sql | sed 's/Olaide_Daniel_301911975_//')
  printf '%s ... ' "$name"
  { echo "=====================================================================";
    echo "$name";
    echo "=====================================================================";
    sed -n '1,/^$/p' "$f" | grep '^--' || true; } >> "$out"

  best=999999; plan_ms=""; scan=""
  for i in $(seq $runs); do
    printf 'EXPLAIN (ANALYZE, BUFFERS)\n' > /tmp/mit8103_q.sql
    cat "$f" >> /tmp/mit8103_q.sql
    docker cp /tmp/mit8103_q.sql $PG:/tmp/q.sql >/dev/null
    res=$(docker exec $PG psql -U postgres -d hdmb -q -A -t -f /tmp/q.sql 2>&1)
    ex=$(echo "$res" | grep 'Execution Time' | sed 's/[^0-9.]//g')
    pl=$(echo "$res" | grep 'Planning Time'  | sed 's/[^0-9.]//g')
    if [ -n "$ex" ] && awk "BEGIN{exit !($ex < $best)}"; then
      best=$ex; plan_ms=$pl; lastplan="$res"
    fi
  done
  scan=$(echo "$lastplan" | grep -oE '(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan|Parallel Seq Scan)' | sort -u | paste -sd'+' -)
  { echo; echo "--- fastest of ${runs} runs ---"; echo "$lastplan"; echo; } >> "$out"
  echo "$name,$best,$plan_ms,$scan" >> "$csv"
  printf '%s ms (%s)\n' "$best" "$scan"
done
echo "wrote $out and $csv"

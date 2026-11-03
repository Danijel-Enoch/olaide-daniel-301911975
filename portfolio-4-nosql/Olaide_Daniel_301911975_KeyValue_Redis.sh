#!/bin/zsh
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 4
# Student : Olaide Daniel (301911975)
# File    : Key-value model (Redis) for the HDMB mobile channel
# Usage   : ./Olaide_Daniel_301911975_KeyValue_Redis.sh
# =====================================================================
# A document store replaced the JOIN. A key-value store replaces something
# else: the small, hot, short-lived state that a disk-based ACID engine is
# the wrong tool for - session tokens, rate limits, idempotency markers and
# cached balances. Every one of these has a natural expiry, and expiry is
# exactly what a relational table has no concept of.
# =====================================================================
set -e
R="docker exec mit8103-redis redis-cli"
EV=evidence/Olaide_Daniel_301911975_KeyValue_Evidence.txt

exec > >(tee $EV) 2>&1
print "MIT 8103 Portfolio 4 - key-value (Redis) evidence"
print "Student : Olaide Daniel (301911975)"
print "Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"
print "Engine  : Redis $(${=R} INFO server | grep redis_version | tr -d '\r' | cut -d: -f2)"
eval "$R FLUSHALL" > /dev/null

print "\n======================================================================"
print "K1  SESSION TOKEN - state with a lifetime the store enforces itself"
print "======================================================================"
print "# a mobile login issues a token that must die on its own after 15 min"
eval "$R SET 'session:tok_8fc21a' '{\"customer_id\":41,\"device\":\"android\",\"tier\":3}' EX 900"
print "GET  -> $(eval "$R GET 'session:tok_8fc21a'")"
print "TTL  -> $(eval "$R TTL 'session:tok_8fc21a'") seconds remaining"
print "# the same thing in PostgreSQL needs a session table plus a cron job to"
print "# delete expired rows. Here expiry is a property of the key."

print "\n======================================================================"
print "K2  IDEMPOTENCY MARKER - SET NX replaces a UNIQUE constraint"
print "======================================================================"
print "# the payment switch retries on timeout. The second attempt must not"
print "# produce a second transfer."
print "first  attempt: $(eval "$R SET 'idem:HDMB-20261105-000000777' 'PROCESSING' NX EX 86400")"
print "retry  attempt: $(eval "$R SET 'idem:HDMB-20261105-000000777' 'PROCESSING' NX EX 86400")"
print "# nil means 'somebody already claimed this reference' - a single round"
print "# trip, no table, no lock, and it self-cleans after 24 hours."

print "\n======================================================================"
print "K3  DAILY DEBIT LIMIT - the write-skew problem from Portfolio 3 D5,"
print "    solved by atomicity instead of by SERIALIZABLE"
print "======================================================================"
print "# D5 showed two REPEATABLE READ transactions each checking a 50,000.00"
print "# daily limit, both passing, and together breaching it. Here the check"
print "# and the increment are ONE atomic server-side script, so no two"
print "# clients can interleave between them."
cat > /tmp/limit.lua <<'LUA'
local used  = tonumber(redis.call('GET', KEYS[1]) or '0')
local want  = tonumber(ARGV[1])
local limit = tonumber(ARGV[2])
if used + want > limit then
  return {0, tostring(used), 'LIMIT_EXCEEDED'}
end
redis.call('INCRBYFLOAT', KEYS[1], want)
redis.call('EXPIRE', KEYS[1], tonumber(ARGV[3]))
return {1, redis.call('GET', KEYS[1]), 'ALLOWED'}
LUA
docker cp /tmp/limit.lua mit8103-redis:/tmp/limit.lua > /dev/null
print "# three 30,000.00 debit attempts against a 50,000.00 daily limit:"
for i in 1 2 3; do
  res=$(docker exec mit8103-redis redis-cli --eval /tmp/limit.lua "limit:debit:900001:2026-11-05" , 30000 50000 86400 | tr -d '\r' | paste -sd'|' -)
  print "  attempt $i -> $res"
done
print "total recorded: $(eval "$R GET 'limit:debit:900001:2026-11-05'")"
print "# exactly one 30,000.00 debit was admitted. The limit held without any"
print "# isolation level, retry loop or 40001 error to handle."

print "\n======================================================================"
print "K4  ATOMICITY UNDER REAL CONCURRENCY - contrast with the lost update"
print "======================================================================"
print "# Portfolio 3 D3 lost an update because the application did"
print "#   read -> compute -> write. INCR does it inside the server."
eval "$R SET 'counter:ussd:txn_count' 0" > /dev/null
print "# two clients, 1,000 increments each, fired in parallel:"
( docker exec mit8103-redis redis-cli -r 1000 INCR counter:ussd:txn_count > /dev/null ) &
( docker exec mit8103-redis redis-cli -r 1000 INCR counter:ussd:txn_count > /dev/null ) &
wait
print "expected 2000, actual -> $(eval "$R GET 'counter:ussd:txn_count'")"

print "\n======================================================================"
print "K5  CACHED BALANCE - speed bought with staleness, deliberately bounded"
print "======================================================================"
print "# the balance enquiry screen can tolerate 30 seconds of staleness;"
print "# the transfer path never reads this key, it reads PostgreSQL."
eval "$R SET 'balance:0000000041' '1396750.00' EX 30"
print "cached balance -> NGN $(eval "$R GET 'balance:0000000041'")  (TTL $(eval "$R TTL 'balance:0000000041'") s)"
print "# the TTL IS the consistency policy, written in one place and enforced"
print "# by the store rather than by remembering to invalidate."

print "\n======================================================================"
print "K6  RECENT ACTIVITY - a bounded list, the Redis form of the embedded"
print "    recent_activity array in the document model"
print "======================================================================"
for e in 'TRANSFER|750.00|ATM' 'DEPOSIT|25000.00|BRANCH' 'FEE|52.50|USSD' 'TRANSFER|1750.00|MOBILE' 'WITHDRAWAL|5000.00|POS'; do
  eval "$R LPUSH 'activity:0000000041' '$e'" > /dev/null
done
eval "$R LTRIM 'activity:0000000041' 0 3" > /dev/null    # keep only the 4 newest
print "list length after LTRIM -> $(eval "$R LLEN 'activity:0000000041'")"
eval "$R LRANGE 'activity:0000000041' 0 -1"
print "# LPUSH + LTRIM keeps the window bounded with no delete job and no"
print "# unbounded array growth - the same design goal as maxItems: 10 in the"
print "# MongoDB validator."

print "\n======================================================================"
print "K7  CHANNEL LEAGUE TABLE - sorted set"
print "======================================================================"
eval "$R ZADD 'channel:value:2026-11' 3234850 MOBILE 3435600 ATM 2634750 WEB 2480350 USSD 180515155 BRANCH 3272800 POS" > /dev/null
print "# top 3 channels by value moved this month (ZREVRANGE, O(log n)):"
eval "$R ZREVRANGE 'channel:value:2026-11' 0 2 WITHSCORES"
print "# rank of USSD -> $(eval "$R ZREVRANK 'channel:value:2026-11' USSD")"

print "\n======================================================================"
print "K8  WHAT IS IN THE STORE, AND WHAT IT COSTS"
print "======================================================================"
eval "$R DBSIZE"
eval "$R INFO memory" | grep -E "used_memory_human|maxmemory_policy" | tr -d '\r'
print "# keys and their types:"
for k in $(eval "$R KEYS '*'" | tr -d '\r' | sort); do
  print "  $(printf '%-38s' $k) type=$(eval "$R TYPE $k")  ttl=$(eval "$R TTL $k")"
done
print "\n# Every key above is either reconstructible from PostgreSQL or"
print "# genuinely disposable. Nothing here is the system of record: Redis"
print "# holds no data whose loss would cost a customer money."

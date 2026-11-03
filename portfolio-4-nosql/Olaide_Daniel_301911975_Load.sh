#!/bin/zsh
# =====================================================================
# MIT 8103 Advanced Database Systems - Portfolio 4
# Student : Olaide Daniel (301911975)
# File    : ETL step 2 - load the exported documents into MongoDB
# Usage   : ./Olaide_Daniel_301911975_Load.sh
# =====================================================================
# PostgreSQL -> Extended JSON (JSONL) -> mongoimport. The two engines run in
# separate containers, so the files travel via the host. The schema
# validators created by Document_Model.js are active during the import: a
# document that breaks the contract is rejected on the way in, which is the
# point of running the import AFTER the model rather than before it.
# =====================================================================
set -e
PG=mit8103-pg
MONGO=mit8103-mongo
EV=evidence/Olaide_Daniel_301911975_Load_Log.txt

print "MIT 8103 Portfolio 4 - ETL load log"            >  $EV
print "Student : Olaide Daniel (301911975)"            >> $EV
print "Captured: $(date '+%Y-%m-%d %H:%M:%S %Z')"      >> $EV
print ""                                               >> $EV

print "--- 1. export from PostgreSQL ---"              | tee -a $EV
docker cp Olaide_Daniel_301911975_Export_Documents.sql $PG:/tmp/export.sql >/dev/null
docker exec $PG psql -U postgres -d hdmb -q -v ON_ERROR_STOP=1 -f /tmp/export.sql 2>&1 | tee -a $EV
docker exec $PG sh -c 'wc -l /tmp/hdmb_customer_profile.jsonl /tmp/hdmb_txn_event.jsonl' | tee -a $EV

print "--- 2. move the files to the MongoDB container ---" | tee -a $EV
for f in hdmb_customer_profile hdmb_txn_event; do
    docker cp $PG:/tmp/$f.jsonl /tmp/$f.jsonl   >/dev/null
    docker cp /tmp/$f.jsonl $MONGO:/tmp/$f.jsonl >/dev/null
    print "  staged $f.jsonl" | tee -a $EV
done

print "--- 3. mongoimport (validators active) ---" | tee -a $EV
docker exec $MONGO mongoimport --quiet --db hdmb --collection customer_profile \
    --type json --file /tmp/hdmb_customer_profile.jsonl --numInsertionWorkers 4 2>&1 | tee -a $EV
docker exec $MONGO mongoimport --quiet --db hdmb --collection txn_event \
    --type json --file /tmp/hdmb_txn_event.jsonl --numInsertionWorkers 4 2>&1 | tee -a $EV

print "--- 4. what landed ---" | tee -a $EV
docker exec $MONGO mongosh hdmb --quiet --eval '
  const s = db.stats();
  print("customer_profile docs : " + db.customer_profile.countDocuments());
  print("txn_event docs        : " + db.txn_event.countDocuments());
  print("database size (MB)    : " + (s.dataSize / 1048576).toFixed(2));
  print("index size (MB)       : " + (s.indexSize / 1048576).toFixed(2));
  print("");
  print("--- a stored document, as the mobile app receives it ---");
  printjson(db.customer_profile.findOne({customer_id: 13}));
' 2>&1 | tee -a $EV
print "" ; print "wrote $EV"

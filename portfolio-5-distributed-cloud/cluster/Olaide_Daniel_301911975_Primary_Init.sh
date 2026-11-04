#!/bin/sh
# =====================================================================
# MIT 8103 - Portfolio 5 | Olaide Daniel (301911975)
# Runs once, on the primary, during first initialisation.
# Creates the replication role, the physical slots, and the pg_hba rule
# that lets the standbys connect.
# =====================================================================
set -e

psql -v ON_ERROR_STOP=1 -U postgres -d hdmb <<'SQL'
-- a dedicated role with REPLICATION but no data privileges: a standby needs
-- to stream WAL, not to read tables
CREATE ROLE repl WITH REPLICATION LOGIN PASSWORD 'replpass';

-- Physical slots make the primary RETAIN WAL for each standby. Without them a
-- standby that falls behind can be orphaned when the WAL it still needs is
-- recycled; with them the primary keeps that WAL - which is also a risk, since
-- a permanently dead standby will fill the primary's disk. Named slots are the
-- right trade for a two-standby cluster that is monitored.
SELECT pg_create_physical_replication_slot('replica_1');
SELECT pg_create_physical_replication_slot('replica_2');
SQL

# replication connections need their own pg_hba entry; the image's default
# rules cover ordinary database connections only
cat >> "$PGDATA/pg_hba.conf" <<'HBA'

# MIT 8103 Portfolio 5: allow the standbys to stream WAL
host    replication     repl            all                     scram-sha-256
HBA

echo "[primary-init] replication role, slots and pg_hba rule created"

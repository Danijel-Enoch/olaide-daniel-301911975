#!/bin/sh
# =====================================================================
# MIT 8103 - Portfolio 5 | Olaide Daniel (301911975)
# Standby bootstrap: clone the primary with pg_basebackup, then start in
# hot standby mode.
# =====================================================================
set -e
PGDATA=${PGDATA:-/var/lib/postgresql/18/docker}

echo "[$APPLICATION_NAME] waiting for $PRIMARY_HOST ..."
until pg_isready -h "$PRIMARY_HOST" -U postgres -q; do sleep 1; done

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "[$APPLICATION_NAME] cloning primary with pg_basebackup (slot $REPLICATION_SLOT)"
    rm -rf "$PGDATA"
    mkdir -p "$PGDATA"
    # -R writes standby.signal + primary_conninfo, which is what makes this a
    #    standby rather than an independent copy
    # -Xs streams WAL during the backup, so the clone is consistent without
    #    needing the primary to retain WAL for the whole copy
    pg_basebackup \
        -h "$PRIMARY_HOST" -U repl -D "$PGDATA" \
        -Fp -Xs -R -S "$REPLICATION_SLOT" -P \
        -d "application_name=$APPLICATION_NAME"
    chmod 0700 "$PGDATA"
    echo "[$APPLICATION_NAME] clone complete"
else
    echo "[$APPLICATION_NAME] existing data directory found, skipping basebackup"
fi

exec postgres -c hot_standby=on -c hot_standby_feedback=on

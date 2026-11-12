#!/bin/bash
# Runs once, when the primary's data directory is first initialised.
# 1. Create the role the replica will connect as.
# 2. Allow replication connections from other containers.
set -e

psql -v ON_ERROR_STOP=1 -U postgres -d cartify <<'SQL'
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
SQL

echo "host replication replicator 0.0.0.0/0 scram-sha-256" >> "$PGDATA/pg_hba.conf"
echo "Primary: replicator role created and pg_hba.conf updated"

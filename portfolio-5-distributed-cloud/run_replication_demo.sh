#!/bin/bash
# =====================================================================
# Cartify: replication demonstration
# Portfolio 5 - Distributed and Cloud Database Exercise
#
# Proves, with output:
#   1. the replica is streaming from the primary
#   2. a write on the primary appears on the replica within milliseconds
#   3. the replica refuses writes (read-only)
#   4. replication lag can be measured
#   5. the replica can be promoted to primary (failover)
#
# Usage (from repo root):
#   bash portfolio-5-distributed-cloud/run_replication_demo.sh
# Requires the containers from docker/docker-compose.yml to be up.
# =====================================================================
set -u
cd "$(dirname "$0")"
OUT=results; mkdir -p "$OUT"
export PGPASSWORD=cartify_pass
P="psql -h localhost -p 5433 -U postgres -d cartify -X"   # primary
R="psql -h localhost -p 5434 -U postgres -d cartify -X"   # replica

{
echo "################ 1. Load the Cartify schema and data into the primary ################"
# Copy the local cartify database (schema + 50k orders) into the primary container.
PGPASSWORD= pg_dump -d cartify --no-owner --no-privileges \
  | $P -q -v ON_ERROR_STOP=0 > /dev/null 2>&1
$P -c "SELECT 'orders' AS tbl, COUNT(*) FROM orders UNION ALL SELECT 'products', COUNT(*) FROM products;"

echo
echo "################ 2. Replication status, seen from the primary ################"
$P -c "SELECT client_addr, state, sync_state, sent_lsn, replay_lsn FROM pg_stat_replication;"

echo
echo "################ 3. Is each node in recovery (i.e. a standby)? ################"
echo "primary:"; $P -Atc "SELECT pg_is_in_recovery();"
echo "replica:"; $R -Atc "SELECT pg_is_in_recovery();"

echo
echo "################ 4. The replica already has the data that was loaded on the primary ################"
$R -c "SELECT 'orders' AS tbl, COUNT(*) FROM orders UNION ALL SELECT 'products', COUNT(*) FROM products;"

echo
echo "################ 5. Write on the primary, read on the replica ################"
$P -c "INSERT INTO products (category_id, name, price, stock_quantity)
       VALUES (6, 'REPLICATION TEST Samsung Galaxy S26', 899000.00, 25) RETURNING id, name;"
sleep 1
echo "replica sees:"
$R -c "SELECT id, name, price, stock_quantity FROM products WHERE name LIKE 'REPLICATION TEST%';"

echo
echo "################ 6. Replication lag (bytes and seconds) ################"
$P -c "SELECT client_addr, state,
              pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
              replay_lag
       FROM pg_stat_replication;"

echo
echo "################ 7. The replica refuses writes ################"
$R -c "UPDATE products SET stock_quantity = 0 WHERE name LIKE 'REPLICATION TEST%';" 2>&1 || true

echo
echo "################ 8. A burst of writes: 1,000 orders on the primary ################"
$P -c "INSERT INTO orders (customer_id, address_id, status, total_amount)
       SELECT 1, 1, 'paid', 1000 FROM generate_series(1, 1000);"
sleep 1
echo "primary count:"; $P -Atc "SELECT COUNT(*) FROM orders;"
echo "replica count:"; $R -Atc "SELECT COUNT(*) FROM orders;"

echo
echo "################ 9. Failover: promote the replica to a standalone primary ################"
docker exec cartify-replica pg_ctl promote -D /var/lib/postgresql/data
sleep 3
echo "replica in recovery now?"; $R -Atc "SELECT pg_is_in_recovery();"
echo "replica accepts writes now:"
$R -c "UPDATE products SET stock_quantity = 0 WHERE name LIKE 'REPLICATION TEST%' RETURNING id, name, stock_quantity;"
echo "old primary no longer has a standby attached:"
$P -c "SELECT COUNT(*) AS standbys FROM pg_stat_replication;"
} 2>&1 | tee "$OUT/replication_demo.txt"

echo
echo "Done. Output saved to $OUT/replication_demo.txt"
echo "To reset the cluster: docker compose -f docker/docker-compose.yml down -v && docker compose -f docker/docker-compose.yml up -d"

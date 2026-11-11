#!/bin/bash
# =====================================================================
# Cartify: runs each two-session concurrency demo and saves the output.
# Each demo starts Session A and Session B as separate psql processes
# at the same moment; pg_sleep() calls inside the scripts control the
# interleaving so the result is reproducible.
#
# Usage:  bash portfolio-3-transactions-concurrency/run_concurrency_demos.sh
# =====================================================================
set -u
cd "$(dirname "$0")"
SQL=sql
OUT=results
mkdir -p "$OUT"
PSQL="psql -d cartify -X -q"

run_pair () {   # name, session_a_file, session_b_file, extra psql vars...
  local name=$1 a=$2 b=$3; shift 3
  local out="$OUT/$name.txt"
  echo "--- running $name ---"
  { $PSQL "$@" -f "$SQL/$a" 2>&1 | sed 's/^/A: /' &
    $PSQL "$@" -f "$SQL/$b" 2>&1 | sed 's/^/B: /' ;
    wait; } > "$out"
  cat "$out"
  echo
}

echo "================ ISOLATION LEVELS ================"
$PSQL -c "UPDATE products SET price = 250000.00 WHERE id = 1;"
run_pair "isolation_read_committed"  session_a_isolation.sql session_b_isolation.sql -v level="READ COMMITTED"
$PSQL -c "UPDATE products SET price = 250000.00 WHERE id = 1;"
run_pair "isolation_repeatable_read" session_a_isolation.sql session_b_isolation.sql -v level="REPEATABLE READ"

echo "================ OVERSOLD STOCK ================"
$PSQL -c "UPDATE products SET stock_quantity = 1 WHERE id = 3;"
run_pair "oversell_unsafe" session_a_oversell.sql session_b_oversell.sql
$PSQL -c "SELECT id, name, stock_quantity AS stock_after_unsafe FROM products WHERE id = 3;" | tee -a "$OUT/oversell_unsafe.txt"
$PSQL -c "SELECT COUNT(*) AS orders_sold_unsafe FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000;" | tee -a "$OUT/oversell_unsafe.txt"

$PSQL -c "DELETE FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000; UPDATE products SET stock_quantity = 1 WHERE id = 3;"
run_pair "oversell_safe_for_update" session_a_oversell.sql session_b_oversell.sql -v safe=1
$PSQL -c "SELECT id, name, stock_quantity AS stock_after_safe FROM products WHERE id = 3;" | tee -a "$OUT/oversell_safe_for_update.txt"
$PSQL -c "SELECT COUNT(*) AS orders_sold_safe FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000;" | tee -a "$OUT/oversell_safe_for_update.txt"
$PSQL -c "DELETE FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000;"

$PSQL -c "UPDATE products SET stock_quantity = 1 WHERE id = 3;"
run_pair "oversell_safe_serializable" session_a_oversell_serializable.sql session_b_oversell_serializable.sql
$PSQL -c "SELECT id, name, stock_quantity AS stock_after_serializable FROM products WHERE id = 3;" | tee -a "$OUT/oversell_safe_serializable.txt"
$PSQL -c "SELECT COUNT(*) AS orders_sold_serializable FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000;" | tee -a "$OUT/oversell_safe_serializable.txt"
$PSQL -c "DELETE FROM orders WHERE customer_id IN (10,11) AND total_amount = 50000;"

echo "================ LOST UPDATE ON PRICE ================"
$PSQL -c "UPDATE products SET price = 100000.00 WHERE id = 4;"
run_pair "lost_update_unsafe" session_a_lost_update.sql session_b_lost_update.sql
$PSQL -c "SELECT id, price AS price_after_unsafe, 'expected 95000.00 (100000 * 0.9 + 5000)' AS note FROM products WHERE id = 4;" | tee -a "$OUT/lost_update_unsafe.txt"

$PSQL -c "UPDATE products SET price = 100000.00 WHERE id = 4;"
run_pair "lost_update_safe_for_update" session_a_lost_update.sql session_b_lost_update.sql -v safe=1
$PSQL -c "SELECT id, price AS price_after_safe, 'expected 95000.00' AS note FROM products WHERE id = 4;" | tee -a "$OUT/lost_update_safe_for_update.txt"

echo "All demos complete. Results in $OUT/"

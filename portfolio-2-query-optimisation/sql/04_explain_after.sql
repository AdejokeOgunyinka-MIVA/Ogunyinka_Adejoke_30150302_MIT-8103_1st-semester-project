-- =====================================================================
-- Cartify: execution plans AFTER indexing
-- Run with:
--   psql -d cartify -f portfolio-2-query-optimisation/sql/04_explain_after.sql \
--        > portfolio-2-query-optimisation/results/explain_after.txt
--
-- State of the database: the seven indexes from 03_create_indexes.sql
-- =====================================================================

\echo '=== Existing indexes (PK/UNIQUE + custom) ==='
SELECT tablename, indexname FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename, indexname;

\echo
\echo '=== Q1. Customer order history ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, o.order_date, o.status, o.total_amount
FROM orders o
WHERE o.customer_id = 4123
ORDER BY o.order_date DESC;

\echo
\echo '=== Q2. Catalogue search by name ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, price, stock_quantity
FROM products
WHERE name ILIKE 'Samsung%'
ORDER BY price;

\echo
\echo '=== Q3. Products in category with stock ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, p.price, c.name AS category
FROM products p
JOIN categories c ON c.id = p.category_id
WHERE c.name = 'Phones' AND p.stock_quantity > 0
ORDER BY p.price;

\echo
\echo '=== Q4. Shipped orders in last 30 days ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'shipped'
  AND order_date >= NOW() - INTERVAL '30 days';

\echo
\echo '=== Q5. Top 10 selling products ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.name, SUM(oi.quantity) AS units_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON p.id = oi.product_id
JOIN orders o   ON o.id = oi.order_id
WHERE o.status = 'delivered'
GROUP BY p.id, p.name
ORDER BY units_sold DESC
LIMIT 10;

\echo
\echo '=== Q6. Revenue by state ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT a.state, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
FROM orders o
JOIN addresses a ON a.id = o.address_id
WHERE o.status IN ('paid','shipped','delivered')
GROUP BY a.state
ORDER BY revenue DESC;

\echo
\echo '=== Q2 rewritten to use the expression index ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, price, stock_quantity
FROM products
WHERE lower(name) LIKE 'samsung%'
ORDER BY price;

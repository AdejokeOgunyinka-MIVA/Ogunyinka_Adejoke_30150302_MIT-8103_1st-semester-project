-- =====================================================================
-- Cartify: materialised view for the top-products report (Q5)
-- Portfolio 2 - Query Processing and Optimisation
--
-- Q5 aggregates ~75,000 delivered order lines every time it runs.
-- No index helps, because the query genuinely needs most of the table.
-- The right tool is to precompute the aggregate and refresh it on a
-- schedule (e.g. nightly), trading freshness for speed.
--
-- Run with:  psql -d cartify -f portfolio-2-query-optimisation/sql/05_materialized_view.sql
-- =====================================================================

\timing on

DROP MATERIALIZED VIEW IF EXISTS mv_product_sales;

CREATE MATERIALIZED VIEW mv_product_sales AS
SELECT p.id AS product_id, p.name,
       SUM(oi.quantity)                  AS units_sold,
       SUM(oi.quantity * oi.unit_price)  AS revenue
FROM order_items oi
JOIN products p ON p.id = oi.product_id
JOIN orders o   ON o.id = oi.order_id
WHERE o.status = 'delivered'
GROUP BY p.id, p.name;

-- An index on the view lets "top 10" read just 10 rows.
CREATE INDEX idx_mv_product_sales_units ON mv_product_sales (units_sold DESC);

\echo
\echo '=== Q5 via materialised view ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT product_id, name, units_sold, revenue
FROM mv_product_sales
ORDER BY units_sold DESC
LIMIT 10;

\echo
\echo '=== Same 10 rows as the live query ==='
SELECT product_id, name, units_sold, revenue
FROM mv_product_sales
ORDER BY units_sold DESC
LIMIT 10;

-- To bring it up to date after new orders are delivered:
-- REFRESH MATERIALIZED VIEW mv_product_sales;

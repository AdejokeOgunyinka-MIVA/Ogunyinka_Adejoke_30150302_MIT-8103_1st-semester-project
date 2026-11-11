-- =====================================================================
-- Cartify: indexing strategy
-- Portfolio 2 - Query Processing and Optimisation
--
-- Each index is justified by a specific query from 01_queries.sql.
-- Run with:  psql -d cartify -f portfolio-2-query-optimisation/sql/03_create_indexes.sql
-- =====================================================================

\timing on

-- Q1. Customer order history: filter by customer_id, sort by order_date DESC.
-- Composite index serves both the WHERE and the ORDER BY in one pass.
CREATE INDEX idx_orders_customer_date
    ON orders (customer_id, order_date DESC);

-- Q4. Orders by status within a date range.
-- status first (equality), order_date second (range): the standard
-- "equality column before range column" rule for composite B-trees.
CREATE INDEX idx_orders_status_date
    ON orders (status, order_date);

-- Q3. Products by category. Foreign key columns are NOT indexed
-- automatically by PostgreSQL; only PK and UNIQUE columns are.
CREATE INDEX idx_products_category
    ON products (category_id);

-- Q5. The two join columns on the largest table (~150k rows).
-- Without these, every join to order_items is a full scan.
CREATE INDEX idx_order_items_order
    ON order_items (order_id);
CREATE INDEX idx_order_items_product
    ON order_items (product_id);

-- Q6. Join column from orders to addresses.
CREATE INDEX idx_orders_address
    ON orders (address_id);

-- Q2. Case-insensitive prefix search. A plain B-tree cannot serve
-- ILIKE 'Samsung%'. An expression index on lower(name) with
-- text_pattern_ops supports a rewritten query:
--   WHERE lower(name) LIKE 'samsung%'
CREATE INDEX idx_products_name_lower
    ON products (lower(name) text_pattern_ops);

-- Refresh planner statistics so it knows about the new indexes.
ANALYZE;

\echo
\echo '=== Indexes now present ==='
SELECT tablename, indexname,
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

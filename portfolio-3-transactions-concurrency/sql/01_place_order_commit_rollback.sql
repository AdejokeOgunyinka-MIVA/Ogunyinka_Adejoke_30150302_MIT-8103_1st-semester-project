-- =====================================================================
-- Cartify: the "place order" transaction - COMMIT, ROLLBACK, SAVEPOINT
-- Portfolio 3 - Transactions and Concurrency
--
-- Run with: psql -d cartify -f portfolio-3-transactions-concurrency/sql/01_place_order_commit_rollback.sql
-- =====================================================================

-- Fixed test data so the demo is reproducible.
UPDATE products SET stock_quantity = 10, price = 250000.00 WHERE id = 1;
UPDATE products SET stock_quantity = 2,  price = 15000.00  WHERE id = 2;

\echo '=========================================================='
\echo 'PART A: a successful order, committed'
\echo '=========================================================='
\echo 'Stock before:'
SELECT id, name, stock_quantity FROM products WHERE id IN (1, 2) ORDER BY id;

BEGIN;

INSERT INTO orders (customer_id, address_id, status)
VALUES (1, 1, 'pending')
RETURNING id AS new_order_id \gset

-- Two items: 1 of product 1, 2 of product 2
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT :new_order_id, id, CASE id WHEN 1 THEN 1 ELSE 2 END, price
FROM products WHERE id IN (1, 2);

-- Reduce stock for each item in the order
UPDATE products p
SET stock_quantity = p.stock_quantity - oi.quantity
FROM order_items oi
WHERE oi.order_id = :new_order_id AND oi.product_id = p.id;

-- Set the order total from its items
UPDATE orders
SET total_amount = (SELECT SUM(quantity * unit_price) FROM order_items WHERE order_id = :new_order_id)
WHERE id = :new_order_id;

COMMIT;

\echo 'Order created:'
SELECT id, customer_id, status, total_amount FROM orders WHERE id = :new_order_id;
\echo 'Stock after COMMIT (10 -> 9, 2 -> 0):'
SELECT id, name, stock_quantity FROM products WHERE id IN (1, 2) ORDER BY id;


\echo
\echo '=========================================================='
\echo 'PART B: an order that fails midway, rolled back'
\echo 'Product 2 now has 0 stock. The CHECK constraint rejects the'
\echo 'stock update, and the whole transaction is undone.'
\echo '=========================================================='
\echo 'Orders count before:'
SELECT COUNT(*) AS orders_before FROM orders;

BEGIN;

INSERT INTO orders (customer_id, address_id, status)
VALUES (2, 2, 'pending')
RETURNING id AS failed_order_id \gset

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (:failed_order_id, 2, 1, 15000.00);

\echo 'Attempting to reduce stock of product 2 below zero...'
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE id = 2;
-- ERROR: violates check constraint "products_stock_quantity_check"
-- PostgreSQL has now marked the transaction as failed; nothing else
-- in it can commit. ROLLBACK discards the order and item inserted above.

ROLLBACK;

\echo 'Orders count after ROLLBACK (unchanged):'
SELECT COUNT(*) AS orders_after FROM orders;
\echo 'The failed order id does not exist:'
SELECT COUNT(*) AS rows_with_failed_id FROM orders WHERE id = :failed_order_id;


\echo
\echo '=========================================================='
\echo 'PART C: SAVEPOINT - partial rollback inside a transaction'
\echo 'Customer adds two items; the second is out of stock. Keep the'
\echo 'first, drop only the second, and still commit the order.'
\echo '=========================================================='

BEGIN;

INSERT INTO orders (customer_id, address_id, status)
VALUES (3, 3, 'pending')
RETURNING id AS sp_order_id \gset

-- Item 1: product 1, in stock
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (:sp_order_id, 1, 1, 250000.00);
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE id = 1;

SAVEPOINT before_item_2;

-- Item 2: product 2, out of stock -> this fails
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (:sp_order_id, 2, 1, 15000.00);
UPDATE products SET stock_quantity = stock_quantity - 1 WHERE id = 2;

-- Undo only item 2, keep item 1 and the order
ROLLBACK TO SAVEPOINT before_item_2;

UPDATE orders
SET total_amount = (SELECT SUM(quantity * unit_price) FROM order_items WHERE order_id = :sp_order_id)
WHERE id = :sp_order_id;

COMMIT;

\echo 'Order committed with only item 1:'
SELECT oi.order_id, oi.product_id, oi.quantity, o.total_amount
FROM order_items oi JOIN orders o ON o.id = oi.order_id
WHERE oi.order_id = :sp_order_id;
\echo 'Stock after (product 1: 9 -> 8, product 2 still 0):'
SELECT id, name, stock_quantity FROM products WHERE id IN (1, 2) ORDER BY id;

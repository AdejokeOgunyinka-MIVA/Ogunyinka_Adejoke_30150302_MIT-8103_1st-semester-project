-- =====================================================================
-- Cartify: constraint tests
-- Each statement below is EXPECTED TO FAIL. The error message is the
-- evidence that the constraint works.
-- Run with:  psql -d cartify -f portfolio-1-database-design/sql/02_constraint_tests.sql
-- =====================================================================

-- Minimal valid data to test against
INSERT INTO customers (full_name, email, phone)
VALUES ('Test Customer', 'test@cartify.ng', '08010000000');
INSERT INTO categories (name) VALUES ('Test Category');
INSERT INTO products (category_id, name, price, stock_quantity)
VALUES (1, 'Test Product', 1000.00, 5);

\echo '--- TEST 1: duplicate email (expect UNIQUE violation) ---'
INSERT INTO customers (full_name, email, phone)
VALUES ('Another Person', 'test@cartify.ng', '08020000000');

\echo '--- TEST 2: negative stock (expect CHECK violation) ---'
UPDATE products SET stock_quantity = -1 WHERE id = 1;

\echo '--- TEST 3: invalid order status (expect CHECK violation) ---'
INSERT INTO orders (customer_id, address_id, status)
VALUES (1, 1, 'lost');

\echo '--- TEST 4: order for a customer that does not exist (expect FK violation) ---'
INSERT INTO addresses (customer_id, street, city, state)
VALUES (999, '1 Nowhere St', 'Lagos', 'Lagos');

\echo '--- TEST 5: rating of 7 (expect CHECK violation) ---'
INSERT INTO reviews (customer_id, product_id, rating) VALUES (1, 1, 7);

\echo '--- TEST 6: negative price (expect CHECK violation) ---'
INSERT INTO products (category_id, name, price) VALUES (1, 'Bad Price', -50);

-- Clean up the test rows so seed data starts from empty tables
DELETE FROM products;
DELETE FROM categories;
DELETE FROM customers;
\echo '--- All six statements above should have shown an ERROR. That is the expected result. ---'

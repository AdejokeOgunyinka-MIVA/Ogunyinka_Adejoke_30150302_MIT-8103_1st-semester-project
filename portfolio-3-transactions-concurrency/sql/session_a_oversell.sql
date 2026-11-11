-- Session A: customer A buys the last unit of product 3.
-- Pattern: READ stock, DECIDE in the application, WRITE the new value.
-- This is how many real applications are written, and it is the bug.
-- Invoked with -v mode=unsafe or -v mode=safe
\echo '[A] BEGIN'
BEGIN;
\if :{?safe}
\echo '[A] reading stock WITH row lock (SELECT ... FOR UPDATE)'
SELECT stock_quantity AS stock FROM products WHERE id = 3 FOR UPDATE \gset
\else
\echo '[A] reading stock WITHOUT lock (plain SELECT)'
SELECT stock_quantity AS stock FROM products WHERE id = 3 \gset
\endif
\echo '[A] sees stock =' :stock
SELECT pg_sleep(2);
\if :stock
\echo '[A] stock > 0, so A sells one unit and writes stock =' :stock '- 1'
UPDATE products SET stock_quantity = :stock - 1 WHERE id = 3;
INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (10, 10, 'paid', 50000);
\echo '[A] COMMIT'
COMMIT;
\else
\echo '[A] stock is 0, A refuses the sale'
ROLLBACK;
\endif

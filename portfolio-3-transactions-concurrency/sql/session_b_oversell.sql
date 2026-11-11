-- Session B: customer B tries to buy the same last unit, one second later.
SELECT pg_sleep(1);
\echo '[B] BEGIN'
BEGIN;
\if :{?safe}
\echo '[B] reading stock WITH row lock - this will WAIT until A commits'
SELECT stock_quantity AS stock FROM products WHERE id = 3 FOR UPDATE \gset
\else
\echo '[B] reading stock WITHOUT lock'
SELECT stock_quantity AS stock FROM products WHERE id = 3 \gset
\endif
\echo '[B] sees stock =' :stock
\if :stock
\echo '[B] stock > 0, so B sells one unit and writes stock =' :stock '- 1'
UPDATE products SET stock_quantity = :stock - 1 WHERE id = 3;
INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (11, 11, 'paid', 50000);
\echo '[B] COMMIT'
COMMIT;
\else
\echo '[B] stock is 0, B refuses the sale'
ROLLBACK;
\endif

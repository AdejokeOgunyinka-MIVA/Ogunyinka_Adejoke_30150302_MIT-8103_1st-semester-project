-- Session B under SERIALIZABLE: reads and commits while A is still thinking.
SELECT pg_sleep(1);
\echo '[B] BEGIN ISOLATION LEVEL SERIALIZABLE'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_quantity AS stock FROM products WHERE id = 3 \gset
\echo '[B] sees stock =' :stock
UPDATE products SET stock_quantity = :stock - 1 WHERE id = 3;
INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (11, 11, 'paid', 50000);
\echo '[B] COMMIT'
COMMIT;

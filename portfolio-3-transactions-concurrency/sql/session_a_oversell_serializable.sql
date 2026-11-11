-- Session A under SERIALIZABLE: same unsafe read-decide-write pattern,
-- no explicit lock. PostgreSQL detects the conflict instead.
\echo '[A] BEGIN ISOLATION LEVEL SERIALIZABLE'
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT stock_quantity AS stock FROM products WHERE id = 3 \gset
\echo '[A] sees stock =' :stock
SELECT pg_sleep(2);
\echo '[A] writes stock =' :stock '- 1 (B has already committed its sale)'
UPDATE products SET stock_quantity = :stock - 1 WHERE id = 3;
INSERT INTO orders (customer_id, address_id, status, total_amount) VALUES (10, 10, 'paid', 50000);
\echo '[A] COMMIT'
COMMIT;

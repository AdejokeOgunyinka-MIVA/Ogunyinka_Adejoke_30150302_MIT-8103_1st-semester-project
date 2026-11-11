-- Session B: staff member B adds 5,000 naira delivery surcharge to product 4,
-- one second after A started. Without a lock, B overwrites A's discount.
SELECT pg_sleep(1);
\echo '[B] BEGIN'
BEGIN;
\if :{?safe}
SELECT price FROM products WHERE id = 4 FOR UPDATE \gset
\else
SELECT price FROM products WHERE id = 4 \gset
\endif
\echo '[B] read price =' :price ', adding 5000 surcharge'
UPDATE products SET price = :price + 5000 WHERE id = 4;
\echo '[B] COMMIT'
COMMIT;

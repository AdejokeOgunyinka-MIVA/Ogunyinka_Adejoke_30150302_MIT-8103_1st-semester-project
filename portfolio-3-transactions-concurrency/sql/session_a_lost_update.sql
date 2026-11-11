-- Session A: staff member A applies a 10% discount to product 4.
-- Reads price, computes in the application, writes the result.
\echo '[A] BEGIN'
BEGIN;
\if :{?safe}
SELECT price FROM products WHERE id = 4 FOR UPDATE \gset
\else
SELECT price FROM products WHERE id = 4 \gset
\endif
\echo '[A] read price =' :price ', applying 10% discount'
SELECT pg_sleep(2);
UPDATE products SET price = round(:price * 0.90, 2) WHERE id = 4;
\echo '[A] COMMIT'
COMMIT;

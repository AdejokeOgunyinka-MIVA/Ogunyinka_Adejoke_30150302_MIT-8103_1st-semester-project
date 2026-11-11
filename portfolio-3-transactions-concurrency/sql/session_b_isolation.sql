-- Session B: a staff member changes the price while Session A is mid-report.
SELECT pg_sleep(1);
\echo '[B] updating price of product 1 to 199999.00 and committing'
BEGIN;
UPDATE products SET price = 199999.00 WHERE id = 1;
COMMIT;
\echo '[B] done'

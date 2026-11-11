-- Session A: a report that reads the same price twice inside one transaction.
-- Invoked with -v level='READ COMMITTED' or -v level='REPEATABLE READ'.
\echo '[A] starting transaction at isolation level' :level
BEGIN ISOLATION LEVEL :level;
\echo '[A] first read:'
SELECT id, name, price FROM products WHERE id = 1;
SELECT pg_sleep(2);
\echo '[A] second read, after Session B committed a price change:'
SELECT id, name, price FROM products WHERE id = 1;
COMMIT;

-- =====================================================================
-- Cartify: sharding in miniature with declarative partitioning
-- Portfolio 5 - Distributed and Cloud Database Exercise
--
-- Sharding splits one logical table across several physical stores by
-- a shard key. PostgreSQL's declarative partitioning does the same split
-- inside one server, and is the first step towards real sharding
-- (each partition can later live on a different node via postgres_fdw
-- or Citus). The shard key here is the delivery region.
--
-- Run with:  psql -d cartify -f portfolio-5-distributed-cloud/sql/partitioning_demo.sql
-- =====================================================================

DROP TABLE IF EXISTS orders_by_region CASCADE;

CREATE TABLE orders_by_region (
    id            INT NOT NULL,
    customer_id   INT NOT NULL,
    region        VARCHAR(20) NOT NULL,     -- the shard key
    state         VARCHAR(50) NOT NULL,
    status        VARCHAR(20) NOT NULL,
    order_date    TIMESTAMP NOT NULL,
    total_amount  NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (id, region)                -- the shard key must be part of the key
) PARTITION BY LIST (region);

CREATE TABLE orders_south_west PARTITION OF orders_by_region FOR VALUES IN ('South West');
CREATE TABLE orders_north       PARTITION OF orders_by_region FOR VALUES IN ('North');
CREATE TABLE orders_south_east  PARTITION OF orders_by_region FOR VALUES IN ('South East');
CREATE TABLE orders_south_south PARTITION OF orders_by_region FOR VALUES IN ('South South');

-- Map each state to a region and route every order to its partition.
INSERT INTO orders_by_region
SELECT o.id, o.customer_id,
       CASE a.state
         WHEN 'Lagos' THEN 'South West' WHEN 'Oyo' THEN 'South West'
         WHEN 'Ogun' THEN 'South West'  WHEN 'Kwara' THEN 'South West'
         WHEN 'FCT' THEN 'North'        WHEN 'Kano' THEN 'North'
         WHEN 'Kaduna' THEN 'North'     WHEN 'Plateau' THEN 'North'
         WHEN 'Enugu' THEN 'South East' WHEN 'Imo' THEN 'South East'
         WHEN 'Anambra' THEN 'South East'
         ELSE 'South South' END,
       a.state, o.status, o.order_date, o.total_amount
FROM orders o JOIN addresses a ON a.id = o.address_id;

ANALYZE orders_by_region;

\echo '=== Rows per partition (shard) ==='
SELECT tableoid::regclass AS partition, COUNT(*) AS orders, SUM(total_amount) AS revenue
FROM orders_by_region GROUP BY tableoid ORDER BY partition;

\echo
\echo '=== Partition pruning: a query for one region touches only that partition ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*), SUM(total_amount)
FROM orders_by_region
WHERE region = 'South East' AND status = 'delivered';

\echo
\echo '=== A query without the shard key must scan every partition (scatter-gather) ==='
EXPLAIN (ANALYZE)
SELECT COUNT(*) FROM orders_by_region WHERE status = 'delivered';

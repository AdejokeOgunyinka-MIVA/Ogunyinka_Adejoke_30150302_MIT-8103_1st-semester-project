-- =====================================================================
-- Cartify: seed data generator
-- Produces ~5,000 customers, ~7,500 addresses, 20 categories,
-- 500 products, 50,000 orders, ~120,000 order items, 50,000 payments,
-- ~45,000 deliveries and ~20,000 reviews.
--
-- Volume matters: Portfolio 2 needs enough rows for the query planner
-- to prefer an index over a sequential scan.
--
-- Run with:  psql -d cartify -f portfolio-1-database-design/sql/03_seed_data.sql
-- Re-runnable: it truncates every table first.
-- =====================================================================

\timing on

TRUNCATE reviews, deliveries, payments, order_items, orders,
         products, categories, addresses, customers RESTART IDENTITY CASCADE;

-- Make the random data reproducible: same seed, same dataset every run.
SELECT setseed(0.42);

-- ---------------------------------------------------------------------
-- 1. Customers (5,000)
-- ---------------------------------------------------------------------
INSERT INTO customers (full_name, email, phone, created_at)
SELECT
    first_names[1 + floor(random() * array_length(first_names, 1))::int] || ' ' ||
    last_names [1 + floor(random() * array_length(last_names, 1))::int],
    'customer' || g || '@example.ng',
    '080' || lpad((10000000 + floor(random() * 89999999))::text, 8, '0'),
    NOW() - (random() * 730) * INTERVAL '1 day'
FROM generate_series(1, 5000) AS g,
     (SELECT ARRAY['Adejoke','Chinedu','Ngozi','Tunde','Amina','Emeka','Funmi','Ibrahim',
                   'Kemi','Obinna','Zainab','Segun','Chiamaka','Musa','Bola','Uche',
                   'Halima','Femi','Ifeoma','Yusuf','Adaeze','Kunle','Blessing','Sani'] AS first_names,
             ARRAY['Ogunyinka','Okafor','Adeyemi','Bello','Eze','Abubakar','Okonkwo','Balogun',
                   'Nwosu','Lawal','Ibe','Oyelaran','Mohammed','Chukwu','Adebayo','Danjuma',
                   'Okoro','Afolabi','Umar','Igwe'] AS last_names) AS names;

-- ---------------------------------------------------------------------
-- 2. Addresses (1 default per customer + ~50% get a second one)
-- ---------------------------------------------------------------------
INSERT INTO addresses (customer_id, street, city, state, is_default)
SELECT c.id,
       (1 + floor(random() * 200))::int || ' ' ||
       streets[1 + floor(random() * array_length(streets, 1))::int],
       loc.city, loc.state, TRUE
FROM customers c,
     LATERAL (SELECT city, state FROM (VALUES
        ('Ikeja','Lagos'),('Lekki','Lagos'),('Surulere','Lagos'),('Yaba','Lagos'),
        ('Wuse','FCT'),('Garki','FCT'),('Gwarinpa','FCT'),
        ('Port Harcourt','Rivers'),('Ibadan','Oyo'),('Kano','Kano'),
        ('Enugu','Enugu'),('Benin City','Edo'),('Kaduna','Kaduna'),
        ('Owerri','Imo'),('Calabar','Cross River'),('Jos','Plateau'),
        ('Abeokuta','Ogun'),('Uyo','Akwa Ibom'),('Onitsha','Anambra'),('Ilorin','Kwara')
     ) AS t(city, state) ORDER BY random() + c.id * 0 LIMIT 1) AS loc,
     (SELECT ARRAY['Allen Avenue','Admiralty Way','Adeola Odeku Street','Herbert Macaulay Way',
                   'Aminu Kano Crescent','Ahmadu Bello Way','Trans Amadi Road','Ring Road',
                   'Zik Avenue','Sapele Road','Awolowo Road','Opebi Road'] AS streets) AS s;

INSERT INTO addresses (customer_id, street, city, state, is_default)
SELECT c.id,
       (1 + floor(random() * 200))::int || ' ' || 'Market Road',
       'Lagos Island', 'Lagos', FALSE
FROM customers c
WHERE random() < 0.5;

-- ---------------------------------------------------------------------
-- 3. Categories (5 top-level, 15 sub-categories)
-- ---------------------------------------------------------------------
INSERT INTO categories (name, parent_id) VALUES
    ('Electronics', NULL), ('Fashion', NULL), ('Groceries', NULL),
    ('Home & Kitchen', NULL), ('Beauty & Health', NULL);

INSERT INTO categories (name, parent_id) VALUES
    ('Phones', 1), ('Laptops', 1), ('Audio', 1),
    ('Men''s Clothing', 2), ('Women''s Clothing', 2), ('Shoes', 2),
    ('Rice & Grains', 3), ('Beverages', 3), ('Snacks', 3),
    ('Cookware', 4), ('Furniture', 4), ('Appliances', 4),
    ('Skincare', 5), ('Hair Care', 5), ('Supplements', 5);

-- ---------------------------------------------------------------------
-- 4. Products (500, in sub-categories only, naira prices)
-- ---------------------------------------------------------------------
INSERT INTO products (category_id, name, description, price, stock_quantity, created_at)
SELECT
    6 + floor(random() * 15)::int,
    brands[1 + floor(random() * array_length(brands, 1))::int] || ' ' ||
    items [1 + floor(random() * array_length(items, 1))::int] || ' ' || g,
    'Quality product sold on Cartify. Item number ' || g || '.',
    round((500 + random() * 499500)::numeric, 2),
    floor(random() * 200)::int,
    NOW() - (random() * 365) * INTERVAL '1 day'
FROM generate_series(1, 500) AS g,
     (SELECT ARRAY['Samsung','Tecno','Infinix','HP','Dell','Nike','Adidas','Mama Gold',
                   'Golden Penny','Peak','Indomie','Binatone','Nexus','Oraimo','Dano',
                   'Nivea','Dettol','Ankara','Zara','Itel'] AS brands,
             ARRAY['Smartphone','Laptop','Earbuds','Sneakers','Gown','Shirt','Rice 50kg',
                   'Milk Powder','Noodles','Blender','Fridge','Sofa','Lotion','Shampoo',
                   'Vitamin C','Bluetooth Speaker','Kaftan','Pressure Cooker','Agbada','Headset'] AS items) AS w;

-- ---------------------------------------------------------------------
-- 5. Orders (50,000) over the past 2 years
-- random() is called in the row-producing SELECT so it runs once per row.
-- (A random() inside an uncorrelated subquery is evaluated only once.)
-- ---------------------------------------------------------------------
WITH bounds AS (SELECT max(id) AS max_addr FROM addresses),
picks AS (
    SELECT g, 1 + floor(random() * b.max_addr)::int AS address_id
    FROM generate_series(1, 50000) AS g, bounds b
)
INSERT INTO orders (customer_id, address_id, status, order_date, total_amount)
SELECT
    a.customer_id,
    a.id,
    (ARRAY['pending','paid','shipped','delivered','delivered','delivered','cancelled'])
        [1 + floor(random() * 7)::int],
    NOW() - (random() * 730) * INTERVAL '1 day',
    0
FROM picks p
JOIN addresses a ON a.id = p.address_id;

-- ---------------------------------------------------------------------
-- 6. Order items (1 to 4 lines per order, unit_price copied from product)
-- Line 1 is always kept; lines 2-4 are each kept with 45% probability.
-- ---------------------------------------------------------------------
WITH picks AS (
    SELECT o.id AS order_id,
           1 + floor(random() * 500)::int AS product_id,
           1 + floor(random() * 3)::int   AS quantity
    FROM orders o
    CROSS JOIN generate_series(1, 4) AS k
    WHERE k = 1 OR random() < 0.45
)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT DISTINCT ON (pk.order_id, pk.product_id)
    pk.order_id, pk.product_id, pk.quantity, pr.price
FROM picks pk
JOIN products pr ON pr.id = pk.product_id;

-- Derive the order totals from their items (same rule Portfolio 3 enforces in a transaction)
UPDATE orders o
SET total_amount = s.total
FROM (SELECT order_id, SUM(quantity * unit_price) AS total
      FROM order_items GROUP BY order_id) AS s
WHERE o.id = s.order_id;

-- ---------------------------------------------------------------------
-- 7. Payments (one per order; cancelled orders get a failed payment)
-- ---------------------------------------------------------------------
INSERT INTO payments (order_id, method, amount, status, paid_at)
SELECT
    o.id,
    (ARRAY['card','bank_transfer','ussd','wallet','cash_on_delivery'])[1 + floor(random() * 5)::int],
    o.total_amount,
    CASE o.status
        WHEN 'cancelled' THEN 'failed'
        WHEN 'pending'   THEN 'pending'
        ELSE 'successful'
    END,
    CASE WHEN o.status IN ('pending','cancelled') THEN NULL
         ELSE o.order_date + INTERVAL '5 minutes' END
FROM orders o;

-- ---------------------------------------------------------------------
-- 8. Deliveries (for shipped and delivered orders)
-- ---------------------------------------------------------------------
INSERT INTO deliveries (order_id, courier, tracking_number, status, dispatched_at, delivered_at)
SELECT
    o.id,
    (ARRAY['GIG Logistics','DHL','Kwik','Sendbox','Red Star Express'])[1 + floor(random() * 5)::int],
    'CTF' || lpad(o.id::text, 8, '0'),
    CASE o.status WHEN 'shipped' THEN 'in_transit' ELSE 'delivered' END,
    o.order_date + INTERVAL '1 day',
    CASE o.status WHEN 'delivered' THEN o.order_date + INTERVAL '4 days' ELSE NULL END
FROM orders o
WHERE o.status IN ('shipped','delivered');

-- ---------------------------------------------------------------------
-- 9. Reviews (~20,000; one per customer-product pair)
-- ---------------------------------------------------------------------
INSERT INTO reviews (customer_id, product_id, rating, comment, created_at)
SELECT DISTINCT ON (o.customer_id, oi.product_id)
    o.customer_id, oi.product_id,
    1 + floor(random() * 5)::int,
    (ARRAY['Great product','Fast delivery','Not as described','Would buy again',
           'Average quality','Excellent value'])[1 + floor(random() * 6)::int],
    o.order_date + INTERVAL '7 days'
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
WHERE o.status = 'delivered' AND random() < 0.5;

-- ---------------------------------------------------------------------
-- Row counts: the evidence that the load worked
-- ---------------------------------------------------------------------
ANALYZE;

SELECT 'customers'   AS table_name, COUNT(*) FROM customers   UNION ALL
SELECT 'addresses',   COUNT(*) FROM addresses   UNION ALL
SELECT 'categories',  COUNT(*) FROM categories  UNION ALL
SELECT 'products',    COUNT(*) FROM products    UNION ALL
SELECT 'orders',      COUNT(*) FROM orders      UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'payments',    COUNT(*) FROM payments    UNION ALL
SELECT 'deliveries',  COUNT(*) FROM deliveries  UNION ALL
SELECT 'reviews',     COUNT(*) FROM reviews;

-- =====================================================================
-- Cartify: the six business queries used for optimisation analysis
-- Portfolio 2 - Query Processing and Optimisation
--
-- Each query maps to a key operation from the case study statement.
-- They are run twice: before indexing (02_explain_before.sql) and
-- after indexing (04_explain_after.sql).
-- =====================================================================

-- Q1. Customer order history (operation 6: "retrieve a customer's order history")
--     Used on the "My Orders" page. Filters orders by customer_id.
SELECT o.id, o.order_date, o.status, o.total_amount
FROM orders o
WHERE o.customer_id = 4123
ORDER BY o.order_date DESC;

-- Q2. Catalogue search by name (operation 5: "search the catalogue")
--     Case-insensitive prefix search as typed in the search box.
SELECT id, name, price, stock_quantity
FROM products
WHERE name ILIKE 'Samsung%'
ORDER BY price;

-- Q3. Products in a category with stock (operation 5)
--     Category page listing. Joins products to categories.
SELECT p.id, p.name, p.price, c.name AS category
FROM products p
JOIN categories c ON c.id = p.category_id
WHERE c.name = 'Phones' AND p.stock_quantity > 0
ORDER BY p.price;

-- Q4. Orders in a date range with status (reporting)
--     Operations dashboard: "what shipped last month?"
SELECT id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'shipped'
  AND order_date >= NOW() - INTERVAL '30 days';

-- Q5. Top 10 selling products (operation 7: "report top-selling products")
--     Aggregates ~150k order lines, joined to products.
SELECT p.id, p.name, SUM(oi.quantity) AS units_sold,
       SUM(oi.quantity * oi.unit_price) AS revenue
FROM order_items oi
JOIN products p ON p.id = oi.product_id
JOIN orders o   ON o.id = oi.order_id
WHERE o.status = 'delivered'
GROUP BY p.id, p.name
ORDER BY units_sold DESC
LIMIT 10;

-- Q6. Revenue by state (operation 7: "revenue by state")
--     Management report: joins orders to addresses, aggregates by state.
SELECT a.state, COUNT(*) AS orders, SUM(o.total_amount) AS revenue
FROM orders o
JOIN addresses a ON a.id = o.address_id
WHERE o.status IN ('paid','shipped','delivered')
GROUP BY a.state
ORDER BY revenue DESC;

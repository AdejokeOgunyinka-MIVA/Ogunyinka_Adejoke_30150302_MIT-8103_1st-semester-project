-- =====================================================================
-- Cartify: build MongoDB documents from the PostgreSQL schema
-- Portfolio 4 - NoSQL and Advanced Data Models
--
-- Each query below produces a JSON array. The relational tables are
-- joined and nested into the document shape MongoDB will store:
--   products: embeds category, per-category attributes, recent reviews
--   orders:   embeds customer snapshot, delivery address, line items
--
-- Run with:
--   psql -d cartify -At -f portfolio-4-nosql/scripts/01_export_from_postgres.sql
-- (the companion shell script writes the two outputs to data/*.json)
-- =====================================================================

\o portfolio-4-nosql/data/products.json
SELECT json_agg(doc ORDER BY (doc->>'_id')::int)
FROM (
  SELECT json_build_object(
    '_id',          p.id,
    'name',         p.name,
    'description',  p.description,
    'price',        p.price,
    'stock',        p.stock_quantity,
    'category',     json_build_object(
                      'id',     c.id,
                      'name',   c.name,
                      'parent', pc.name),
    -- Attributes differ by category: this is what the relational model
    -- could not express without 30 nullable columns or an EAV table.
    'attributes',   CASE c.name
      WHEN 'Phones'    THEN json_build_object('ram_gb', (ARRAY[4,6,8,12])[1 + p.id % 4],
                                              'storage_gb', (ARRAY[64,128,256])[1 + p.id % 3],
                                              'colour', (ARRAY['Black','Blue','Silver'])[1 + p.id % 3],
                                              'dual_sim', p.id % 2 = 0)
      WHEN 'Laptops'   THEN json_build_object('ram_gb', (ARRAY[8,16,32])[1 + p.id % 3],
                                              'cpu', (ARRAY['Intel i5','Intel i7','Ryzen 5'])[1 + p.id % 3],
                                              'screen_inch', (ARRAY[13.3,14.0,15.6])[1 + p.id % 3])
      WHEN 'Audio'     THEN json_build_object('wireless', p.id % 2 = 0,
                                              'battery_hours', 10 + p.id % 30)
      WHEN 'Shoes'     THEN json_build_object('size_eu', 38 + p.id % 8,
                                              'colour', (ARRAY['Black','White','Brown'])[1 + p.id % 3],
                                              'material', (ARRAY['Leather','Canvas','Mesh'])[1 + p.id % 3])
      WHEN 'Men''s Clothing'   THEN json_build_object('size', (ARRAY['S','M','L','XL'])[1 + p.id % 4],
                                                      'fabric', (ARRAY['Cotton','Ankara','Linen'])[1 + p.id % 3])
      WHEN 'Women''s Clothing' THEN json_build_object('size', (ARRAY['S','M','L','XL'])[1 + p.id % 4],
                                                      'fabric', (ARRAY['Cotton','Ankara','Silk'])[1 + p.id % 3])
      WHEN 'Rice & Grains' THEN json_build_object('weight_kg', (ARRAY[5,10,25,50])[1 + p.id % 4],
                                                  'origin', (ARRAY['Local','Imported'])[1 + p.id % 2])
      WHEN 'Beverages'     THEN json_build_object('volume_litres', (ARRAY[0.5,1.0,1.5])[1 + p.id % 3],
                                                  'pack_size', (ARRAY[1,6,12])[1 + p.id % 3])
      WHEN 'Snacks'        THEN json_build_object('weight_g', 50 * (1 + p.id % 10))
      WHEN 'Cookware'      THEN json_build_object('material', (ARRAY['Non-stick','Stainless','Cast iron'])[1 + p.id % 3],
                                                  'pieces', 1 + p.id % 12)
      WHEN 'Furniture'     THEN json_build_object('material', (ARRAY['Wood','Metal','Fabric'])[1 + p.id % 3],
                                                  'assembly_required', p.id % 2 = 0)
      WHEN 'Appliances'    THEN json_build_object('power_watts', 500 + 100 * (p.id % 15),
                                                  'warranty_months', (ARRAY[12,24])[1 + p.id % 2])
      WHEN 'Skincare'      THEN json_build_object('skin_type', (ARRAY['Oily','Dry','All'])[1 + p.id % 3],
                                                  'volume_ml', (ARRAY[50,100,200])[1 + p.id % 3])
      WHEN 'Hair Care'     THEN json_build_object('hair_type', (ARRAY['Natural','Relaxed','All'])[1 + p.id % 3],
                                                  'volume_ml', (ARRAY[250,500])[1 + p.id % 2])
      WHEN 'Supplements'   THEN json_build_object('capsules', (ARRAY[30,60,90])[1 + p.id % 3],
                                                  'vegan', p.id % 2 = 0)
      ELSE '{}'::json END,
    'rating',       json_build_object(
                      'average', COALESCE(ROUND(r.avg_rating, 2), 0),
                      'count',   COALESCE(r.review_count, 0)),
    -- Only the 3 most recent reviews are embedded (bounded array);
    -- the full history stays in PostgreSQL.
    'recent_reviews', COALESCE(rr.reviews, '[]'::json),
    'created_at',   p.created_at
  ) AS doc
  FROM products p
  JOIN categories c  ON c.id = p.category_id
  LEFT JOIN categories pc ON pc.id = c.parent_id
  LEFT JOIN (SELECT product_id, AVG(rating) AS avg_rating, COUNT(*) AS review_count
             FROM reviews GROUP BY product_id) r ON r.product_id = p.id
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object('customer', cu.full_name, 'rating', rv.rating,
                                      'comment', rv.comment, 'date', rv.created_at)
                    ORDER BY rv.created_at DESC) AS reviews
    FROM (SELECT * FROM reviews WHERE product_id = p.id ORDER BY created_at DESC LIMIT 3) rv
    JOIN customers cu ON cu.id = rv.customer_id
  ) rr ON TRUE
) sub;
\o

\o portfolio-4-nosql/data/orders.json
SELECT json_agg(doc ORDER BY (doc->>'_id')::int)
FROM (
  SELECT json_build_object(
    '_id',         o.id,
    'status',      o.status,
    'order_date',  o.order_date,
    'total',       o.total_amount,
    -- Customer snapshot: name and email as they were at order time.
    -- customer_id is kept as a reference for lookups.
    'customer',    json_build_object('id', cu.id, 'name', cu.full_name, 'email', cu.email),
    -- Address embedded in full: an order must keep where it shipped
    -- even if the customer later edits or deletes the address.
    'ship_to',     json_build_object('street', a.street, 'city', a.city, 'state', a.state),
    -- Line items embedded: they are never read without their order.
    'items',       (SELECT json_agg(json_build_object(
                        'product_id', oi.product_id, 'name', p.name,
                        'qty', oi.quantity, 'unit_price', oi.unit_price,
                        'line_total', oi.quantity * oi.unit_price))
                    FROM order_items oi JOIN products p ON p.id = oi.product_id
                    WHERE oi.order_id = o.id),
    'payment',     (SELECT json_build_object('method', pm.method, 'status', pm.status, 'paid_at', pm.paid_at)
                    FROM payments pm WHERE pm.order_id = o.id LIMIT 1),
    'delivery',    (SELECT json_build_object('courier', d.courier, 'tracking', d.tracking_number,
                                             'status', d.status, 'delivered_at', d.delivered_at)
                    FROM deliveries d WHERE d.order_id = o.id)
  ) AS doc
  FROM orders o
  JOIN customers cu ON cu.id = o.customer_id
  JOIN addresses a  ON a.id = o.address_id
  WHERE o.id <= 5000          -- 5,000 orders is enough to demonstrate; keeps the JSON file small
) sub;
\o

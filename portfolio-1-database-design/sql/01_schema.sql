-- =====================================================================
-- Cartify: relational schema (PostgreSQL 17)
-- Portfolio 1 - Database Design and Modelling
-- Author: Adejoke Ogunyinka (30150302)
--
-- Run with:  psql -d cartify -f portfolio-1-database-design/sql/01_schema.sql
-- =====================================================================

-- Start clean so the script can be re-run safely.
DROP TABLE IF EXISTS reviews, deliveries, payments, order_items, orders,
                     products, categories, addresses, customers CASCADE;

-- ---------------------------------------------------------------------
-- customers: one row per registered shopper.
-- Identity only; nothing that changes per order lives here.
-- ---------------------------------------------------------------------
CREATE TABLE customers (
    id          SERIAL PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL UNIQUE,
    phone       VARCHAR(20)  NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- addresses: one customer can have many delivery addresses (1:N).
-- Kept separate to satisfy 1NF (no repeating address columns).
-- ---------------------------------------------------------------------
CREATE TABLE addresses (
    id           SERIAL PRIMARY KEY,
    customer_id  INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    street       VARCHAR(200) NOT NULL,
    city         VARCHAR(100) NOT NULL,
    state        VARCHAR(50)  NOT NULL,
    is_default   BOOLEAN NOT NULL DEFAULT FALSE
);

-- ---------------------------------------------------------------------
-- categories: product grouping. parent_id is a self-reference so that
-- "Phones" can sit under "Electronics" without a second table.
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    id         SERIAL PRIMARY KEY,
    name       VARCHAR(100) NOT NULL UNIQUE,
    parent_id  INT REFERENCES categories(id)
);

-- ---------------------------------------------------------------------
-- products: the catalogue. Live stock belongs to the product, not to
-- any order. Price is NUMERIC, never FLOAT, because money must be exact.
-- ---------------------------------------------------------------------
CREATE TABLE products (
    id              SERIAL PRIMARY KEY,
    category_id     INT NOT NULL REFERENCES categories(id),
    name            VARCHAR(150) NOT NULL,
    description     TEXT,
    price           NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    stock_quantity  INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------
-- orders: the order header. Who bought, where it ships, when, status.
-- total_amount is stored for fast reporting; it is derived from
-- order_items at the moment the order is placed.
-- ---------------------------------------------------------------------
CREATE TABLE orders (
    id            SERIAL PRIMARY KEY,
    customer_id   INT NOT NULL REFERENCES customers(id),
    address_id    INT NOT NULL REFERENCES addresses(id),
    status        VARCHAR(20) NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','paid','shipped','delivered','cancelled')),
    order_date    TIMESTAMP NOT NULL DEFAULT NOW(),
    total_amount  NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)
);

-- ---------------------------------------------------------------------
-- order_items: resolves the many-to-many between orders and products.
-- unit_price is copied from products on purpose: if the catalogue price
-- changes next week, historical orders must not change with it.
-- ---------------------------------------------------------------------
CREATE TABLE order_items (
    id          SERIAL PRIMARY KEY,
    order_id    INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id  INT NOT NULL REFERENCES products(id),
    quantity    INT NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (order_id, product_id)
);

-- ---------------------------------------------------------------------
-- payments: separate from orders because an order can have a failed
-- attempt followed by a successful one. Payment has its own lifecycle.
-- ---------------------------------------------------------------------
CREATE TABLE payments (
    id        SERIAL PRIMARY KEY,
    order_id  INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    method    VARCHAR(20) NOT NULL
              CHECK (method IN ('card','bank_transfer','ussd','wallet','cash_on_delivery')),
    amount    NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    status    VARCHAR(20) NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','successful','failed','refunded')),
    paid_at   TIMESTAMP
);

-- ---------------------------------------------------------------------
-- deliveries: dispatch and delivery happen after payment, with their
-- own courier and timestamps, so they do not belong on the order row.
-- One delivery per order (1:1), enforced by UNIQUE on order_id.
-- ---------------------------------------------------------------------
CREATE TABLE deliveries (
    id               SERIAL PRIMARY KEY,
    order_id         INT NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    courier          VARCHAR(50) NOT NULL,
    tracking_number  VARCHAR(50) UNIQUE,
    status           VARCHAR(20) NOT NULL DEFAULT 'processing'
                     CHECK (status IN ('processing','dispatched','in_transit','delivered','failed')),
    dispatched_at    TIMESTAMP,
    delivered_at     TIMESTAMP
);

-- ---------------------------------------------------------------------
-- reviews: optional, many per product, one per customer per product.
-- ---------------------------------------------------------------------
CREATE TABLE reviews (
    id           SERIAL PRIMARY KEY,
    customer_id  INT NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    product_id   INT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    rating       SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment      TEXT,
    created_at   TIMESTAMP NOT NULL DEFAULT NOW(),
    UNIQUE (customer_id, product_id)
);

-- Project : UK E-Commerce Analytics
-- Database: ecommerce_db (PostgreSQL) | Schema: ecommerce
-- Purpose : Create the database, define the eight tables, then load the eight CSV files.
--
-- Usage (from the uk-ecommerce-analytics/sql/ folder, because the CSVs in ../data/
-- are read by relative path):
--   psql -U postgres -f 00_schema_and_load.sql
--
-- Safe to re-run. ecommerce_db is created only if it does not exist yet. The
-- ecommerce schema inside it is then dropped and rebuilt, so anything stored
-- in that schema (including views built on its tables) is replaced. Other
-- schemas in the database are not touched. Stops at the first error.

\set ON_ERROR_STOP on

\c postgres
SELECT 'CREATE DATABASE ecommerce_db'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'ecommerce_db') \gexec
\c ecommerce_db

-- ---------------------------------------------------------------------------
-- 1. Schema: drop and rebuild the ecommerce schema, then define the eight tables
-- ---------------------------------------------------------------------------

DROP SCHEMA IF EXISTS ecommerce CASCADE;
CREATE SCHEMA ecommerce;
SET search_path TO ecommerce;

CREATE TABLE customers (
    customer_id INT PRIMARY KEY, customer_name TEXT, gender TEXT, date_of_birth DATE,
    city TEXT, region TEXT, postcode TEXT, signup_date DATE, acquisition_channel TEXT
);
CREATE TABLE products (
    product_id INT PRIMARY KEY, product_name TEXT, category TEXT, subcategory TEXT,
    brand TEXT, unit_price NUMERIC(10,2), cost_price NUMERIC(10,2), stock_quantity INT
);
CREATE TABLE orders (
    order_id INT PRIMARY KEY, customer_id INT REFERENCES customers(customer_id),
    order_date DATE, order_status TEXT, shipping_method TEXT, delivery_date DATE,
    discount_amount NUMERIC(10,2), shipping_cost NUMERIC(10,2), total_amount NUMERIC(10,2)
);
CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY, order_id INT REFERENCES orders(order_id),
    product_id INT REFERENCES products(product_id), quantity INT,
    unit_price NUMERIC(10,2), discount NUMERIC(10,2), item_total NUMERIC(10,2)
);
CREATE TABLE payments (
    payment_id INT PRIMARY KEY, order_id INT REFERENCES orders(order_id),
    payment_date DATE, payment_method TEXT, payment_status TEXT, amount NUMERIC(10,2)
);
CREATE TABLE returns (
    return_id INT PRIMARY KEY, order_id INT REFERENCES orders(order_id),
    product_id INT REFERENCES products(product_id), return_date DATE,
    return_reason TEXT, quantity_returned INT, refund_amount NUMERIC(10,2)
);
CREATE TABLE reviews (
    review_id INT PRIMARY KEY, customer_id INT REFERENCES customers(customer_id),
    product_id INT REFERENCES products(product_id), review_date DATE,
    rating INT, verified_purchase BOOLEAN
);
CREATE TABLE website_sessions (
    session_id INT PRIMARY KEY, customer_id INT NULL REFERENCES customers(customer_id),
    session_date DATE, device_type TEXT, traffic_source TEXT, pages_viewed INT,
    session_duration_seconds INT, added_to_cart BOOLEAN, checkout_started BOOLEAN,
    purchase_completed BOOLEAN
);

-- ---------------------------------------------------------------------------
-- 2. Load: copy the CSV files into the tables
-- ---------------------------------------------------------------------------

\copy ecommerce.customers FROM '../data/customers.csv' CSV HEADER;
\copy ecommerce.products FROM '../data/products.csv' CSV HEADER;
\copy ecommerce.orders FROM '../data/orders.csv' CSV HEADER;
\copy ecommerce.order_items FROM '../data/order_items.csv' CSV HEADER;
\copy ecommerce.payments FROM '../data/payments.csv' CSV HEADER;
\copy ecommerce.returns FROM '../data/returns.csv' CSV HEADER;

-- ---------------------------------------------------------------------------
-- Two CSV columns store whole-number IDs as decimals ("118.0", "823.0"), which
-- an INT column rejects. They are loaded into a staging table as NUMERIC and
-- cast to INT on insert. The CSV files themselves are left unchanged.
--   reviews.csv           product_id  (all 11,308 rows)
--   website_sessions.csv  customer_id (29,979 rows; the other 21 are empty = anonymous session)
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE reviews_stage (
    review_id INT, customer_id INT, product_id NUMERIC, review_date DATE,
    rating INT, verified_purchase BOOLEAN
);
\copy reviews_stage FROM '../data/reviews.csv' CSV HEADER;
INSERT INTO ecommerce.reviews (review_id, customer_id, product_id, review_date, rating, verified_purchase)
SELECT review_id, customer_id, product_id::INT, review_date, rating, verified_purchase
FROM reviews_stage;

CREATE TEMP TABLE website_sessions_stage (
    session_id INT, customer_id NUMERIC, session_date DATE, device_type TEXT,
    traffic_source TEXT, pages_viewed INT, session_duration_seconds INT,
    added_to_cart BOOLEAN, checkout_started BOOLEAN, purchase_completed BOOLEAN
);
\copy website_sessions_stage FROM '../data/website_sessions.csv' CSV HEADER;
INSERT INTO ecommerce.website_sessions (session_id, customer_id, session_date, device_type,
    traffic_source, pages_viewed, session_duration_seconds, added_to_cart,
    checkout_started, purchase_completed)
SELECT session_id, customer_id::INT, session_date, device_type,
    traffic_source, pages_viewed, session_duration_seconds, added_to_cart,
    checkout_started, purchase_completed
FROM website_sessions_stage;

-- Sanity check: expect customers 5000, products 504, orders 15000, order_items 28331,
-- payments 15000, returns 1233, reviews 11308, website_sessions 30000
SELECT 'customers' AS table_name, COUNT(*) AS rows_loaded FROM ecommerce.customers
UNION ALL SELECT 'products',         COUNT(*) FROM ecommerce.products
UNION ALL SELECT 'orders',           COUNT(*) FROM ecommerce.orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM ecommerce.order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM ecommerce.payments
UNION ALL SELECT 'returns',          COUNT(*) FROM ecommerce.returns
UNION ALL SELECT 'reviews',          COUNT(*) FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions', COUNT(*) FROM ecommerce.website_sessions;

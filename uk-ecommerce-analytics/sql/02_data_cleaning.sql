-- ============================================================================
-- UK E-Commerce Analytics: Data Cleaning                       (DRAFT)
-- Database: ecommerce_db    Schema: ecommerce
--
-- Only the load was changed. No rows were removed or edited, so every query
-- in this file only reads data (SELECT). Nothing here changes the database.
--
-- Problems found, and what fixed them:
--   1. IDs written as decimals ("118.0") stopped the original load.
--        -> Fixed in sql/00_schema_and_load.sql (temporary tables, then whole numbers).
--   2. The SQL and workbook say ecommerce_db, but the load script created ecommerce_analytics.
--        -> The load script now creates ecommerce_db.
--   3. In Tableau, products with no returns have empty (NULL) return fields,
--      and the Product Performance chart then leaves them out.
--        -> Keep them and show their returns as 0 (Part 3 below).
--
-- Each part below shows the problem is gone. Part 4 confirms that nothing was lost.
-- Run from psql:  \c ecommerce_db  then  \i sql/02_data_cleaning.sql
-- ============================================================================


-- ============================================================================
-- PART 1. IDs written as decimals
-- ============================================================================

-- The fix, as it appears in sql/00_schema_and_load.sql. It is shown here for reading only:
-- running it again would load the rows a second time. Website sessions use the same pattern.
--
--   CREATE TEMP TABLE reviews_stage (
--       review_id INT, customer_id INT, product_id NUMERIC, review_date DATE,
--       rating INT, verified_purchase BOOLEAN
--   );
--   \copy reviews_stage FROM '../data/reviews.csv' CSV HEADER;
--   INSERT INTO ecommerce.reviews (review_id, customer_id, product_id, review_date, rating, verified_purchase)
--   SELECT review_id, customer_id, product_id::INT, review_date, rating, verified_purchase
--   FROM reviews_stage;

-- Both columns are now whole numbers, not decimals.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ecommerce'
  AND (table_name, column_name) IN (('reviews', 'product_id'), ('website_sessions', 'customer_id'))
ORDER BY table_name;

-- Every ID loaded. The 21 website sessions without a customer are visitors who were
-- not logged in. Their customer ID is empty in the CSV and stays empty.
SELECT 'reviews.product_id'            AS column_checked,
       COUNT(*)                        AS rows_loaded,
       COUNT(product_id)               AS ids_converted,
       COUNT(*) - COUNT(product_id)    AS ids_empty
FROM ecommerce.reviews
UNION ALL
SELECT 'website_sessions.customer_id',
       COUNT(*),
       COUNT(customer_id),
       COUNT(*) - COUNT(customer_id)
FROM ecommerce.website_sessions;

-- Every converted ID still points to a real product or customer (none were changed by the conversion).
SELECT (SELECT COUNT(*) FROM ecommerce.reviews r
        LEFT JOIN ecommerce.products p ON p.product_id = r.product_id
        WHERE p.product_id IS NULL)                                      AS reviews_with_unknown_product,
       (SELECT COUNT(*) FROM ecommerce.website_sessions s
        LEFT JOIN ecommerce.customers c ON c.customer_id = s.customer_id
        WHERE s.customer_id IS NOT NULL AND c.customer_id IS NULL)       AS sessions_with_unknown_customer;


-- ============================================================================
-- PART 2. The database name
-- ============================================================================

-- The database you are connected to should be ecommerce_db, as the workbook and every query expect.
SELECT current_database() AS database_name,
       (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'ecommerce') AS tables_in_ecommerce_schema;


-- ============================================================================
-- PART 3. Products with no returns (empty fields in Tableau)
-- ============================================================================

-- The problem. A product that was never returned has no matching row in the returns table,
-- so its return fields are NULL when the tables are joined. A chart that removes NULL rows
-- also removes these products, even though they sold normally.
SELECT COUNT(DISTINCT p.product_id)  AS products_never_returned,
       ROUND(SUM(oi.item_total))     AS item_sales
FROM ecommerce.products p
JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
LEFT JOIN ecommerce.returns r ON r.product_id = p.product_id
WHERE r.return_id IS NULL;

-- The fix: keep every product and show its returns as 0.
-- Use this table (or the same COALESCE in Tableau) for the Product Performance chart.
WITH sales AS (
    SELECT product_id, SUM(item_total) AS item_sales
    FROM ecommerce.order_items
    GROUP BY product_id
),
returned AS (
    SELECT product_id, COUNT(*) AS returns, SUM(refund_amount) AS refunded
    FROM ecommerce.returns
    GROUP BY product_id
)
SELECT p.product_name,
       p.category,
       ROUND(s.item_sales)           AS item_sales,
       COALESCE(r.returns, 0)        AS returns,
       COALESCE(ROUND(r.refunded), 0) AS refunded
FROM ecommerce.products p
JOIN sales s ON s.product_id = p.product_id
LEFT JOIN returned r ON r.product_id = p.product_id
ORDER BY s.item_sales DESC
LIMIT 5;

-- Check the fix. All 504 products are kept, and their sales add up to the same total
-- as the order lines (so nothing is hidden and nothing is counted twice).
WITH per_product AS (
    SELECT p.product_id,
           SUM(oi.item_total) AS item_sales,
           NOT EXISTS (SELECT 1 FROM ecommerce.returns r WHERE r.product_id = p.product_id) AS never_returned
    FROM ecommerce.products p
    JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
    GROUP BY p.product_id
)
SELECT COUNT(*)                                                  AS products_kept,
       COUNT(*) FILTER (WHERE never_returned)                    AS of_which_never_returned,
       ROUND(SUM(item_sales))                                    AS item_sales_all_products,
       (SELECT ROUND(SUM(item_total)) FROM ecommerce.order_items) AS item_sales_order_lines
FROM per_product;


-- ============================================================================
-- PART 4. Nothing was lost
-- ============================================================================

-- Row counts after loading. They should match the CSV files in data/ (row count = lines minus the header).
SELECT 'customers' AS table_name, COUNT(*) AS rows_loaded FROM ecommerce.customers
UNION ALL SELECT 'products',         COUNT(*) FROM ecommerce.products
UNION ALL SELECT 'orders',           COUNT(*) FROM ecommerce.orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM ecommerce.order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM ecommerce.payments
UNION ALL SELECT 'returns',          COUNT(*) FROM ecommerce.returns
UNION ALL SELECT 'reviews',          COUNT(*) FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions', COUNT(*) FROM ecommerce.website_sessions;

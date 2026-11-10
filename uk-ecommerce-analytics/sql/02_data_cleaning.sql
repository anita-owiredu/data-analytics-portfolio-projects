-- UK E-Commerce: data cleaning

-- Part 1. IDs stored as decimals

-- Are both ID columns now whole numbers?
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'ecommerce'
  AND (table_name, column_name) IN (('reviews', 'product_id'), ('website_sessions', 'customer_id'))
ORDER BY table_name;

-- Did every ID load? Sessions with no customer are logged-out visitors
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

-- Do the converted IDs still point to real products and customers?
SELECT (SELECT COUNT(*) FROM ecommerce.reviews r
        LEFT JOIN ecommerce.products p ON p.product_id = r.product_id
        WHERE p.product_id IS NULL)                                      AS reviews_with_unknown_product,
       (SELECT COUNT(*) FROM ecommerce.website_sessions s
        LEFT JOIN ecommerce.customers c ON c.customer_id = s.customer_id
        WHERE s.customer_id IS NOT NULL AND c.customer_id IS NULL)       AS sessions_with_unknown_customer;

-- Part 2. Database name

-- Which database are we in, and how many tables does it hold?
SELECT current_database() AS database_name,
       (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'ecommerce') AS tables_in_ecommerce_schema;

-- Part 3. Products with no returns

-- How many products were never returned, and what did they sell?
SELECT COUNT(DISTINCT p.product_id)  AS products_never_returned,
       ROUND(SUM(oi.item_total))     AS item_sales
FROM ecommerce.products p
JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
LEFT JOIN ecommerce.returns r ON r.product_id = p.product_id
WHERE r.return_id IS NULL;

-- Fix: keep every product and show missing returns as 0
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

-- Are all products kept, and do their sales match the order lines?
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

-- Part 4. Row counts after loading

-- How many rows are in each table?
SELECT 'customers' AS table_name, COUNT(*) AS rows_loaded FROM ecommerce.customers
UNION ALL SELECT 'products',         COUNT(*) FROM ecommerce.products
UNION ALL SELECT 'orders',           COUNT(*) FROM ecommerce.orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM ecommerce.order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM ecommerce.payments
UNION ALL SELECT 'returns',          COUNT(*) FROM ecommerce.returns
UNION ALL SELECT 'reviews',          COUNT(*) FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions', COUNT(*) FROM ecommerce.website_sessions;

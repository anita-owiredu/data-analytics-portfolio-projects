-- ============================================================================
-- Project : UK E-Commerce Analytics
-- Database: ecommerce_db (PostgreSQL) | Schema: ecommerce
-- 01. EXPLORATORY DATA ANALYSIS (volume, coverage and data checks)
--
-- Run after sql/00_schema_and_load.sql. Each check says what it expects. Nothing
-- here changes the data; the findings and the decisions taken are in section 6
-- of the README.
-- ============================================================================

-- Rows per table (expect 5000 / 504 / 15000 / 28331 / 15000 / 1233 / 11308 / 30000)
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM ecommerce.customers
UNION ALL SELECT 'products',         COUNT(*) FROM ecommerce.products
UNION ALL SELECT 'orders',           COUNT(*) FROM ecommerce.orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM ecommerce.order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM ecommerce.payments
UNION ALL SELECT 'returns',          COUNT(*) FROM ecommerce.returns
UNION ALL SELECT 'reviews',          COUNT(*) FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions', COUNT(*) FROM ecommerce.website_sessions;

-- Date coverage of each table
SELECT 'customers.signup_date' AS date_column, MIN(signup_date) AS first, MAX(signup_date) AS last FROM ecommerce.customers
UNION ALL SELECT 'orders.order_date',        MIN(order_date),    MAX(order_date)    FROM ecommerce.orders
UNION ALL SELECT 'orders.delivery_date',     MIN(delivery_date), MAX(delivery_date) FROM ecommerce.orders
UNION ALL SELECT 'payments.payment_date',    MIN(payment_date),  MAX(payment_date)  FROM ecommerce.payments
UNION ALL SELECT 'returns.return_date',      MIN(return_date),   MAX(return_date)   FROM ecommerce.returns
UNION ALL SELECT 'reviews.review_date',      MIN(review_date),   MAX(review_date)   FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions.session_date', MIN(session_date), MAX(session_date) FROM ecommerce.website_sessions;

-- NULLs that exist (everything else is NOT NULL in practice).
-- Expect: 2984 orders without a delivery date, 21 sessions without a customer.
SELECT
    (SELECT COUNT(*) FROM ecommerce.orders WHERE delivery_date IS NULL)            AS orders_no_delivery_date,
    (SELECT COUNT(*) FROM ecommerce.website_sessions WHERE customer_id IS NULL)    AS sessions_no_customer;

-- Orders with no delivery date, by status (expect: only Shipped, Processing, Cancelled)
SELECT order_status, COUNT(*) AS orders, COUNT(*) FILTER (WHERE delivery_date IS NULL) AS no_delivery_date
FROM ecommerce.orders
GROUP BY order_status
ORDER BY order_status;

-- Customers with no orders (expect 246)
SELECT COUNT(*) AS customers_without_orders
FROM ecommerce.customers c
WHERE NOT EXISTS (SELECT 1 FROM ecommerce.orders o WHERE o.customer_id = c.customer_id);

-- ----------------------------------------------------------------------------
-- Money checks
-- ----------------------------------------------------------------------------

-- Each line: item_total = quantity * unit_price - discount (expect 0 rows off)
SELECT COUNT(*) AS lines_off
FROM ecommerce.order_items
WHERE ABS(item_total - (quantity * unit_price - discount)) > 0.01;

-- Line unit_price equals the product's unit_price (expect 0 rows off)
SELECT COUNT(*) AS lines_price_differs
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
WHERE oi.unit_price <> p.unit_price;

-- Order total = sum of its lines + shipping - order discount (expect 67 off: see next check)
WITH basket AS (
    SELECT order_id, SUM(item_total) AS items FROM ecommerce.order_items GROUP BY order_id
)
SELECT COUNT(*) AS orders,
       COUNT(*) FILTER (WHERE ABS(o.total_amount - (b.items + o.shipping_cost - o.discount_amount)) > 0.01) AS orders_off
FROM ecommerce.orders o
JOIN basket b ON b.order_id = o.order_id;

-- The orders that are off: the total is 0 because the discount is larger than
-- the basket plus shipping (the total is floored at 0). Expect 67 rows, all with total 0.
WITH basket AS (
    SELECT order_id, SUM(item_total) AS items FROM ecommerce.order_items GROUP BY order_id
)
SELECT COUNT(*)                                   AS orders_off,
       COUNT(*) FILTER (WHERE o.total_amount = 0) AS with_total_zero,
       COUNT(*) FILTER (WHERE b.items + o.shipping_cost - o.discount_amount < 0) AS discount_exceeds_basket,
       COUNT(*) FILTER (WHERE o.order_status <> 'Cancelled') AS not_cancelled
FROM ecommerce.orders o
JOIN basket b ON b.order_id = o.order_id
WHERE ABS(o.total_amount - (b.items + o.shipping_cost - o.discount_amount)) > 0.01;

-- Payment amount equals order total, one payment per order (expect 0 rows off)
SELECT COUNT(*) AS payments, COUNT(DISTINCT p.order_id) AS orders_paid,
       COUNT(*) FILTER (WHERE ABS(p.amount - o.total_amount) > 0.01) AS amount_differs
FROM ecommerce.payments p
JOIN ecommerce.orders o ON o.order_id = p.order_id;

-- Order status against payment status.
-- Expect: Cancelled orders are either Refunded (544) or still Paid (221).
SELECT o.order_status, p.payment_status, COUNT(*) AS orders
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
GROUP BY o.order_status, p.payment_status
ORDER BY o.order_status, p.payment_status;

-- ----------------------------------------------------------------------------
-- Date and logic checks
-- ----------------------------------------------------------------------------

-- Delivery and payment dates are not before the order (expect 0), delivery takes 1-7 days
SELECT COUNT(*) FILTER (WHERE delivery_date < order_date) AS delivered_before_ordered,
       MIN(delivery_date - order_date)                    AS fastest_days,
       MAX(delivery_date - order_date)                    AS slowest_days
FROM ecommerce.orders;

SELECT COUNT(*) FILTER (WHERE p.payment_date < o.order_date) AS paid_before_ordered
FROM ecommerce.payments p
JOIN ecommerce.orders o ON o.order_id = p.order_id;

-- Returns: only on delivered orders, for a product that was in the order, no more
-- than the quantity bought, and not before the order (expect 0 for all four).
SELECT
    COUNT(*) FILTER (WHERE o.order_status <> 'Delivered')       AS return_on_undelivered_order,
    COUNT(*) FILTER (WHERE r.return_date < o.order_date)        AS returned_before_ordered,
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1 FROM ecommerce.order_items i
        WHERE i.order_id = r.order_id AND i.product_id = r.product_id)) AS product_not_in_order,
    COUNT(*) FILTER (WHERE r.quantity_returned > (
        SELECT COALESCE(SUM(i.quantity), 0) FROM ecommerce.order_items i
        WHERE i.order_id = r.order_id AND i.product_id = r.product_id)) AS more_than_bought
FROM ecommerce.returns r
JOIN ecommerce.orders o ON o.order_id = r.order_id;

-- Returns and reviews dated after the last order (not an error; both can follow an order)
SELECT
    (SELECT COUNT(*) FROM ecommerce.returns WHERE return_date > (SELECT MAX(order_date) FROM ecommerce.orders)) AS returns_after_last_order,
    (SELECT COUNT(*) FROM ecommerce.reviews WHERE review_date > (SELECT MAX(order_date) FROM ecommerce.orders)) AS reviews_after_last_order;

-- Verified reviews: the customer did buy the product (expect 0 without a purchase)
SELECT COUNT(*) AS verified_without_purchase
FROM ecommerce.reviews r
WHERE r.verified_purchase
  AND NOT EXISTS (
      SELECT 1
      FROM ecommerce.orders o
      JOIN ecommerce.order_items i ON i.order_id = o.order_id
      WHERE o.customer_id = r.customer_id AND i.product_id = r.product_id);

-- Customers who reviewed the same product more than once (expect 29 pairs)
SELECT COUNT(*) AS pairs_reviewed_twice
FROM (SELECT customer_id, product_id FROM ecommerce.reviews GROUP BY 1, 2 HAVING COUNT(*) > 1) x;

-- Website funnel flags are consistent: purchase implies checkout implies cart (expect 0, 0)
SELECT COUNT(*) FILTER (WHERE purchase_completed AND NOT checkout_started) AS purchase_without_checkout,
       COUNT(*) FILTER (WHERE checkout_started AND NOT added_to_cart)      AS checkout_without_cart
FROM ecommerce.website_sessions;

-- Product prices make sense (expect 0 rows off)
SELECT COUNT(*) FILTER (WHERE cost_price >= unit_price) AS cost_not_below_price,
       COUNT(*) FILTER (WHERE stock_quantity < 0)       AS negative_stock
FROM ecommerce.products;

-- ----------------------------------------------------------------------------
-- Customer date checks (these show the signup_date and date_of_birth problems)
-- ----------------------------------------------------------------------------

-- Activity dated before the customer's signup_date.
-- Expect roughly half of orders, reviews and sessions.
SELECT
    (SELECT COUNT(*) FROM ecommerce.orders o JOIN ecommerce.customers c USING (customer_id)
      WHERE o.order_date < c.signup_date)                                      AS orders_before_signup,
    (SELECT COUNT(*) FROM ecommerce.reviews r JOIN ecommerce.customers c USING (customer_id)
      WHERE r.review_date < c.signup_date)                                     AS reviews_before_signup,
    (SELECT COUNT(*) FROM ecommerce.website_sessions w JOIN ecommerce.customers c USING (customer_id)
      WHERE w.session_date < c.signup_date)                                    AS sessions_before_signup;

-- Customers whose first order is before their signup_date
-- (expect 3,373 of the 4,754 customers who have ordered; signup about 198 days later on average)
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM ecommerce.orders GROUP BY customer_id
)
SELECT COUNT(*)                                                       AS customers_with_orders,
       COUNT(*) FILTER (WHERE f.first_order_date < c.signup_date)     AS first_order_before_signup,
       ROUND(AVG(c.signup_date - f.first_order_date))                 AS avg_days_signup_after_first_order
FROM first_order f
JOIN ecommerce.customers c ON c.customer_id = f.customer_id;

-- Impossible or implausible ages (expect 72 born after signup, 2010 under 18 at signup)
SELECT COUNT(*) FILTER (WHERE date_of_birth > signup_date)            AS born_after_signup,
       COUNT(*) FILTER (WHERE signup_date - date_of_birth < 18 * 365) AS under_18_at_signup,
       MAX(date_of_birth)                                             AS latest_date_of_birth
FROM ecommerce.customers;


-- ----------------------------------------------------------------------------
-- Completeness, duplicates and place data
-- ----------------------------------------------------------------------------

-- Missing values in EVERY column of every table. Only two columns have any:
-- orders.delivery_date (2,984) and website_sessions.customer_id (21).
WITH rows_as_json AS (
    SELECT 'customers' AS table_name, to_jsonb(t) AS j FROM ecommerce.customers t
    UNION ALL SELECT 'products',         to_jsonb(t) FROM ecommerce.products t
    UNION ALL SELECT 'orders',           to_jsonb(t) FROM ecommerce.orders t
    UNION ALL SELECT 'order_items',      to_jsonb(t) FROM ecommerce.order_items t
    UNION ALL SELECT 'payments',         to_jsonb(t) FROM ecommerce.payments t
    UNION ALL SELECT 'returns',          to_jsonb(t) FROM ecommerce.returns t
    UNION ALL SELECT 'reviews',          to_jsonb(t) FROM ecommerce.reviews t
    UNION ALL SELECT 'website_sessions', to_jsonb(t) FROM ecommerce.website_sessions t
)
SELECT table_name, key AS column_name, COUNT(*) AS missing_values
FROM rows_as_json, jsonb_each(j)
WHERE value = 'null'::jsonb
GROUP BY table_name, key
ORDER BY table_name, key;

-- Duplicates: the same product twice in one order, and the same customer twice (expect 0 and 0)
SELECT
    (SELECT COUNT(*) FROM (SELECT order_id, product_id FROM ecommerce.order_items
                           GROUP BY order_id, product_id HAVING COUNT(*) > 1) d)              AS products_repeated_in_an_order,
    (SELECT COUNT(*) FROM (SELECT customer_name, date_of_birth, postcode FROM ecommerce.customers
                           GROUP BY 1, 2, 3 HAVING COUNT(*) > 1) d)                           AS duplicate_customers;

-- Each city belongs to one region (expect 16 of 16)
SELECT COUNT(*) AS cities, COUNT(*) FILTER (WHERE regions = 1) AS cities_in_one_region
FROM (SELECT city, COUNT(DISTINCT region) AS regions FROM ecommerce.customers GROUP BY city) t;

-- The postcode column does not hold postcodes: none is in UK postcode format, the values are street
-- addresses such as '10 High Road', and almost every value appears in more than one city.
-- Customer names are all generic placeholders ('Customer_00001'). Place analysis therefore uses city only.
SELECT COUNT(*)                                                                         AS customers,
       COUNT(*) FILTER (WHERE postcode ~ '^[A-Z]{1,2}[0-9][0-9A-Z]? ?[0-9][A-Z]{2}$')   AS in_uk_postcode_format,
       COUNT(DISTINCT postcode)                                                         AS distinct_values,
       (SELECT COUNT(*) FROM (SELECT postcode FROM ecommerce.customers
                              GROUP BY postcode HAVING COUNT(DISTINCT city) > 1) x)    AS values_found_in_2_or_more_cities,
       COUNT(*) FILTER (WHERE customer_name ~ '^Customer_[0-9]{5}$')                    AS placeholder_names
FROM ecommerce.customers;

-- Unusually large orders: above the usual cut-off for outliers (third quartile + 1.5 x the quartile range).
-- These are real large baskets (up to 5 lines), not errors, so they are kept.
WITH q AS (
    SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_amount) AS q1,
           PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_amount) AS q3
    FROM ecommerce.orders
)
SELECT ROUND((q3 + 1.5 * (q3 - q1))::numeric)                                                  AS cut_off,
       COUNT(*) FILTER (WHERE total_amount > q3 + 1.5 * (q3 - q1))                             AS orders_above_cut_off,
       ROUND(100.0 * COUNT(*) FILTER (WHERE total_amount > q3 + 1.5 * (q3 - q1)) / COUNT(*), 1) AS pct_of_orders,
       ROUND(MAX(total_amount))                                                                AS largest_order
FROM ecommerce.orders, q
GROUP BY q1, q3;

-- ----------------------------------------------------------------------------
-- The compact checks shown in the README (section 6). They repeat the checks above
-- in a short form, so the queries in the README can be run as they appear.
-- ----------------------------------------------------------------------------

-- Rows in each table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM ecommerce.customers
UNION ALL SELECT 'products',         COUNT(*) FROM ecommerce.products
UNION ALL SELECT 'orders',           COUNT(*) FROM ecommerce.orders
UNION ALL SELECT 'order_items',      COUNT(*) FROM ecommerce.order_items
UNION ALL SELECT 'payments',         COUNT(*) FROM ecommerce.payments
UNION ALL SELECT 'returns',          COUNT(*) FROM ecommerce.returns
UNION ALL SELECT 'reviews',          COUNT(*) FROM ecommerce.reviews
UNION ALL SELECT 'website_sessions', COUNT(*) FROM ecommerce.website_sessions;

-- Missing values in every column of every table (only two columns have any)
WITH rows_as_json AS (
    SELECT 'customers' AS table_name, to_jsonb(t) AS j FROM ecommerce.customers t
    UNION ALL SELECT 'products',         to_jsonb(t) FROM ecommerce.products t
    UNION ALL SELECT 'orders',           to_jsonb(t) FROM ecommerce.orders t
    UNION ALL SELECT 'order_items',      to_jsonb(t) FROM ecommerce.order_items t
    UNION ALL SELECT 'payments',         to_jsonb(t) FROM ecommerce.payments t
    UNION ALL SELECT 'returns',          to_jsonb(t) FROM ecommerce.returns t
    UNION ALL SELECT 'reviews',          to_jsonb(t) FROM ecommerce.reviews t
    UNION ALL SELECT 'website_sessions', to_jsonb(t) FROM ecommerce.website_sessions t
)
SELECT table_name, key AS column_name, COUNT(*) AS missing_values
FROM rows_as_json, jsonb_each(j)
WHERE value = 'null'::jsonb
GROUP BY table_name, key
ORDER BY table_name, key;

-- Does each order's total equal its items plus shipping minus the order discount?
WITH basket AS (
    SELECT order_id, SUM(item_total) AS items FROM ecommerce.order_items GROUP BY order_id
)
SELECT COUNT(*)                                                         AS orders,
       COUNT(*) FILTER (WHERE ABS(o.total_amount - (b.items + o.shipping_cost - o.discount_amount)) > 0.01) AS orders_that_do_not_add_up,
       COUNT(*) FILTER (WHERE o.total_amount = 0)                       AS orders_with_a_zero_total
FROM ecommerce.orders o
JOIN basket b ON b.order_id = o.order_id;

-- How many customers placed their first order before their signup date?
WITH first_order AS (
    SELECT customer_id, MIN(order_date) AS first_order_date
    FROM ecommerce.orders GROUP BY customer_id
)
SELECT COUNT(*)                                                       AS customers_with_orders,
       COUNT(*) FILTER (WHERE f.first_order_date < c.signup_date)     AS first_order_before_signup,
       ROUND(AVG(c.signup_date - f.first_order_date))                 AS avg_days_signup_after_first_order
FROM first_order f
JOIN ecommerce.customers c ON c.customer_id = f.customer_id;

-- Dates of birth that cannot be right
SELECT COUNT(*) FILTER (WHERE date_of_birth > signup_date)            AS born_after_signup,
       COUNT(*) FILTER (WHERE signup_date - date_of_birth < 18 * 365) AS under_18_at_signup,
       MAX(date_of_birth)                                             AS latest_date_of_birth
FROM ecommerce.customers;

-- The postcode column: none is in UK postcode format, and the names are placeholders
SELECT COUNT(*)                                                                         AS customers,
       COUNT(*) FILTER (WHERE postcode ~ '^[A-Z]{1,2}[0-9][0-9A-Z]? ?[0-9][A-Z]{2}$')   AS in_uk_postcode_format,
       COUNT(*) FILTER (WHERE customer_name ~ '^Customer_[0-9]{5}$')                    AS placeholder_names
FROM ecommerce.customers;

-- Cancelled orders whose payment is still marked Paid
SELECT COUNT(*)                   AS cancelled_but_paid,
       ROUND(SUM(o.total_amount)) AS value
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status = 'Cancelled' AND p.payment_status = 'Paid';

-- Orders still Shipped or Processing more than 90 days after the order
SELECT order_status,
       COUNT(*)                         AS orders,
       COUNT(*) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - order_date > 90) AS older_than_90_days,
       ROUND(SUM(total_amount) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - order_date > 90)) AS value_older_than_90_days
FROM ecommerce.orders
WHERE order_status IN ('Shipped', 'Processing')
GROUP BY order_status
ORDER BY order_status;

-- Products that were never returned. Joined to the returns table, their return fields are NULL.
SELECT COUNT(DISTINCT p.product_id)  AS products_never_returned,
       ROUND(SUM(oi.item_total))     AS item_sales
FROM ecommerce.products p
JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
LEFT JOIN ecommerce.returns r ON r.product_id = p.product_id
WHERE r.return_id IS NULL;

-- ============================================================================
-- PART 2. EXPLORATION (distributions, outliers, relationships, patterns over time)
-- Descriptive profiling of every table, on all orders (the dashboard basis).
-- The checks quoted in the README on whether a difference is real were run on
-- the counts these queries return.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Orders: value, size, discounts and shipping
-- ----------------------------------------------------------------------------

-- Order value distribution: skewed, so the average is well above the typical order
SELECT COUNT(*)                                                            AS orders,
       ROUND(MIN(total_amount), 2)                                         AS min,
       ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY total_amount)::numeric, 2) AS p25,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY total_amount)::numeric, 2) AS typical_order,
       ROUND(AVG(total_amount), 2)                                         AS mean,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY total_amount)::numeric, 2) AS p75,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_amount)::numeric, 2) AS p95,
       ROUND(MAX(total_amount), 2)                                         AS max
FROM ecommerce.orders;

-- Product lines per order, and quantity per line
SELECT lines AS lines_in_order, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM (SELECT order_id, COUNT(*) AS lines FROM ecommerce.order_items GROUP BY order_id) t
GROUP BY lines ORDER BY lines;

SELECT quantity, COUNT(*) AS lines, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM ecommerce.order_items GROUP BY quantity ORDER BY quantity;

-- Discounts: order-level (a fixed amount off the order) and line-level (a percentage off a line)
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE discount_amount > 0) / COUNT(*), 1)                AS pct_orders_with_order_discount,
    ROUND(AVG(discount_amount) FILTER (WHERE discount_amount > 0), 2)                       AS avg_order_discount,
    ROUND(MAX(discount_amount), 2)                                                          AS max_order_discount,
    ROUND(SUM(discount_amount))                                                             AS total_order_discounts,
    (SELECT ROUND(SUM(discount)) FROM ecommerce.order_items)                                AS total_line_discounts,
    (SELECT ROUND(SUM(quantity * unit_price)) FROM ecommerce.order_items)                   AS gross_item_value,
    ROUND(100.0 * (SUM(discount_amount) + (SELECT SUM(discount) FROM ecommerce.order_items))
          / (SELECT SUM(quantity * unit_price) FROM ecommerce.order_items), 1)             AS total_discount_pct_of_gross
FROM ecommerce.orders;

-- Order discounts are not scaled to the basket: orders whose discount is more than half the basket
WITH basket AS (SELECT order_id, SUM(item_total) AS items FROM ecommerce.order_items GROUP BY order_id)
SELECT COUNT(*) FILTER (WHERE o.discount_amount > 0.5 * b.items)                     AS orders_discount_over_half_basket,
       ROUND(100.0 * COUNT(*) FILTER (WHERE o.discount_amount > 0.5 * b.items) / COUNT(*), 1) AS pct_of_orders,
       ROUND(AVG(o.discount_amount) FILTER (WHERE o.discount_amount > 0.5 * b.items), 2) AS avg_discount,
       ROUND(AVG(b.items) FILTER (WHERE o.discount_amount > 0.5 * b.items), 2)       AS avg_basket
FROM ecommerce.orders o JOIN basket b ON b.order_id = o.order_id;

-- Shipping fee rule: free from a £60 basket, otherwise £2.99, £4.99 or £6.99; Next Day is priced like Standard
WITH basket AS (SELECT order_id, SUM(item_total) AS items FROM ecommerce.order_items GROUP BY order_id)
SELECT o.shipping_method, o.shipping_cost,
       COUNT(*)                         AS orders,
       ROUND(MIN(b.items))              AS lowest_basket,
       ROUND(MAX(b.items))              AS highest_basket
FROM ecommerce.orders o JOIN basket b ON b.order_id = o.order_id
GROUP BY o.shipping_method, o.shipping_cost
ORDER BY o.shipping_method, o.shipping_cost;

-- ----------------------------------------------------------------------------
-- Products: price, margin, concentration
-- ----------------------------------------------------------------------------

SELECT category, COUNT(*) AS products,
       ROUND(MIN(unit_price), 2) AS min_price, ROUND(AVG(unit_price), 2) AS mean_price, ROUND(MAX(unit_price), 2) AS max_price,
       ROUND(AVG(100 * (unit_price - cost_price) / unit_price), 1) AS avg_margin_pct
FROM ecommerce.products GROUP BY category ORDER BY mean_price DESC;

-- Every product is sold (37 to 104 units); revenue follows price, not units sold
WITH sales AS (
    SELECT p.product_id, p.unit_price, SUM(oi.quantity) AS units, SUM(oi.item_total) AS revenue
    FROM ecommerce.products p JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
    GROUP BY p.product_id, p.unit_price
)
SELECT COUNT(*) AS products_sold, MIN(units) AS fewest_units, MAX(units) AS most_units,
       ROUND(CORR(unit_price, units)::numeric, 2)   AS corr_price_units,
       ROUND(CORR(unit_price, revenue)::numeric, 2) AS corr_price_revenue
FROM sales;

-- Concentration: share of item sales from the top 10%, 20% and 50% of products
WITH r AS (
    SELECT product_id, SUM(item_total) AS revenue FROM ecommerce.order_items GROUP BY product_id
),
ranked AS (
    SELECT revenue, ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rn, COUNT(*) OVER () AS n,
           SUM(revenue) OVER (ORDER BY revenue DESC) AS cum, SUM(revenue) OVER () AS total
    FROM r
)
SELECT ROUND(100.0 * MAX(cum) FILTER (WHERE rn <= n * 0.1) / MAX(total), 1) AS top_10_pct_products,
       ROUND(100.0 * MAX(cum) FILTER (WHERE rn <= n * 0.2) / MAX(total), 1) AS top_20_pct_products,
       ROUND(100.0 * MAX(cum) FILTER (WHERE rn <= n * 0.5) / MAX(total), 1) AS top_50_pct_products
FROM ranked;

-- ----------------------------------------------------------------------------
-- Customers: demographics and ordering rhythm
-- ----------------------------------------------------------------------------

SELECT gender, COUNT(*) AS customers, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM ecommerce.customers GROUP BY gender ORDER BY customers DESC;

-- Age at the end of the data, by band: ages run from 0 to 48 and 42% are under 20 (not plausible)
SELECT CASE WHEN age < 10 THEN '0-9' WHEN age < 20 THEN '10-19' WHEN age < 30 THEN '20-29'
            WHEN age < 40 THEN '30-39' ELSE '40-48' END AS age_band,
       COUNT(*) AS customers, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM (SELECT EXTRACT(YEAR FROM age(DATE '2026-06-30', date_of_birth))::int AS age FROM ecommerce.customers) t
GROUP BY 1 ORDER BY 1;

-- Time between orders, and customers who have gone a year or more: moved to sql/03_business_questions.sql (Q4), which is where the README quotes it.

-- ----------------------------------------------------------------------------
-- Time patterns: do orders and sign-ups follow a weekly or yearly pattern?
-- ----------------------------------------------------------------------------

-- Orders by weekday: even
SELECT to_char(order_date, 'ID Dy') AS weekday, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct, ROUND(AVG(total_amount), 1) AS avg_order_value
FROM ecommerce.orders GROUP BY 1 ORDER BY 1;

-- Orders per day: variance divided by mean is 1.03, which is what random arrivals give (1.00)
WITH daily AS (SELECT order_date, COUNT(*) AS n FROM ecommerce.orders GROUP BY order_date)
SELECT COUNT(*) AS days, ROUND(AVG(n), 2) AS mean_orders, ROUND(STDDEV(n), 2) AS sd_orders,
       ROUND(VARIANCE(n) / AVG(n), 2) AS variance_to_mean, MIN(n) AS fewest, MAX(n) AS most
FROM daily;

-- Seasonality by calendar month, for orders and sign-ups, against the days each month is observed
-- (orders run to 29 Jun 2026, sign-ups to 30 Jun 2026). Comparing each month's count with what its
-- length alone would predict, sign-ups show a real seasonal pattern, driven by June; orders do not.
WITH order_days AS (
    SELECT EXTRACT(MONTH FROM d)::int AS month_number, COUNT(*) AS days_observed
    FROM generate_series(DATE '2024-01-01', DATE '2026-06-29', INTERVAL '1 day') AS d GROUP BY 1
),
signup_days AS (
    SELECT EXTRACT(MONTH FROM d)::int AS month_number, COUNT(*) AS days_observed
    FROM generate_series(DATE '2024-01-01', DATE '2026-06-30', INTERVAL '1 day') AS d GROUP BY 1
),
orders  AS (SELECT EXTRACT(MONTH FROM order_date)::int  AS month_number, COUNT(*) AS orders  FROM ecommerce.orders    GROUP BY 1),
signups AS (SELECT EXTRACT(MONTH FROM signup_date)::int AS month_number, COUNT(*) AS signups FROM ecommerce.customers GROUP BY 1)
SELECT od.month_number,
       o.orders,
       ROUND(((o.orders::numeric  / od.days_observed) / (SUM(o.orders)  OVER () / SUM(od.days_observed) OVER ())), 3) AS orders_per_day_index,
       s.signups,
       ROUND(((s.signups::numeric / sd.days_observed) / (SUM(s.signups) OVER () / SUM(sd.days_observed) OVER ())), 3) AS signups_per_day_index
FROM order_days od
JOIN signup_days sd ON sd.month_number = od.month_number
JOIN orders  o ON o.month_number = od.month_number
JOIN signups s ON s.month_number = od.month_number
ORDER BY od.month_number;

-- ----------------------------------------------------------------------------
-- Reviews: ratings
-- ----------------------------------------------------------------------------

SELECT rating, COUNT(*) AS reviews, ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM ecommerce.reviews GROUP BY rating ORDER BY rating;

-- Do products really differ in rating? The spread of product averages (about 0.22) is
-- what sampling alone gives (about 0.23 for ~22 reviews each), and ratings do not relate
-- to returns or sales volume.
WITH per_product AS (
    SELECT product_id, COUNT(*) AS n, AVG(rating) AS avg_rating FROM ecommerce.reviews GROUP BY product_id
),
overall AS (SELECT STDDEV_SAMP(rating) AS sd FROM ecommerce.reviews)
SELECT COUNT(*) AS products_reviewed, MIN(n) AS fewest_reviews, ROUND(AVG(n), 1) AS mean_reviews, MAX(n) AS most_reviews,
       ROUND(STDDEV_SAMP(avg_rating)::numeric, 2)                              AS sd_of_product_averages,
       ROUND(AVG((SELECT sd FROM overall) / SQRT(n))::numeric, 2)              AS sd_expected_from_sampling
FROM per_product;

WITH sold AS (
    SELECT oi.product_id, COUNT(*) AS lines FROM ecommerce.order_items oi
    JOIN ecommerce.orders o ON o.order_id = oi.order_id WHERE o.order_status = 'Delivered' GROUP BY oi.product_id
),
ret AS (SELECT product_id, COUNT(*) AS returns FROM ecommerce.returns GROUP BY product_id),
rt  AS (SELECT product_id, AVG(rating) AS avg_rating FROM ecommerce.reviews GROUP BY product_id)
SELECT ROUND(CORR(rt.avg_rating, 100.0 * COALESCE(ret.returns, 0) / sold.lines)::numeric, 2) AS corr_rating_return_rate,
       ROUND(CORR(rt.avg_rating, sold.lines)::numeric, 2)                                    AS corr_rating_sales_volume
FROM sold JOIN rt USING (product_id) LEFT JOIN ret USING (product_id);

-- ----------------------------------------------------------------------------
-- Website sessions
-- ----------------------------------------------------------------------------

-- Pages viewed and time on site against buying: moved to sql/03_business_questions.sql (Q5), which is where the README quotes it.

-- Conversion by year (the drift from 7.7% to 7.1% is too small to call a trend)
SELECT EXTRACT(YEAR FROM session_date)::int AS year, COUNT(*) AS sessions,
       COUNT(*) FILTER (WHERE purchase_completed) AS purchases,
       ROUND(100.0 * AVG(purchase_completed::int), 2) AS conversion_pct
FROM ecommerce.website_sessions GROUP BY 1 ORDER BY 1;

-- ----------------------------------------------------------------------------
-- Returns: timing, size and refund rule
-- ----------------------------------------------------------------------------

-- Days from order to return
SELECT ROUND(AVG(r.return_date - o.order_date), 1) AS avg_days, MIN(r.return_date - o.order_date) AS fastest,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.return_date - o.order_date)::numeric) AS typical_days,
       MAX(r.return_date - o.order_date) AS slowest
FROM ecommerce.returns r JOIN ecommerce.orders o ON o.order_id = r.order_id;

-- Refunds against what customers paid: moved to sql/03_business_questions.sql (Q6), which is where the README quotes it.

-- Does any product's return rate stand out from the rest: moved to sql/03_business_questions.sql (Q6), which is where the README quotes it.

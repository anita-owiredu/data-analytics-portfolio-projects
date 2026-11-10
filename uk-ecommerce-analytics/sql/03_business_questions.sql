-- UK E-Commerce: business questions

-- Sales & Profitability

-- Q1. Is revenue growing?

-- Total revenue, average order value and year-on-year growth
SELECT
    ROUND(SUM(total_amount))                                        AS total_revenue,
    ROUND(AVG(total_amount))                                        AS average_order_value,
    ROUND(100.0 * (SUM(total_amount) FILTER (WHERE EXTRACT(YEAR FROM order_date) = 2025)
                 - SUM(total_amount) FILTER (WHERE EXTRACT(YEAR FROM order_date) = 2024))
          / SUM(total_amount) FILTER (WHERE EXTRACT(YEAR FROM order_date) = 2024), 1) AS yoy_growth_2025_vs_2024_pct
FROM ecommerce.orders;

-- Revenue and orders by year, and for the first half of each year
SELECT
    EXTRACT(YEAR FROM order_date)::int                                              AS year,
    COUNT(*)                                                                        AS orders,
    ROUND(SUM(total_amount))                                                        AS revenue,
    COUNT(*) FILTER (WHERE EXTRACT(MONTH FROM order_date) <= 6)                     AS h1_orders,
    ROUND(SUM(total_amount) FILTER (WHERE EXTRACT(MONTH FROM order_date) <= 6))     AS h1_revenue
FROM ecommerce.orders
GROUP BY 1
ORDER BY 1;

-- Headline figures without cancelled orders: orders, revenue, order value, gross profit
SELECT
    (SELECT COUNT(*) FROM ecommerce.orders WHERE order_status <> 'Cancelled')                AS orders,
    (SELECT ROUND(SUM(total_amount)) FROM ecommerce.orders WHERE order_status <> 'Cancelled') AS revenue,
    (SELECT ROUND(AVG(total_amount)) FROM ecommerce.orders WHERE order_status <> 'Cancelled') AS aov,
    (SELECT ROUND(SUM(oi.quantity * (oi.unit_price - p.cost_price) - oi.discount))
       FROM ecommerce.order_items oi
       JOIN ecommerce.products p ON p.product_id = oi.product_id
       JOIN ecommerce.orders   o ON o.order_id   = oi.order_id
      WHERE o.order_status <> 'Cancelled')                                                    AS gross_profit,
    (SELECT ROUND(100.0 * SUM(oi.quantity * (oi.unit_price - p.cost_price) - oi.discount)
                  / SUM(oi.item_total), 1)
       FROM ecommerce.order_items oi
       JOIN ecommerce.products p ON p.product_id = oi.product_id
       JOIN ecommerce.orders   o ON o.order_id   = oi.order_id
      WHERE o.order_status <> 'Cancelled')                                                    AS gross_margin_pct;

-- Same by year, without cancelled orders
SELECT
    EXTRACT(YEAR FROM order_date)::int                                                       AS year,
    COUNT(*)                                                                                 AS orders,
    ROUND(SUM(total_amount))                                                                 AS revenue,
    ROUND(AVG(total_amount))                                                                 AS aov,
    COUNT(*) FILTER (WHERE EXTRACT(MONTH FROM order_date) <= 6)                              AS h1_orders,
    ROUND(SUM(total_amount) FILTER (WHERE EXTRACT(MONTH FROM order_date) <= 6))              AS h1_revenue
FROM ecommerce.orders
WHERE order_status <> 'Cancelled'
GROUP BY 1
ORDER BY 1;

-- Monthly revenue and orders (cancelled orders left out)
SELECT
    date_trunc('month', order_date)::date AS month,
    COUNT(DISTINCT order_id)               AS orders,
    ROUND(SUM(total_amount), 2)            AS revenue
FROM ecommerce.orders
WHERE order_status != 'Cancelled'
GROUP BY 1
ORDER BY 1;

-- Average order value by month
SELECT
    date_trunc('month', order_date)::date AS month,
    ROUND(AVG(total_amount), 2)            AS aov
FROM ecommerce.orders
WHERE order_status != 'Cancelled'
GROUP BY 1
ORDER BY 1;

-- Which months grew the most on the month before?
WITH monthly AS (
    SELECT
        date_trunc('month', order_date)::date AS month,
        SUM(total_amount)                       AS revenue
    FROM ecommerce.orders
    WHERE order_status != 'Cancelled'
    GROUP BY 1
)
SELECT
    month,
    ROUND(revenue, 2)                                                       AS revenue,
    ROUND(revenue - LAG(revenue) OVER (ORDER BY month), 2)                  AS mom_change,
    ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
          / NULLIF(LAG(revenue) OVER (ORDER BY month), 0), 2)              AS mom_growth_pct
FROM monthly
ORDER BY mom_growth_pct DESC NULLS LAST
LIMIT 5;

-- What share of orders are cancelled?
SELECT
    COUNT(*)                                                           AS total_orders,
    COUNT(*) FILTER (WHERE order_status = 'Cancelled')                 AS cancelled_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Cancelled') / COUNT(*), 2) AS pct_cancelled
FROM ecommerce.orders;

-- Cancellation rate by year and half-year
SELECT
    EXTRACT(YEAR FROM order_date)::int                                     AS year,
    CASE WHEN EXTRACT(MONTH FROM order_date) <= 6 THEN 'H1' ELSE 'H2' END  AS half,
    COUNT(*)                                                               AS orders,
    COUNT(*) FILTER (WHERE order_status = 'Cancelled')                     AS cancelled,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Cancelled') / COUNT(*), 1) AS cancellation_rate_pct
FROM ecommerce.orders
GROUP BY 1, 2
ORDER BY 1, 2;

-- Does cancellation differ by shipping, payment, channel, region, order value or weekday?
WITH o AS (
    SELECT o.order_id,
           (o.order_status = 'Cancelled')                      AS cancelled,
           o.shipping_method,
           p.payment_method,
           c.acquisition_channel,
           c.region,
           CASE WHEN o.total_amount < 50  THEN '1 under £50'
                WHEN o.total_amount < 100 THEN '2 £50-99'
                WHEN o.total_amount < 150 THEN '3 £100-149'
                ELSE '4 £150 and over' END                     AS order_value,
           to_char(o.order_date, 'ID Dy')                      AS weekday
    FROM ecommerce.orders o
    JOIN ecommerce.customers c ON c.customer_id = o.customer_id
    JOIN ecommerce.payments  p ON p.order_id    = o.order_id
),
long AS (
    SELECT 'shipping method' AS dimension, shipping_method AS grp, cancelled FROM o
    UNION ALL SELECT 'payment method',      payment_method,      cancelled FROM o
    UNION ALL SELECT 'acquisition channel', acquisition_channel, cancelled FROM o
    UNION ALL SELECT 'region',              region,              cancelled FROM o
    UNION ALL SELECT 'order value',         order_value,         cancelled FROM o
    UNION ALL SELECT 'weekday',             weekday,             cancelled FROM o
)
SELECT dimension, grp,
       COUNT(*)                                              AS orders,
       COUNT(*) FILTER (WHERE cancelled)                     AS cancelled,
       ROUND(100.0 * COUNT(*) FILTER (WHERE cancelled) / COUNT(*), 1) AS cancellation_rate_pct
FROM long
GROUP BY dimension, grp
ORDER BY dimension, cancellation_rate_pct DESC;

-- Were cancelled orders refunded or still paid?
SELECT
    'all cancelled orders' AS grp,
    COUNT(*)                                                                 AS cancelled,
    COUNT(*) FILTER (WHERE p.payment_status = 'Refunded')                    AS refunded,
    COUNT(*) FILTER (WHERE p.payment_status = 'Paid')                        AS still_paid,
    ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'Paid') / COUNT(*), 1) AS pct_still_paid,
    ROUND(SUM(o.total_amount) FILTER (WHERE p.payment_status = 'Paid'))      AS value_still_paid
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status = 'Cancelled'
UNION ALL
SELECT EXTRACT(YEAR FROM o.order_date)::text,
       COUNT(*),
       COUNT(*) FILTER (WHERE p.payment_status = 'Refunded'),
       COUNT(*) FILTER (WHERE p.payment_status = 'Paid'),
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'Paid') / COUNT(*), 1),
       ROUND(SUM(o.total_amount) FILTER (WHERE p.payment_status = 'Paid'))
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status = 'Cancelled'
GROUP BY EXTRACT(YEAR FROM o.order_date)
UNION ALL
SELECT p.payment_method,
       COUNT(*),
       COUNT(*) FILTER (WHERE p.payment_status = 'Refunded'),
       COUNT(*) FILTER (WHERE p.payment_status = 'Paid'),
       ROUND(100.0 * COUNT(*) FILTER (WHERE p.payment_status = 'Paid') / COUNT(*), 1),
       ROUND(SUM(o.total_amount) FILTER (WHERE p.payment_status = 'Paid'))
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status = 'Cancelled'
GROUP BY p.payment_method;

-- Are cancellations concentrated in certain customers?
WITH per_customer AS (
    SELECT customer_id,
           COUNT(*)                                        AS orders,
           COUNT(*) FILTER (WHERE order_status = 'Cancelled') AS cancelled
    FROM ecommerce.orders
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                                                AS customers_with_orders,
    COUNT(*) FILTER (WHERE cancelled >= 1)                                  AS with_a_cancellation,
    COUNT(*) FILTER (WHERE cancelled >= 2)                                  AS with_two_or_more,
    ROUND(100.0 * COUNT(*) FILTER (WHERE cancelled >= 1) / COUNT(*), 1)     AS pct_with_a_cancellation,
    ROUND(100 * (1 - POWER(1 - (SELECT 1.0 * COUNT(*) FILTER (WHERE order_status = 'Cancelled') / COUNT(*)
                                  FROM ecommerce.orders), AVG(orders))), 1) AS pct_if_random
FROM per_customer;

-- Do customers order again after a cancelled order, compared with a delivered one?
SELECT
    o.order_status,
    COUNT(*)                                                                AS orders,
    COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM ecommerce.orders later
        WHERE later.customer_id = o.customer_id
          AND later.order_date  > o.order_date
          AND later.order_status <> 'Cancelled'))                           AS customer_ordered_again,
    ROUND(100.0 * COUNT(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM ecommerce.orders later
        WHERE later.customer_id = o.customer_id
          AND later.order_date  > o.order_date
          AND later.order_status <> 'Cancelled')) / COUNT(*), 1)            AS pct_ordered_again
FROM ecommerce.orders o
WHERE o.order_status IN ('Cancelled', 'Delivered')
GROUP BY o.order_status
ORDER BY o.order_status;

-- Which orders are stuck as Shipped or Processing?
SELECT
    o.order_status,
    COUNT(*)                                                                AS orders,
    COUNT(*) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - o.order_date > 30) AS older_than_30_days,
    COUNT(*) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - o.order_date > 90) AS older_than_90_days,
    ROUND(SUM(o.total_amount) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - o.order_date > 90)) AS value_older_than_90_days,
    COUNT(*) FILTER (WHERE p.payment_status = 'Pending')                    AS payment_pending,
    MIN(o.order_date)                                                       AS oldest_order
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status IN ('Shipped', 'Processing')
GROUP BY o.order_status
ORDER BY o.order_status;

-- How do stuck orders spread across quarters?
SELECT
    to_char(date_trunc('quarter', order_date), 'YYYY"-Q"Q')                 AS quarter,
    COUNT(*)                                                                AS orders,
    COUNT(*) FILTER (WHERE order_status IN ('Shipped', 'Processing'))       AS still_shipped_or_processing,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_status IN ('Shipped', 'Processing')) / COUNT(*), 1) AS pct
FROM ecommerce.orders
GROUP BY date_trunc('quarter', order_date)
ORDER BY date_trunc('quarter', order_date);

-- Which cancelled orders were paid and not refunded?
SELECT COUNT(*)                       AS cancelled_but_paid,
       ROUND(SUM(o.total_amount))     AS value
FROM ecommerce.orders o
JOIN ecommerce.payments p ON p.order_id = o.order_id
WHERE o.order_status = 'Cancelled' AND p.payment_status = 'Paid';

-- How much of the sales figure is cancelled orders?
SELECT
    ROUND(SUM(total_amount))                                                       AS dashboard_revenue,
    ROUND(SUM(total_amount) FILTER (WHERE order_status <> 'Cancelled'))            AS realised_revenue,
    ROUND(SUM(total_amount) FILTER (WHERE order_status = 'Cancelled'))             AS cancelled_revenue,
    ROUND(100.0 * SUM(total_amount) FILTER (WHERE order_status = 'Cancelled') / SUM(total_amount), 1) AS cancelled_pct,
    COUNT(*)                                                                       AS dashboard_orders,
    COUNT(*) FILTER (WHERE order_status <> 'Cancelled')                            AS realised_orders
FROM ecommerce.orders;

-- Q2. What drives sales and profit?

-- Which categories sell the most?
SELECT
    p.category,
    ROUND(SUM(oi.item_total))                                       AS item_sales,
    ROUND(100.0 * SUM(oi.item_total) / SUM(SUM(oi.item_total)) OVER (), 1) AS share_pct
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
GROUP BY p.category
ORDER BY item_sales DESC;

-- Which 10 products sell the most?
SELECT
    p.product_name,
    p.category,
    ROUND(SUM(oi.item_total))                                                AS item_sales,
    ROUND(100.0 * SUM(oi.item_total) / SUM(SUM(oi.item_total)) OVER (), 1)   AS pct_of_item_sales
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY item_sales DESC
LIMIT 10;

-- How much do the top 10 products add up to?
WITH product_sales AS (
    SELECT p.product_id, p.category, SUM(oi.item_total) AS item_sales
    FROM ecommerce.order_items oi
    JOIN ecommerce.products p ON p.product_id = oi.product_id
    GROUP BY p.product_id, p.category
),
top_10 AS (
    SELECT * FROM product_sales ORDER BY item_sales DESC LIMIT 10
)
SELECT ROUND(SUM(item_sales))                                                  AS top_10_sales,
       ROUND(100.0 * SUM(item_sales) / (SELECT SUM(item_sales) FROM product_sales), 1) AS pct_of_item_sales,
       COUNT(DISTINCT category)                                                AS categories_covered
FROM top_10;

-- Which products were never returned, and how well do they sell?
WITH sales AS (
    SELECT p.product_id, p.product_name,
           SUM(oi.item_total)                                         AS item_sales,
           RANK() OVER (ORDER BY SUM(oi.item_total) DESC)             AS sales_rank,
           NOT EXISTS (SELECT 1 FROM ecommerce.returns r WHERE r.product_id = p.product_id) AS has_no_returns
    FROM ecommerce.products p
    JOIN ecommerce.order_items oi ON oi.product_id = p.product_id
    GROUP BY p.product_id, p.product_name
)
SELECT COUNT(*) FILTER (WHERE has_no_returns)                                           AS products_with_no_returns,
       ROUND(SUM(item_sales) FILTER (WHERE has_no_returns))                             AS item_sales,
       ROUND(100.0 * SUM(item_sales) FILTER (WHERE has_no_returns) / SUM(item_sales), 1) AS pct_of_all_item_sales,
       MIN(sales_rank) FILTER (WHERE has_no_returns)                                    AS best_rank_among_them,
       (SELECT product_name FROM sales WHERE has_no_returns ORDER BY sales_rank LIMIT 1) AS best_selling_of_them
FROM sales;

-- Which 10 products bring in the most revenue?
SELECT
    p.product_name,
    p.category,
    ROUND(SUM(oi.item_total), 2) AS revenue
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
JOIN ecommerce.orders   o ON o.order_id   = oi.order_id
WHERE o.order_status != 'Cancelled'
GROUP BY p.product_id, p.product_name, p.category
ORDER BY revenue DESC
LIMIT 10;

-- Which categories make the most gross profit?
SELECT
    p.category,
    ROUND(SUM(oi.quantity * (oi.unit_price - p.cost_price) - oi.discount), 2) AS gross_profit
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
JOIN ecommerce.orders   o ON o.order_id   = oi.order_id
WHERE o.order_status != 'Cancelled'
GROUP BY p.category
ORDER BY gross_profit DESC;

-- Revenue and gross margin by category
SELECT
    p.category,
    ROUND(SUM(oi.item_total))                                                                AS item_revenue,
    ROUND(100.0 * SUM(oi.quantity * (oi.unit_price - p.cost_price) - oi.discount)
          / SUM(oi.item_total))                                                              AS gross_margin_pct
FROM ecommerce.order_items oi
JOIN ecommerce.products p ON p.product_id = oi.product_id
JOIN ecommerce.orders   o ON o.order_id   = oi.order_id
WHERE o.order_status <> 'Cancelled'
GROUP BY p.category
ORDER BY item_revenue DESC;

-- How much comes from the top 10 products and the top 20 customers?
SELECT
    (SELECT ROUND(100.0 * SUM(revenue) / (SELECT SUM(oi.item_total)
                                            FROM ecommerce.order_items oi
                                            JOIN ecommerce.orders o ON o.order_id = oi.order_id
                                           WHERE o.order_status <> 'Cancelled'), 1)
       FROM (SELECT SUM(oi.item_total) AS revenue
               FROM ecommerce.order_items oi
               JOIN ecommerce.orders o ON o.order_id = oi.order_id
              WHERE o.order_status <> 'Cancelled'
              GROUP BY oi.product_id ORDER BY 1 DESC LIMIT 10) t)                            AS top10_products_pct_of_item_revenue,
    (SELECT ROUND(SUM(revenue)) FROM (SELECT SUM(total_amount) AS revenue
               FROM ecommerce.orders WHERE order_status <> 'Cancelled'
              GROUP BY customer_id ORDER BY 1 DESC LIMIT 20) t)                              AS top20_customers_revenue,
    (SELECT ROUND(100.0 * SUM(revenue) / (SELECT SUM(total_amount) FROM ecommerce.orders WHERE order_status <> 'Cancelled'), 1)
       FROM (SELECT SUM(total_amount) AS revenue FROM ecommerce.orders
              WHERE order_status <> 'Cancelled'
              GROUP BY customer_id ORDER BY 1 DESC LIMIT 20) t)                              AS top20_customers_pct_of_revenue;

-- Which payment methods are used most?
SELECT
    payment_method,
    COUNT(*)                                             AS transactions,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)   AS pct_of_transactions
FROM ecommerce.payments
GROUP BY payment_method
ORDER BY transactions DESC;

-- Monthly sales by payment method
SELECT
    date_trunc('month', payment_date)::date                         AS month,
    payment_method,
    ROUND(SUM(amount))                                              AS sales,
    ROUND(100.0 * SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY date_trunc('month', payment_date)), 1) AS pct_of_month
FROM ecommerce.payments
GROUP BY date_trunc('month', payment_date), payment_method
ORDER BY date_trunc('month', payment_date), sales DESC;

-- Quarterly sales by payment method
SELECT
    to_char(date_trunc('quarter', payment_date), 'YYYY"-Q"Q')       AS quarter,
    payment_method,
    ROUND(SUM(amount))                                              AS sales,
    ROUND(100.0 * SUM(amount) / SUM(SUM(amount)) OVER (PARTITION BY date_trunc('quarter', payment_date)), 1) AS pct_of_quarter
FROM ecommerce.payments
GROUP BY date_trunc('quarter', payment_date), payment_method
ORDER BY date_trunc('quarter', payment_date), sales DESC;

-- Sales by payment method overall, and 2025 against 2024
SELECT
    payment_method,
    ROUND(SUM(amount))                                              AS sales,
    ROUND(100.0 * SUM(amount) / SUM(SUM(amount)) OVER (), 1)        AS share_pct,
    ROUND(SUM(amount) FILTER (WHERE EXTRACT(YEAR FROM payment_date) = 2024)) AS sales_2024,
    ROUND(SUM(amount) FILTER (WHERE EXTRACT(YEAR FROM payment_date) = 2025)) AS sales_2025,
    ROUND(100.0 * (SUM(amount) FILTER (WHERE EXTRACT(YEAR FROM payment_date) = 2025)
                 - SUM(amount) FILTER (WHERE EXTRACT(YEAR FROM payment_date) = 2024))
          / SUM(amount) FILTER (WHERE EXTRACT(YEAR FROM payment_date) = 2024), 1) AS change_2025_vs_2024_pct
FROM ecommerce.payments
GROUP BY payment_method
ORDER BY sales DESC;

-- Sales and orders by acquisition channel
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id)                                   AS customers,
    COUNT(o.order_id)                                               AS orders,
    ROUND(SUM(o.total_amount))                                      AS sales,
    ROUND(100.0 * SUM(o.total_amount) / SUM(SUM(o.total_amount)) OVER (), 1) AS share_pct
FROM ecommerce.customers c
LEFT JOIN ecommerce.orders o ON o.customer_id = c.customer_id
GROUP BY c.acquisition_channel
ORDER BY sales DESC;

-- Customer Insights

-- Q3. Where do customers come from, and is that changing?

-- Which acquisition channels bring the most customers?
SELECT
    acquisition_channel,
    COUNT(*)                                          AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_customers,
    ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY COUNT(*) DESC) / SUM(COUNT(*)) OVER (), 1) AS cumulative_pct
FROM ecommerce.customers
GROUP BY acquisition_channel
ORDER BY customers DESC;

-- Monthly new customers, with a 3-month average and month and year change
WITH monthly AS (
    SELECT date_trunc('month', signup_date)::date AS month,
           COUNT(*)                               AS customers
    FROM ecommerce.customers
    GROUP BY 1
)
SELECT
    month,
    customers,
    CASE WHEN ROW_NUMBER() OVER w >= 3
         THEN ROUND(AVG(customers) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1)
    END                                                                       AS moving_avg_3m,
    ROUND(100.0 * (customers - LAG(customers)     OVER w) / NULLIF(LAG(customers)     OVER w, 0), 1) AS mom_pct,
    ROUND(100.0 * (customers - LAG(customers, 12) OVER w) / NULLIF(LAG(customers, 12) OVER w, 0), 1) AS yoy_pct
FROM monthly
WINDOW w AS (ORDER BY month)
ORDER BY month;

-- Quarterly new customers by channel, with quarter and year change
WITH quarterly AS (
    SELECT date_trunc('quarter', signup_date)::date AS quarter_start,
           acquisition_channel,
           COUNT(*)                                 AS customers
    FROM ecommerce.customers
    GROUP BY 1, 2
)
SELECT
    to_char(quarter_start, 'YYYY"-Q"Q')                                              AS quarter,
    acquisition_channel,
    customers,
    ROUND(100.0 * customers / SUM(customers) OVER (PARTITION BY quarter_start), 1)  AS pct_of_quarter,
    ROUND(100.0 * (customers - LAG(customers)    OVER w) / NULLIF(LAG(customers)    OVER w, 0), 1) AS qoq_pct,
    ROUND(100.0 * (customers - LAG(customers, 4) OVER w) / NULLIF(LAG(customers, 4) OVER w, 0), 1) AS yoy_pct
FROM quarterly
WINDOW w AS (PARTITION BY acquisition_channel ORDER BY quarter_start)
ORDER BY quarter_start, customers DESC;

-- Is any channel trending up or down?
WITH monthly AS (
    SELECT date_trunc('month', signup_date)::date AS month,
           COALESCE(acquisition_channel, 'All channels') AS channel,
           COUNT(*)                                      AS customers
    FROM ecommerce.customers
    GROUP BY GROUPING SETS ((date_trunc('month', signup_date), acquisition_channel),
                            (date_trunc('month', signup_date)))
),
numbered AS (
    SELECT channel, customers,
           ROW_NUMBER() OVER (PARTITION BY channel ORDER BY month) AS x
    FROM monthly
),
fit AS (
    SELECT channel,
           AVG(customers)               AS avg_per_month,
           regr_slope(customers, x)     AS slope,
           regr_r2(customers, x)        AS r2,
           COUNT(*)                     AS n
    FROM numbered
    GROUP BY channel
)
SELECT
    channel,
    ROUND(avg_per_month::numeric, 1)                              AS avg_per_month,
    ROUND(slope::numeric, 3)                                      AS slope_per_month,
    ROUND((100.0 * 12 * slope / avg_per_month)::numeric, 1)       AS pct_change_per_year,
    ROUND((SIGN(slope) * SQRT(r2 * (n - 2) / (1 - r2)))::numeric, 2) AS t_stat
FROM fit
ORDER BY CASE WHEN channel = 'All channels' THEN 0 ELSE 1 END, avg_per_month DESC;

-- Full-year and first-half sign-ups by channel, like for like
SELECT
    acquisition_channel,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2024)  AS fy_2024,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2025)  AS fy_2025,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2025)
                 - COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2024))
          / COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2024), 1) AS fy_pct_change,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2024 AND EXTRACT(MONTH FROM signup_date) <= 6) AS h1_2024,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2025 AND EXTRACT(MONTH FROM signup_date) <= 6) AS h1_2025,
    COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2026 AND EXTRACT(MONTH FROM signup_date) <= 6) AS h1_2026,
    ROUND(100.0 * (COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2026 AND EXTRACT(MONTH FROM signup_date) <= 6)
                 - COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2025 AND EXTRACT(MONTH FROM signup_date) <= 6))
          / COUNT(*) FILTER (WHERE EXTRACT(YEAR FROM signup_date) = 2025 AND EXTRACT(MONTH FROM signup_date) <= 6), 1) AS h1_pct_change_26_vs_25
FROM ecommerce.customers
GROUP BY acquisition_channel
ORDER BY fy_2025 DESC;

-- Which calendar months bring the most sign-ups?
WITH monthly AS (
    SELECT date_trunc('month', signup_date)::date AS month,
           COUNT(*)                               AS customers
    FROM ecommerce.customers
    GROUP BY 1
),
overall AS (
    SELECT AVG(customers) AS avg_customers FROM monthly
)
SELECT
    EXTRACT(MONTH FROM month)::int                           AS month_number,
    to_char(MIN(month), 'Mon')                               AS month_name,
    COUNT(*)                                                 AS years_observed,
    MIN(customers)                                           AS lowest,
    MAX(customers)                                           AS highest,
    ROUND(AVG(customers), 1)                                 AS avg_customers,
    ROUND(AVG(customers) / (SELECT avg_customers FROM overall), 3) AS seasonal_index
FROM monthly
GROUP BY EXTRACT(MONTH FROM month)
ORDER BY month_number;

-- Sign-ups per day in each calendar month, against an average day
WITH span AS (
    SELECT g.day::date AS day
    FROM generate_series((SELECT MIN(signup_date) FROM ecommerce.customers),
                         (SELECT MAX(signup_date) FROM ecommerce.customers), INTERVAL '1 day') AS g(day)
),
days_per_month AS (
    SELECT EXTRACT(MONTH FROM day)::int AS month_number, COUNT(*) AS days
    FROM span
    GROUP BY 1
),
signups AS (
    SELECT EXTRACT(MONTH FROM signup_date)::int AS month_number, COUNT(*) AS customers
    FROM ecommerce.customers
    GROUP BY 1
)
SELECT d.month_number,
       s.customers,
       d.days,
       ROUND(1.0 * s.customers / d.days, 2)                                                    AS average_signups_per_day,
       ROUND(100.0 * ((1.0 * s.customers / d.days)
             / ((SELECT COUNT(*) FROM ecommerce.customers)::numeric / (SELECT COUNT(*) FROM span)) - 1), 1) AS pct_compared_with_average_day
FROM days_per_month d
JOIN signups s ON s.month_number = d.month_number
ORDER BY d.month_number;

-- Does each channel have busier quarters?
WITH quarterly AS (
    SELECT date_trunc('quarter', signup_date)::date AS quarter_start,
           acquisition_channel,
           COUNT(*)                                 AS customers
    FROM ecommerce.customers
    GROUP BY 1, 2
),
indexed AS (
    SELECT acquisition_channel,
           EXTRACT(QUARTER FROM quarter_start)::int AS quarter_of_year,
           customers::numeric / AVG(customers) OVER (PARTITION BY acquisition_channel) AS idx
    FROM quarterly
)
SELECT
    acquisition_channel,
    ROUND(AVG(idx) FILTER (WHERE quarter_of_year = 1), 2) AS q1_index,
    ROUND(AVG(idx) FILTER (WHERE quarter_of_year = 2), 2) AS q2_index,
    ROUND(AVG(idx) FILTER (WHERE quarter_of_year = 3), 2) AS q3_index,
    ROUND(AVG(idx) FILTER (WHERE quarter_of_year = 4), 2) AS q4_index
FROM indexed
GROUP BY acquisition_channel
ORDER BY acquisition_channel;

-- Q4. What is a customer worth, and do they come back?

-- Customers, orders, orders per customer and revenue per customer
SELECT
    (SELECT COUNT(*) FROM ecommerce.customers)                      AS total_customers,
    (SELECT COUNT(*) FROM ecommerce.orders)                         AS total_orders,
    ROUND((SELECT COUNT(*) FROM ecommerce.orders)::numeric
          / (SELECT COUNT(DISTINCT customer_id) FROM ecommerce.orders), 1) AS avg_orders_per_customer,
    ROUND((SELECT SUM(total_amount) FROM ecommerce.orders)
          / (SELECT COUNT(*) FROM ecommerce.customers))             AS avg_revenue_per_customer;

-- Average revenue per customer by acquisition channel
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id)                                   AS customers,
    ROUND(SUM(o.total_amount))                                      AS revenue,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT c.customer_id))      AS clv
FROM ecommerce.customers c
LEFT JOIN ecommerce.orders o ON o.customer_id = c.customer_id
GROUP BY c.acquisition_channel
ORDER BY clv DESC;

-- Which channels bring the most valuable customers?
SELECT
    c.acquisition_channel,
    COUNT(DISTINCT c.customer_id)                                        AS customers,
    ROUND(COALESCE(SUM(o.total_amount), 0), 2)                           AS revenue,
    ROUND(COALESCE(SUM(o.total_amount), 0) / COUNT(DISTINCT c.customer_id), 2) AS revenue_per_customer
FROM ecommerce.customers c
LEFT JOIN ecommerce.orders o
       ON o.customer_id = c.customer_id
      AND o.order_status != 'Cancelled'
GROUP BY c.acquisition_channel
ORDER BY revenue_per_customer DESC;

-- What percentage of customers are repeat purchasers?
WITH customer_orders AS (
    SELECT customer_id, COUNT(*) AS order_count
    FROM ecommerce.orders
    WHERE order_status != 'Cancelled'
    GROUP BY customer_id
)
SELECT
    COUNT(*)                                                       AS customers_with_orders,
    COUNT(*) FILTER (WHERE order_count > 1)                        AS repeat_customers,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_count > 1) / COUNT(*), 2) AS pct_repeat
FROM customer_orders;

-- How many orders does each customer place?
SELECT orders_per_customer, COUNT(*) AS customers
FROM (SELECT customer_id, COUNT(*) AS orders_per_customer
        FROM ecommerce.orders WHERE order_status <> 'Cancelled' GROUP BY customer_id) t
GROUP BY orders_per_customer
ORDER BY orders_per_customer;

-- Who are the top 20 customers by lifetime revenue?
SELECT
    c.customer_id,
    c.customer_name,
    ROUND(SUM(o.total_amount), 2) AS lifetime_revenue,
    COUNT(o.order_id)             AS orders
FROM ecommerce.customers c
JOIN ecommerce.orders o ON o.customer_id = c.customer_id
WHERE o.order_status != 'Cancelled'
GROUP BY c.customer_id, c.customer_name
ORDER BY lifetime_revenue DESC
LIMIT 20;

-- How many orders fall before, in and after the signup month?
SELECT
    COUNT(*)                                                        AS orders,
    COUNT(*) FILTER (WHERE months_since_signup < 0)                 AS orders_before_signup_month,
    COUNT(*) FILTER (WHERE months_since_signup = 0)                 AS orders_in_signup_month,
    COUNT(*) FILTER (WHERE months_since_signup > 0)                 AS orders_after_signup_month,
    ROUND(100.0 * COUNT(*) FILTER (WHERE months_since_signup < 0) / COUNT(*), 1) AS pct_before_signup_month
FROM (
    SELECT (EXTRACT(YEAR FROM age(date_trunc('month', o.order_date), date_trunc('month', c.signup_date))) * 12
            + EXTRACT(MONTH FROM age(date_trunc('month', o.order_date), date_trunc('month', c.signup_date))))::int AS months_since_signup
    FROM ecommerce.orders o
    JOIN ecommerce.customers c ON c.customer_id = o.customer_id
) t;

-- Orders and customers ordering, by months since signup
SELECT
    months_since_signup,
    COUNT(*)                                                        AS orders,
    COUNT(DISTINCT customer_id)                                     AS customers_ordering
FROM (
    SELECT o.customer_id,
           (EXTRACT(YEAR FROM age(date_trunc('month', o.order_date), date_trunc('month', c.signup_date))) * 12
            + EXTRACT(MONTH FROM age(date_trunc('month', o.order_date), date_trunc('month', c.signup_date))))::int AS months_since_signup
    FROM ecommerce.orders o
    JOIN ecommerce.customers c ON c.customer_id = o.customer_id
) t
WHERE months_since_signup BETWEEN 0 AND 6
GROUP BY months_since_signup
ORDER BY months_since_signup;

-- What share of customers order again the following month?
WITH monthly_customers AS (
    SELECT DISTINCT
        date_trunc('month', order_date)::date AS month,
        customer_id
    FROM ecommerce.orders
    WHERE order_status != 'Cancelled'
),
retention AS (
    SELECT
        curr.month,
        COUNT(DISTINCT curr.customer_id)                                   AS active_customers,
        COUNT(DISTINCT prev.customer_id)                                   AS retained_from_prior_month
    FROM monthly_customers curr
    LEFT JOIN monthly_customers prev
           ON prev.customer_id = curr.customer_id
          AND prev.month = curr.month - INTERVAL '1 month'
    GROUP BY curr.month
)
SELECT
    month,
    active_customers,
    retained_from_prior_month,
    ROUND(100.0 * retained_from_prior_month / NULLIF(active_customers, 0), 2) AS retention_rate_pct
FROM retention
ORDER BY month;

-- Average, lowest and highest monthly retention
WITH monthly_customers AS (
    SELECT DISTINCT date_trunc('month', order_date)::date AS month, customer_id
    FROM ecommerce.orders WHERE order_status <> 'Cancelled'
),
retention AS (
    SELECT curr.month,
           100.0 * COUNT(DISTINCT prev.customer_id) / COUNT(DISTINCT curr.customer_id) AS retention_pct
    FROM monthly_customers curr
    LEFT JOIN monthly_customers prev
           ON prev.customer_id = curr.customer_id
          AND prev.month = curr.month - INTERVAL '1 month'
    GROUP BY curr.month
)
SELECT COUNT(*)                         AS months,
       ROUND(AVG(retention_pct), 1)     AS avg_retention_pct,
       ROUND(MIN(retention_pct), 1)     AS lowest_pct,
       ROUND(MAX(retention_pct), 1)     AS highest_pct
FROM retention
WHERE month > (SELECT MIN(month) FROM retention);

-- Retention by first-purchase cohort
WITH first_purchase AS (
    SELECT
        customer_id,
        date_trunc('month', MIN(order_date))::date AS cohort_month
    FROM ecommerce.orders
    WHERE order_status != 'Cancelled'
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT
        o.customer_id,
        date_trunc('month', o.order_date)::date AS activity_month
    FROM ecommerce.orders o
    WHERE o.order_status != 'Cancelled'
),
cohort_activity AS (
    SELECT
        fp.cohort_month,
        a.activity_month,
        (EXTRACT(YEAR FROM age(a.activity_month, fp.cohort_month)) * 12
         + EXTRACT(MONTH FROM age(a.activity_month, fp.cohort_month)))::int AS month_number,
        a.customer_id
    FROM first_purchase fp
    JOIN activity a ON a.customer_id = fp.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.customers                                                     AS cohort_size,
    ca.month_number,
    COUNT(DISTINCT ca.customer_id)                                   AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT ca.customer_id) / cs.customers, 1)  AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
GROUP BY ca.cohort_month, cs.customers, ca.month_number
ORDER BY ca.cohort_month, ca.month_number;

-- Retention by first-purchase cohort, pooled across all cohorts
WITH first_purchase AS (
    SELECT customer_id, date_trunc('month', MIN(order_date))::date AS cohort_month
    FROM ecommerce.orders WHERE order_status <> 'Cancelled' GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT customer_id, date_trunc('month', order_date)::date AS activity_month
    FROM ecommerce.orders WHERE order_status <> 'Cancelled'
),
cohort_activity AS (
    SELECT fp.cohort_month, a.customer_id,
           (EXTRACT(YEAR FROM age(a.activity_month, fp.cohort_month)) * 12
            + EXTRACT(MONTH FROM age(a.activity_month, fp.cohort_month)))::int AS month_number
    FROM first_purchase fp
    JOIN activity a ON a.customer_id = fp.customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS customers FROM first_purchase GROUP BY cohort_month
),
by_cohort AS (
    SELECT ca.cohort_month, ca.month_number, cs.customers, COUNT(DISTINCT ca.customer_id) AS active
    FROM cohort_activity ca
    JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
    GROUP BY ca.cohort_month, ca.month_number, cs.customers
)
SELECT month_number,
       COUNT(*)                                      AS cohorts,
       SUM(customers)                                AS cohort_customers,
       SUM(active)                                   AS active_customers,
       ROUND(100.0 * SUM(active) / SUM(customers), 1) AS pooled_retention_pct
FROM by_cohort
WHERE month_number IN (0, 1, 2, 3, 6, 12)
GROUP BY month_number
ORDER BY month_number;

-- Which RFM segment is each customer in (how recently, how often, how much)?
WITH ref_date AS (
    SELECT MAX(order_date) + 1 AS as_of FROM ecommerce.orders
),
customer_agg AS (
    SELECT
        o.customer_id,
        (SELECT as_of FROM ref_date) - MAX(o.order_date) AS recency,
        COUNT(*)                                          AS frequency,
        SUM(o.total_amount)                               AS monetary
    FROM ecommerce.orders o
    WHERE o.order_status != 'Cancelled'
    GROUP BY o.customer_id
),
scored AS (
    SELECT
        customer_id,
        recency,
        frequency,
        monetary,
        NTILE(5) OVER (ORDER BY recency DESC,  customer_id) AS r_score,  -- 5 = most recent
        NTILE(5) OVER (ORDER BY frequency ASC, customer_id) AS f_score,  -- 5 = most frequent
        NTILE(5) OVER (ORDER BY monetary ASC,  customer_id) AS m_score   -- 5 = highest spend
    FROM customer_agg
)
SELECT
    customer_id,
    recency,
    frequency,
    ROUND(monetary, 2) AS monetary,
    r_score, f_score, m_score,
    (r_score + f_score + m_score)              AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score <= 2                   THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4  THEN 'At Risk (High Value)'
        WHEN r_score <= 2 AND f_score <= 2                   THEN 'Lost'
        ELSE 'Core / Needs Nurturing'
    END AS rfm_segment
FROM scored
ORDER BY rfm_total DESC;

-- How many customers, and how much revenue, in each RFM segment?
WITH ref_date AS (
    SELECT MAX(order_date) + 1 AS as_of FROM ecommerce.orders
),
customer_agg AS (
    SELECT customer_id,
           (SELECT as_of FROM ref_date) - MAX(order_date) AS recency,
           COUNT(*)                                       AS frequency,
           SUM(total_amount)                              AS monetary
    FROM ecommerce.orders
    WHERE order_status <> 'Cancelled'
    GROUP BY customer_id
),
scored AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY recency DESC,  customer_id) AS r_score,
           NTILE(5) OVER (ORDER BY frequency ASC, customer_id) AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC,  customer_id) AS m_score
    FROM customer_agg
)
SELECT
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score <= 2                   THEN 'New / Promising'
        WHEN r_score <= 2 AND f_score >= 4 AND m_score >= 4  THEN 'At Risk (High Value)'
        WHEN r_score <= 2 AND f_score <= 2                   THEN 'Lost'
        ELSE 'Core / Needs Nurturing'
    END                         AS rfm_segment,
    COUNT(*)                                                   AS customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_of_customers,
    ROUND(AVG(recency))                                        AS avg_days_since_last_order,
    ROUND(AVG(frequency), 1)                                   AS avg_orders,
    ROUND(SUM(monetary))                                       AS revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue
FROM scored
GROUP BY 1
ORDER BY revenue DESC;

-- Which customers have not ordered for 90+ days?
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM ecommerce.orders
    WHERE order_status != 'Cancelled'
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    lo.last_order_date,
    (SELECT MAX(order_date) FROM ecommerce.orders) - lo.last_order_date AS days_since_last_order
FROM last_order lo
JOIN ecommerce.customers c ON c.customer_id = lo.customer_id
WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - lo.last_order_date >= 90
ORDER BY days_since_last_order DESC;

-- How many customers have not ordered for 90+ days?
WITH last_order AS (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM ecommerce.orders WHERE order_status <> 'Cancelled' GROUP BY customer_id
)
SELECT COUNT(*)                                                                                   AS customers_with_orders,
       COUNT(*) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - last_order_date >= 90) AS inactive_90_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE (SELECT MAX(order_date) FROM ecommerce.orders) - last_order_date >= 90)
             / COUNT(*), 1)                                                                       AS pct_inactive
FROM last_order;

-- How many days pass between a customer's orders?
WITH gaps AS (
    SELECT order_date - LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS gap
    FROM ecommerce.orders
)
SELECT COUNT(gap) AS gaps,
       ROUND(AVG(gap))                                                       AS mean_days,
       ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY gap)::numeric)     AS typical_days,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gap)::numeric)     AS p75_days,
       ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY gap)::numeric)     AS p90_days,
       ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gap)::numeric)     AS p95_days
FROM gaps;

-- How long since each customer's last order?
WITH last_order AS (
    SELECT customer_id, (SELECT MAX(order_date) FROM ecommerce.orders) - MAX(order_date) AS days_since
    FROM ecommerce.orders WHERE order_status <> 'Cancelled' GROUP BY customer_id
)
SELECT COUNT(*)                                          AS customers,
       COUNT(*) FILTER (WHERE days_since >= 90)          AS over_90_days,
       COUNT(*) FILTER (WHERE days_since >= 180)         AS over_180_days,
       COUNT(*) FILTER (WHERE days_since >= 365)         AS over_365_days,
       COUNT(*) FILTER (WHERE days_since >= 540)         AS over_540_days,
       COUNT(*) FILTER (WHERE days_since >= 730)         AS over_730_days
FROM last_order;

-- Website & Returns

-- Q5. Where does the website lose buyers?

-- How many sessions add to cart, start checkout and buy?
SELECT
    COUNT(*)                                                                AS sessions,
    COUNT(*) FILTER (WHERE added_to_cart)                                   AS added_to_cart,
    COUNT(*) FILTER (WHERE checkout_started)                                AS checkout_started,
    COUNT(*) FILTER (WHERE purchase_completed)                              AS purchased,
    ROUND(100.0 * COUNT(*) FILTER (WHERE added_to_cart) / COUNT(*), 2)      AS pct_add_to_cart,
    ROUND(100.0 * COUNT(*) FILTER (WHERE checkout_started) / COUNT(*), 2)   AS pct_checkout,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_completed) / COUNT(*), 2) AS pct_converted
FROM ecommerce.website_sessions;

-- Website funnel: sessions, add to cart, checkout, purchase
SELECT
    COUNT(*)                                                        AS "1 Page views",
    COUNT(*) FILTER (WHERE added_to_cart)                           AS "2 Add to cart",
    COUNT(*) FILTER (WHERE checkout_started)                        AS "3 Checkout start",
    COUNT(*) FILTER (WHERE purchase_completed)                      AS "4 Purchase complete"
FROM ecommerce.website_sessions;

-- Step by step: cart to checkout, checkout to purchase, cart abandonment
SELECT
    ROUND(100.0 * COUNT(*) FILTER (WHERE checkout_started)  / COUNT(*) FILTER (WHERE added_to_cart), 1)      AS cart_to_checkout_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_completed) / COUNT(*) FILTER (WHERE checkout_started), 1)  AS checkout_to_purchase_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE added_to_cart AND NOT purchase_completed)
          / COUNT(*) FILTER (WHERE added_to_cart), 1)                                                        AS cart_abandonment_pct
FROM ecommerce.website_sessions;

-- Which traffic source converts best?
SELECT
    traffic_source,
    COUNT(*)                                                                AS sessions,
    COUNT(*) FILTER (WHERE purchase_completed)                              AS purchases,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_completed) / COUNT(*), 2) AS conversion_rate_pct
FROM ecommerce.website_sessions
GROUP BY traffic_source
ORDER BY conversion_rate_pct DESC;

-- How does conversion differ by device?
SELECT
    device_type,
    COUNT(*)                                                                AS sessions,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_completed) / COUNT(*), 2) AS conversion_rate_pct
FROM ecommerce.website_sessions
GROUP BY device_type
ORDER BY conversion_rate_pct DESC;

-- Funnel by traffic source
SELECT
    traffic_source,
    COUNT(*)                                                              AS sessions,
    ROUND(100.0 * COUNT(*) FILTER (WHERE added_to_cart) / COUNT(*), 2)    AS pct_add_to_cart,
    ROUND(100.0 * COUNT(*) FILTER (WHERE checkout_started) / COUNT(*), 2) AS pct_checkout,
    ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_completed) / COUNT(*), 2) AS pct_converted
FROM ecommerce.website_sessions
GROUP BY traffic_source
ORDER BY pct_converted DESC;

-- Do pages viewed or time on site relate to buying?
SELECT CASE WHEN pages_viewed <= 2 THEN '1-2' WHEN pages_viewed <= 4 THEN '3-4' WHEN pages_viewed <= 6 THEN '5-6'
            WHEN pages_viewed <= 9 THEN '7-9' ELSE '10+' END AS pages_viewed,
       COUNT(*) AS sessions,
       ROUND(100.0 * AVG(added_to_cart::int), 1)       AS added_to_cart_pct,
       ROUND(100.0 * AVG(purchase_completed::int), 1)  AS purchase_pct
FROM ecommerce.website_sessions GROUP BY 1 ORDER BY MIN(pages_viewed);

SELECT CASE WHEN session_duration_seconds < 60 THEN '1 under 1 min' WHEN session_duration_seconds < 180 THEN '2 1-3 min'
            WHEN session_duration_seconds < 420 THEN '3 3-7 min' ELSE '4 over 7 min' END AS duration,
       COUNT(*) AS sessions,
       ROUND(100.0 * AVG(added_to_cart::int), 1)       AS added_to_cart_pct,
       ROUND(100.0 * AVG(purchase_completed::int), 1)  AS purchase_pct
FROM ecommerce.website_sessions GROUP BY 1 ORDER BY 1;

-- Q6. How many orders are returned, why, and when?

-- Average return value and return rate
SELECT
    ROUND(SUM(refund_amount) / COUNT(*))                            AS avg_return_value,
    COUNT(*)                                                        AS returns,
    COUNT(DISTINCT order_id)                                        AS orders_with_return,
    ROUND(100.0 * COUNT(DISTINCT order_id) / (SELECT COUNT(*) FROM ecommerce.orders), 1) AS return_rate_pct
FROM ecommerce.returns;

-- What share of orders have a return, and how much was refunded?
SELECT
    COUNT(DISTINCT r.order_id)                                                              AS orders_with_return,
    (SELECT COUNT(*) FROM ecommerce.orders WHERE order_status = 'Delivered')                AS delivered_orders,
    ROUND(100.0 * COUNT(DISTINCT r.order_id)
          / (SELECT COUNT(*) FROM ecommerce.orders WHERE order_status = 'Delivered'), 1)    AS pct_of_delivered_orders,
    ROUND(100.0 * COUNT(DISTINCT r.order_id) / (SELECT COUNT(*) FROM ecommerce.orders), 1)  AS pct_of_all_orders,
    SUM(r.quantity_returned)                                                                AS units_returned,
    ROUND(SUM(r.refund_amount))                                                             AS refund_value
FROM ecommerce.returns r;

-- What are the most common return reasons?
SELECT
    return_reason,
    COUNT(*)                                                   AS returns,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS pct_of_returns
FROM ecommerce.returns
GROUP BY return_reason
ORDER BY returns DESC;

-- What is the return rate by product category?
SELECT
    p.category,
    COUNT(r.return_id)                                                       AS returns,
    item_counts.items_sold,
    ROUND(100.0 * COUNT(r.return_id) / item_counts.items_sold, 2)           AS return_rate_pct
FROM ecommerce.returns r
JOIN ecommerce.products p ON p.product_id = r.product_id
JOIN (
    SELECT p2.category, COUNT(*) AS items_sold
    FROM ecommerce.order_items oi2
    JOIN ecommerce.orders   o2 ON o2.order_id   = oi2.order_id
    JOIN ecommerce.products p2 ON p2.product_id = oi2.product_id
    WHERE o2.order_status = 'Delivered'
    GROUP BY p2.category
) item_counts ON item_counts.category = p.category
GROUP BY p.category, item_counts.items_sold
ORDER BY return_rate_pct DESC;

-- Which products have high return rates and low margins?
WITH item_counts AS (
    SELECT oi.product_id, COUNT(*) AS items_sold
    FROM ecommerce.order_items oi
    JOIN ecommerce.orders o ON o.order_id = oi.order_id
    WHERE o.order_status = 'Delivered'
    GROUP BY oi.product_id
),
return_counts AS (
    SELECT product_id, COUNT(*) AS returns
    FROM ecommerce.returns
    GROUP BY product_id
)
SELECT
    p.product_name,
    p.category,
    ROUND(100.0 * rc.returns / ic.items_sold, 2)                      AS return_rate_pct,
    ROUND((p.unit_price - p.cost_price) / p.unit_price * 100, 2)      AS margin_pct
FROM ecommerce.products p
JOIN item_counts ic   ON ic.product_id = p.product_id
JOIN return_counts rc ON rc.product_id = p.product_id
WHERE ic.items_sold >= 20          -- filter out low-volume noise
ORDER BY return_rate_pct DESC, margin_pct ASC
LIMIT 10;

-- Which products sell a lot but are rated poorly?
WITH revenue AS (
    SELECT oi.product_id, SUM(oi.item_total) AS revenue
    FROM ecommerce.order_items oi
    JOIN ecommerce.orders o ON o.order_id = oi.order_id
    WHERE o.order_status != 'Cancelled'
    GROUP BY oi.product_id
),
ratings AS (
    SELECT product_id, AVG(rating) AS avg_rating, COUNT(*) AS n_reviews
    FROM ecommerce.reviews
    GROUP BY product_id
)
SELECT
    p.product_name,
    p.category,
    ROUND(revenue.revenue, 2)      AS revenue,
    ROUND(ratings.avg_rating, 2)   AS avg_rating,
    ratings.n_reviews
FROM revenue
JOIN ecommerce.products p ON p.product_id = revenue.product_id
JOIN ratings ON ratings.product_id = revenue.product_id
WHERE ratings.avg_rating < 3.8
  AND revenue.revenue >= (
        SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue)
        FROM revenue
      )
ORDER BY revenue.revenue DESC;

-- What is the average delivery time by shipping method?
SELECT
    shipping_method,
    ROUND(AVG(delivery_date - order_date), 2) AS avg_delivery_days
FROM ecommerce.orders
WHERE delivery_date IS NOT NULL
GROUP BY shipping_method
ORDER BY avg_delivery_days;

-- Delivery time, share delivered within a day, and shipping cost by shipping method
SELECT
    shipping_method,
    COUNT(*) FILTER (WHERE delivery_date IS NOT NULL)                                        AS delivered_orders,
    ROUND(AVG(delivery_date - order_date), 1)                                                AS avg_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivery_date - order_date <= 1)
          / COUNT(*) FILTER (WHERE delivery_date IS NOT NULL), 1)                            AS pct_within_1_day,
    ROUND(AVG(shipping_cost), 2)                                                             AS avg_shipping_cost
FROM ecommerce.orders
GROUP BY shipping_method
ORDER BY shipping_method;

-- Returns and refunds by month
SELECT
    date_trunc('month', return_date)::date                          AS month,
    COUNT(*)                                                        AS returns,
    ROUND(SUM(refund_amount))                                       AS refunds
FROM ecommerce.returns
GROUP BY 1
ORDER BY 1;

-- Average returns per month, by year
SELECT
    EXTRACT(YEAR FROM month)::int                                   AS year,
    COUNT(*)                                                        AS months,
    ROUND(AVG(returns), 1)                                          AS avg_returns_per_month,
    MIN(returns)                                                    AS lowest_month,
    MAX(returns)                                                    AS highest_month
FROM (
    SELECT date_trunc('month', return_date)::date AS month, COUNT(*) AS returns
    FROM ecommerce.returns
    GROUP BY 1
) m
WHERE month > '2024-01-01' AND month < '2026-07-01'      -- drop the partly covered first and last months
GROUP BY 1
ORDER BY 1;

-- Are refunds bigger than what customers paid?
WITH line AS (
    SELECT r.refund_amount, r.quantity_returned, oi.unit_price, oi.quantity, oi.discount, oi.item_total
    FROM ecommerce.returns r
    JOIN ecommerce.order_items oi ON oi.order_id = r.order_id AND oi.product_id = r.product_id
)
SELECT COUNT(*)                                                              AS returns,
       ROUND(SUM(refund_amount))                                             AS refunded,
       ROUND(SUM(item_total * quantity_returned / quantity))                 AS net_paid_for_returned_units,
       ROUND(SUM(refund_amount) - SUM(item_total * quantity_returned / quantity)) AS refunded_above_paid,
       COUNT(*) FILTER (WHERE ABS(refund_amount - unit_price * quantity_returned) < 0.015) AS refund_equals_undiscounted_price,
       COUNT(*) FILTER (WHERE discount > 0)                                  AS returns_on_discounted_lines
FROM line;

-- Does any product have an unusually high return rate?
WITH sold AS (
    SELECT oi.product_id, COUNT(*) AS lines FROM ecommerce.order_items oi
    JOIN ecommerce.orders o ON o.order_id = oi.order_id WHERE o.order_status = 'Delivered' GROUP BY oi.product_id
),
ret AS (SELECT product_id, COUNT(*) AS returns FROM ecommerce.returns GROUP BY product_id),
overall AS (SELECT (SELECT COUNT(*) FROM ecommerce.returns)::numeric / (SELECT SUM(lines) FROM sold) AS p)
SELECT p.product_name, s.lines, COALESCE(r.returns, 0) AS returns,
       ROUND(100.0 * COALESCE(r.returns, 0) / s.lines, 1) AS return_rate_pct,
       ROUND(((COALESCE(r.returns, 0) - s.lines * o.p) / SQRT(s.lines * o.p * (1 - o.p)))::numeric, 1) AS z_score
FROM sold s
JOIN ecommerce.products p ON p.product_id = s.product_id
LEFT JOIN ret r ON r.product_id = s.product_id
CROSS JOIN overall o
ORDER BY z_score DESC
LIMIT 5;

-- Geographic Insights

-- Q7. Which cities earn the most, and where are the customers?

-- Revenue, customers, orders and revenue per customer by city
SELECT
    c.city,
    c.region,
    COUNT(DISTINCT c.customer_id)                                   AS customers,
    COUNT(o.order_id)                                               AS orders,
    ROUND(SUM(o.total_amount))                                      AS revenue,
    ROUND(100.0 * SUM(o.total_amount) / SUM(SUM(o.total_amount)) OVER (), 1) AS revenue_share_pct,
    ROUND(SUM(o.total_amount) / COUNT(DISTINCT c.customer_id))      AS revenue_per_customer
FROM ecommerce.customers c
LEFT JOIN ecommerce.orders o ON o.customer_id = c.customer_id
GROUP BY c.city, c.region
ORDER BY revenue DESC;

-- Best and worst city on each measure
WITH city AS (
    SELECT c.city,
           COUNT(DISTINCT c.customer_id)                            AS customers,
           COUNT(o.order_id)                                        AS orders,
           SUM(o.total_amount)                                      AS revenue,
           SUM(o.total_amount) / COUNT(DISTINCT c.customer_id)      AS revenue_per_customer
    FROM ecommerce.customers c
    LEFT JOIN ecommerce.orders o ON o.customer_id = c.customer_id
    GROUP BY c.city
)
SELECT
    COUNT(*)                                                        AS cities,
    ROUND(MAX(revenue))                                             AS highest_revenue,
    ROUND(MIN(revenue))                                             AS lowest_revenue,
    ROUND(100.0 * (SELECT SUM(revenue) FROM (SELECT revenue FROM city ORDER BY revenue DESC LIMIT 3) t) / SUM(revenue), 1) AS top3_cities_share_pct,
    MAX(customers)                                                  AS most_customers,
    MIN(customers)                                                  AS fewest_customers,
    ROUND(MAX(revenue_per_customer))                                AS highest_revenue_per_customer,
    ROUND(MIN(revenue_per_customer))                                AS lowest_revenue_per_customer
FROM city;

-- Q8. Are cities worth different amounts per customer?

-- Does a customer's value differ from city to city, beyond normal variation?
WITH customer_revenue AS (
    SELECT c.customer_id, c.city, COALESCE(SUM(o.total_amount), 0) AS revenue
    FROM ecommerce.customers c
    LEFT JOIN ecommerce.orders o ON o.customer_id = c.customer_id
    GROUP BY c.customer_id, c.city
),
by_city AS (
    SELECT city, COUNT(*) AS customers, AVG(revenue) AS revenue_per_customer
    FROM customer_revenue GROUP BY city
)
SELECT
    ROUND((SELECT STDDEV_SAMP(revenue) FROM customer_revenue))                       AS typical_gap_between_customers,
    ROUND(AVG((SELECT STDDEV_SAMP(revenue) FROM customer_revenue) / SQRT(customers))) AS gap_from_customer_spending,
    ROUND(STDDEV_SAMP(revenue_per_customer))                                         AS actual_gap_between_cities
FROM by_city;

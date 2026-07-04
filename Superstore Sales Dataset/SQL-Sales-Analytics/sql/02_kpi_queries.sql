/* =====================================================================
   02_KPI_QUERIES.sql — Data Discovery & High-Level KPIs
   Note: "Total Profit" is not computable — the source data has no
   Profit column (see 01_database_setup.sql). Replaced with a clean
   revenue (Sales) KPI set. Full narrative in ../REPORT.md.
   ===================================================================== */

-- -----------------------------------------------------------------------
-- 2.1  Headline KPI card (Total Sales, Total Orders, Avg/Max/Min Sale)
-- -----------------------------------------------------------------------
WITH order_level AS (
    -- Collapse line items to one row per order first — "avg sale per
    -- order" and "highest/lowest sale" mean different things at the
    -- line-item grain vs. the order grain, so we compute both explicitly.
    SELECT
        order_id,
        SUM(sales) AS order_sales
    FROM sales_data
    GROUP BY order_id
)
SELECT
    COUNT(DISTINCT s.order_id)               AS total_orders,
    COUNT(*)                                 AS total_line_items,
    COUNT(DISTINCT s.customer_id)            AS total_customers,
    COUNT(DISTINCT s.product_id)             AS total_products,
    ROUND(SUM(s.sales), 2)                   AS total_sales,
    ROUND(AVG(ol.order_sales), 2)            AS avg_sales_per_order,
    ROUND(MAX(ol.order_sales), 2)            AS highest_order_value,
    ROUND(MIN(ol.order_sales), 2)            AS lowest_order_value,
    ROUND(MAX(s.sales), 2)                   AS highest_single_line_sale,
    ROUND(MIN(s.sales), 2)                   AS lowest_single_line_sale,
    MIN(s.order_date)                        AS first_order_date,
    MAX(s.order_date)                        AS last_order_date
FROM sales_data s
JOIN order_level ol ON ol.order_id = s.order_id;

-- -----------------------------------------------------------------------
-- 2.2  Best client (customer with the highest lifetime Sales)
-- -----------------------------------------------------------------------
SELECT
    customer_id,
    customer_name,
    COUNT(DISTINCT order_id)   AS total_orders,
    ROUND(SUM(sales), 2)       AS total_sales,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2) AS avg_order_value
FROM sales_data
GROUP BY customer_id, customer_name
ORDER BY total_sales DESC
LIMIT 10;                                   -- SQL Server: use TOP 10 instead

-- -----------------------------------------------------------------------
-- 2.3  Best city and best state by Sales
-- -----------------------------------------------------------------------
SELECT city, ROUND(SUM(sales), 2) AS total_sales
FROM sales_data
GROUP BY city
ORDER BY total_sales DESC
LIMIT 5;

SELECT state, ROUND(SUM(sales), 2) AS total_sales
FROM sales_data
GROUP BY state
ORDER BY total_sales DESC
LIMIT 5;

-- -----------------------------------------------------------------------
-- 2.4  Best-selling products
--      IMPORTANT: there is no Quantity column, so "best-selling" is
--      reported two ways so the business doesn't confuse them:
--        (a) by revenue generated  -> true commercial winners
--        (b) by number of order lines -> reorder/repeat-purchase frequency
-- -----------------------------------------------------------------------
SELECT
    product_name,
    category,
    sub_category,
    ROUND(SUM(sales), 2)     AS total_sales,
    COUNT(*)                 AS times_ordered
FROM sales_data
GROUP BY product_name, category, sub_category
ORDER BY total_sales DESC
LIMIT 10;

SELECT
    product_name,
    category,
    COUNT(*) AS times_ordered            -- proxy for order frequency, NOT units sold
FROM sales_data
GROUP BY product_name, category
ORDER BY times_ordered DESC
LIMIT 10;

-- -----------------------------------------------------------------------
-- 2.5  "Most profitable category" -> re-scoped to top revenue category
--      (Profit column doesn't exist; Sales is the closest honest proxy)
-- -----------------------------------------------------------------------
SELECT
    category,
    ROUND(SUM(sales), 2)                                        AS total_sales,
    ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 2)       AS pct_of_company_sales,
    COUNT(DISTINCT order_id)                                     AS total_orders
FROM sales_data
GROUP BY category
ORDER BY total_sales DESC;

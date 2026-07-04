/* =====================================================================
   03_SALES_ANALYSIS.sql — Deep Dive & "Why" Analysis
   Full narrative in ../REPORT.md.
   ===================================================================== */

-- -----------------------------------------------------------------------
-- 3.1  Breakdown by Category / Best Products / Cities
-- -----------------------------------------------------------------------
SELECT category, sub_category, ROUND(SUM(sales), 2) AS total_sales
FROM sales_data
GROUP BY category, sub_category
ORDER BY category, total_sales DESC;

SELECT city, ROUND(SUM(sales), 2) AS total_sales
FROM sales_data
GROUP BY city
ORDER BY total_sales DESC
LIMIT 10;

-- -----------------------------------------------------------------------
-- 3.2  THE "WHY" LOGIC
--      Discount/margin fields don't exist, so "why is city X the best"
--      is answered with a Sales decomposition instead:
--          Total City Sales = Customers x Orders-per-Customer x Avg Order Value
--      This isolates whether a city wins on CUSTOMER VOLUME (reach) or
--      on ORDER ECONOMICS (bigger/more frequent baskets) — a cleaner,
--      more actionable driver-tree than "profit" would have been alone.
-- -----------------------------------------------------------------------
WITH city_metrics AS (
    SELECT
        city,
        COUNT(DISTINCT customer_id)                              AS customer_count,
        COUNT(DISTINCT order_id)                                 AS order_count,
        SUM(sales)                                                AS total_sales
    FROM sales_data
    GROUP BY city
),
company_avg AS (
    SELECT
        SUM(sales) / COUNT(DISTINCT order_id)      AS company_avg_order_value,
        SUM(sales) / COUNT(DISTINCT customer_id)    AS company_avg_sales_per_customer
    FROM sales_data
)
SELECT
    cm.city,
    cm.customer_count,
    cm.order_count,
    ROUND(cm.order_count * 1.0 / cm.customer_count, 2)   AS orders_per_customer,
    ROUND(cm.total_sales, 2)                              AS total_sales,
    ROUND(cm.total_sales / cm.order_count, 2)             AS avg_order_value,
    ca.company_avg_order_value,
    -- >100 = this city's baskets are bigger than the company average
    ROUND(100.0 * (cm.total_sales / cm.order_count) / ca.company_avg_order_value, 1) AS aov_index_vs_company
FROM city_metrics cm
CROSS JOIN company_avg ca
ORDER BY cm.total_sales DESC
LIMIT 10;

-- Category mix per top city — tests whether a city over-indexes on a
-- higher-ticket category (a real driver of Average Order Value)
SELECT
    city,
    category,
    ROUND(SUM(sales), 2)                                                AS category_sales,
    ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (PARTITION BY city), 1) AS pct_of_city_sales
FROM sales_data
WHERE city IN (
    SELECT city FROM sales_data GROUP BY city ORDER BY SUM(sales) DESC LIMIT 5
)
GROUP BY city, category
ORDER BY city, category_sales DESC;

-- Region-level view of the same decomposition (coarser cut than city)
SELECT
    region,
    COUNT(DISTINCT customer_id)                          AS customer_count,
    COUNT(DISTINCT order_id)                              AS order_count,
    ROUND(SUM(sales), 2)                                  AS total_sales,
    ROUND(SUM(sales) / COUNT(DISTINCT order_id), 2)       AS avg_order_value,
    ROUND(SUM(sales) / COUNT(DISTINCT customer_id), 2)    AS avg_sales_per_customer
FROM sales_data
GROUP BY region
ORDER BY total_sales DESC;

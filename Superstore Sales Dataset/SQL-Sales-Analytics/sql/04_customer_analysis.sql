/* =====================================================================
   04_CUSTOMER_ANALYSIS.sql — Customer Filtering & Segmentation
   Full narrative in ../REPORT.md.
   ===================================================================== */

-- -----------------------------------------------------------------------
-- 4.1  Top 10 customers by lifetime Sales
-- -----------------------------------------------------------------------
SELECT customer_id, customer_name, ROUND(SUM(sales), 2) AS total_sales
FROM sales_data
GROUP BY customer_id, customer_name
ORDER BY total_sales DESC
LIMIT 10;

-- -----------------------------------------------------------------------
-- 4.2  Customer filtering & segmentation (total Sales > $10,000)
--
--      DATA NUANCE: Region is NOT a stable attribute of a customer in
--      this dataset — 765 of 793 customers have shipped orders into
--      more than one region. So "sort within region" first requires a
--      derived HOME REGION per customer: the region that generated the
--      most of that customer's Sales. A window function (ROW_NUMBER)
--      picks that region deterministically instead of just GROUP BY,
--      which would either explode one customer into many rows or
--      silently pick an arbitrary region.
--
--      SEGMENT DEFINITIONS (business rules, not just "make it fit"):
--        VIP     = total_sales > 10,000 AND order_count >= 8
--                  (repeat, frequent, high-value — the customers you
--                   protect with loyalty perks; churn risk is costly)
--        NEW     = total_sales > 10,000 AND tenure_days <= 730
--                  (already high value within 2 years of their first
--                   order — high-potential, fast-ramping accounts)
--        REGULAR = total_sales > 10,000 and meets neither rule above
--                  (high lifetime value but low order frequency and/or
--                   long tenure — often "whale" one-off big-ticket buys)
--      Thresholds (8 orders / 730 days) are review points for the
--      business to tune, not hard-coded magic numbers — expose them as
--      CTE constants so they're changed in one place.
-- -----------------------------------------------------------------------
WITH customer_rollup AS (
    SELECT
        customer_id,
        customer_name,
        SUM(sales)                     AS total_sales,
        COUNT(DISTINCT order_id)       AS order_count,
        MIN(order_date)                AS first_order_date,
        MAX(order_date)                AS last_order_date
    FROM sales_data
    GROUP BY customer_id, customer_name
),
customer_region_sales AS (
    -- Sales generated per customer, per region they've ever ordered from
    SELECT
        customer_id,
        region,
        SUM(sales) AS region_sales,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY SUM(sales) DESC, region ASC   -- deterministic tiebreak
        ) AS region_rank
    FROM sales_data
    GROUP BY customer_id, region
),
home_region AS (
    SELECT customer_id, region AS home_region
    FROM customer_region_sales
    WHERE region_rank = 1
),
snapshot AS (
    -- Cast back to DATE (not TIMESTAMP) so DATE - DATE below yields a
    -- plain integer day count instead of an INTERVAL type
    SELECT (MAX(order_date) + INTERVAL '1 day')::DATE AS snapshot_date   -- SQL Server: DATEADD(day, 1, MAX(order_date))
    FROM sales_data
)
SELECT
    hr.home_region,
    cr.customer_id,
    cr.customer_name,
    cr.order_count,
    ROUND(cr.total_sales, 2)                              AS total_sales,
    (sn.snapshot_date - cr.first_order_date)               AS tenure_days,   -- SQL Server: DATEDIFF(day, first_order_date, snapshot_date)
    (sn.snapshot_date - cr.last_order_date)                AS recency_days,
    CASE
        WHEN cr.order_count >= 8                                        THEN 'VIP'
        WHEN (sn.snapshot_date - cr.first_order_date) <= 730             THEN 'New'
        ELSE 'Regular'
    END AS customer_segment
FROM customer_rollup cr
JOIN home_region hr ON hr.customer_id = cr.customer_id
CROSS JOIN snapshot sn
WHERE cr.total_sales > 10000
ORDER BY
    hr.home_region ASC,
    -- Ordinal (not alphabetical) so VIP always sorts first within a region;
    -- sorting on the CASE string directly would give 'New' < 'Regular' < 'VIP'
    CASE
        WHEN cr.order_count >= 8                                THEN 1   -- VIP
        WHEN (sn.snapshot_date - cr.first_order_date) <= 730     THEN 2   -- New
        ELSE 3                                                            -- Regular
    END,
    cr.total_sales DESC;

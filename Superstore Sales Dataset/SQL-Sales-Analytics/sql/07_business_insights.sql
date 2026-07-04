/* =====================================================================
   07_BUSINESS_INSIGHTS.sql — Executive Summary Queries
   =====================================================================
   Purpose: this file does not introduce new analytical territory — it
   pulls together the handful of queries from 02-06 that a stakeholder
   actually acts on, plus two additional decision-support views (revenue
   concentration, growth-momentum check) that don't belong in any single
   earlier phase. Every number here is explained in full in ../REPORT.md.
   ===================================================================== */

-- -----------------------------------------------------------------------
-- 7.1  Revenue concentration (Pareto check)
--      "How many customers actually drive the business?" — answers it
--      directly instead of assuming the textbook 80/20 split holds.
-- -----------------------------------------------------------------------
WITH customer_totals AS (
    SELECT customer_id, SUM(sales) AS total_sales
    FROM sales_data
    GROUP BY customer_id
),
ranked AS (
    SELECT
        customer_id,
        total_sales,
        SUM(total_sales) OVER (
            ORDER BY total_sales DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )                                              AS cume_sales,
        SUM(total_sales) OVER ()                        AS grand_total,
        ROW_NUMBER() OVER (ORDER BY total_sales DESC)   AS customer_rank,
        COUNT(*) OVER ()                                 AS total_customers
    FROM customer_totals
)
SELECT
    MIN(CASE WHEN cume_sales / grand_total >= 0.8 THEN customer_rank END)  AS customers_needed_for_80pct_sales,
    MAX(total_customers)                                                   AS total_customers,
    ROUND(
        100.0 * MIN(CASE WHEN cume_sales / grand_total >= 0.8 THEN customer_rank END)
              / MAX(total_customers)
    , 1)                                                                   AS pct_of_customers_driving_80pct_sales
FROM ranked;

-- -----------------------------------------------------------------------
-- 7.2  Growth momentum check — is YoY growth accelerating or decelerating?
--      A second LAG() on top of the first turns a single growth number
--      into a trend-of-the-trend, which is what actually flags risk
--      early (see REPORT.md — 2018 growth rate fell 10.3pp vs. 2017).
-- -----------------------------------------------------------------------
WITH yearly_sales AS (
    SELECT
        EXTRACT(YEAR FROM order_date) AS sales_year,
        SUM(sales)                    AS total_sales
    FROM sales_data
    GROUP BY EXTRACT(YEAR FROM order_date)
),
yoy AS (
    SELECT
        sales_year,
        total_sales,
        100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY sales_year))
              / NULLIF(LAG(total_sales) OVER (ORDER BY sales_year), 0)   AS yoy_growth_pct
    FROM yearly_sales
)
SELECT
    sales_year,
    ROUND(total_sales, 2)      AS total_sales,
    ROUND(yoy_growth_pct, 2)   AS yoy_growth_pct,
    ROUND(yoy_growth_pct - LAG(yoy_growth_pct) OVER (ORDER BY sales_year), 2) AS growth_rate_change_vs_prior_year
FROM yoy
ORDER BY sales_year;

-- -----------------------------------------------------------------------
-- 7.3  Revenue at risk — pulls the "At Risk" RFM segment's dollar
--      exposure directly (mirrors 05_rfm_analysis.sql section 5.1,
--      filtered to the one segment that needs a campaign this quarter)
-- -----------------------------------------------------------------------
WITH snapshot AS (
    SELECT (MAX(order_date) + INTERVAL '1 day')::DATE AS snapshot_date FROM sales_data
),
rfm_base AS (
    SELECT
        s.customer_id,
        s.customer_name,
        (sn.snapshot_date - MAX(s.order_date))     AS recency_days,
        COUNT(DISTINCT s.order_id)                  AS frequency,
        SUM(s.sales)                                AS monetary
    FROM sales_data s
    CROSS JOIN snapshot sn
    GROUP BY s.customer_id, s.customer_name, sn.snapshot_date
),
rfm_scores AS (
    -- customer_id tiebreaker keeps NTILE's quintile cutoffs deterministic
    -- across runs when recency/frequency/monetary values tie (see the
    -- note in 05_rfm_analysis.sql for the verified before/after impact)
    SELECT
        *,
        (6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_id))  AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC, customer_id)           AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC, customer_id)            AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary
FROM rfm_scores
WHERE r_score <= 2 AND f_score >= 3        -- "At Risk" rule from 05_rfm_analysis.sql
ORDER BY monetary DESC;

-- -----------------------------------------------------------------------
-- 7.4  Expansion targets — cities with above-average customer volume but
--      below-average basket size (AOV) are the best candidates to copy
--      the NYC/LA "why" playbook (see REPORT.md section 2)
-- -----------------------------------------------------------------------
WITH city_metrics AS (
    SELECT
        city,
        COUNT(DISTINCT customer_id)  AS customer_count,
        COUNT(DISTINCT order_id)     AS order_count,
        SUM(sales)                   AS total_sales
    FROM sales_data
    GROUP BY city
),
company_avg AS (
    SELECT
        AVG(customer_count)               AS avg_customer_count,
        SUM(total_sales) / SUM(order_count) AS company_avg_order_value
    FROM city_metrics
)
SELECT
    cm.city,
    cm.customer_count,
    ROUND(cm.total_sales / cm.order_count, 2)  AS avg_order_value,
    ca.company_avg_order_value
FROM city_metrics cm
CROSS JOIN company_avg ca
WHERE cm.customer_count > ca.avg_customer_count                       -- above-average reach
  AND (cm.total_sales / cm.order_count) < ca.company_avg_order_value  -- below-average basket size
ORDER BY cm.customer_count DESC;

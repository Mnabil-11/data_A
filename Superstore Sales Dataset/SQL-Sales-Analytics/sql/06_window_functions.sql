/* =====================================================================
   06_WINDOW_FUNCTIONS.sql — Time-Series Analysis Using Window Functions
   Full narrative in ../REPORT.md.
   =====================================================================
   DESIGN NOTE — why GROUP BY still appears once, briefly:
   Line items must be collapsed to a single row per calendar period
   before "growth vs. the previous period" means anything — that grain
   change is unavoidable and GROUP BY is the correct tool for it.
   What we DON'T do is use a second GROUP BY, a self-join, or a
   correlated subquery to fetch "last period's value" — every one of
   those comparisons (MoM, YoY, QoQ, running total, moving average,
   ranking) is computed with LAG(), LEAD(), SUM() OVER, and RANK() OVER
   against the already-aggregated period rows. That is the "strictly
   window functions" part, and it is also strictly better performance:
   one pass over the period rows instead of N self-joins.
   ===================================================================== */

-- -----------------------------------------------------------------------
-- 6.1  Monthly Sales + Month-over-Month (MoM) growth  [LAG]
--      + running total + 3-month moving average (both window functions)
-- -----------------------------------------------------------------------
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE  AS month_start,     -- SQL Server: DATEFROMPARTS(YEAR(order_date), MONTH(order_date), 1)
        EXTRACT(YEAR FROM order_date)   AS sales_year,
        EXTRACT(MONTH FROM order_date)  AS sales_month,
        SUM(sales)                      AS total_sales
    FROM sales_data
    GROUP BY DATE_TRUNC('month', order_date), EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
)
SELECT
    sales_year,
    sales_month,
    ROUND(total_sales, 2)                                                        AS total_sales,

    -- MoM growth: LAG() reaches back one row (one month) with zero self-joins
    ROUND(LAG(total_sales) OVER (ORDER BY month_start), 2)                       AS prev_month_sales,
    ROUND(
        100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY month_start))
              / NULLIF(LAG(total_sales) OVER (ORDER BY month_start), 0)
    , 2)                                                                         AS mom_growth_pct,

    -- Running total (year-to-date-and-beyond) — cumulative frame
    ROUND(SUM(total_sales) OVER (ORDER BY month_start
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2)                  AS running_total_sales,

    -- 3-month trailing moving average — smooths noise for trend charts
    ROUND(AVG(total_sales) OVER (ORDER BY month_start
          ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2)                          AS moving_avg_3mo
FROM monthly_sales
ORDER BY month_start;

-- -----------------------------------------------------------------------
-- 6.2  Yearly Sales + Year-over-Year (YoY) growth  [LAG]
-- -----------------------------------------------------------------------
WITH yearly_sales AS (
    SELECT
        EXTRACT(YEAR FROM order_date) AS sales_year,
        SUM(sales)                    AS total_sales
    FROM sales_data
    GROUP BY EXTRACT(YEAR FROM order_date)
)
SELECT
    sales_year,
    ROUND(total_sales, 2)                                                  AS total_sales,
    ROUND(LAG(total_sales) OVER (ORDER BY sales_year), 2)                  AS prior_year_sales,
    ROUND(
        100.0 * (total_sales - LAG(total_sales) OVER (ORDER BY sales_year))
              / NULLIF(LAG(total_sales) OVER (ORDER BY sales_year), 0)
    , 2)                                                                   AS yoy_growth_pct
FROM yearly_sales
ORDER BY sales_year;

-- -----------------------------------------------------------------------
-- 6.3  Quarterly Sales + Quarter-over-Quarter (QoQ) AND
--      "same quarter last year" YoY comparison  [LAG with offset 4]
-- -----------------------------------------------------------------------
WITH quarterly_sales AS (
    SELECT
        EXTRACT(YEAR FROM order_date)    AS sales_year,
        EXTRACT(QUARTER FROM order_date) AS sales_quarter,               -- SQL Server: DATEPART(quarter, order_date)
        SUM(sales)                       AS total_sales
    FROM sales_data
    GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(QUARTER FROM order_date)
)
SELECT
    sales_year,
    sales_quarter,
    ROUND(total_sales, 2)                                                          AS total_sales,

    -- QoQ: previous row = previous quarter
    ROUND(
        100.0 * (total_sales - LAG(total_sales, 1) OVER (ORDER BY sales_year, sales_quarter))
              / NULLIF(LAG(total_sales, 1) OVER (ORDER BY sales_year, sales_quarter), 0)
    , 2)                                                                            AS qoq_growth_pct,

    -- YoY at quarterly grain: offset 4 rows back = same quarter, prior year
    ROUND(
        100.0 * (total_sales - LAG(total_sales, 4) OVER (ORDER BY sales_year, sales_quarter))
              / NULLIF(LAG(total_sales, 4) OVER (ORDER BY sales_year, sales_quarter), 0)
    , 2)                                                                            AS yoy_same_quarter_growth_pct
FROM quarterly_sales
ORDER BY sales_year, sales_quarter;

-- -----------------------------------------------------------------------
-- 6.4  Forward-looking view with LEAD() + a calendar-gap data-quality
--      check (confirms there is no missing month in the series — a
--      real risk when trusting LAG/LEAD offsets to mean "one period")
-- -----------------------------------------------------------------------
WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', order_date)::DATE AS month_start,
        SUM(sales)                            AS total_sales
    FROM sales_data
    GROUP BY DATE_TRUNC('month', order_date)
)
SELECT
    month_start,
    ROUND(total_sales, 2)                                            AS total_sales,
    ROUND(LEAD(total_sales) OVER (ORDER BY month_start), 2)          AS next_month_sales,
    ROUND(
        LEAD(total_sales) OVER (ORDER BY month_start) - total_sales
    , 2)                                                              AS sales_change_to_next_month,
    LEAD(month_start) OVER (ORDER BY month_start)                    AS next_month_start,
    -- Should always be exactly 1 month; anything else flags a gap in the series
    DATE_DIFF('month', month_start, LEAD(month_start) OVER (ORDER BY month_start)) AS months_to_next_row
FROM monthly_sales
ORDER BY month_start;

-- -----------------------------------------------------------------------
-- 6.5  Best / worst month within each year  [RANK / DENSE_RANK]
--      Answers "which month drives each year's performance" without a
--      second query per year (no GROUP BY + MAX + self-join needed)
-- -----------------------------------------------------------------------
WITH monthly_sales AS (
    SELECT
        EXTRACT(YEAR FROM order_date)  AS sales_year,
        EXTRACT(MONTH FROM order_date) AS sales_month,
        SUM(sales)                     AS total_sales
    FROM sales_data
    GROUP BY EXTRACT(YEAR FROM order_date), EXTRACT(MONTH FROM order_date)
)
SELECT
    sales_year,
    sales_month,
    ROUND(total_sales, 2)                                                            AS total_sales,
    RANK() OVER (PARTITION BY sales_year ORDER BY total_sales DESC)                  AS rank_within_year_desc,
    RANK() OVER (PARTITION BY sales_year ORDER BY total_sales ASC)                   AS rank_within_year_asc
FROM monthly_sales
QUALIFY rank_within_year_desc = 1 OR rank_within_year_asc = 1        -- DuckDB/Snowflake QUALIFY; Postgres/SQL Server: wrap in an outer SELECT ... WHERE instead
ORDER BY sales_year, rank_within_year_desc;

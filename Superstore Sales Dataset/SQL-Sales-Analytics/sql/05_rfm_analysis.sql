/* =====================================================================
   05_RFM_ANALYSIS.sql — RFM Analysis (Marketing Segmentation)
   Full narrative in ../REPORT.md.
   =====================================================================
   R = Recency:   days since the customer's most recent order
                  (lower is better — scored 1..5, 5 = most recent)
   F = Frequency: distinct orders placed (higher is better, 5 = most)
   M = Monetary:  lifetime Sales (higher is better, 5 = most)

   Snapshot date = the day AFTER the last order in the dataset. In
   production this should be CURRENT_DATE — using max(order_date)+1
   here only because this dataset ends in the past (2018-12-30) and
   CURRENT_DATE would make every customer look "lost."
   ===================================================================== */

WITH snapshot AS (
    -- Cast back to DATE (not TIMESTAMP) so DATE - DATE below yields a
    -- plain integer day count instead of an INTERVAL type
    SELECT (MAX(order_date) + INTERVAL '1 day')::DATE AS snapshot_date   -- Prod: use CURRENT_DATE instead
    FROM sales_data
),

-- Step 1: collapse line items down to one row per customer (the RFM grain)
rfm_base AS (
    SELECT
        s.customer_id,
        s.customer_name,
        (sn.snapshot_date - MAX(s.order_date))     AS recency_days,     -- SQL Server: DATEDIFF(day, MAX(s.order_date), sn.snapshot_date)
        COUNT(DISTINCT s.order_id)                 AS frequency,
        SUM(s.sales)                               AS monetary
    FROM sales_data s
    CROSS JOIN snapshot sn
    GROUP BY s.customer_id, s.customer_name, sn.snapshot_date
),

-- Step 2: NTILE(5) buckets every customer into quintiles per metric.
-- Recency is inverted (6 - NTILE) because NTILE(... ORDER BY x ASC)
-- puts the SMALLEST recency_days (= most recent = best customer) in
-- bucket 1, but our score convention says 5 = best — flipping it once
-- here means every downstream CASE rule can just say "high score = good".
rfm_scores AS (
    -- customer_id is appended as a deterministic tiebreaker: recency/
    -- frequency/monetary all have heavy ties (frequency is only 1-17),
    -- and NTILE's bucket cutoff for tied values is otherwise undefined
    -- by the SQL standard — different engines/runs can silently assign
    -- a tied customer to a different quintile without it. Verified: on
    -- this dataset, omitting the tiebreaker made the "At Risk" segment
    -- count fluctuate between 141/143/141 across three identical runs;
    -- adding it made every run return exactly 141.
    SELECT
        *,
        (6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_id))  AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC, customer_id)           AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC, customer_id)            AS m_score
    FROM rfm_base
),

-- Step 3: translate the 3 scores into a single marketing segment.
-- Rule order matters (first match wins) — Champions is checked before
-- the broader Loyal rule so a Champion is never demoted by a looser rule.
rfm_segments AS (
    SELECT
        *,
        (r_score + f_score + m_score) AS rfm_total_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4
                THEN 'Champions'          -- bought recently, often, and big
            WHEN f_score >= 4 AND r_score >= 3
                THEN 'Loyal Customers'    -- frequent buyers, still active
            WHEN r_score <= 2 AND f_score >= 3
                THEN 'At Risk'            -- used to buy often/big, gone quiet
            WHEN r_score <= 2 AND f_score <= 2
                THEN 'Lost Customers'     -- rarely bought, long gone
            ELSE 'Needs Attention'         -- doesn't cleanly fit an extreme —
                                            -- mid-tier on every axis; a real
                                            -- 5th bucket, not a bug
        END AS rfm_segment
    FROM rfm_scores
)

SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    ROUND(monetary, 2)   AS monetary,
    r_score,
    f_score,
    m_score,
    rfm_total_score,
    rfm_segment
FROM rfm_segments
ORDER BY rfm_total_score DESC, monetary DESC;

-- -----------------------------------------------------------------------
-- 5.1  Segment-level rollup for the marketing team (size + value at stake)
-- -----------------------------------------------------------------------
WITH snapshot AS (
    SELECT (MAX(order_date) + INTERVAL '1 day')::DATE AS snapshot_date FROM sales_data
),
rfm_base AS (
    SELECT
        s.customer_id,
        (sn.snapshot_date - MAX(s.order_date))     AS recency_days,
        COUNT(DISTINCT s.order_id)                  AS frequency,
        SUM(s.sales)                                AS monetary
    FROM sales_data s
    CROSS JOIN snapshot sn
    GROUP BY s.customer_id, sn.snapshot_date
),
rfm_scores AS (
    -- customer_id is appended as a deterministic tiebreaker: recency/
    -- frequency/monetary all have heavy ties (frequency is only 1-17),
    -- and NTILE's bucket cutoff for tied values is otherwise undefined
    -- by the SQL standard — different engines/runs can silently assign
    -- a tied customer to a different quintile without it. Verified: on
    -- this dataset, omitting the tiebreaker made the "At Risk" segment
    -- count fluctuate between 141/143/141 across three identical runs;
    -- adding it made every run return exactly 141.
    SELECT
        *,
        (6 - NTILE(5) OVER (ORDER BY recency_days ASC, customer_id))  AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC, customer_id)           AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC, customer_id)            AS m_score
    FROM rfm_base
),
rfm_segments AS (
    SELECT
        *,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN f_score >= 4 AND r_score >= 3                  THEN 'Loyal Customers'
            WHEN r_score <= 2 AND f_score >= 3                  THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2                  THEN 'Lost Customers'
            ELSE 'Needs Attention'
        END AS rfm_segment
    FROM rfm_scores
)
SELECT
    rfm_segment,
    COUNT(*)                                                     AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_customers,
    ROUND(AVG(recency_days), 1)                                  AS avg_recency_days,
    ROUND(AVG(frequency), 1)                                     AS avg_frequency,
    ROUND(SUM(monetary), 2)                                      AS total_monetary,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1)  AS pct_of_total_sales
FROM rfm_segments
GROUP BY rfm_segment
ORDER BY total_monetary DESC;

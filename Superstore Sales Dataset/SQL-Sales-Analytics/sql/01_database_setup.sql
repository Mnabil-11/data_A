/* =====================================================================
   01_DATABASE_SETUP.sql
   Superstore Sales Analytics Project — Staging/Fact Table & Indexes
   Compatible with: PostgreSQL and SQL Server (dialect notes inline)
   =====================================================================
   DATA REALITY CHECK (verified against the actual data/train.csv):
     - Grain: one row = one order LINE ITEM (Order ID repeats when an
       order has multiple products). 9,800 line items / 4,922 orders.
     - Columns available: Row ID, Order ID, Order Date, Ship Date,
       Ship Mode, Customer ID, Customer Name, Segment, Country, City,
       State, Postal Code, Region, Product ID, Category, Sub-Category,
       Product Name, Sales.
     - There is NO Profit, NO Discount, NO Quantity column in this
       dataset. Every query in this project is therefore built on Sales
       (revenue) as the single performance metric. Anywhere the
       business asked for "profit" or "discount" logic, it has been
       re-scoped to the nearest Sales-based equivalent and is called
       out explicitly in the relevant script.
     - Postal Code has 11 NULLs (rows with missing ZIP) — harmless for
       these queries since we never join or filter on it.
     - Customer ID is NOT 1:1 with Region: 765 of 793 customers have
       shipped orders into more than one region. Any query that claims
       a single "region" per customer (see 04_customer_analysis.sql)
       must derive a "home region" (the region driving most of that
       customer's Sales) rather than assuming one exists as a raw
       column.
   ===================================================================== */

CREATE TABLE sales_data (
    row_id          INT             NOT NULL PRIMARY KEY,
    order_id        VARCHAR(20)     NOT NULL,
    order_date      DATE            NOT NULL,
    ship_date       DATE            NOT NULL,
    ship_mode       VARCHAR(20)     NOT NULL,
    customer_id     VARCHAR(20)     NOT NULL,
    customer_name   VARCHAR(100)    NOT NULL,
    segment         VARCHAR(20)     NOT NULL,
    country         VARCHAR(50)     NOT NULL,
    city            VARCHAR(50)     NOT NULL,
    state           VARCHAR(50)     NOT NULL,
    postal_code     VARCHAR(10)     NULL,
    region          VARCHAR(20)     NOT NULL,
    product_id      VARCHAR(20)     NOT NULL,
    category        VARCHAR(30)     NOT NULL,
    sub_category    VARCHAR(30)     NOT NULL,
    product_name    VARCHAR(255)    NOT NULL,
    sales           DECIMAL(12,4)   NOT NULL
);

/* ---------------------------------------------------------------------
   Load data (adjust to your engine):
     PostgreSQL : \copy sales_data FROM 'data/train.csv' WITH (FORMAT csv, HEADER true)
     SQL Server : BULK INSERT sales_data FROM 'data\train.csv'
                  WITH (FORMAT='CSV', FIRSTROW=2)
   A pre-loaded reference copy also ships at database/superstore.duckdb
   for local reproducibility without installing a full RDBMS.
   --------------------------------------------------------------------- */

/* ---------------------------------------------------------------------
   INDEXING STRATEGY
   Every index below is justified by a query pattern used in the other
   sql/ scripts, not added speculatively. See 07_business_insights.sql
   and the README for the full rationale (composite key order, covering
   indexes, etc.).
   --------------------------------------------------------------------- */

-- Time-series queries (06_window_functions.sql) always filter/group on order_date first
CREATE INDEX ix_sales_order_date       ON sales_data (order_date);

-- Customer roll-ups (04_customer_analysis.sql, 05_rfm_analysis.sql) key off customer_id
CREATE INDEX ix_sales_customer_id      ON sales_data (customer_id, order_date, sales);

-- Geography roll-ups (02_kpi_queries.sql, 03_sales_analysis.sql region/city "why" analysis)
CREATE INDEX ix_sales_geo              ON sales_data (region, state, city);

-- Product/category roll-ups (02_kpi_queries.sql, 03_sales_analysis.sql)
CREATE INDEX ix_sales_category         ON sales_data (category, sub_category);

-- Order-level rollups (many CTEs collapse line items to one row per order)
CREATE INDEX ix_sales_order_id         ON sales_data (order_id);

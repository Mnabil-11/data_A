# Power BI Dashboard

**Note on `PowerBI.pbix`:** a `.pbix` is a binary file that only Power BI Desktop can
produce — it can't be generated from a script. This folder is the placeholder for it;
open Power BI Desktop, build the report using the steps below, and save it here as
`PowerBI.pbix`.

## Fastest path: import the pre-built CSVs

Every table below is already exported to [`../outputs/`](../outputs) using the exact
queries in [`../sql/`](../sql) run against the real data — no DAX aggregation needed to
get started, just load and visualize.

`Get Data -> Text/CSV` each of:

| File | Use for |
|---|---|
| `kpi_summary.csv` | KPI cards (Total Sales, Total Orders, Avg Order Value...) |
| `monthly_sales_trend.csv` | Line chart: Sales + MoM growth % + 3-month moving average |
| `yearly_sales_yoy.csv` | YoY growth bar/column chart |
| `top_customers.csv` | Top 25 customers table/bar chart |
| `city_region_performance.csv` | Map + AOV-index bar chart (the "why" analysis) |
| `category_breakdown.csv` | Category/Sub-Category treemap |
| `customer_segments_over_10k.csv` | VIP/New/Regular table, sliceable by region |
| `rfm_customer_scores.csv` | Customer-level RFM scatter (Recency vs. Frequency, sized by Monetary) |
| `rfm_segment_summary.csv` | Segment donut/bar chart (Champions/Loyal/At Risk/Lost/Needs Attention) |

## Live-connection path (recommended once you move past a static snapshot)

Instead of static CSVs, connect Power BI directly to `../database/superstore.duckdb`
(via the DuckDB ODBC driver) or point the same `sql/*.sql` scripts at a real
PostgreSQL/SQL Server instance loaded from `../sql/01_database_setup.sql` — the queries
are written to run unmodified against either engine (dialect notes are inline as SQL
comments). This way each visual's underlying query re-runs against fresh data instead of
a point-in-time export.

## Suggested report pages (mirrors the project's 5 analysis phases)

1. **Executive Overview** — KPI cards, YoY trend line, category treemap
2. **Sales Deep Dive** — city/region map with AOV index, category mix by city
3. **Customer Segmentation** — VIP/New/Regular table, home-region slicer
4. **Time Intelligence** — monthly trend with MoM/running total/moving average
5. **RFM & Marketing** — Recency vs. Frequency scatter, segment sizes, revenue-at-risk callout

See [`../REPORT.md`](../REPORT.md) for the narrative each page should support.

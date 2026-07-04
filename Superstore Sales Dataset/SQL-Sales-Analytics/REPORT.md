# Superstore Sales Analytics — Business Report

All figures below were produced by running the scripts in [`sql/`](sql) against the real
9,800-row dataset (verified via DuckDB, not estimated). Where a query underlying a
statement lives in a specific file, it's noted in parentheses.

**Scope note:** the source data has no Profit, Discount, or Quantity column — only
Sales. Every "why," "best," and "most profitable"-style question below is answered using
Sales (revenue) as the metric, with the substitution called out wherever it changes what
the original ask would have measured with Profit/Discount.

---

## 1. Executive Overview

| Metric | Value |
|---|---|
| Total Sales | $2,261,536.78 |
| Total Orders | 4,922 |
| Total Line Items | 9,800 |
| Total Customers | 793 |
| Total Products | ~1,850 |
| Avg Sales per Order | $459.48 |
| Highest single order | $23,661.23 |
| Lowest single order | $0.56 |
| Date range | 2015-01-03 → 2018-12-30 |

*(`sql/02_kpi_queries.sql` §2.1)*

Order values are highly skewed — the largest single line item is $22,638 (a Cisco
TelePresence unit) against a $0.44 floor — so mean-based views understate how
concentrated value actually is. See the concentration finding in §5.

---

## 2. Who and where: best performers

- **Best client:** Sean Miller — $25,043 lifetime Sales from only 5 orders. A "whale"
  who buys big and infrequently, not a loyal repeat buyer — contrast with Adrian Barton
  or Ken Lonsdale, who post similar lifetime value across 10–12 orders. Same dollar
  value, very different retention profile (see §6 RFM).
- **Best city / state:** New York City ($252,463) / California ($446,306, driven by
  both LA and San Francisco).
- **Best category by revenue:** Technology ($827,456 / 36.6% of Sales), narrowly ahead
  of Furniture (32.2%) and Office Supplies (31.2%). This is standing in for "most
  profitable category" since margin data doesn't exist — **flag to stakeholders before
  using it to justify inventory or marketing spend**, since a high-revenue category can
  still be low-margin.
- **Best-selling products by revenue:** Canon imageCLASS 2200 Advanced Copier ($61,600),
  Fellowes PB500 Binding Machine ($27,453), Cisco TelePresence EX90 ($22,638).
- **Most frequently re-ordered (proxy for "best-selling" since there's no Quantity
  column):** Staple envelope (47 order lines), Staples (46), Easy-staple paper (44) — cheap
  consumables ordered often, a completely different signal from the revenue leaders above.

*(`sql/02_kpi_queries.sql` §2.2–2.5)*

---

## 3. The "Why" — root-cause of city/region performance

Without Discount data, "why does City X win" is answered with a Sales decomposition
instead: **Total Sales = Customers × Orders-per-Customer × Avg Order Value (AOV)**. This
isolates whether a city wins on *reach* (customer volume) or *order economics* (bigger
baskets), and is arguably more actionable than a raw discount figure would have been.

- **NYC's edge is basket size, not customer count.** NYC's AOV ($575) runs **~25% above**
  the company average ($459), while its customer count (349) is only slightly above LA's
  (300). NYC and LA both over-index on Technology (43%/42% of city Sales vs. 36.6%
  company-wide) — more high-ticket Technology items per order is the actual driver.
  **Action:** replicate the Technology bundling/cross-sell approach used in NYC/LA in
  mid-tier cities that currently under-index on AOV (see the expansion-target list below).
- **Region view:** West leads on raw Sales ($710k) from a genuine volume *and* frequency
  advantage — more customers (681 vs. East's 669) *and* more orders per customer (2.33
  vs. 2.05). East, however, has the highest AOV ($489 vs. West's $447) — East customers
  buy less often but spend more per basket. **Different growth levers apply:** West
  should focus on retention/frequency programs (it already wins on reach); East is the
  better candidate for basket-size upsell tactics (bundles, cross-sell).

*(`sql/03_sales_analysis.sql` §3.2)*

### Expansion targets (`sql/07_business_insights.sql` §7.4)

Cities with above-average customer reach but below-average AOV — the best candidates to
copy the NYC/LA playbook: **Los Angeles, Philadelphia, San Francisco, Houston, Chicago**,
plus a long tail of smaller metros (Columbus, Dallas, Miami, Phoenix, etc.). These are
customer-rich but basket-poor — cross-sell/bundle campaigns should show up here first.

---

## 4. Customer segmentation (>$10,000 lifetime Sales)

Only **19 of 793 customers (2.4%)** have crossed $10,000 lifetime Sales — high-value
customers are rare here, so retaining each one has outsized impact.

**Data nuance worth calling out:** Region is *not* a stable attribute of a customer in
this dataset — 765 of 793 customers have shipped orders into more than one region.
"Sort within region" therefore required deriving a **home region** per customer (the
region generating the most of that customer's Sales, via `ROW_NUMBER()`), not reading it
off a raw column.

**Segment rules** (`sql/04_customer_analysis.sql` §4.2): VIP = ≥8 orders (repeat,
loyal, high-value); New = first order within the last 2 years (already high-value on a
short tenure); Regular = everything else (often a "whale" one-off big-ticket buyer).

| Segment | Count | Notable names |
|---|---|---|
| VIP | 9 | Adrian Barton, Sanjit Chand, Greg Tran, Seth Vernon, Caroline Jumper, Sanjit Engle, Maria Etezadi, Ken Lonsdale, Clay Ludtke |
| New | 2 | Raymond Buch, Christopher Conant |
| Regular | 8 | Sean Miller ($25,043 from just 5 orders — the single biggest account by revenue but *not* high-frequency, a concentration risk rather than a loyalty win), Tamara Chand, Becky Martin, Tom Ashbrook, Hunter Lopez, Todd Sumrall, Bill Shonely, Karen Ferguson |

---

## 5. Revenue concentration (`sql/07_business_insights.sql` §7.1)

**49.6% of customers (393 of 793) drive 80% of total Sales.** This is notably *less*
concentrated than the textbook 80/20 rule — revenue is broadly spread across roughly
half the customer base rather than resting on a small clique of whales. That's a
healthier risk profile than the Sean Miller-style "biggest account" headline alone
would suggest, but it also means retention programs need to reach a wide base, not just
a handful of top accounts.

---

## 6. Time-series trends (window functions: LAG, LEAD, RANK, running totals)

*(`sql/06_window_functions.sql`, cross-checked in `sql/07_business_insights.sql` §7.2)*

| Year | Total Sales | YoY Growth |
|---|---|---|
| 2015 | $479,856.21 | — |
| 2016 | $459,436.01 | −4.26% |
| 2017 | $600,192.55 | +30.64% |
| 2018 | $722,052.02 | +20.30% |

- **2016 was the only down year** in the dataset — worth a root-cause dig (region/category
  regression) if the source system is ever revisited.
- **Growth is decelerating despite still being strong:** 2017 added $140,757 in YoY Sales
  (+30.6%); 2018 added only $121,859 (+20.3%) — both the growth *rate* and the absolute
  *dollar* increase shrank year-over-year (a 10.3-point drop in growth rate). Worth
  flagging to leadership now, before it shows up as an outright down year like 2016 did.
- **Consistent seasonality:** September, November, and December are — in some order —
  the top-3 months every single year (peak $117,938 in Nov 2018), while January/February
  are the weakest month every single year. This is a back-to-school (Sep) plus
  holiday-driven (Nov/Dec) demand curve. Inventory and staffing should front-load Q4;
  promotional calendars should treat Jan/Feb as the expected trough, not a marketing
  failure.

---

## 7. RFM analysis & marketing segments

*(`sql/05_rfm_analysis.sql`; verified, deterministic output — see the correctness note
below)*

Recency = days since last order, Frequency = distinct orders, Monetary = lifetime Sales,
each scored into quintiles (`NTILE(5)`) and combined into a segment via `CASE`.

| Segment | Customers | % of customers | Total Sales | % of Sales | Avg Recency | Avg Frequency |
|---|---|---|---|---|---|---|
| Needs Attention | 238 | 30.0% | $585,175.77 | 25.9% | 45.4 days | 4.8 |
| Champions | 103 | 13.0% | $547,977.51 | 24.2% | 26.0 days | 9.3 |
| At Risk | 141 | 17.8% | $489,373.34 | 21.6% | 226.8 days | 7.4 |
| Loyal Customers | 136 | 17.2% | $365,512.88 | 16.2% | 52.9 days | 8.3 |
| Lost Customers | 175 | 22.1% | $273,497.28 | 12.1% | 375.7 days | 3.7 |

**Reading the segments:**

- **Champions** are only 13% of customers but drive 24% of Sales — protect this group
  first (early access, loyalty perks, dedicated account management).
- **At Risk is the most financially urgent segment.** These 141 customers already proved
  they spend big and often (frequency 7.4, nearly as high as Champions) but haven't
  ordered in an average of 227 days — **~$489k in Sales actively slipping away.** A
  targeted win-back campaign has a clear, quantifiable revenue target
  (`sql/07_business_insights.sql` §7.3 pulls this exact customer list).
- **Lost Customers** (175, avg 376 days silent) were low-frequency to begin with
  (3.7 orders) — reactivation ROI is lower than for At Risk; a low-cost automated
  win-back email is more appropriate than high-touch outreach.
- **Needs Attention** is the largest bucket by both customer count (30%) and revenue
  (26%) — customers who don't fit a clean extreme (recent-but-infrequent, or
  frequent-but-small-basket). Best pool for A/B-tested upsell/cross-sell campaigns since
  they're still actively engaged (avg recency 45 days) but haven't converted into
  high-value repeat buyers.

**Correctness note:** `NTILE()` has no defined tie-breaking behavior in the SQL
standard. On this dataset (heavy ties in `frequency`, which only ranges 1–17), omitting
a deterministic tiebreaker made the "At Risk" segment count fluctuate between 141/143/141
across three otherwise-identical runs. Adding `customer_id` as a secondary `ORDER BY` key
inside every `NTILE(...)` call fixed it — every run now returns exactly the numbers
above. See `sql/05_rfm_analysis.sql` for the fix.

---

## 8. Recommendations (priority order)

1. **Win back the At Risk segment now** — 141 customers, ~$489k in Sales, all previously
   high-frequency spenders gone quiet for 227+ days on average. Highest-ROI action on
   this list.
2. **Protect Champions** (103 customers, 24% of Sales) with loyalty perks before they
   have a reason to look elsewhere.
3. **Replicate the NYC/LA Technology-bundling playbook** in Houston, Chicago, and the
   other customer-rich/AOV-poor cities identified in §3.
4. **Flag the growth deceleration** (30.6% → 20.3% YoY) to leadership as an early
   warning, using the same LAG()-driven trend that caught it.
5. **Request Profit/Discount/Quantity data** from the source system if margin-based
   decisions (e.g. "should Technology be discounted more") are actually needed — Sales
   volume alone can make a high-revenue, low-margin category look like an unqualified
   winner.

---

## 9. Technical design notes (Phase 5 summary)

Full detail lives inline as comments in the `sql/` scripts; summary:

- **CTEs over nested subqueries:** every multi-step query (RFM scoring, home-region
  derivation) reads top-to-bottom in the same order a human would explain it, and each
  named step can be run standalone for debugging. Not chosen for a performance
  difference — modern optimizers largely treat them the same.
- **Window functions over GROUP BY:** used exactly where a row needs to keep its
  identity *and* be compared against a value from its group (LAG for period-over-period
  growth, ROW_NUMBER for home-region selection, NTILE for RFM quintiles) — GROUP BY
  cannot express "same number of rows out, enriched with group context" without a
  self-join or correlated subquery.
- **Scaling this past 9,800 rows:** index the actual query predicates (done in
  `sql/01_database_setup.sql`), avoid `SELECT *`, materialize the slow-changing rollups
  (monthly Sales, RFM snapshot) instead of recomputing them live, and partition the fact
  table by `order_date` once it spans multiple years of real volume.

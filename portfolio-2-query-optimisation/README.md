# Portfolio 2: Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems
**Student:** Adejoke Ogunyinka (30150302)
**DBMS:** PostgreSQL 17, Cartify database (50,000 orders, ~150,000 order lines, 5,000 customers, 500 products)

---

## 1. Objective

Take six real Cartify business queries, measure how PostgreSQL executes them on a freshly loaded database with no custom indexes, design an indexing strategy, and measure again. Where an index does not help, explain why and apply a different technique.

## 2. Files

| File | Purpose |
|---|---|
| `sql/01_queries.sql` | The six business queries, each tied to a case-study operation |
| `sql/02_explain_before.sql` | `EXPLAIN (ANALYZE, BUFFERS)` for each query, before indexing |
| `sql/03_create_indexes.sql` | The seven indexes, each with its justification |
| `sql/04_explain_after.sql` | The same plans after indexing, plus a rewritten Q2 |
| `sql/05_materialized_view.sql` | Precomputed aggregate for the report query (Q5) |
| `results/query_results.txt` | Output rows of the six queries |
| `results/explain_before.txt` | Full before-plans with timings and buffer counts |
| `results/create_indexes.txt` | Index build times and sizes |
| `results/explain_after.txt` | Full after-plans |
| `results/materialized_view.txt` | Plan and output for the materialised view |
| `screenshots/` | Terminal evidence |

## 3. How to reproduce

```
psql -d cartify -f sql/02_explain_before.sql > results/explain_before.txt
psql -d cartify -f sql/03_create_indexes.sql > results/create_indexes.txt
psql -d cartify -f sql/04_explain_after.sql  > results/explain_after.txt
psql -d cartify -f sql/05_materialized_view.sql > results/materialized_view.txt
```

## 4. How to read the plans

`EXPLAIN (ANALYZE, BUFFERS)` runs the query and reports, for every step:
- the **scan type**: `Seq Scan` reads the whole table; `Index Scan` or `Bitmap Index Scan` uses an index to jump to matching rows;
- **actual rows** versus **estimated rows**, which shows whether the planner's statistics are accurate;
- **Buffers: shared hit=N**: how many 8 KB pages were read. This is the most reliable cost measure on a small, in-memory dataset, because timings fluctuate but page counts do not;
- **Execution Time** in milliseconds.

## 5. Baseline: before indexing

Only the indexes PostgreSQL creates automatically for `PRIMARY KEY` and `UNIQUE` constraints existed. Foreign key columns and search columns had none. Every query was a sequential scan:

| # | Query | Plan | Pages read | Time |
|---|---|---|---|---|
| Q1 | Customer order history | Seq Scan on orders, then sort | 887 | 2.60 ms |
| Q2 | Catalogue search `ILIKE 'Samsung%'` | Seq Scan on products | 11 | 0.20 ms |
| Q3 | Products in category with stock | Seq Scan on products and categories, hash join | 9 | 0.09 ms |
| Q4 | Shipped orders in last 30 days | Seq Scan on orders | 884 | 4.15 ms |
| Q5 | Top 10 selling products | Parallel Seq Scan on order_items, Seq Scan on orders, hash joins, aggregate, sort | 2,898 | 31.3 ms |
| Q6 | Revenue by state | Seq Scan on orders and addresses, hash join, aggregate | 952 | 17.6 ms |

Q1 is the clearest problem: PostgreSQL read all 887 pages of the orders table (50,000 rows) to return 11 rows for one customer. On the "My Orders" page this runs once per page view for every customer.

## 6. Indexing strategy

Each index is justified by one query. A general rule applied throughout: **index the columns in `WHERE` and `JOIN ... ON`, and put equality columns before range columns in a composite index.**

| Index | Columns | For | Reasoning |
|---|---|---|---|
| `idx_orders_customer_date` | `orders (customer_id, order_date DESC)` | Q1 | Composite: equality on customer_id, then the sort column, so the index returns rows already in the required order and the sort step disappears. |
| `idx_orders_status_date` | `orders (status, order_date)` | Q4 | Equality on status first, range on order_date second. |
| `idx_products_category` | `products (category_id)` | Q3 | Foreign key column, not auto-indexed. |
| `idx_order_items_order` | `order_items (order_id)` | Q5, Portfolio 3 | Join column on the largest table. |
| `idx_order_items_product` | `order_items (product_id)` | Q5 | Join column on the largest table. |
| `idx_orders_address` | `orders (address_id)` | Q6 | Join column. |
| `idx_products_name_lower` | `products (lower(name) text_pattern_ops)` | Q2 | Expression index for case-insensitive prefix search. |

All seven built in under 200 ms total and occupy about 5 MB (see `results/create_indexes.txt`).

## 7. Results: after indexing

| # | Query | Plan after | Pages before | Pages after | Time before | Time after | Verdict |
|---|---|---|---|---|---|---|---|
| Q1 | Customer order history | Bitmap Index Scan on `idx_orders_customer_date` | 887 | 16 | 2.60 ms | 0.08 ms | **55x fewer pages, 33x faster** |
| Q2 | Catalogue search (original `ILIKE`) | Seq Scan, unchanged | 11 | 11 | 0.20 ms | 0.29 ms | No change (see below) |
| Q2' | Catalogue search (rewritten `lower(name) LIKE`) | Bitmap Index Scan on `idx_products_name_lower` | 11 | 9 | 0.20 ms | 0.04 ms | Index now used, 5x faster |
| Q3 | Products in category | Bitmap Index Scan on `idx_products_category` | 9 | 10 | 0.09 ms | 0.04 ms | Index used, 2x faster |
| Q4 | Shipped orders, 30 days | Bitmap Index Scan on `idx_orders_status_date` | 884 | 198 | 4.15 ms | 0.45 ms | **4.5x fewer pages, 9x faster** |
| Q5 | Top 10 products | Unchanged: Parallel Seq Scan | 2,898 | 2,898 | 31.3 ms | 32.3 ms | No change (see below) |
| Q5' | Top 10 products via materialised view | Index Scan on `mv_product_sales` | 2,898 | 10 | 31.3 ms | 0.02 ms | **290x fewer pages, 1,500x faster** |
| Q6 | Revenue by state | Unchanged: Seq Scan, hash join | 952 | 952 | 17.6 ms | 18.8 ms | No change (see below) |

### 7.1 Why Q1 and Q4 improved the most
Both are *selective*: they need a small fraction of a large table (11 of 50,000 rows; 247 of 50,000). This is the case indexes are built for. In Q1 the composite index also removed the `Sort` step entirely, because the index already stores each customer's orders in `order_date DESC` order.

### 7.2 Why Q2 did not change until the query was rewritten
`ILIKE 'Samsung%'` cannot use a B-tree index: case-insensitive matching means the index's sorted order of `name` does not correspond to the matching rows. The fix is an *expression index* on `lower(name)` with `text_pattern_ops`, and rewriting the query as `lower(name) LIKE 'samsung%'`. The application should always send lower-cased search terms. Lesson: the query text and the index must be designed together.

### 7.3 Why Q3 shows a small gain
`products` has only 500 rows and fits in 9 pages. The planner's cost estimate for a sequential scan (14.25) and an index scan (12.90) are close. The index was chosen, but on a table this small the difference is marginal. At 50,000 products the gap would be large. Lesson: the benefit of an index grows with table size.

### 7.4 Why Q5 and Q6 did not change
Both read a large fraction of their tables. Q5 needs every delivered order line (about 75,000 of 150,000 rows); Q6 needs 71% of orders. When most rows are needed, following an index means jumping around the table page by page, which costs more than reading the pages in order. The planner correctly chose a sequential scan both times. The join-column indexes are still valuable for the *other* direction (looking up one order's items, which Portfolio 3 does), but they do not help these aggregates.

### 7.5 The right tool for Q5: a materialised view
Because Q5 is a report, not a transactional lookup, freshness to the second is not required. `mv_product_sales` precomputes the aggregate once (500 rows) and an index on `units_sold DESC` lets "top 10" read exactly 10 rows. The cost moves to a scheduled `REFRESH MATERIALIZED VIEW`, for example nightly. The 1,500x speed-up is the difference between computing and remembering.

## 8. Trade-offs of indexing

- **Write cost.** Every `INSERT` into orders now updates three indexes (customer_date, status_date, address). On a checkout-heavy system this is measurable but acceptable; reads outnumber writes by a wide margin on an e-commerce site.
- **Space.** About 5 MB for seven indexes on a 30 MB database.
- **Stale statistics.** After bulk loads, `ANALYZE` must run or the planner may make poor choices. The scripts call it explicitly.
- **Materialised views go stale.** Acceptable for reports; wrong for anything a customer acts on (stock levels, balances).

## 9. Reflection notes

- The most useful habit learned: read `Buffers: shared hit` rather than milliseconds. On a laptop with the whole database in memory, timings varied by 20% between runs; page counts did not vary at all.
- The most surprising result: adding an index to Q6 did nothing, and that was correct. I expected every index to help.
- The Q2 rewrite showed that optimisation is not just a DBA task; the application code must cooperate with the index design.

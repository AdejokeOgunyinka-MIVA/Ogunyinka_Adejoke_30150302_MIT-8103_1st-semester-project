# Portfolio 2: Query Processing and Optimisation

**Course:** MIT 8103 Advanced Database Systems
**Student:** Adejoke Ogunyinka (30150302)
**DBMS:** PostgreSQL 17, Cartify database (50,000 orders, ~150,000 order lines)

## Status
- [x] Day 1: six business queries written (`sql/01_queries.sql`), results captured (`results/query_results.txt`), execution plans captured before any indexing (`results/explain_before.txt`).
- [ ] Day 2: indexes designed and created, plans captured after indexing, before/after analysis written.

## Queries under analysis

| # | Business operation | Tables touched | Before-index plan |
|---|---|---|---|
| Q1 | Customer order history | orders | Seq Scan on orders (50,000 rows read to return 11) |
| Q2 | Catalogue search by name prefix | products | Seq Scan on products |
| Q3 | Products in a category with stock | products, categories | Seq Scan on both |
| Q4 | Shipped orders in last 30 days | orders | Seq Scan on orders (50,000 rows read to return 247) |
| Q5 | Top 10 selling products | order_items, orders, products | Parallel Seq Scan on order_items, Seq Scan on orders |
| Q6 | Revenue by state | orders, addresses | Seq Scan on both, hash join |

Full plans with timings and buffer counts are in `results/explain_before.txt`.

*(Analysis, indexing strategy and after-plans to follow on day 2.)*

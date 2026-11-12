# MIT 8103 Advanced Database Systems: Practical Portfolio

**Student:** Adejoke Ogunyinka (30150302)
**Programme:** Master of Information Technology, MIVA Open University
**Session:** 2026/2027, First Semester Continuous Assessment
**Case study:** Cartify, a simulated Nigerian e-commerce platform

---

## Selected organisation

**Cartify** is a simulated online retail platform selling consumer goods (electronics, fashion, groceries, home and kitchen, beauty and health) to customers across Nigeria, priced in naira. Customers browse a catalogue, place orders, pay by card, bank transfer, USSD, wallet or cash on delivery, and have goods delivered by third-party couriers.

| | |
|---|---|
| **Users** | Customers (browse, order, pay, track, review); operations staff (products, stock, deliveries); finance staff (payments, refunds); management (reports) |
| **Major data** | Customers and addresses, categories, products with price and stock, orders and line items, payments, deliveries, reviews |
| **Key operations** | Add or update products; place an order and reduce stock atomically; record payments; dispatch and track deliveries; search the catalogue; view order history; report top products and revenue by state |

The same case study is used in all five portfolios.

## Repository structure

```
.
├── portfolio-1-database-design/        ER diagram, schema, constraints, normalisation, seed data
├── portfolio-2-query-optimisation/     queries, execution plans before/after, indexes, materialised view
├── portfolio-3-transactions-concurrency/ commit/rollback/savepoint, isolation levels, race conditions and fixes
├── portfolio-4-nosql/                  MongoDB document model, export from PostgreSQL, queries, validation
├── portfolio-5-distributed-cloud/      streaming replication in Docker, failover, partitioning, cloud discussion
├── final-documentation/                2-3 page LMS summary, reflection, AI-use declaration
├── AI-USE-LOG.md                       running log of AI assistance and how it was verified
└── README.md
```

Each portfolio folder has its own `README.md` explaining what was built, how to reproduce it, the results, and the reasoning. Evidence is in `results/` (captured terminal output) and `screenshots/`.

## Portfolio summary

| # | Portfolio | Headline evidence |
|---|---|---|
| 1 | [Database Design and Modelling](portfolio-1-database-design/README.md) | 9-table 3NF schema with keys, CHECK constraints and two justified denormalisations; Mermaid and dbdiagram.io ER diagrams; constraint tests; 50,000-order generated dataset |
| 2 | [Query Processing and Optimisation](portfolio-2-query-optimisation/README.md) | 6 business queries; `EXPLAIN (ANALYZE, BUFFERS)` before and after 7 indexes; order-history query 887 pages to 16 pages; materialised view 2,898 pages to 10; honest analysis of two queries indexes could not help |
| 3 | [Transactions and Concurrency](portfolio-3-transactions-concurrency/README.md) | COMMIT, ROLLBACK, SAVEPOINT; READ COMMITTED vs REPEATABLE READ; oversold-stock race reproduced (1 unit, 2 sales) and fixed two ways (`FOR UPDATE`, SERIALIZABLE); lost update on price reproduced and fixed |
| 4 | [NoSQL and Advanced Data Models](portfolio-4-nosql/README.md) | Product and order documents built from the relational data; attributes vary by category; schema validation; multikey and text indexes; aggregation pipelines; atomic stock guard; polyglot persistence argument |
| 5 | [Distributed and Cloud Database Exercise](portfolio-5-distributed-cloud/README.md) | PostgreSQL primary + hot-standby replica in Docker; write replicated in 0.6 ms; replica read-only; manual failover by promotion; partitioning by region with pruning evidence; CAP, sync vs async, shard-key and cloud deployment discussion |

## Tools

| Tool | Version | Used for |
|---|---|---|
| PostgreSQL | 17.11 (Homebrew) | Portfolios 1, 2, 3, 5 (partitioning) |
| PostgreSQL in Docker | 17 (official image) | Portfolio 5 replication |
| MongoDB | 7.0 (Docker) with mongosh | Portfolio 4 |
| Docker Desktop | current | Portfolios 4 and 5 |
| dbdiagram.io, Mermaid | | ER diagrams |

## How to run everything from scratch

```
# Portfolio 1
createdb cartify
psql -d cartify -f portfolio-1-database-design/sql/01_schema.sql
psql -d cartify -f portfolio-1-database-design/sql/02_constraint_tests.sql
psql -d cartify -f portfolio-1-database-design/sql/03_seed_data.sql

# Portfolio 2
psql -d cartify -f portfolio-2-query-optimisation/sql/02_explain_before.sql
psql -d cartify -f portfolio-2-query-optimisation/sql/03_create_indexes.sql
psql -d cartify -f portfolio-2-query-optimisation/sql/04_explain_after.sql
psql -d cartify -f portfolio-2-query-optimisation/sql/05_materialized_view.sql

# Portfolio 3
psql -d cartify -f portfolio-3-transactions-concurrency/sql/01_place_order_commit_rollback.sql
bash portfolio-3-transactions-concurrency/run_concurrency_demos.sh

# Portfolio 4
docker compose -f portfolio-4-nosql/docker/docker-compose.yml up -d
psql -d cartify -At -f portfolio-4-nosql/scripts/01_export_from_postgres.sql
mongosh cartify portfolio-4-nosql/scripts/02_load_into_mongodb.js
mongosh cartify portfolio-4-nosql/scripts/03_queries.js

# Portfolio 5
docker compose -f portfolio-5-distributed-cloud/docker/docker-compose.yml up -d
bash portfolio-5-distributed-cloud/run_replication_demo.sh
psql -d cartify -f portfolio-5-distributed-cloud/sql/partitioning_demo.sql
```

## AI use

AI tools were used as a learning aid and drafting assistant. The full log of what was generated, what was written by me, and how each output was verified is in [AI-USE-LOG.md](AI-USE-LOG.md). The formal declaration is in the final documentation.

# Portfolio 4: NoSQL and Advanced Data Models

**Course:** MIT 8103 Advanced Database Systems
**Student:** Adejoke Ogunyinka (30150302)
**NoSQL DBMS:** MongoDB 7.0 (document model), running in Docker

---

## 1. Objective

Re-model the Cartify catalogue and orders as MongoDB documents, build the documents from the real PostgreSQL data, load them, index them, run queries that only make sense in a document database, and explain where MongoDB fits in Cartify and where it does not.

## 2. Files

| File | Purpose |
|---|---|
| `docker/docker-compose.yml` | Starts MongoDB 7.0 in a container |
| `scripts/01_export_from_postgres.sql` | Joins and nests the relational tables into JSON documents |
| `scripts/02_load_into_mongodb.js` | Creates collections with schema validation, loads documents, builds indexes |
| `scripts/03_queries.js` | Twelve queries, aggregations, updates and an explain |
| `data/products.json`, `data/orders.json` | The exported documents (500 products, 5,000 orders) |
| `results/load_output.txt` | Load counts, index list, one sample document of each kind |
| `results/queries_output.txt` | Output of all twelve queries |
| `screenshots/` | Terminal evidence |

## 3. How to reproduce

```
docker compose -f docker/docker-compose.yml up -d
psql -d cartify -At -f scripts/01_export_from_postgres.sql
mongosh cartify scripts/02_load_into_mongodb.js
mongosh cartify scripts/03_queries.js
```

## 4. Why a document model for the catalogue

The relational `products` table has the same columns for every product. But a phone needs RAM, storage, colour and dual-SIM; a bag of rice needs weight and origin; shoes need size and material. In PostgreSQL there are two ways to store this, both poor:

1. **Wide table:** add every possible attribute as a nullable column. Thirty-plus columns, mostly NULL, and a schema change for every new product type.
2. **Entity-Attribute-Value (EAV) table:** `product_attributes(product_id, name, value)`. Flexible, but "phones with 8GB RAM under 300,000" becomes a self-join per attribute with string-typed values.

In MongoDB each product document carries exactly the attributes it needs:

```json
{ "_id": 234, "name": "...", "price": 1707.58, "stock": 42,
  "category": { "id": 6, "name": "Phones", "parent": "Electronics" },
  "attributes": { "ram_gb": 8, "storage_gb": 64, "colour": "Black", "dual_sim": true },
  "rating": { "average": 3.4, "count": 57 },
  "recent_reviews": [ { "customer": "...", "rating": 5, "comment": "...", "date": "..." } ] }
```

The rice document has `"attributes": { "weight_kg": 25, "origin": "Local" }` and nothing else. The query `{"attributes.ram_gb": {$gte: 8}}` is one indexed field lookup. This is the single strongest reason to use a document store for an e-commerce catalogue.

## 5. The document model

### products collection
| Field | Modelling decision | Why |
|---|---|---|
| `category` | **Embedded** (id, name, parent name) | Always displayed with the product; category names change rarely. The id is kept so a rename can be propagated with one `updateMany`. |
| `attributes` | **Embedded, variable shape** | The point of the exercise; see section 4. |
| `rating.average`, `rating.count` | **Precomputed** | Product listings show the star rating on every card; recomputing from reviews on every page view is wasteful. Updated with `$inc` when a review is added. |
| `recent_reviews` | **Embedded, bounded to 3** | The product page shows the latest few. The full review history stays in PostgreSQL. Bounding the array avoids the unbounded-growth anti-pattern (a popular product with 50,000 reviews would otherwise become a 16 MB document). |

### orders collection
| Field | Modelling decision | Why |
|---|---|---|
| `customer` | **Snapshot + reference** (id, name, email) | The id lets us find a customer's orders; the name and email are copied so the order record stays correct if the customer later changes them. |
| `ship_to` | **Embedded copy** | An order must remember where it shipped even if the address is edited or deleted. |
| `items` | **Embedded array** | Line items are never read without their order. One read returns the whole order. `product_id` is kept for reporting; `name` and `unit_price` are copied for history, exactly as `order_items.unit_price` was in the relational design. |
| `payment`, `delivery` | **Embedded sub-documents** | One-to-one with the order; read together on the order tracking page. |

The rule applied: **embed what is read together and owned by the parent; reference what is shared or changes independently.** This is the document-model equivalent of normalisation decisions.

## 6. Schema validation

MongoDB is schema-flexible, not schema-free. `02_load_into_mongodb.js` creates `products` with a `$jsonSchema` validator that requires `name`, `price`, `stock`, `category` and `attributes`, forces `price >= 0` and `stock >= 0`, limits `recent_reviews` to three entries with ratings 1 to 5, and leaves `attributes` as an open object. Query 11 proves it: inserting a product with a negative price is rejected with "Document failed validation". This gives the catalogue the same guarantees as the PostgreSQL CHECK constraints, while keeping the per-category flexibility.

## 7. Indexes

| Index | Collection | Serves |
|---|---|---|
| `{category.name: 1, price: 1}` | products | Category page sorted by price (Q1) |
| `{attributes.ram_gb: 1}` | products | Attribute filters on phones and laptops |
| `{name: "text", description: "text"}` | products | Full-text search (Q3), replacing Portfolio 2's `LIKE 'samsung%'` with ranked relevance |
| `{customer.id: 1, order_date: -1}` | orders | Order history (Q4), same shape as `idx_orders_customer_date` in PostgreSQL |
| `{status: 1, order_date: -1}` | orders | Operations dashboard |
| `{items.product_id: 1}` | orders | **Multikey index** on an array field: "which orders contain product X" (Q5) |

Query 12's explain shows an `IXSCAN` using the `category.name_1_price_1` index: 32 documents examined to return 18. The planner preferred the compound category index over the single-field RAM index because the category predicate is more selective; the same cost-based reasoning as PostgreSQL's planner in Portfolio 2.

## 8. Queries that show the model working

Full output in `results/queries_output.txt`.

- **Q1, attribute filter.** Phones with 8GB+ RAM under 300,000 naira. One find, one index, no join.
- **Q2, product page in one read.** Category, rating summary and latest reviews arrive in the same document.
- **Q3, text search** with relevance score.
- **Q6 and Q7, aggregation pipeline.** Revenue by state (`$match`, `$group`, `$sort`) and top products by units sold, which requires `$unwind` to flatten the embedded items array before grouping. This is the MongoDB equivalent of Portfolio 2's Q5 and Q6.
- **Q9, bounded array update.** `$push` with `$each`, `$position: 0` and `$slice: 3` inserts the newest review at the front and drops the oldest in a single atomic operation, while `$inc` bumps the counter.
- **Q10, atomic stock guard.** `updateOne({_id: 3, stock: {$gte: 1}}, {$inc: {stock: -1}})` run twice: the first matches and decrements, the second matches nothing. Single-document updates are atomic in MongoDB, so this is safe without a transaction. It is the same idea as the conditional UPDATE in Portfolio 3's comparison table.

## 9. Suitability: where MongoDB fits Cartify and where it does not

| Cartify function | Store | Reason |
|---|---|---|
| Product catalogue, search, product page | **MongoDB** | Variable attributes per category, one-read product pages, text search, horizontal scaling for a read-heavy storefront. |
| Order history display, order tracking | **MongoDB (read copy)** | Whole order in one document; written once, read many times. |
| Checkout: stock reduction, order creation, payment | **PostgreSQL** | Needs multi-row atomicity and row locking (Portfolio 3). MongoDB has multi-document transactions since 4.0, but they are slower and the relational model enforces the constraints natively. |
| Finance and reporting | **PostgreSQL** | Joins across customers, orders, payments; ACID guarantees; materialised views. |

This split, transactional core in a relational database with a document store for the catalogue and read models, is called **polyglot persistence** and is how most large e-commerce platforms are built. The order documents in this portfolio are a *read model* derived from PostgreSQL, not the system of record.

## 10. Other NoSQL models considered

- **Key-value (Redis):** ideal for the shopping cart (key = session id, value = cart JSON) and for caching product documents. Not a fit for queries by attribute.
- **Column-family (Cassandra):** fits write-heavy, time-ordered data such as clickstreams or delivery location pings. Overkill for a 500-product catalogue.
- **Graph (Neo4j):** fits "customers who bought X also bought Y" recommendations. A sensible future addition, not a replacement for the catalogue store.

## 11. Reflection notes

- Building the documents with SQL `json_build_object` made the relational-to-document mapping concrete: The embed (JOIN) decisions all disappear.
- Bounding `recent_reviews` to three was the decision I had to think hardest about. The most common MongoDB mistakes are Unbounded arrays.
- MongoDB's schema validator was a surprise. "Schemaless" is actually a myth; the schema lives in a different location.
- The product names in the synthetic data (e.g. a "Lotion" in the Phones category) come from the random seed generator and do not affect the modelling; a real catalogue would be curated.

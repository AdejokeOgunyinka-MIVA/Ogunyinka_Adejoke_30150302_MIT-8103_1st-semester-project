// =====================================================================
// Cartify: MongoDB queries that show what the document model is for
// Portfolio 4 - NoSQL and Advanced Data Models
//
// Run with:  mongosh cartify portfolio-4-nosql/scripts/03_queries.js
// =====================================================================

function section(t) { print("\n=== " + t + " ==="); }

// ---------------------------------------------------------------------
section("Q1. Phones with at least 8GB RAM under 300,000 naira");
// In PostgreSQL this needs an EAV table or 30 nullable columns.
// Here ram_gb is just a field on phone documents.
db.products.find(
  { "category.name": "Phones", "attributes.ram_gb": { $gte: 8 }, price: { $lt: 300000 } },
  { _id: 1, name: 1, price: 1, "attributes.ram_gb": 1, "attributes.storage_gb": 1 }
).sort({ price: 1 }).limit(5).forEach(printjson);

// ---------------------------------------------------------------------
section("Q2. Product page: one document read, no joins");
// Category, rating summary and latest reviews arrive with the product.
printjson(db.products.findOne({ _id: 1 }, { name: 1, price: 1, category: 1, rating: 1, recent_reviews: 1 }));

// ---------------------------------------------------------------------
section("Q3. Full-text catalogue search");
db.products.find(
  { $text: { $search: "samsung smartphone" } },
  { _id: 1, name: 1, price: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } }).limit(5).forEach(printjson);

// ---------------------------------------------------------------------
section("Q4. Customer order history (uses index on customer.id + order_date)");
const sampleCustomer = db.orders.findOne().customer.id;
db.orders.find(
  { "customer.id": sampleCustomer },
  { _id: 1, order_date: 1, status: 1, total: 1, "items.name": 1 }
).sort({ order_date: -1 }).limit(3).forEach(printjson);

// ---------------------------------------------------------------------
section("Q5. Orders that contain a specific product (multikey index on items.product_id)");
print("count: " + db.orders.countDocuments({ "items.product_id": 1 }));

// ---------------------------------------------------------------------
section("Q6. Aggregation: revenue by state for delivered orders");
db.orders.aggregate([
  { $match: { status: "delivered" } },
  { $group: { _id: "$ship_to.state", orders: { $sum: 1 }, revenue: { $sum: "$total" } } },
  { $sort: { revenue: -1 } },
  { $limit: 5 }
]).forEach(printjson);

// ---------------------------------------------------------------------
section("Q7. Aggregation: top 5 products by units sold ($unwind the embedded items)");
db.orders.aggregate([
  { $match: { status: "delivered" } },
  { $unwind: "$items" },
  { $group: { _id: "$items.product_id", name: { $first: "$items.name" },
              units: { $sum: "$items.qty" }, revenue: { $sum: "$items.line_total" } } },
  { $sort: { units: -1 } },
  { $limit: 5 }
]).forEach(printjson);

// ---------------------------------------------------------------------
section("Q8. Aggregation: average rating and count per top-level category");
db.products.aggregate([
  { $match: { "rating.count": { $gt: 0 } } },
  { $group: { _id: "$category.parent", products: { $sum: 1 }, avg_rating: { $avg: "$rating.average" } } },
  { $project: { products: 1, avg_rating: { $round: ["$avg_rating", 2] } } },
  { $sort: { avg_rating: -1 } }
]).forEach(printjson);

// ---------------------------------------------------------------------
section("Q9. Update: add a review, keep only the 3 newest ($push with $slice), bump the counters");
const before = db.products.findOne({ _id: 2 }, { rating: 1, recent_reviews: 1 });
print("before: count=" + before.rating.count + ", embedded=" + before.recent_reviews.length);
db.products.updateOne(
  { _id: 2 },
  {
    $push: { recent_reviews: {
      $each: [{ customer: "Adejoke Ogunyinka", rating: 5, comment: "Excellent", date: new Date() }],
      $position: 0, $slice: 3 } },
    $inc: { "rating.count": 1 }
  }
);
const after = db.products.findOne({ _id: 2 }, { rating: 1, recent_reviews: 1 });
print("after:  count=" + after.rating.count + ", embedded=" + after.recent_reviews.length +
      ", newest by " + after.recent_reviews[0].customer);

// ---------------------------------------------------------------------
section("Q10. Atomic stock decrement with a guard (no oversell, single document)");
db.products.updateOne({ _id: 3 }, { $set: { stock: 1 } });
const r1 = db.products.updateOne({ _id: 3, stock: { $gte: 1 } }, { $inc: { stock: -1 } });
const r2 = db.products.updateOne({ _id: 3, stock: { $gte: 1 } }, { $inc: { stock: -1 } });
print("first buyer  matched=" + r1.matchedCount + " modified=" + r1.modifiedCount);
print("second buyer matched=" + r2.matchedCount + " modified=" + r2.modifiedCount + "  <- refused, stock already 0");
print("stock now: " + db.products.findOne({ _id: 3 }).stock);

// ---------------------------------------------------------------------
section("Q11. Schema validation rejects a bad document");
try {
  db.products.insertOne({ _id: 9999, name: "Bad Product", price: -5, stock: 1,
                          category: { id: 6, name: "Phones" }, attributes: {} });
  print("UNEXPECTED: insert succeeded");
} catch (e) {
  print("rejected as expected: " + e.message.split("\n")[0]);
}

// ---------------------------------------------------------------------
section("Q12. Explain: which index the planner chose for Q1");
const plan = db.products.find({ "category.name": "Phones", "attributes.ram_gb": { $gte: 8 } })
  .explain("executionStats");
print("winning plan stage: " + JSON.stringify(plan.queryPlanner.winningPlan.inputStage?.stage || plan.queryPlanner.winningPlan.stage));
print("index used: " + JSON.stringify(plan.queryPlanner.winningPlan.inputStage?.indexName || "none"));
print("docs examined: " + plan.executionStats.totalDocsExamined + ", returned: " + plan.executionStats.nReturned);

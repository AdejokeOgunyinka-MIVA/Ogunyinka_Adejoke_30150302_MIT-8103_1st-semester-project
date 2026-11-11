// =====================================================================
// Cartify: load the exported documents into MongoDB
// Portfolio 4 - NoSQL and Advanced Data Models
//
// Run with (from the repo root):
//   mongosh cartify portfolio-4-nosql/scripts/02_load_into_mongodb.js
// =====================================================================

const fs = require("fs");

const products = JSON.parse(fs.readFileSync("portfolio-4-nosql/data/products.json", "utf8"));
const orders   = JSON.parse(fs.readFileSync("portfolio-4-nosql/data/orders.json",   "utf8"));

// Convert ISO date strings back to real Date objects so range queries work.
for (const p of products) {
  p.created_at = new Date(p.created_at);
  for (const r of p.recent_reviews) r.date = new Date(r.date);
}
for (const o of orders) {
  o.order_date = new Date(o.order_date);
  if (o.payment && o.payment.paid_at) o.payment.paid_at = new Date(o.payment.paid_at);
  if (o.delivery && o.delivery.delivered_at) o.delivery.delivered_at = new Date(o.delivery.delivered_at);
}

db.products.drop();
db.orders.drop();

// ---------------------------------------------------------------------
// Schema validation: MongoDB is schema-flexible, not schema-less.
// We require the fields every product must have, and leave
// `attributes` open so each category can carry its own keys.
// ---------------------------------------------------------------------
db.createCollection("products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "name", "price", "stock", "category", "attributes"],
      properties: {
        name:   { bsonType: "string" },
        price:  { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
        stock:  { bsonType: "int", minimum: 0 },
        category: {
          bsonType: "object",
          required: ["id", "name"],
          properties: { id: { bsonType: "int" }, name: { bsonType: "string" } }
        },
        attributes: { bsonType: "object" },     // shape varies by category
        recent_reviews: {
          bsonType: "array",
          maxItems: 3,                            // bounded embedded array
          items: {
            bsonType: "object",
            required: ["rating"],
            properties: { rating: { bsonType: "int", minimum: 1, maximum: 5 } }
          }
        }
      }
    }
  }
});

const pr = db.products.insertMany(products);
const or = db.orders.insertMany(orders);
print(`Inserted ${Object.keys(pr.insertedIds).length} products`);
print(`Inserted ${Object.keys(or.insertedIds).length} orders`);

// ---------------------------------------------------------------------
// Indexes, each tied to a query in 03_queries.js
// ---------------------------------------------------------------------
db.products.createIndex({ "category.name": 1, price: 1 });        // category page sorted by price
db.products.createIndex({ "attributes.ram_gb": 1 });              // attribute filter (phones/laptops)
db.products.createIndex({ name: "text", description: "text" });   // full-text catalogue search
db.orders.createIndex({ "customer.id": 1, order_date: -1 });      // customer order history
db.orders.createIndex({ status: 1, order_date: -1 });             // operations dashboard
db.orders.createIndex({ "items.product_id": 1 });                 // multikey: which orders contain product X

print("\nCollections:");
printjson(db.getCollectionNames());
print("\nproducts indexes:");
db.products.getIndexes().forEach(i => print("  " + i.name));
print("orders indexes:");
db.orders.getIndexes().forEach(i => print("  " + i.name));

print("\nSample product document:");
printjson(db.products.findOne({ "category.name": "Phones" }));
print("\nSample order document:");
printjson(db.orders.findOne({ status: "delivered" }));

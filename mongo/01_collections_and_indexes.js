use("bitestream");

// Remove old collections so the script can be safely rerun
db.menus.drop();
db.reviews.drop();
db.driverPings.drop();

// Create collections
db.createCollection("menus");
db.createCollection("reviews");
db.createCollection("driverPings");

// -------------------------
// MENUS INDEXES
// -------------------------

db.menus.createIndex(
    { restaurant_id: 1 },
    { name: "idx_menus_restaurant" }
);

db.menus.createIndex(
    { "categories.name": 1 },
    { name: "idx_menus_category" }
);

// -------------------------
// REVIEWS INDEXES
// -------------------------

db.reviews.createIndex(
    { restaurant_id: 1 },
    { name: "idx_reviews_restaurant" }
);

db.reviews.createIndex(
    { rating: 1 },
    { name: "idx_reviews_rating" }
);

// -------------------------
// DRIVER PINGS INDEXES
// -------------------------

// Required 2dsphere index
db.driverPings.createIndex(
    { location: "2dsphere" },
    { name: "idx_driverPings_location_2dsphere" }
);

// Required TTL index: 2 hours
db.driverPings.createIndex(
    { created_at: 1 },
    {
        name: "idx_driverPings_created_at_ttl",
        expireAfterSeconds: 7200
    }
);

// Index for active-driver filtering
db.driverPings.createIndex(
    { active: 1 },
    { name: "idx_driverPings_active" }
);

// -------------------------
// VERIFY
// -------------------------

print("Menus indexes:");
printjson(db.menus.getIndexes());

print("Reviews indexes:");
printjson(db.reviews.getIndexes());

print("DriverPings indexes:");
printjson(db.driverPings.getIndexes());

print("MongoDB setup completed successfully.");
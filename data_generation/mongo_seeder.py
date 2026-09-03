from pymongo import MongoClient
from datetime import datetime, timedelta, timezone
import random
import uuid
import os


MONGO_URI = os.getenv(
    "MONGO_URI",
    "mongodb://localhost:27017/"
)

DATABASE_NAME = "bitestream"

DRIVER_PINGS_COUNT = 500_000
REVIEW_COUNT = 50_000
MENU_COUNT = 100

BATCH_SIZE = 5_000

RESTAURANT_COUNT = 100
DRIVER_COUNT = 2_000


FOOD_CATEGORIES = [
    "Pizza",
    "Burgers",
    "Biryani",
    "Indian",
    "Chinese",
    "Desserts",
    "Beverages",
    "South Indian",
    "North Indian",
    "Fast Food"
]

MENU_ITEMS = [
    "Chicken Biryani",
    "Veg Biryani",
    "Margherita Pizza",
    "Chicken Burger",
    "Veg Burger",
    "Fried Rice",
    "Noodles",
    "Paneer Tikka",
    "Butter Chicken",
    "Masala Dosa",
    "Idli",
    "Gulab Jamun",
    "Chocolate Cake",
    "Cold Coffee",
    "Fresh Lime Soda"
]

REVIEW_TAGS = [
    "tasty",
    "delicious",
    "fresh",
    "fast delivery",
    "good packaging",
    "friendly",
    "spicy",
    "value for money",
    "late delivery",
    "cold food",
    "excellent",
    "average"
]


def connect_database():

    client = MongoClient(MONGO_URI)

    client.admin.command("ping")

    db = client[DATABASE_NAME]

    print("Connected to MongoDB.")
    print(f"Database: {DATABASE_NAME}")

    return client, db


def generate_menus(db):

    collection = db["menus"]

    documents = []

    for restaurant_id in range(1, MENU_COUNT + 1):

        categories = []

        selected_categories = random.sample(
            FOOD_CATEGORIES,
            random.randint(2, 5)
        )

        for category in selected_categories:

            items = []

            for _ in range(random.randint(3, 8)):

                items.append({
                    "item_id": str(uuid.uuid4()),
                    "name": random.choice(MENU_ITEMS),
                    "description": "Freshly prepared food item.",
                    "price": round(random.uniform(80, 600), 2),
                    "available": random.choice(
                        [True, True, True, False]
                    ),
                    "customization_addons": [
                        {
                            "name": "Extra cheese",
                            "price": 50
                        },
                        {
                            "name": "Extra sauce",
                            "price": 30
                        }
                    ]
                })

            categories.append({
                "name": category,
                "items": items
            })

        documents.append({
            "_id": str(uuid.uuid4()),
            "restaurant_id": restaurant_id,
            "restaurant_name": f"Restaurant {restaurant_id}",
            "categories": categories,
            "updated_at": datetime.now(timezone.utc)
        })

    collection.insert_many(documents)

    print(f"Inserted {len(documents)} menu documents.")


def generate_reviews(db):

    collection = db["reviews"]

    documents = []

    for i in range(REVIEW_COUNT):

        rating = random.randint(1, 5)

        tags = random.sample(
            REVIEW_TAGS,
            random.randint(1, 3)
        )

        documents.append({
            "_id": str(uuid.uuid4()),

            "restaurant_id": random.randint(
                1,
                RESTAURANT_COUNT
            ),

            "user_id": str(uuid.uuid4()),

            "rating": rating,

            "comment": "Food and delivery review.",

            "sentiment_tags": tags,

            "created_at": (
                datetime.now(timezone.utc)
                - timedelta(
                    days=random.randint(0, 365)
                )
            )
        })

        if len(documents) >= BATCH_SIZE:

            collection.insert_many(documents)

            documents.clear()

            print(
                f"Inserted reviews: "
                f"{i + 1}/{REVIEW_COUNT}"
            )

    if documents:
        collection.insert_many(documents)

    print(
        f"Inserted {REVIEW_COUNT} review documents."
    )


def generate_driver_pings(db):

    collection = db["driverPings"]

    documents = []

    print(
        f"Generating {DRIVER_PINGS_COUNT:,} "
        "driver pings..."
    )

    for i in range(DRIVER_PINGS_COUNT):

        driver_id = random.randint(
            1,
            DRIVER_COUNT
        )

        longitude = random.uniform(
            78.30,
            78.60
        )

        latitude = random.uniform(
            17.25,
            17.60
        )

        created_at = (
            datetime.now(timezone.utc)
            - timedelta(
                minutes=random.randint(
                    0,
                    240
                )
            )
        )

        documents.append({
            "_id": str(uuid.uuid4()),

            "driver_id": driver_id,

            "active": random.choice(
                [
                    True,
                    True,
                    True,
                    False
                ]
            ),

            "location": {
                "type": "Point",
                "coordinates": [
                    longitude,
                    latitude
                ]
            },

            "created_at": created_at
        })

        if len(documents) >= BATCH_SIZE:

            collection.insert_many(documents)

            documents.clear()

            if (i + 1) % 50_000 == 0:

                print(
                    f"Inserted driver pings: "
                    f"{i + 1:,}/{DRIVER_PINGS_COUNT:,}"
                )

    if documents:
        collection.insert_many(documents)

    print(
        f"Inserted {DRIVER_PINGS_COUNT:,} "
        "driver ping documents."
    )


def main():

    client, db = connect_database()

    try:

        print("\n--- Generating menus ---")
        generate_menus(db)

        print("\n--- Generating reviews ---")
        generate_reviews(db)

        print("\n--- Generating driver pings ---")
        generate_driver_pings(db)

        print("\nMongoDB seeding completed successfully.")

    finally:

        client.close()

        print("MongoDB connection closed.")


if __name__ == "__main__":
    main()
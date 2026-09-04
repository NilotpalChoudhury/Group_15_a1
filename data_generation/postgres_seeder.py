import os
import random
from decimal import Decimal
import psycopg2


# ============================================================
# BiteStream | PostgreSQL Data Seeder
# ============================================================

DB_CONFIG = {
    "host": os.getenv("PGHOST", "localhost"),
    "port": os.getenv("PGPORT", "5432"),
    "dbname": os.getenv("PGDATABASE", "bitestream"),
    "user": os.getenv("PGUSER", "postgres"),
    "password": os.getenv("PGPASSWORD", "postgres"),
}

# Start with a manageable test dataset.
NUMBER_OF_USERS = 1000
NUMBER_OF_RESTAURANTS = 100
NUMBER_OF_ORDERS = 100000

STARTING_BALANCE = Decimal("1000000.00")


def connect():
    return psycopg2.connect(**DB_CONFIG)


def seed_users(cur):
    user_ids = []

    for i in range(NUMBER_OF_USERS):
        name = f"Test User {i + 1}"

        cur.execute(
            """
            INSERT INTO users (name, wallet_balance)
            VALUES (%s, %s)
            RETURNING id;
            """,
            (name, STARTING_BALANCE),
        )

        user_ids.append(cur.fetchone()[0])

    return user_ids


def seed_restaurants(cur):
    restaurant_ids = []

    for i in range(NUMBER_OF_RESTAURANTS):
        name = f"Test Restaurant {i + 1}"

        latitude = random.uniform(-90, 90)
        longitude = random.uniform(-180, 180)

        cur.execute(
            """
            INSERT INTO restaurants (name, latitude, longitude)
            VALUES (%s, %s, %s)
            RETURNING id;
            """,
            (name, latitude, longitude),
        )

        restaurant_ids.append(cur.fetchone()[0])

    return restaurant_ids


def seed_orders_using_procedure(cur, user_ids, restaurant_ids):
    created_orders = 0

    for i in range(NUMBER_OF_ORDERS):

        # Pick a user that currently has no active order.
        cur.execute(
            """
            SELECT id
            FROM users
            WHERE id NOT IN (
                SELECT user_id
                FROM orders
                WHERE status IN ('PREPARING', 'DELIVERING')
            )
            ORDER BY random()
            LIMIT 1;
            """
        )

        row = cur.fetchone()

        if row is None:
            print("No user available for another active order.")
            break

        user_id = row[0]
        restaurant_id = random.choice(restaurant_ids)

        amount = (
            Decimal(random.randint(500, 2500))
            / Decimal("100")
        )

        try:
            cur.execute("SAVEPOINT checkout_attempt;")

            # Execute the actual checkout procedure.
            cur.execute(
                """
                CALL sp_execute_checkout(%s, %s, %s);
                """,
                (user_id, restaurant_id, amount),
            )

            # Find the order created by this checkout.
            cur.execute(
                """
                SELECT id
                FROM orders
                WHERE user_id = %s
                ORDER BY created_at DESC
                LIMIT 1;
                """,
                (user_id,),
            )

            order_row = cur.fetchone()

            if order_row is None:
                raise RuntimeError(
                    "Checkout succeeded but no order was created."
                )

            order_id = order_row[0]

            # Complete the test order so the user can
            # participate in another checkout.
            cur.execute(
                """
                UPDATE orders
                SET status = 'DELIVERED'
                WHERE id = %s;
                """,
                (order_id,),
            )

            cur.execute(
                "RELEASE SAVEPOINT checkout_attempt;"
            )

            created_orders += 1

        except Exception as e:
            print(f"Order skipped: {e}")

            cur.execute(
                "ROLLBACK TO SAVEPOINT checkout_attempt;"
            )
            cur.execute(
                "RELEASE SAVEPOINT checkout_attempt;"
            )

        if (i + 1) % 100 == 0:
            cur.connection.commit()

            print(
                f"Progress: {i + 1:,}/{NUMBER_OF_ORDERS:,} "
                f"attempts | "
                f"{created_orders:,} orders created"
            )

    cur.connection.commit()

    return created_orders


def main():
    print("========================================")
    print(" BiteStream PostgreSQL Seeder")
    print("========================================")

    conn = connect()

    try:
        conn.autocommit = False

        with conn.cursor() as cur:

            print("\nCreating users...")
            user_ids = seed_users(cur)
            print(f"Created {len(user_ids)} users.")

            print("\nCreating restaurants...")
            restaurant_ids = seed_restaurants(cur)
            print(f"Created {len(restaurant_ids)} restaurants.")

            conn.commit()

            print(
                "\nCreating orders through checkout procedure..."
            )

            created_orders = seed_orders_using_procedure(
                cur,
                user_ids,
                restaurant_ids,
            )

            print(f"\nCreated {created_orders} orders.")

        print("\n========================================")
        print(" PostgreSQL seeding completed")
        print("========================================")

    except Exception as e:
        conn.rollback()

        print("\nSEEDING FAILED")
        print(e)

    finally:
        conn.close()


if __name__ == "__main__":
    main()
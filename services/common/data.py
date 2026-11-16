"""Deterministic synthetic listing data for repeatable load tests."""
from __future__ import annotations

import random

CITIES = [
    "Mumbai", "Goa", "Delhi", "Bengaluru", "Pune", "Jaipur", "Hyderabad",
    "Chennai", "Kochi", "Ahmedabad", "Shimla", "Manali", "Udaipur", "Rishikesh",
]
ADJECTIVES = ["Sunny", "Quiet", "Modern", "Cozy", "Bright", "Garden", "Heritage", "Seaside"]
PROPERTY_TYPES = ["Apartment", "Villa", "Studio", "Cottage", "Loft", "Guesthouse"]


def listing_for_id(listing_id: int) -> dict:
    rng = random.Random(listing_id)
    city = CITIES[listing_id % len(CITIES)]
    return {
        "id": listing_id,
        "city": city,
        "title": f"{rng.choice(ADJECTIVES)} {city} {rng.choice(PROPERTY_TYPES)} #{listing_id}",
        "nightly_price": round(rng.uniform(900, 12_000), 2),
        "rating": round(rng.uniform(3.0, 5.0), 2),
        "bedrooms": rng.randint(1, 5),
    }


def generate_listing_batch(start_id: int, end_id: int) -> list[tuple]:
    return [
        (
            item["id"], item["city"], item["title"], item["nightly_price"],
            item["rating"], item["bedrooms"],
        )
        for item in (listing_for_id(i) for i in range(start_id, end_id + 1))
    ]


def generate_in_memory_listings(count: int) -> list[dict]:
    return [listing_for_id(i) for i in range(1, count + 1)]

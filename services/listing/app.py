"""Listing detail service with Redis cache-aside and PostgreSQL fallback."""
from __future__ import annotations

from fastapi import APIRouter, FastAPI, HTTPException

from services.common import config
from services.common.cache import get_json, set_json
from services.common.db import close_pool, connection, ensure_schema, seed_listings
from services.common.health import router as health_router

router = APIRouter()


@router.get("/listings/{listing_id}", tags=["listings"])
def get_listing(listing_id: int) -> dict:
    if listing_id <= 0:
        raise HTTPException(status_code=400, detail="listing_id must be positive")

    cache_key = f"listing:{listing_id}"
    cached = get_json(cache_key)
    if cached is not None:
        cached["cache"] = "hit"
        return cached

    with connection(dict_cursor=True) as (_, cur):
        cur.execute(
            """SELECT id, city, title, nightly_price, rating, bedrooms
               FROM listings WHERE id = %s""",
            (listing_id,),
        )
        row = cur.fetchone()

    if row is None:
        raise HTTPException(status_code=404, detail="listing not found")
    result = {**dict(row), "nightly_price": float(row["nightly_price"]), "rating": float(row["rating"]), "cache": "miss"}
    set_json(cache_key, result)
    return result


app = FastAPI(title="Airbnb PoC - Listing Service", version="1.0.0")
app.include_router(health_router)
app.include_router(router)


@app.on_event("startup")
def startup() -> None:
    ensure_schema()
    seed_listings(config.LISTING_DATASET_SIZE)


@app.on_event("shutdown")
def shutdown() -> None:
    close_pool()

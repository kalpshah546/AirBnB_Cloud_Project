"""Single-process baseline exposing the same three capabilities under /monolith."""
from fastapi import FastAPI

from services.booking.app import router as booking_router
from services.common.db import close_pool, ensure_schema, seed_listings
from services.common.health import router as health_router
from services.common import config
from services.listing.app import router as listing_router
from services.search.app import initialize_search_data, router as search_router

app = FastAPI(title="Airbnb PoC - Monolith Baseline", version="1.0.0")
app.include_router(health_router)
app.include_router(search_router, prefix="/monolith")
app.include_router(listing_router, prefix="/monolith")
app.include_router(booking_router, prefix="/monolith")


@app.on_event("startup")
def startup() -> None:
    initialize_search_data()
    ensure_schema()
    seed_listings(config.LISTING_DATASET_SIZE)


@app.on_event("shutdown")
def shutdown() -> None:
    close_pool()

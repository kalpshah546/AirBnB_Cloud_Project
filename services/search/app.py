"""CPU-intensive Search service used to expose horizontal scaling behaviour."""
from __future__ import annotations

import time
from functools import lru_cache
from typing import Optional

from fastapi import APIRouter, FastAPI, Query

from services.common import config
from services.common.data import generate_in_memory_listings
from services.common.health import router as health_router

router = APIRouter()
_listings: list[dict] = []


def initialize_search_data() -> int:
    global _listings
    if not _listings:
        _listings = generate_in_memory_listings(config.LISTING_DATASET_SIZE)
    return len(_listings)


def burn_cpu(milliseconds: int) -> int:
    """Perform deterministic integer work for a bounded amount of thread CPU time."""
    duration = max(0, min(milliseconds, config.SEARCH_MAX_WORK_MS)) / 1000.0
    deadline = time.thread_time() + duration
    value = 0x12345678
    operations = 0
    while time.thread_time() < deadline:
        value = ((value * 1_664_525) + 1_013_904_223) & 0xFFFFFFFF
        value ^= (value >> 13)
        operations += 1
    return operations


@router.get("/search", tags=["search"])
def search_listings(
    city: Optional[str] = Query(default=None),
    max_price: Optional[float] = Query(default=None, gt=0),
    min_rating: float = Query(default=0.0, ge=0, le=5),
    limit: int = Query(default=20, ge=1, le=100),
    work_ms: Optional[int] = Query(default=None, ge=0, le=500),
) -> dict:
    initialize_search_data()
    configured_work = config.SEARCH_CPU_WORK_MS if work_ms is None else work_ms
    operations = burn_cpu(configured_work)

    city_norm = city.casefold() if city else None
    matches = [
        item for item in _listings
        if (city_norm is None or item["city"].casefold() == city_norm)
        and (max_price is None or item["nightly_price"] <= max_price)
        and item["rating"] >= min_rating
    ]
    matches.sort(key=lambda item: (item["rating"], -item["nightly_price"]), reverse=True)
    return {
        "service": "search",
        "dataset_size": len(_listings),
        "result_count": len(matches),
        "cpu_work_ms": configured_work,
        "cpu_operations": operations,
        "results": matches[:limit],
    }


app = FastAPI(title="Airbnb PoC - Search Service", version="1.0.0")
app.include_router(health_router)
app.include_router(router)


@app.on_event("startup")
def startup() -> None:
    initialize_search_data()

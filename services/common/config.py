"""Environment configuration shared by all services."""
from __future__ import annotations

import os


def env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"Environment variable {name} must be an integer") from exc


AWS_REGION = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "ap-south-1"))
DB_HOST = os.getenv("DB_HOST", "postgres")
DB_PORT = env_int("DB_PORT", 5432)
DB_NAME = os.getenv("DB_NAME", "airbnbpoc")
DB_USER = os.getenv("DB_USER", "airbnb")
DB_PASSWORD = os.getenv("DB_PASSWORD", "airbnb-dev-only")
DB_CONNECT_TIMEOUT = env_int("DB_CONNECT_TIMEOUT", 5)
DB_POOL_MIN = env_int("DB_POOL_MIN", 1)
DB_POOL_MAX = env_int("DB_POOL_MAX", 4)
CACHE_HOST = os.getenv("CACHE_HOST", "redis")
CACHE_PORT = env_int("CACHE_PORT", 6379)
CACHE_TTL_SECONDS = env_int("CACHE_TTL_SECONDS", 120)
CACHE_ENABLED = os.getenv("CACHE_ENABLED", "true").lower() in {"1", "true", "yes", "on"}
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
SQS_QUEUE_NAME = os.getenv("SQS_QUEUE_NAME", "airbnb-bookings")
SQS_ENDPOINT_URL = os.getenv("SQS_ENDPOINT_URL", "")
BOOKING_ASYNC = os.getenv("BOOKING_ASYNC", "true").lower() in {"1", "true", "yes", "on"}
LISTING_DATASET_SIZE = env_int("LISTING_DATASET_SIZE", 50_000)
SEARCH_CPU_WORK_MS = env_int("SEARCH_CPU_WORK_MS", 35)
SEARCH_MAX_WORK_MS = env_int("SEARCH_MAX_WORK_MS", 500)
APP_ENV = os.getenv("APP_ENV", "local")

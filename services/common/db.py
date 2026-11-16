"""Small, bounded PostgreSQL connection pool and schema helpers."""
from __future__ import annotations

import time
from contextlib import contextmanager
from typing import Iterator

import psycopg2
from psycopg2.extras import RealDictCursor
from psycopg2.pool import ThreadedConnectionPool

from services.common import config

_pool: ThreadedConnectionPool | None = None


def get_pool() -> ThreadedConnectionPool:
    global _pool
    if _pool is None:
        _pool = ThreadedConnectionPool(
            minconn=config.DB_POOL_MIN,
            maxconn=config.DB_POOL_MAX,
            host=config.DB_HOST,
            port=config.DB_PORT,
            dbname=config.DB_NAME,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            connect_timeout=config.DB_CONNECT_TIMEOUT,
            application_name="airbnb-soa-poc",
        )
    return _pool


@contextmanager
def connection(*, dict_cursor: bool = False) -> Iterator:
    pool = get_pool()
    conn = pool.getconn()
    try:
        conn.autocommit = False
        if dict_cursor:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                yield conn, cur
        else:
            with conn.cursor() as cur:
                yield conn, cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def close_pool() -> None:
    global _pool
    if _pool is not None:
        _pool.closeall()
        _pool = None


def wait_for_db(attempts: int = 30, delay_seconds: float = 2.0) -> None:
    last_error: Exception | None = None
    for _ in range(attempts):
        try:
            with connection() as (_, cur):
                cur.execute("SELECT 1")
            return
        except Exception as exc:  # startup retry for local Compose and cloud boot
            last_error = exc
            time.sleep(delay_seconds)
    raise RuntimeError(f"PostgreSQL was not ready after {attempts} attempts: {last_error}")


def ensure_schema() -> None:
    wait_for_db()
    with connection() as (_, cur):
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS listings (
                id BIGINT PRIMARY KEY,
                city TEXT NOT NULL,
                title TEXT NOT NULL,
                nightly_price NUMERIC(10,2) NOT NULL,
                rating NUMERIC(3,2) NOT NULL,
                bedrooms SMALLINT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )
        cur.execute("CREATE INDEX IF NOT EXISTS idx_listings_city_price ON listings(city, nightly_price)")
        cur.execute("CREATE INDEX IF NOT EXISTS idx_listings_rating ON listings(rating)")
        cur.execute(
            """
            CREATE TABLE IF NOT EXISTS bookings (
                id BIGSERIAL PRIMARY KEY,
                idempotency_key TEXT NOT NULL UNIQUE,
                listing_id BIGINT NOT NULL,
                guest_id TEXT NOT NULL,
                check_in DATE NOT NULL,
                check_out DATE NOT NULL,
                guest_count SMALLINT NOT NULL DEFAULT 1,
                status TEXT NOT NULL DEFAULT 'pending',
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
            """
        )
        cur.execute("CREATE INDEX IF NOT EXISTS idx_bookings_status ON bookings(status)")


def seed_listings(count: int, *, batch_size: int = 2_000) -> int:
    """Seed deterministic demo records once. A DB advisory lock avoids races at scale-out."""
    from services.common.data import generate_listing_batch
    from psycopg2.extras import execute_values

    ensure_schema()
    inserted = 0
    with connection() as (_, cur):
        cur.execute("SELECT pg_advisory_xact_lock(478291)")
        cur.execute("SELECT COUNT(*) FROM listings")
        existing = cur.fetchone()[0]
        if existing >= count:
            return existing
        start_id = 1
        while start_id <= count:
            batch_end = min(count, start_id + batch_size - 1)
            rows = generate_listing_batch(start_id, batch_end)
            execute_values(
                cur,
                """INSERT INTO listings (id, city, title, nightly_price, rating, bedrooms)
                   VALUES %s ON CONFLICT (id) DO NOTHING""",
                rows,
                page_size=batch_size,
            )
            inserted += len(rows)
            start_id = batch_end + 1
    return inserted

"""Redis cache-aside helper; gracefully bypasses cache if Redis is unavailable."""
from __future__ import annotations

import json
import logging
from typing import Any

import redis

from services.common import config

log = logging.getLogger(__name__)
_client: redis.Redis | None = None


def get_redis() -> redis.Redis:
    global _client
    if _client is None:
        _client = redis.Redis(
            host=config.CACHE_HOST,
            port=config.CACHE_PORT,
            decode_responses=True,
            socket_connect_timeout=1.5,
            socket_timeout=1.5,
        )
    return _client


def get_json(key: str) -> Any | None:
    if not config.CACHE_ENABLED:
        return None
    try:
        value = get_redis().get(key)
        return json.loads(value) if value else None
    except redis.RedisError as exc:
        log.warning("Redis read failed; bypassing cache: %s", exc)
        return None


def set_json(key: str, value: Any, ttl: int | None = None) -> None:
    if not config.CACHE_ENABLED:
        return
    try:
        get_redis().setex(key, ttl or config.CACHE_TTL_SECONDS, json.dumps(value, default=str))
    except redis.RedisError as exc:
        log.warning("Redis write failed; bypassing cache: %s", exc)

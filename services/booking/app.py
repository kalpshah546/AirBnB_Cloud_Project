"""Booking API: durable idempotency record followed by SQS enqueue."""
from __future__ import annotations

from datetime import date
from typing import Optional

from fastapi import APIRouter, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field, model_validator

from services.common import config
from services.common.db import close_pool, connection, ensure_schema
from services.common.health import router as health_router
from services.common.queue import enqueue_booking

router = APIRouter()


class BookingRequest(BaseModel):
    listing_id: int = Field(gt=0)
    guest_id: str = Field(min_length=1, max_length=80)
    check_in: date
    check_out: date
    guest_count: int = Field(default=1, ge=1, le=16)

    @model_validator(mode="after")
    def validate_dates(self):
        if self.check_out <= self.check_in:
            raise ValueError("check_out must be after check_in")
        return self


@router.post("/bookings", status_code=202, tags=["bookings"])
def create_booking(
    payload: BookingRequest,
    idempotency_key: Optional[str] = Header(default=None, alias="Idempotency-Key"),
) -> dict:
    if not idempotency_key or len(idempotency_key) > 160:
        raise HTTPException(status_code=400, detail="A valid Idempotency-Key header is required")

    with connection(dict_cursor=True) as (_, cur):
        cur.execute(
            """INSERT INTO bookings
               (idempotency_key, listing_id, guest_id, check_in, check_out, guest_count, status)
               VALUES (%s, %s, %s, %s, %s, %s, %s)
               ON CONFLICT (idempotency_key) DO NOTHING
               RETURNING id, status, listing_id, guest_id, check_in, check_out, guest_count""",
            (
                idempotency_key, payload.listing_id, payload.guest_id,
                payload.check_in, payload.check_out, payload.guest_count,
                "pending" if config.BOOKING_ASYNC else "confirmed",
            ),
        )
        row = cur.fetchone()
        created = row is not None
        if row is None:
            cur.execute(
                """SELECT id, status, listing_id, guest_id, check_in, check_out, guest_count
                   FROM bookings WHERE idempotency_key = %s""",
                (idempotency_key,),
            )
            row = cur.fetchone()
            if row is None:
                raise HTTPException(status_code=500, detail="Could not resolve idempotency record")
            same_request = (
                row["listing_id"] == payload.listing_id
                and row["guest_id"] == payload.guest_id
                and row["check_in"] == payload.check_in
                and row["check_out"] == payload.check_out
                and row["guest_count"] == payload.guest_count
            )
            if not same_request:
                raise HTTPException(status_code=409, detail="Idempotency-Key was already used with a different booking payload")

    # In direct-write mode the database commit is the completion point. In queue
    # mode, duplicate delivery is safe because the worker updates by unique key.
    should_enqueue = config.BOOKING_ASYNC and (created or row["status"] == "queue_error")
    if should_enqueue:
        if row["status"] == "queue_error":
            with connection() as (_, cur):
                cur.execute(
                    "UPDATE bookings SET status = 'pending', updated_at = NOW() WHERE id = %s AND status = 'queue_error'",
                    (row["id"],),
                )
            row["status"] = "pending"
        message = {
            "idempotency_key": idempotency_key,
            "booking_id": row["id"],
            "listing_id": payload.listing_id,
            "guest_id": payload.guest_id,
            "check_in": payload.check_in.isoformat(),
            "check_out": payload.check_out.isoformat(),
            "guest_count": payload.guest_count,
        }
        try:
            enqueue_booking(message)
        except Exception as exc:
            with connection() as (_, cur):
                cur.execute(
                    "UPDATE bookings SET status = 'queue_error', updated_at = NOW() WHERE id = %s AND status <> 'confirmed'",
                    (row["id"],),
                )
            raise HTTPException(status_code=503, detail=f"Booking recorded but queue unavailable: {type(exc).__name__}")

    return {
        "booking_id": row["id"],
        "status": row["status"],
        "idempotency_key": idempotency_key,
        "created": created,
        "message": "Booking queued for asynchronous processing" if config.BOOKING_ASYNC else "Booking written directly to the database",
    }


app = FastAPI(title="Airbnb PoC - Booking Service", version="1.0.0")
app.include_router(health_router)
app.include_router(router)


@app.on_event("startup")
def startup() -> None:
    ensure_schema()


@app.on_event("shutdown")
def shutdown() -> None:
    close_pool()

"""SQS worker. Database status transitions are safe under duplicate SQS delivery."""
from __future__ import annotations

import json
import logging
import os
import signal
import time

from services.common.db import close_pool, connection, ensure_schema, wait_for_db
from services.common.queue import delete_message, receive_messages

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
log = logging.getLogger("booking-worker")
_running = True


def stop(*_args) -> None:
    global _running
    _running = False


def process_message(body: dict) -> None:
    key = body.get("idempotency_key")
    if not key:
        raise ValueError("Queue message has no idempotency_key")
    with connection() as (_, cur):
        cur.execute(
            """UPDATE bookings
               SET status = 'confirmed', updated_at = NOW()
               WHERE idempotency_key = %s AND status <> 'confirmed'""",
            (key,),
        )
        if cur.rowcount == 0:
            cur.execute("SELECT 1 FROM bookings WHERE idempotency_key = %s", (key,))
            if cur.fetchone() is None:
                raise ValueError(f"Booking record for {key} does not exist")


def main() -> None:
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    wait_for_db()
    ensure_schema()
    log.info("Booking worker started")
    while _running:
        try:
            for message in receive_messages(max_messages=10, wait_seconds=10):
                try:
                    payload = json.loads(message["Body"])
                    process_message(payload)
                    delete_message(message["ReceiptHandle"])
                    log.info("Processed booking idempotency key %s", payload.get("idempotency_key"))
                except Exception:
                    # Do not delete the message; SQS will make it visible again.
                    log.exception("Booking message processing failed")
            time.sleep(0.2)
        except Exception:
            log.exception("Worker polling failed")
            time.sleep(3)
    close_pool()
    log.info("Booking worker stopped")


if __name__ == "__main__":
    main()

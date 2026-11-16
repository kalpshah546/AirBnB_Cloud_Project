"""SQS wrapper that works with AWS SQS and LocalStack for local development."""
from __future__ import annotations

import json
import time
from functools import lru_cache

import boto3
from botocore.exceptions import ClientError

from services.common import config


@lru_cache(maxsize=1)
def sqs_client():
    kwargs = {"region_name": config.AWS_REGION}
    if config.SQS_ENDPOINT_URL:
        kwargs["endpoint_url"] = config.SQS_ENDPOINT_URL
    return boto3.client("sqs", **kwargs)


@lru_cache(maxsize=1)
def get_queue_url() -> str:
    if config.SQS_QUEUE_URL:
        return config.SQS_QUEUE_URL
    client = sqs_client()
    for attempt in range(15):
        try:
            return client.create_queue(QueueName=config.SQS_QUEUE_NAME)["QueueUrl"]
        except Exception:
            if attempt == 14:
                raise
            time.sleep(2)
    raise RuntimeError("Unable to obtain SQS queue URL")


def enqueue_booking(payload: dict) -> str:
    response = sqs_client().send_message(
        QueueUrl=get_queue_url(),
        MessageBody=json.dumps(payload),
    )
    return response["MessageId"]


def receive_messages(max_messages: int = 10, wait_seconds: int = 10) -> list[dict]:
    response = sqs_client().receive_message(
        QueueUrl=get_queue_url(),
        MaxNumberOfMessages=max_messages,
        WaitTimeSeconds=wait_seconds,
        VisibilityTimeout=60,
    )
    return response.get("Messages", [])


def delete_message(receipt_handle: str) -> None:
    sqs_client().delete_message(QueueUrl=get_queue_url(), ReceiptHandle=receipt_handle)

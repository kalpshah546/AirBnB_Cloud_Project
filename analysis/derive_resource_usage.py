"""Turn minute-level ASG CloudWatch metrics + k6 summary into E6 input rows."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strategy", required=True)
    parser.add_argument("--cloudwatch", required=True)
    parser.add_argument("--k6-summary", required=True)
    parser.add_argument("--ec2-hourly-usd", required=True, type=float,
                        help="Use the current ap-south-1 instance price from AWS Pricing Calculator.")
    parser.add_argument("--period-seconds", default=60, type=int)
    parser.add_argument("--output", default="results/raw/resource_usage.csv")
    args = parser.parse_args()

    cw = pd.read_csv(args.cloudwatch)
    if "in_service_instances" not in cw:
        raise SystemExit("CloudWatch CSV must contain in_service_instances")
    counts = pd.to_numeric(cw["in_service_instances"], errors="coerce").dropna()
    instance_seconds = float(counts.sum() * args.period_seconds)

    summary = json.loads(Path(args.k6_summary).read_text(encoding="utf-8"))
    metrics = summary.get("metrics", {})
    request_count = float(metrics.get("http_reqs", {}).get("values", {}).get("count", 0))
    error_rate = float(metrics.get("http_req_failed", {}).get("values", {}).get("rate", 0))
    successful_requests = max(0, int(round(request_count * (1 - error_rate))))
    if successful_requests == 0:
        raise SystemExit("No successful requests in k6 summary; cannot compute per-request cost")

    row = {
        "strategy": args.strategy,
        "successful_requests": successful_requests,
        "instance_seconds": instance_seconds,
        "ec2_hourly_usd": args.ec2_hourly_usd,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    exists = output.exists()
    pd.DataFrame([row]).to_csv(output, mode="a" if exists else "w", header=not exists, index=False)
    print(f"Appended E6 row: {row}")


if __name__ == "__main__":
    main()

"""Compute compute-only USD cost per 1M successful requests from measured usage."""
from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", nargs="?", default="results/raw/resource_usage.csv")
    parser.add_argument("--output", default="results/raw/cost_per_million.csv")
    args = parser.parse_args()

    path = Path(args.input)
    if not path.exists():
        raise SystemExit(
            f"{path} not found. Create it with columns: strategy, successful_requests, instance_seconds, "
            "ec2_hourly_usd. Use the AWS Pricing Calculator price for your region and instance type."
        )
    frame = pd.read_csv(path)
    required = {"strategy", "successful_requests", "instance_seconds", "ec2_hourly_usd"}
    missing = required - set(frame.columns)
    if missing:
        raise SystemExit(f"Missing required columns: {sorted(missing)}")
    if (frame["successful_requests"] <= 0).any() or (frame["ec2_hourly_usd"] < 0).any():
        raise SystemExit("successful_requests must be > 0 and ec2_hourly_usd must be >= 0")
    frame["compute_cost_usd"] = frame["instance_seconds"] / 3600 * frame["ec2_hourly_usd"]
    frame["compute_usd_per_1m_requests"] = frame["compute_cost_usd"] / frame["successful_requests"] * 1_000_000
    frame.to_csv(args.output, index=False)
    print(frame[["strategy", "compute_cost_usd", "compute_usd_per_1m_requests"]].to_string(index=False))
    print("Note: this excludes ALB, RDS, Redis, SQS, data transfer, logs, and taxes.")


if __name__ == "__main__":
    main()

"""Collect aligned CloudWatch metrics for an E1/E2 experiment window."""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from pathlib import Path

import boto3


def parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def collect_metric(client, namespace, metric_name, dimensions, start, end, statistic="Average", period=60):
    response = client.get_metric_statistics(
        Namespace=namespace,
        MetricName=metric_name,
        Dimensions=[{"Name": key, "Value": value} for key, value in dimensions.items()],
        StartTime=start,
        EndTime=end,
        Period=period,
        Statistics=[statistic],
    )
    return {
        point["Timestamp"].astimezone(timezone.utc).replace(second=0, microsecond=0): point[statistic]
        for point in response.get("Datapoints", [])
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--region", default="ap-south-1")
    parser.add_argument("--asg", action="append", required=True, help="Repeat for each ASG name")
    parser.add_argument("--start", required=True, help="ISO-8601 start time, e.g. 2026-11-16T10:00:00Z")
    parser.add_argument("--end", required=True, help="ISO-8601 end time")
    parser.add_argument("--load-balancer-dimension", default="", help="ALB dimension suffix from Terraform output/console")
    parser.add_argument("--target-group-dimension", default="", help="Target group dimension suffix; optional")
    parser.add_argument("--output", default="results/raw/cloudwatch_metrics.csv")
    args = parser.parse_args()

    start, end = parse_time(args.start), parse_time(args.end)
    cw = boto3.client("cloudwatch", region_name=args.region)
    rows: list[dict] = []

    for asg in args.asg:
        metrics = {
            "in_service_instances": collect_metric(cw, "AWS/AutoScaling", "GroupInServiceInstances", {"AutoScalingGroupName": asg}, start, end, "Average"),
            "desired_capacity": collect_metric(cw, "AWS/AutoScaling", "GroupDesiredCapacity", {"AutoScalingGroupName": asg}, start, end, "Average"),
            "cpu_pct": collect_metric(cw, "AWS/EC2", "CPUUtilization", {"AutoScalingGroupName": asg}, start, end, "Average"),
        }
        timestamps = sorted(set().union(*(set(values) for values in metrics.values())))
        for timestamp in timestamps:
            row = {"timestamp_utc": timestamp.isoformat(), "asg_name": asg}
            for name, values in metrics.items():
                row[name] = values.get(timestamp, "")
            rows.append(row)

    if args.load_balancer_dimension:
        request_count = collect_metric(cw, "AWS/ApplicationELB", "RequestCount", {"LoadBalancer": args.load_balancer_dimension}, start, end, "Sum")
        latency_dimensions = {"LoadBalancer": args.load_balancer_dimension}
        if args.target_group_dimension:
            latency_dimensions["TargetGroup"] = args.target_group_dimension
        latency = collect_metric(cw, "AWS/ApplicationELB", "TargetResponseTime", latency_dimensions, start, end, "Average")
        existing_timestamps = set()
        for row in rows:
            key = row["timestamp_utc"]
            timestamp = datetime.fromisoformat(key).astimezone(timezone.utc).replace(second=0, microsecond=0)
            row["alb_request_count"] = request_count.get(timestamp, "")
            row["target_response_time_seconds"] = latency.get(timestamp, "")
            existing_timestamps.add(timestamp)
        # Retain an ALB-only row only when no ASG metric row exists for that minute.
        for timestamp in (set(request_count) | set(latency)) - existing_timestamps:
            rows.append({
                "timestamp_utc": timestamp.isoformat(),
                "asg_name": "ALB",
                "alb_request_count": request_count.get(timestamp, ""),
                "target_response_time_seconds": latency.get(timestamp, ""),
            })

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({key for row in rows for key in row})
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(sorted(rows, key=lambda row: (row["timestamp_utc"], row["asg_name"])))
    print(f"Wrote {len(rows)} CloudWatch rows to {output}")


if __name__ == "__main__":
    main()

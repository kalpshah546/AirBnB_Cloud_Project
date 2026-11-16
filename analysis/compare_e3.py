"""Compare booking-route latency during the E3 search-only surge."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def metrics(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    all_metrics = data.get("metrics", {})
    duration_metric = next(
        (value for name, value in all_metrics.items()
         if name.startswith("http_req_duration{") and "route:booking" in name),
        {},
    )
    failed_metric = next(
        (value for name, value in all_metrics.items()
         if name.startswith("http_req_failed{") and "route:booking" in name),
        {},
    )
    duration = duration_metric.get("values", {})
    failed = failed_metric.get("values", {})
    name = path.stem.replace("e3_", "")
    architecture = name.split("_run_")[0]
    return {
        "architecture": architecture,
        "run": name.split("_run_")[1] if "_run_" in name else "1",
        "booking_p50_ms": duration.get("med", float("nan")),
        "booking_p95_ms": duration.get("p(95)", float("nan")),
        "booking_p99_ms": duration.get("p(99)", float("nan")),
        "booking_error_rate": failed.get("rate", float("nan")),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+", help="e3_soa.json and e3_monolith.json")
    parser.add_argument("--output", default="results/figures/e3_booking_isolation.png")
    args = parser.parse_args()
    frame = pd.DataFrame([metrics(Path(file)) for file in args.files])
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(output.with_suffix(".csv"), index=False)
    grouped = frame.groupby("architecture").agg(
        p95_mean_ms=("booking_p95_ms", "mean"),
        p95_sd_ms=("booking_p95_ms", "std"),
        p99_mean_ms=("booking_p99_ms", "mean"),
        error_rate_mean=("booking_error_rate", "mean"),
        runs=("run", "count"),
    ).reset_index()
    grouped.to_csv(output.with_name("e3_booking_isolation_summary.csv"), index=False)
    plt.figure(figsize=(8, 5))
    positions = range(len(grouped))
    plt.bar(positions, grouped["p95_mean_ms"], yerr=grouped["p95_sd_ms"].fillna(0), capsize=4)
    plt.xticks(list(positions), grouped["architecture"])
    plt.ylabel("Booking p95 response time (ms)")
    plt.title("E3: Mean booking p95 during a search-only surge")
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(output, dpi=180)
    plt.close()
    print(grouped.to_string(index=False))


if __name__ == "__main__":
    main()

"""Create report-ready experiment graphs from k6 --summary-export JSON files."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "results" / "raw"
FIGURES = ROOT / "results" / "figures"


def read_summary(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    metrics = data.get("metrics", {})
    def val(metric: str, key: str, default=float("nan")):
        return metrics.get(metric, {}).get("values", {}).get(key, default)
    return {
        "file": path.name,
        "p50_ms": val("http_req_duration", "med"),
        "p95_ms": val("http_req_duration", "p(95)"),
        "p99_ms": val("http_req_duration", "p(99)"),
        "avg_ms": val("http_req_duration", "avg"),
        "requests": val("http_reqs", "count", 0),
        "request_rate": val("http_reqs", "rate"),
        "error_rate": val("http_req_failed", "rate"),
        "dropped_iterations": val("dropped_iterations", "count", 0),
    }


def plot_e1(summaries: list[dict]) -> None:
    rows = []
    for item in summaries:
        match = re.search(r"e1_instances_(\d+)", item["file"])
        if match:
            rows.append({**item, "instances": int(match.group(1))})
    if not rows:
        return
    raw = pd.DataFrame(rows)
    frame = raw.groupby("instances").agg(
        p50_mean_ms=("p50_ms", "mean"), p50_sd_ms=("p50_ms", "std"),
        p95_mean_ms=("p95_ms", "mean"), p95_sd_ms=("p95_ms", "std"),
        p99_mean_ms=("p99_ms", "mean"), p99_sd_ms=("p99_ms", "std"),
        request_rate_mean=("request_rate", "mean"), request_rate_sd=("request_rate", "std"),
        runs=("file", "count"),
    ).reset_index().sort_values("instances")
    FIGURES.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(8, 5))
    plt.errorbar(frame["instances"], frame["p50_mean_ms"], yerr=frame["p50_sd_ms"].fillna(0), marker="o", capsize=3, label="p50")
    plt.errorbar(frame["instances"], frame["p95_mean_ms"], yerr=frame["p95_sd_ms"].fillna(0), marker="o", capsize=3, label="p95")
    plt.errorbar(frame["instances"], frame["p99_mean_ms"], yerr=frame["p99_sd_ms"].fillna(0), marker="o", capsize=3, label="p99")
    plt.xlabel("Healthy search instances")
    plt.ylabel("Response time (ms)")
    plt.title("E1: Search latency against fixed instance count (mean ± SD)")
    plt.xticks(frame["instances"])
    plt.grid(True, alpha=0.25)
    plt.legend()
    plt.tight_layout()
    plt.savefig(FIGURES / "e1_latency_vs_instances.png", dpi=180)
    plt.close()

    plt.figure(figsize=(8, 5))
    plt.errorbar(frame["instances"], frame["request_rate_mean"], yerr=frame["request_rate_sd"].fillna(0), marker="o", capsize=3)
    plt.xlabel("Healthy search instances")
    plt.ylabel("Completed requests per second")
    plt.title("E1: Throughput against fixed instance count (mean ± SD)")
    plt.xticks(frame["instances"])
    plt.grid(True, alpha=0.25)
    plt.tight_layout()
    plt.savefig(FIGURES / "e1_throughput_vs_instances.png", dpi=180)
    plt.close()
    frame.to_csv(RAW / "e1_instance_summary.csv", index=False)


def plot_e2(summaries: list[dict]) -> None:
    rows = []
    pattern = re.compile(r"e2_strategy_([a-z]+)_run_(\d+)")
    for item in summaries:
        match = pattern.search(item["file"])
        if match:
            rows.append({**item, "strategy": match.group(1), "run": int(match.group(2))})
    if not rows:
        return
    frame = pd.DataFrame(rows)
    agg = frame.groupby("strategy").agg(
        p95_mean_ms=("p95_ms", "mean"), p95_sd_ms=("p95_ms", "std"),
        error_rate_mean=("error_rate", "mean"), request_rate_mean=("request_rate", "mean"),
    ).reset_index()
    FIGURES.mkdir(parents=True, exist_ok=True)
    plt.figure(figsize=(9, 5))
    plt.bar(agg["strategy"], agg["p95_mean_ms"], yerr=agg["p95_sd_ms"].fillna(0), capsize=4)
    plt.ylabel("p95 response time (ms)")
    plt.title("E2: Mean p95 latency by scaling strategy (3 runs preferred)")
    plt.xticks(rotation=15)
    plt.grid(axis="y", alpha=0.25)
    plt.tight_layout()
    plt.savefig(FIGURES / "e2_p95_by_strategy.png", dpi=180)
    plt.close()
    agg.to_csv(RAW / "e2_strategy_summary.csv", index=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", default=str(RAW))
    args = parser.parse_args()
    raw_dir = Path(args.raw_dir)
    FIGURES.mkdir(parents=True, exist_ok=True)
    summaries = []
    for path in sorted(raw_dir.glob("*.json")):
        try:
            summaries.append(read_summary(path))
        except (json.JSONDecodeError, OSError, KeyError) as exc:
            print(f"Skipping {path.name}: {exc}")
    if not summaries:
        raise SystemExit(f"No k6 summary JSON files found in {raw_dir}")
    pd.DataFrame(summaries).to_csv(raw_dir / "k6_summary_metrics.csv", index=False)
    plot_e1(summaries)
    plot_e2(summaries)
    print(f"Processed {len(summaries)} summaries; figures are in {FIGURES}")


if __name__ == "__main__":
    main()

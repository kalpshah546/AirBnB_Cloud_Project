"""Graphs for the Docker autoscaling experiment (measured data only).

Run in a container (WSL has no matplotlib):
  docker run --rm -v "$PWD":/w -w /w python:3.12-slim sh -c "pip -q install matplotlib && python analysis/docker_plots.py"
Usage: docker_plots.py docker_p5   (reads results/raw/<prefix>_buckets_30s.csv and <prefix>_autoscale_samples.csv)
"""
import csv
from datetime import datetime, timedelta, timezone

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt

import sys
PFX = sys.argv[1] if len(sys.argv) > 1 else "docker_p8"
RAW = "results/raw/"
OUT = "reports/figures/"


def P(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def rows(p):
    with open(p, newline="") as f:
        return list(csv.DictReader(f))


b = rows(RAW + PFX + "_buckets_30s.csv")
s = rows(RAW + PFX + "_autoscale_samples.csv")
bt = [P(r["bucket_start_utc"]) + timedelta(seconds=15) for r in b]
p50 = [float(r["p50_ms"]) for r in b]
p95 = [float(r["p95_ms"]) for r in b]
rps = [float(r["rps"]) for r in b]
st = [P(r["ts_utc"]) for r in s]
reps = [int(r["replicas"]) for r in s]
util = [float(r["avg_cpu_util_pct"]) for r in s]
fmt = mdates.DateFormatter("%H:%M")
x0, x1 = min(bt), max(bt)

# scale events = samples where the replica count changed
events = []
for i in range(1, len(s)):
    if reps[i] != reps[i - 1]:
        events.append((st[i], f"{reps[i - 1]} to {reps[i]}"))

fig, ax = plt.subplots(figsize=(12, 5.5))
ax.plot(bt, p95, color="#c0392b", lw=2, label="p95 response time (ms)")
ax.plot(bt, p50, color="#2980b9", lw=2, label="p50 (median) response time (ms)")
ax.set_ylabel("Response time (ms)")
ax.set_xlabel("Time (UTC)")
ax2 = ax.twinx()
ax2.step(st, reps, where="post", color="#27ae60", lw=3, label="Running search containers")
ax2.set_ylim(0, max(reps) + 1)
ax2.set_yticks(range(0, max(reps) + 2))
ax2.set_ylabel("Number of containers")
YMAX = 400  # clip the axis so normal latency is readable; outliers are annotated instead
ax.set_ylim(0, YMAX)
for t, v in zip(bt, p95):
    if v > YMAX:
        ax.annotate(f"p95 = {v / 1000:.1f} s\n(one slow request\nat scale-in)", xy=(t, YMAX), xytext=(t, YMAX * 0.62),
                    fontsize=8, ha="center", arrowprops=dict(arrowstyle="->", color="#c0392b"), color="#c0392b")
ytop = ax.get_ylim()[1]
for i, (t, lab) in enumerate(events):
    ax.axvline(t, color="k", ls=":", lw=1)
    ax.text(t, ytop * (0.97 - 0.1 * (i % 3)), lab, fontsize=8, ha="center", va="top", bbox=dict(fc="w", ec="none", alpha=.8))
ax.xaxis.set_major_formatter(fmt)
ax.set_xlim(x0, x1)
ax.grid(alpha=.25)
h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper center", bbox_to_anchor=(0.5, -0.13), ncol=3, fontsize=8)
ax.set_title("Docker autoscaling: response time vs number of containers (k6 through Nginx)")
fig.tight_layout()
fig.savefig(OUT + PFX + "_response_time_vs_containers.png", dpi=170)
plt.close(fig)

fig, ax = plt.subplots(figsize=(12, 4))
ax.plot(st, util, color="#8e44ad", lw=2, label="Average container CPU (% of its 0.6 CPU limit)")
ax.axhline(50, color="r", ls="--", label="Scaling target: 50%")
for t, _ in events:
    ax.axvline(t, color="k", ls=":", lw=1)
ax.set_xlim(x0, x1)
ax.xaxis.set_major_formatter(fmt)
ax.set_xlabel("Time (UTC)")
ax.set_ylabel("CPU utilization (%)")
ax.grid(alpha=.25)
ax.legend(loc="upper right")
ax.set_title("Docker autoscaling: CPU utilization (docker stats) and scaling events")
fig.tight_layout()
fig.savefig(OUT + PFX + "_cpu_over_time.png", dpi=170)
plt.close(fig)

fig, ax = plt.subplots(figsize=(12, 3.8))
ax.plot(bt, rps, color="#2980b9", lw=2)
ax.set_xlabel("Time (UTC)")
ax.set_ylabel("Requests per second")
ax.set_xlim(x0, x1)
ax.xaxis.set_major_formatter(fmt)
ax.grid(alpha=.25)
ax.set_title("Docker autoscaling: request rate achieved (k6)")
fig.tight_layout()
fig.savefig(OUT + PFX + "_request_rate.png", dpi=170)
plt.close(fig)
print("events:", events)

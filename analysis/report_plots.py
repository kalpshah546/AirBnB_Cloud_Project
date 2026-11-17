"""Generate report graphs from measured data only.

Run inside a container that has matplotlib (WSL has no pip):
  docker run --rm -v "$PWD":/w -w /w python:3.12-slim sh -c "pip -q install matplotlib && python analysis/report_plots.py"
Inputs: results/raw/e1_buckets_30s.csv, e2_buckets_30s.csv, e2_asg_samples.csv, cw_*.json
"""
import bisect
import csv
import json
import statistics
from datetime import datetime, timedelta, timezone

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt

RAW = "results/raw/"
OUT = "reports/figures/"


def P(s):
    return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def read_csv(p):
    with open(p, newline="") as f:
        return list(csv.DictReader(f))


def cw(path, key):
    d = json.load(open(RAW + path))["Datapoints"]
    d.sort(key=lambda x: x["Timestamp"])
    return [datetime.fromisoformat(x["Timestamp"]).astimezone(timezone.utc) for x in d], [x[key] for x in d]


b = read_csv(RAW + "e2_buckets_30s.csv")
s = read_csv(RAW + "e2_asg_samples.csv")
bt = [P(r["bucket_start_utc"]) + timedelta(seconds=15) for r in b]  # window midpoint
p50 = [float(r["p50_ms"]) for r in b]
p95 = [float(r["p95_ms"]) for r in b]
rps = [float(r["rps"]) for r in b]
er = [float(r["error_rate"]) * 100 for r in b]
st = [P(r["ts_utc"]) for r in s]
healthy = [int(r["healthy_targets"] or 0) for r in s]

# Scaling events taken from the ASG activity history (asg_scaling_activities.json)
events = [("17:10:15", "+1 instance\n(CPU alarm)"), ("17:13:14", "+1 instance\n(CPU alarm)"),
          ("17:35:59", "-1 (scale-in)"), ("17:37:00", "-1 (scale-in)")]
ev = [(P("2026-11-17T" + t + "Z"), lab) for t, lab in events]
fmt = mdates.DateFormatter("%H:%M")
x0, x1 = P("2026-11-17T17:02:00Z"), P("2026-11-17T17:38:00Z")

# 1. MANDATORY graph: response time vs time, with number of instances
fig, ax = plt.subplots(figsize=(12, 5.5))
ax.plot(bt, p95, color="#c0392b", lw=2, label="p95 response time (ms)")
ax.plot(bt, p50, color="#2980b9", lw=2, label="p50 (median) response time (ms)")
ax.set_ylabel("Response time (ms)")
ax.set_xlabel("Time (UTC, 17 Nov 2026)")
ax2 = ax.twinx()
ax2.step(st, healthy, where="post", color="#27ae60", lw=3, label="Healthy instances (ALB target group)")
ax2.set_ylim(0, 4)
ax2.set_yticks([0, 1, 2, 3])
ax2.set_ylabel("Number of healthy instances")
ax.axvspan(P("2026-11-17T17:04:16Z"), P("2026-11-17T17:06:16Z"), color="#f1c40f", alpha=.15, label="Ramp 4 to 16 req/s")
ax.axvspan(P("2026-11-17T17:06:16Z"), P("2026-11-17T17:16:16Z"), color="#e67e22", alpha=.12, label="Peak 16 req/s")
ytop = ax.get_ylim()[1]
for i, (t, lab) in enumerate(ev):
    ax.axvline(t, color="k", ls=":", lw=1)
    ax.text(t, ytop * (0.97 - 0.14 * (i % 2)), lab, fontsize=8, ha="center", va="top", bbox=dict(fc="w", ec="none", alpha=.8))
ax.xaxis.set_major_formatter(fmt)
ax.set_xlim(x0, x1)
ax.grid(alpha=.25)
h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper center", bbox_to_anchor=(0.5, -0.13), ncol=3, fontsize=8)
ax.set_title("E2: Response time vs number of instances during a traffic spike (k6 through the ALB)")
fig.tight_layout()
fig.savefig(OUT + "e2_response_time_vs_instances.png", dpi=170)
plt.close(fig)

# 2. p95 grouped by healthy-instance count, peak window only
def healthy_at(t):
    i = bisect.bisect_right(st, t) - 1
    return healthy[max(i, 0)]


groups = {}
for t, a, c, r in zip(bt, p50, p95, rps):
    if P("2026-11-17T17:06:30Z") <= t <= P("2026-11-17T17:16:00Z") and r >= 14:
        groups.setdefault(healthy_at(t), []).append((a, c))
ks = sorted(groups)
fig, ax = plt.subplots(figsize=(7.5, 5))
ax.boxplot([[c for _, c in groups[k]] for k in ks],
           tick_labels=[f"{k} instance(s)\n(n={len(groups[k])} windows)" for k in ks], showmeans=True)
ax.set_ylabel("p95 response time per 30 s window (ms)")
ax.set_title("E2 peak load (about 16 req/s): p95 vs healthy instances")
ax.grid(axis="y", alpha=.25)
fig.tight_layout()
fig.savefig(OUT + "e2_p95_by_instance_count.png", dpi=170)
plt.close(fig)
rows = []
for k in ks:
    v = [c for _, c in groups[k]]
    m = [a for a, _ in groups[k]]
    rows.append({"healthy_instances": k, "windows_30s": len(v), "p50_median_ms": round(statistics.median(m), 1),
                 "p95_median_ms": round(statistics.median(v), 1), "p95_max_ms": max(v)})
with open("results/evidence/e2_latency_by_instance_count.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)

# 3. CPU over time (CloudWatch)
t, cpu = cw("cw_cpu_asg.json", "Average")
fig, ax = plt.subplots(figsize=(12, 4.5))
ax.plot(t, cpu, color="#8e44ad", lw=2, label="Average CPU of ASG instances (%)")
ax.axhline(50, color="r", ls="--", label="Scaling target: 50% CPU")
ax.set_ylim(0, 105)
for tt, _ in ev:
    ax.axvline(tt, color="k", ls=":", lw=1)
ax.set_xlim(x0, x1)
ax.xaxis.set_major_formatter(fmt)
ax.set_xlabel("Time (UTC)")
ax.set_ylabel("CPU utilization (%)")
ax.grid(alpha=.25)
ax.legend(loc="upper right")
ax.set_title("E2: CPU utilization over time (CloudWatch, 1-minute average; dotted lines = scaling events)")
fig.tight_layout()
fig.savefig(OUT + "e2_cpu_over_time.png", dpi=170)
plt.close(fig)

# 4. Instance count over time
t, n = cw("cw_in_service.json", "Average")
fig, ax = plt.subplots(figsize=(12, 4))
ax.step(t, n, where="post", lw=3, color="#16a085", label="InService instances (CloudWatch)")
ax.step(st, healthy, where="post", lw=1.5, color="#2c3e50", ls="--", label="Healthy targets (15 s monitor samples)")
ax.set_ylim(0, 4)
ax.set_yticks([0, 1, 2, 3])
ax.set_xlim(x0, x1)
ax.xaxis.set_major_formatter(fmt)
ax.grid(alpha=.25)
ax.legend(loc="upper right")
ax.set_xlabel("Time (UTC)")
ax.set_ylabel("Instances")
ax.set_title("E2: Instance count over time (automatic scale-out and scale-in)")
fig.tight_layout()
fig.savefig(OUT + "e2_instance_count_over_time.png", dpi=170)
plt.close(fig)

# 5. Request rate and error rate
fig, ax = plt.subplots(figsize=(12, 4))
ax.plot(bt, rps, color="#2980b9", lw=2, label="Achieved request rate (req/s)")
ax.set_ylabel("Requests per second")
ax.set_xlabel("Time (UTC)")
ax.set_xlim(x0, x1)
ax.xaxis.set_major_formatter(fmt)
ax.grid(alpha=.25)
ax2 = ax.twinx()
ax2.plot(bt, er, color="#c0392b", lw=1.5, label="Error rate (%)")
ax2.set_ylim(0, 5)
ax2.set_ylabel("Error rate (%)")
h1, l1 = ax.get_legend_handles_labels()
h2, l2 = ax2.get_legend_handles_labels()
ax.legend(h1 + h2, l1 + l2, loc="upper right")
ax.set_title("E2: Request rate and error rate")
fig.tight_layout()
fig.savefig(OUT + "e2_request_and_error_rate.png", dpi=170)
plt.close(fig)

# 6. E1: latency vs request rate on one instance (windows before the health-check failure)
e1 = [r for r in read_csv(RAW + "e1_buckets_30s.csv") if float(r["error_rate"]) < 0.5 and float(r["rps"]) > 1]
fig, ax = plt.subplots(figsize=(8, 5))
ax.plot([float(r["rps"]) for r in e1], [float(r["p95_ms"]) for r in e1], "o-", color="#c0392b", label="p95 (ms)")
ax.plot([float(r["rps"]) for r in e1], [float(r["p50_ms"]) for r in e1], "o-", color="#2980b9", label="p50 (ms)")
ax.set_yscale("log")
ax.set_xlabel("Achieved request rate (req/s, 30 s windows)")
ax.set_ylabel("Response time (ms, log scale)")
ax.axvline(15, color="gray", ls="--", label="about 15 req/s: knee for 1 instance")
ax.grid(alpha=.25, which="both")
ax.legend()
ax.set_title("E1: Single t3.micro instance, latency vs request rate")
fig.tight_layout()
fig.savefig(OUT + "e1_latency_vs_rate.png", dpi=170)
plt.close(fig)
print("done", {k: len(v) for k, v in groups.items()})

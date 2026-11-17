"""Per-time-bucket stats from a k6 --out csv file (stdlib only). Usage: bucket_k6.py requests.csv [bucket_seconds] [out.csv]"""
import csv, sys, statistics
from collections import defaultdict
src = sys.argv[1]; width = int(sys.argv[2]) if len(sys.argv) > 2 else 30
out = sys.argv[3] if len(sys.argv) > 3 else None
dur = defaultdict(list); fail = defaultdict(int); t0 = None
with open(src, newline="") as f:
    r = csv.DictReader(f)
    for row in r:
        ts = int(row["timestamp"])
        if t0 is None or ts < t0: t0 = ts
        if row["metric_name"] == "http_req_duration":
            dur[ts // width * width].append(float(row["metric_value"]))
        elif row["metric_name"] == "http_req_failed":
            if float(row["metric_value"]) == 1.0: fail[ts // width * width] += 1
def pct(v, p):
    v = sorted(v); return v[min(len(v) - 1, int(len(v) * p))]
rows = []
for b in sorted(dur):
    v = dur[b]
    rows.append({"bucket_start_utc": __import__("datetime").datetime.utcfromtimestamp(b).strftime("%Y-%m-%dT%H:%M:%SZ"),
                 "rps": round(len(v) / width, 2), "error_rate": round(fail[b] / len(v), 3),
                 "p50_ms": round(statistics.median(v), 1), "p95_ms": round(pct(v, .95), 1), "p99_ms": round(pct(v, .99), 1)})
print("bucket_start_utc,rps,error_rate,p50_ms,p95_ms,p99_ms")
for x in rows: print(",".join(str(x[k]) for k in x))
if out:
    with open(out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

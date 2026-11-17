#!/usr/bin/env bash
# Tiny CPU autoscaler for the Docker Compose demo (docker/compose.autoscale.yaml).
# Same rule as the Kubernetes HPA: desired = ceil(current * utilization / target), clamped to [MIN, MAX].
# Scale-out is immediate; scale-in waits until the low reading has lasted DOWN_STABLE seconds.
# Utilization = container CPU% (docker stats) / (CPU limit * 100), averaged over replicas.
#
# Env: PROJECT FILE SERVICE TARGET MIN MAX CPU_LIMIT INTERVAL DOWN_STABLE OUT
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${PROJECT:-airbnb-autoscale}"
FILE="${FILE:-$ROOT/docker/compose.autoscale.yaml}"
SERVICE="${SERVICE:-search}"
TARGET="${TARGET:-50}"
MIN="${MIN:-1}"
MAX="${MAX:-5}"
CPU_LIMIT="${CPU_LIMIT:-0.6}"
INTERVAL="${INTERVAL:-10}"
DOWN_STABLE="${DOWN_STABLE:-120}"
OUT="${OUT:-$ROOT/results/raw/docker_autoscale_samples.csv}"
mkdir -p "$(dirname "$OUT")"
echo "ts_utc,replicas,avg_cpu_util_pct,desired,action" > "$OUT"
low_since=0

while true; do
  ids="$(docker compose -p "$PROJECT" -f "$FILE" ps -q "$SERVICE" 2>/dev/null)"
  n="$(printf '%s\n' "$ids" | grep -c .)"
  if [[ "$n" -gt 0 ]]; then
    # shellcheck disable=SC2086
    util="$(docker stats --no-stream --format '{{.CPUPerc}}' $ids 2>/dev/null | tr -d '%' \
      | awk -v lim="$CPU_LIMIT" '{s+=$1;c++} END{if(c>0) printf "%.1f", s/c/(lim*100)*100; else print 0}')"
  else
    util=0
  fi
  desired="$(awk -v n="$n" -v u="$util" -v t="$TARGET" -v mn="$MIN" -v mx="$MAX" 'BEGIN{
      r=u/t; if (r>1.1 || r<0.9) d=int(n*r+0.999999); else d=n;
      if(d<mn)d=mn; if(d>mx)d=mx; print d}')"
  action="hold"; now=$(date +%s)
  if (( desired > n )); then
    action="scale_out"; low_since=0
  elif (( desired < n )); then
    if (( low_since == 0 )); then low_since=$now; fi
    if (( now - low_since >= DOWN_STABLE )); then action="scale_in"; low_since=0; else desired=$n; action="hold(stabilizing)"; fi
  else
    low_since=0
  fi
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ),$n,$util,$desired,$action" | tee -a "$OUT"
  if [[ "$action" == "scale_out" || "$action" == "scale_in" ]]; then
    docker compose -p "$PROJECT" -f "$FILE" up -d --no-recreate --scale "$SERVICE=$desired" "$SERVICE" >/dev/null 2>&1
  fi
  sleep "$INTERVAL"
done

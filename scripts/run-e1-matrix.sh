#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${BASE_URL:?Set BASE_URL to the ALB URL, e.g. http://...elb.amazonaws.com}"
: "${SEARCH_ASG:?Set SEARCH_ASG to the search ASG name}"
RATE_MAX="${RATE_MAX:-100}"
WAIT_SECONDS="${WAIT_SECONDS:-240}"
RUNS="${RUNS:-3}"
LISTING_ASG="${LISTING_ASG:-}"
BOOKING_ASG="${BOOKING_ASG:-}"
SEARCH_RESTORE_MIN="${SEARCH_RESTORE_MIN:-1}"
SEARCH_RESTORE_DESIRED="${SEARCH_RESTORE_DESIRED:-1}"
SEARCH_RESTORE_MAX="${SEARCH_RESTORE_MAX:-${NORMAL_MAX_CAPACITY:-8}}"

# E1 measures only search; stop the other service fleets to conserve a small vCPU quota.
for other_asg in "$LISTING_ASG" "$BOOKING_ASG"; do
  if [[ -n "$other_asg" ]]; then
    aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$other_asg" --min-size 0 --desired-capacity 0 --max-size "${NORMAL_MAX_CAPACITY:-8}"
  fi
done

restore_groups() {
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$SEARCH_ASG" \
    --min-size "$SEARCH_RESTORE_MIN" --desired-capacity "$SEARCH_RESTORE_DESIRED" --max-size "$SEARCH_RESTORE_MAX" || true
  for other_asg in "$LISTING_ASG" "$BOOKING_ASG"; do
    if [[ -n "$other_asg" ]]; then
      aws autoscaling update-auto-scaling-group --auto-scaling-group-name "$other_asg" --min-size 1 --desired-capacity 1 --max-size "${NORMAL_MAX_CAPACITY:-8}" || true
    fi
  done
}
trap restore_groups EXIT

mkdir -p "$ROOT/results/raw"
for count in 1 2 4 8; do
  echo "\n=== E1: fixed search fleet = ${count} ==="
  "$ROOT/scripts/set-fixed-capacity.sh" "$SEARCH_ASG" "$count"
  aws autoscaling wait group-in-service --auto-scaling-group-names "$SEARCH_ASG"
  echo "Waiting ${WAIT_SECONDS}s for targets and data to settle..."
  sleep "$WAIT_SECONDS"
  for run in $(seq 1 "$RUNS"); do
    echo "--- E1 instance count ${count}, run ${run}/${RUNS} ---"
    k6 run \
      -e BASE_URL="$BASE_URL" \
      -e RATE_MAX="$RATE_MAX" \
      --summary-export "$ROOT/results/raw/e1_instances_${count}_run_${run}.json" \
      "$ROOT/loadtest/k6/fixed-capacity.js"
  done
done

echo "E1 runs saved to results/raw. The script restores all three service ASGs on exit."
